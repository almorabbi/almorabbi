"""
Identity router — Phase 1.2 optional Google Sign-In.

Allows an anonymous device-bound parent to optionally link a Google
identity. The link survives app reinstall because child_profiles + progress
are keyed off device_id, and the server can copy/merge data from a previous
confirmed device_id linked to the same google_id. This is the seed of
multi-device sync.

Security:
  - The mobile app sends a Google ID token (JWT), not a raw google_id.
  - The server verifies the token signature/claims with Google's public
    tokeninfo endpoint before linking.
  - Cross-device data merge runs ONLY when BOTH devices (the previous device
    and the current device) hold confirmed links (`confirmed = 1` in
    `identity_links`, see `_link_confirmable`). An unconfirmed link
    (`confirmed = 0`) is never pulled from and never copied to — not even
    child names.
"""
import asyncio
import json
import logging
import os
import time
from typing import Optional

import httpx
from fastapi import APIRouter, Request

from app.core.proof import request_access
from app.db.init_db import get_conn
from app.services import conversation_store as store
from app.services import merge_tombstones as tombs
from app.services.child_memory import family_from_conn
from app.services.privacy import Family, reletter_siblings

logger = logging.getLogger(__name__)
router = APIRouter(tags=["identity"])


# Accepted issuers per Google OAuth 2.0 docs.
_GOOGLE_ISSUERS = frozenset({"https://accounts.google.com", "accounts.google.com"})

# Hard-coded, non-secret client ID used to validate the Google ID token audience.
# The web client ID is the one the mobile plugin uses as serverClientId.
_GOOGLE_WEB_CLIENT_ID = "620240456244-d7a3fd35ianuu34i1sobb0pj4ncttmdu.apps.googleusercontent.com"

_LESSON_STATUS_RANK = {"not_started": 0, "in_progress": 1, "completed": 2}
_MISSION_STATUS_RANK = {"not_done": 0, "expired": 0, "assigned": 1, "claimed": 2, "confirmed": 3}
_LICENCE_STATUS_RANK = {"practising": 1, "awaiting_talk": 2, "granted": 3}
_PRAYER_TRACK_RANK = {"preparation": 1, "journey": 2, "ownership": 3}


async def _verify_google_id_token(id_token: str) -> Optional[dict]:
    """Verify a Google ID token via Google's tokeninfo endpoint.

    Returns the token payload on success, None on failure.
    Validates issuer, expiry and audience. `email` is kept only when Google
    says it is verified (see [_verified_email]).
    """
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            r = await client.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"id_token": id_token},
            )
    except httpx.HTTPError as e:
        logger.warning("Google tokeninfo network error: %s", e)
        return None

    if r.status_code != 200:
        logger.warning("Google tokeninfo returned %s: %s", r.status_code, r.text)
        return None

    try:
        payload = r.json()
    except Exception:
        return None

    iss = payload.get("iss", "")
    if iss not in _GOOGLE_ISSUERS:
        logger.warning("Google token invalid issuer: %s", iss)
        return None

    try:
        exp = int(payload.get("exp", "0"))
    except (ValueError, TypeError):
        return None
    # tokeninfo refuses expired tokens itself; checking here too means a
    # proxy or cache in between cannot hand us one.
    if exp <= int(time.time()):
        return None

    # The audience must be our Web client ID (the mobile plugin's
    # serverClientId). `azp` is the party that *requested* the token — on
    # Android that is the Android client — so it says nothing about who the
    # token is for, and accepting `azp == ours` alone let a token minted for
    # another audience through.
    aud = payload.get("aud", "")
    if aud != _GOOGLE_WEB_CLIENT_ID:
        logger.warning("Google token audience not recognised: aud=%s azp=%s",
                       aud, payload.get("azp", ""))
        return None

    return payload


def _verified_email(token_payload: dict) -> str:
    """The token's email, or "" when Google does not vouch for it.

    Linking is keyed on `sub`, which Google controls. `email` is not: an
    account can carry an address its owner never proved (Google accounts made
    with a third-party address). tokeninfo sends `email_verified` as the string
    "true"; the id_token JWT sends a boolean — accept both.
    """
    if str(token_payload.get("email_verified", "")).lower() != "true":
        return ""
    return (token_payload.get("email") or "").strip()


@router.post("/identity/link-google")
async def link_google_identity(request: Request, payload: dict) -> dict:
    device_id = getattr(request.state, "device_id", "")
    id_token = (payload.get("id_token") or "").strip()

    if not id_token or not device_id:
        return {"ok": False, "error": "id_token_and_device_required"}

    token_payload = await _verify_google_id_token(id_token)
    if token_payload is None:
        return {"ok": False, "error": "invalid_google_id_token"}

    google_id = token_payload.get("sub", "").strip()
    email = _verified_email(token_payload)
    display_name = (token_payload.get("name") or "").strip()

    if not google_id:
        return {"ok": False, "error": "invalid_google_id_token"}

    # Whether this session is proven to hold the phone (core/proof.py): only
    # a link made that way carries account deletion or cross-device data merge
    # (PR #26 final review — a bare session for a known device id must not be
    # able to tie a family's phone to someone else's Google account and pull
    # or delete its data).
    confirmed = await asyncio.to_thread(_link_confirmable, request)
    # sqlite is blocking — keep it off the event loop.
    linked = await asyncio.to_thread(
        _link_identity, device_id, google_id, email, display_name, confirmed)
    if not linked:
        return {"ok": False, "error": "device_proof_required"}
    return {"ok": True, "google_id": google_id, "email": email}


def _link_confirmable(request: Request) -> bool:
    """May this session make a CONFIRMED link — one that carries data between
    phones and account deletion across them?

    The security review of PR #175 (2026-10-27) found `request_proven` was not
    enough: a session minted bare for someone else's device id registered its
    own FCM token as the device's first (vouched, so only irreversible routes
    paused), proved itself on it, and got confirmed=1. Now all three:

      * the session was not minted bare (api_tokens.mint_kind) — a bare
        session is anyone who learned the id;
      * it is proven, with no cooldown of EITHER kind — moving a family's
        data to another phone is as irreversible as deleting it, so a first
        token on an established device waits out its pause;
      * (push.py) a later unvouched token change takes confirmed back.
    """
    token = getattr(request.state, "token", None)
    if store.token_is_bare(token):
        return False
    return request_access(request, irreversible=True).ok


def unconfirm_device_links(conn, device_id: str) -> int:
    """The device's push token changed without a proof vouching for it
    (routers/push.py): whoever holds the phone now is not who confirmed its
    Google link. Inside the caller's transaction."""
    try:
        cur = conn.execute(
            "UPDATE identity_links SET confirmed = 0 WHERE device_id = ? AND confirmed = 1",
            (device_id,))
        return cur.rowcount
    except Exception:  # an older schema without the table or column
        return 0


def cross_device_enabled() -> bool:
    """Whether a Google link may move data between phones (merge on link,
    account deletion across linked phones). Off unless IDENTITY_CROSS_DEVICE=1.

    History: `confirmed` used to be reachable by anyone who knew a device id
    (security review of PR #175, 2026-10-27; see _link_confirmable). With v37
    a bare session can no longer confirm, but tokens minted before v37 carry
    no mint_kind and a bare one among them cannot be told apart. Turn this on
    together with SESSION_MINT_ENFORCE, once most active installs hold a
    restore key (ops/tools/runtime_readiness_report.py).
    """
    return os.environ.get("IDENTITY_CROSS_DEVICE", "").strip() == "1"


def _link_identity(device_id: str, google_id: str, email: str, display_name: str,
                   confirmed: bool = False) -> bool:
    """Link the device to the Google identity. False — nothing written — when an
    unconfirmed session tries to replace a link a confirmed session made to a
    different account. A confirmed link is never downgraded by re-linking."""
    conn = get_conn()
    try:
        current = conn.execute(
            "SELECT google_id, confirmed FROM identity_links WHERE device_id = ?", (device_id,)
        ).fetchone()
        if (current is not None and current["confirmed"] and not confirmed
                and current["google_id"] != google_id):
            return False
        conn.execute(
            """
            INSERT INTO parent_identities (google_id, email, display_name)
            VALUES (?, ?, ?)
            ON CONFLICT(google_id) DO UPDATE SET
                email = COALESCE(excluded.email, parent_identities.email),
                display_name = COALESCE(excluded.display_name, parent_identities.display_name)
            """,
            (google_id, email or None, display_name or None),
        )
        conn.execute(
            """
            INSERT INTO identity_links (device_id, google_id, linked_at, confirmed)
            VALUES (?, ?, datetime('now'), ?)
            ON CONFLICT(device_id) DO UPDATE SET
                confirmed = CASE WHEN identity_links.google_id = excluded.google_id
                                 THEN MAX(COALESCE(identity_links.confirmed, 0),
                                          excluded.confirmed)
                                 ELSE excluded.confirmed END,
                google_id = excluded.google_id,
                linked_at = excluded.linked_at
            """,
            (device_id, google_id, 1 if confirmed else 0),
        )
        conn.commit()

        # Merge data from any previously confirmed-linked device_id — off until
        # cross_device_enabled() (see there). Best-effort by design: the link
        # above is already committed.
        if cross_device_enabled():
            try:
                _merge_legacy_device_data(conn, device_id, google_id)
            except Exception as e:
                logger.warning("Legacy device merge failed (link kept): %s", e)
        return True
    finally:
        conn.close()


@router.get("/identity/me")
def get_identity(request: Request) -> dict:
    device_id = getattr(request.state, "device_id", "")
    conn = get_conn()
    try:
        row = conn.execute(
            """
            SELECT p.google_id, p.email, p.display_name, l.linked_at
            FROM identity_links l
            JOIN parent_identities p ON p.google_id = l.google_id
            WHERE l.device_id = ?
            """,
            (device_id,),
        ).fetchone()
    finally:
        conn.close()
    if not row:
        return {"ok": True, "linked": False}
    return {
        "ok": True,
        "linked": True,
        "google_id": row["google_id"],
        "email": row["email"],
        "display_name": row["display_name"],
        "linked_at": row["linked_at"],
    }


def _table_exists(conn, table: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table,),
    ).fetchone()
    return row is not None


def _table_cols(conn, table: str) -> set[str]:
    if not _table_exists(conn, table):
        return set()
    return {c[1] for c in conn.execute(f'PRAGMA table_info("{table}")').fetchall()}


def _row_val(row, col: str, default=None):
    return row[col] if col in row.keys() else default


def _to_family(members: list[tuple[int, str]]) -> Family:
    return Family(
        tuple(
            (int(cid), (name or "").strip())
            for cid, name in members
            if name and len(name.strip()) >= 2
        )
    )


def _memory_enabled(conn, device_id: str) -> bool:
    """child_memory_settings.enabled for the device (no row = on)."""
    if not _table_exists(conn, "child_memory_settings"):
        return True
    row = conn.execute("SELECT enabled FROM child_memory_settings WHERE device_id = ?",
                       (device_id,)).fetchone()
    return row is None or bool(row["enabled"])


def _sync_child_scoped_rows(
    conn,
    old_device: str,
    old_cid: int,
    new_device: str,
    new_cid: int,
    old_fam: Optional[Family] = None,
    after_fam: Optional[Family] = None,
) -> bool:
    """Idempotently and non-destructively copy/merge child-scoped rows from
    `(old_device, old_cid)` onto `(new_device, new_cid)`.

    Never deletes or re-keys rows on `old_device`, so two confirmed phones
    belonging to the same parent never pull data away from each other.
    Returns True if any child memory (`child_facts` or `followups`) was written
    or updated on `new_device`.
    """
    if old_device == new_device and old_cid == new_cid:
        return False

    memory_touched = False

    # What the parent deleted on `new_device` stays deleted (services/
    # merge_tombstones.py): memory rows from before a wipe are not copied, and
    # with memory switched off on `new_device` no facts or follow-ups are.
    wiped_at = tombs.memory_since(conn, new_device, new_cid)
    memory_on = _memory_enabled(conn, new_device)

    def wiped(row) -> bool:
        return tombs.covers(_row_val(row, "created_at"), wiped_at)

    # 1. lesson_progress — UNIQUE(device_id, child_id, lesson_id)
    if _table_exists(conn, "lesson_progress"):
        old_rows = conn.execute(
            "SELECT * FROM lesson_progress WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            new_r = conn.execute(
                """
                SELECT * FROM lesson_progress
                WHERE device_id = ? AND child_id = ? AND lesson_id = ?
                """,
                (new_device, new_cid, old_r["lesson_id"]),
            ).fetchone()
            if new_r is None:
                conn.execute(
                    """
                    INSERT INTO lesson_progress
                        (device_id, child_id, path_id, lesson_id, status,
                         started_at, completed_at, score, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        new_cid,
                        old_r["path_id"],
                        old_r["lesson_id"],
                        old_r["status"],
                        _row_val(old_r, "started_at"),
                        _row_val(old_r, "completed_at"),
                        _row_val(old_r, "score"),
                        _row_val(old_r, "updated_at"),
                    ),
                )
            else:
                old_rank = _LESSON_STATUS_RANK.get(old_r["status"] or "", 0)
                new_rank = _LESSON_STATUS_RANK.get(new_r["status"] or "", 0)
                best_status = old_r["status"] if old_rank > new_rank else new_r["status"]
                if new_r["score"] is not None and old_r["score"] is not None:
                    best_score = max(new_r["score"], old_r["score"])
                else:
                    best_score = new_r["score"] if new_r["score"] is not None else old_r["score"]
                started_at = new_r["started_at"] or old_r["started_at"]
                completed_at = new_r["completed_at"] or old_r["completed_at"]
                updated_at = max(new_r["updated_at"] or "", old_r["updated_at"] or "") or None
                conn.execute(
                    """
                    UPDATE lesson_progress
                    SET status = ?, score = ?, started_at = ?, completed_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (best_status, best_score, started_at, completed_at, updated_at, new_r["id"]),
                )

    # 2. weekly_plans — UNIQUE(device_id, child_id, iso_week, lang, personal)
    if _table_exists(conn, "weekly_plans"):
        old_rows = conn.execute(
            "SELECT * FROM weekly_plans WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            if wiped(old_r) or (_row_val(old_r, "personal", 0) and not memory_on):
                continue
            raw_json = _row_val(old_r, "plan_json") or "{}"
            if old_cid != new_cid and raw_json:
                try:
                    payload = json.loads(raw_json)
                    if isinstance(payload, dict) and payload.get("child_id") != new_cid:
                        payload["child_id"] = new_cid
                        raw_json = json.dumps(payload, ensure_ascii=False)
                except Exception:
                    pass
            conn.execute(
                """
                INSERT OR IGNORE INTO weekly_plans
                    (device_id, child_id, iso_week, lang, plan_json, created_at, personal)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_device,
                    new_cid,
                    old_r["iso_week"],
                    old_r["lang"],
                    raw_json,
                    old_r["created_at"],
                    _row_val(old_r, "personal", 0),
                ),
            )

    # 3. weekly_plan_marks (lanterns) — UNIQUE(device_id, child_id, item_id, marked_on)
    if _table_exists(conn, "weekly_plan_marks"):
        old_rows = conn.execute(
            "SELECT * FROM weekly_plan_marks WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            if wiped(old_r):
                continue
            conn.execute(
                """
                INSERT OR IGNORE INTO weekly_plan_marks
                    (device_id, child_id, item_id, marked_on, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (new_device, new_cid, old_r["item_id"], old_r["marked_on"], old_r["created_at"]),
            )

    # 4. child_facts
    if memory_on and _table_exists(conn, "child_facts"):
        old_rows = conn.execute(
            "SELECT * FROM child_facts WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            fact_text = old_r["fact"]
            if (
                old_fam is not None
                and after_fam is not None
                and old_fam.members
                and old_fam.members != after_fam.members
            ):
                fact_text = reletter_siblings(fact_text, old_fam, after_fam, owner=new_cid)
            if wiped(old_r) or tombs.covers(_row_val(old_r, "created_at"), tombs.since(
                    conn, new_device, "fact",
                    tombs.fact_key(new_cid, old_r["category"], fact_text))):
                continue
            existing = conn.execute(
                """
                SELECT id, confidence, times_seen, status
                FROM child_facts
                WHERE device_id = ? AND child_id = ? AND category = ? AND fact = ?
                """,
                (new_device, new_cid, old_r["category"], fact_text),
            ).fetchone()
            if existing is None:
                conn.execute(
                    """
                    INSERT INTO child_facts
                        (device_id, child_id, category, fact, source, confidence,
                         status, lang, times_seen, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        new_cid,
                        old_r["category"],
                        fact_text,
                        _row_val(old_r, "source", "chat"),
                        _row_val(old_r, "confidence", 0.5),
                        _row_val(old_r, "status", "active"),
                        _row_val(old_r, "lang", "ar"),
                        _row_val(old_r, "times_seen", 1),
                        old_r["created_at"],
                        old_r["updated_at"],
                    ),
                )
                memory_touched = True
            else:
                best_conf = max(
                    float(existing["confidence"] or 0.0),
                    float(_row_val(old_r, "confidence", 0.5) or 0.0),
                )
                best_seen = max(
                    int(existing["times_seen"] or 1),
                    int(_row_val(old_r, "times_seen", 1) or 1),
                )
                conn.execute(
                    """
                    UPDATE child_facts
                    SET confidence = ?, times_seen = ?
                    WHERE id = ?
                    """,
                    (best_conf, best_seen, existing["id"]),
                )

    # 5. followups — ux_followups_pending_topic ON (device_id, child_id, topic) WHERE status = 'pending' AND topic != 'other'
    if memory_on and _table_exists(conn, "followups"):
        f_cols = _table_cols(conn, "followups")
        has_source = "source" in f_cols
        old_rows = conn.execute(
            "SELECT * FROM followups WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            if wiped(old_r):
                continue
            strategy_text = old_r["strategy"]
            if (
                old_fam is not None
                and after_fam is not None
                and old_fam.members
                and old_fam.members != after_fam.members
            ):
                strategy_text = reletter_siblings(
                    strategy_text, old_fam, after_fam, owner=new_cid
                )
            topic = _row_val(old_r, "topic")
            existing = conn.execute(
                """
                SELECT * FROM followups
                WHERE device_id = ? AND child_id = ?
                  AND strategy = ? AND COALESCE(topic, '') = COALESCE(?, '')
                  AND due_at = ?
                """,
                (new_device, new_cid, strategy_text, topic, old_r["due_at"]),
            ).fetchone()
            if (
                existing is None
                and old_r["status"] == "pending"
                and topic is not None
                and topic != "other"
            ):
                existing = conn.execute(
                    """
                    SELECT * FROM followups
                    WHERE device_id = ? AND child_id = ?
                      AND status = 'pending' AND topic = ?
                    """,
                    (new_device, new_cid, topic),
                ).fetchone()
            if existing is None:
                if has_source:
                    conn.execute(
                        """
                        INSERT INTO followups
                            (device_id, child_id, strategy, topic, lang,
                             source_message_id, due_at, status, outcome, note,
                             outcome_fact_id, pushed_at, answered_at, created_at,
                             updated_at, source)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            new_device,
                            new_cid,
                            strategy_text,
                            topic,
                            _row_val(old_r, "lang", "ar"),
                            _row_val(old_r, "source_message_id"),
                            old_r["due_at"],
                            old_r["status"],
                            _row_val(old_r, "outcome"),
                            _row_val(old_r, "note"),
                            _row_val(old_r, "outcome_fact_id"),
                            _row_val(old_r, "pushed_at"),
                            _row_val(old_r, "answered_at"),
                            old_r["created_at"],
                            old_r["updated_at"],
                            _row_val(old_r, "source"),
                        ),
                    )
                else:
                    conn.execute(
                        """
                        INSERT INTO followups
                            (device_id, child_id, strategy, topic, lang,
                             source_message_id, due_at, status, outcome, note,
                             outcome_fact_id, pushed_at, answered_at, created_at,
                             updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            new_device,
                            new_cid,
                            strategy_text,
                            topic,
                            _row_val(old_r, "lang", "ar"),
                            _row_val(old_r, "source_message_id"),
                            old_r["due_at"],
                            old_r["status"],
                            _row_val(old_r, "outcome"),
                            _row_val(old_r, "note"),
                            _row_val(old_r, "outcome_fact_id"),
                            _row_val(old_r, "pushed_at"),
                            _row_val(old_r, "answered_at"),
                            old_r["created_at"],
                            old_r["updated_at"],
                        ),
                    )
                memory_touched = True
            elif old_r["status"] != "pending" and existing["status"] == "pending":
                conn.execute(
                    """
                    UPDATE followups
                    SET status = ?,
                        outcome = COALESCE(outcome, ?),
                        note = COALESCE(note, ?),
                        answered_at = COALESCE(answered_at, ?),
                        updated_at = MAX(COALESCE(updated_at, ''), COALESCE(?, ''))
                    WHERE id = ?
                    """,
                    (
                        old_r["status"],
                        _row_val(old_r, "outcome"),
                        _row_val(old_r, "note"),
                        _row_val(old_r, "answered_at"),
                        _row_val(old_r, "updated_at"),
                        existing["id"],
                    ),
                )
                memory_touched = True

    # 6. program_children — PRIMARY KEY (child_id)
    if _table_exists(conn, "program_children") and new_cid > 0:
        old_r = conn.execute(
            "SELECT * FROM program_children WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchone()
        if old_r is not None:
            conn.execute(
                """
                INSERT INTO program_children (child_id, device_id, reached_puberty, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(child_id) DO UPDATE SET
                    device_id = excluded.device_id,
                    reached_puberty = MAX(COALESCE(program_children.reached_puberty, 0),
                                          COALESCE(excluded.reached_puberty, 0)),
                    updated_at = MAX(COALESCE(program_children.updated_at, ''),
                                     COALESCE(excluded.updated_at, ''))
                """,
                (
                    new_cid,
                    new_device,
                    _row_val(old_r, "reached_puberty", 0),
                    _row_val(old_r, "updated_at"),
                ),
            )

    # 7. ramadan_fasting — UNIQUE(child_id, hijri_year)
    if _table_exists(conn, "ramadan_fasting") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM ramadan_fasting WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            conn.execute(
                """
                INSERT INTO ramadan_fasting (device_id, child_id, hijri_year, step_key, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(child_id, hijri_year) DO UPDATE SET
                    step_key = COALESCE(ramadan_fasting.step_key, excluded.step_key),
                    updated_at = MAX(COALESCE(ramadan_fasting.updated_at, ''),
                                     COALESCE(excluded.updated_at, ''))
                """,
                (
                    new_device,
                    new_cid,
                    old_r["hijri_year"],
                    _row_val(old_r, "step_key"),
                    _row_val(old_r, "updated_at"),
                ),
            )

    # 8. ramadan_marks — UNIQUE(device_id, child_id, hijri_year, day, mark)
    if _table_exists(conn, "ramadan_marks"):
        old_rows = conn.execute(
            "SELECT * FROM ramadan_marks WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            conn.execute(
                """
                INSERT OR IGNORE INTO ramadan_marks
                    (device_id, child_id, hijri_year, day, mark, value, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_device,
                    new_cid,
                    old_r["hijri_year"],
                    old_r["day"],
                    old_r["mark"],
                    _row_val(old_r, "value"),
                    old_r["created_at"],
                ),
            )

    # 9. prayer_journeys — ux_prayer_journeys_active ON (child_id) WHERE status = 'active'
    if _table_exists(conn, "prayer_journeys") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM prayer_journeys WHERE device_id = ? AND child_id = ? ORDER BY id ASC",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            if old_r["status"] == "active":
                new_active = conn.execute(
                    "SELECT * FROM prayer_journeys WHERE child_id = ? AND status = 'active'",
                    (new_cid,),
                ).fetchone()
                if new_active is None:
                    conn.execute(
                        """
                        INSERT INTO prayer_journeys
                            (device_id, child_id, track, stage, status,
                             started_on, stage_started_on, ended_on, created_at, updated_at)
                        VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?)
                        """,
                        (
                            new_device,
                            new_cid,
                            old_r["track"],
                            _row_val(old_r, "stage"),
                            old_r["started_on"],
                            _row_val(old_r, "stage_started_on"),
                            _row_val(old_r, "ended_on"),
                            old_r["created_at"],
                            old_r["updated_at"],
                        ),
                    )
                else:
                    old_key = (
                        _PRAYER_TRACK_RANK.get(_row_val(old_r, "track") or "", 0),
                        _row_val(old_r, "stage") or 0,
                    )
                    new_key = (
                        _PRAYER_TRACK_RANK.get(_row_val(new_active, "track") or "", 0),
                        _row_val(new_active, "stage") or 0,
                    )
                    if old_key > new_key:
                        conn.execute(
                            """
                            UPDATE prayer_journeys
                            SET status = 'ended', ended_on = COALESCE(ended_on, date('now'))
                            WHERE id = ?
                            """,
                            (new_active["id"],),
                        )
                        conn.execute(
                            """
                            INSERT INTO prayer_journeys
                                (device_id, child_id, track, stage, status,
                                 started_on, stage_started_on, ended_on, created_at, updated_at)
                            VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?)
                            """,
                            (
                                new_device,
                                new_cid,
                                old_r["track"],
                                _row_val(old_r, "stage"),
                                old_r["started_on"],
                                _row_val(old_r, "stage_started_on"),
                                _row_val(old_r, "ended_on"),
                                old_r["created_at"],
                                old_r["updated_at"],
                            ),
                        )
            else:
                exists_hist = conn.execute(
                    """
                    SELECT 1 FROM prayer_journeys
                    WHERE device_id = ? AND child_id = ? AND track = ?
                      AND COALESCE(stage, -1) = COALESCE(?, -1)
                      AND status = ? AND started_on = ?
                    """,
                    (
                        new_device,
                        new_cid,
                        old_r["track"],
                        _row_val(old_r, "stage"),
                        old_r["status"],
                        old_r["started_on"],
                    ),
                ).fetchone()
                if exists_hist is None:
                    conn.execute(
                        """
                        INSERT INTO prayer_journeys
                            (device_id, child_id, track, stage, status,
                             started_on, stage_started_on, ended_on, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            new_device,
                            new_cid,
                            old_r["track"],
                            _row_val(old_r, "stage"),
                            old_r["status"],
                            old_r["started_on"],
                            _row_val(old_r, "stage_started_on"),
                            _row_val(old_r, "ended_on"),
                            old_r["created_at"],
                            old_r["updated_at"],
                        ),
                    )

    # 10. milestone_alerts — UNIQUE(child_id, alert_key)
    if _table_exists(conn, "milestone_alerts") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM milestone_alerts WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            conn.execute(
                """
                INSERT INTO milestone_alerts
                    (device_id, child_id, alert_key, milestone_key, status, claimed_at, sent_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(child_id, alert_key) DO UPDATE SET
                    status = CASE
                        WHEN milestone_alerts.status = 'sent' OR excluded.status = 'sent' THEN 'sent'
                        ELSE milestone_alerts.status
                    END,
                    sent_at = COALESCE(milestone_alerts.sent_at, excluded.sent_at)
                """,
                (
                    new_device,
                    new_cid,
                    old_r["alert_key"],
                    old_r["milestone_key"],
                    old_r["status"],
                    old_r["claimed_at"],
                    _row_val(old_r, "sent_at"),
                ),
            )

    # 11. child_challenges — ux_child_challenges_active ON (device_id, child_id) WHERE status = 'active'
    if _table_exists(conn, "child_challenges") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM child_challenges WHERE device_id = ? AND child_id = ? ORDER BY id ASC",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            existing = conn.execute(
                """
                SELECT * FROM child_challenges
                WHERE device_id = ? AND child_id = ?
                  AND challenge_key = ? AND started_at = ?
                """,
                (new_device, new_cid, old_r["challenge_key"], old_r["started_at"]),
            ).fetchone()
            if existing is not None:
                if old_r["status"] == "resolved" and existing["status"] != "resolved":
                    conn.execute(
                        """
                        UPDATE child_challenges
                        SET status = 'resolved',
                            resolved_at = COALESCE(resolved_at, ?, datetime('now'))
                        WHERE id = ?
                        """,
                        (_row_val(old_r, "resolved_at"), existing["id"]),
                    )
                continue

            status_to_insert = old_r["status"]
            resolved_at_to_insert = _row_val(old_r, "resolved_at")
            if status_to_insert == "active":
                new_active = conn.execute(
                    """
                    SELECT id FROM child_challenges
                    WHERE device_id = ? AND child_id = ? AND status = 'active'
                    """,
                    (new_device, new_cid),
                ).fetchone()
                if new_active is not None:
                    status_to_insert = "resolved"
                    if not resolved_at_to_insert:
                        resolved_at_to_insert = conn.execute("SELECT datetime('now')").fetchone()[0]
            conn.execute(
                """
                INSERT INTO child_challenges
                    (device_id, child_id, challenge_key, topic, domain,
                     status, note, started_at, resolved_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_device,
                    new_cid,
                    old_r["challenge_key"],
                    old_r["topic"],
                    _row_val(old_r, "domain"),
                    status_to_insert,
                    _row_val(old_r, "note"),
                    old_r["started_at"],
                    resolved_at_to_insert,
                ),
            )

    # 12. child_daily_routines + routine_events — UNIQUE(device_id, child_id, routine_date)
    if _table_exists(conn, "child_daily_routines") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM child_daily_routines WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            new_r = conn.execute(
                """
                SELECT * FROM child_daily_routines
                WHERE device_id = ? AND child_id = ? AND routine_date = ?
                """,
                (new_device, new_cid, old_r["routine_date"]),
            ).fetchone()
            if new_r is None:
                cur = conn.execute(
                    """
                    INSERT INTO child_daily_routines
                        (device_id, child_id, routine_date, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        new_cid,
                        old_r["routine_date"],
                        old_r["created_at"],
                        old_r["updated_at"],
                    ),
                )
                target_routine_id = cur.lastrowid
            else:
                target_routine_id = new_r["id"]

            if _table_exists(conn, "routine_events"):
                events = conn.execute(
                    "SELECT * FROM routine_events WHERE routine_id = ? ORDER BY id ASC",
                    (old_r["id"],),
                ).fetchall()
                for ev in events:
                    ev_exists = conn.execute(
                        """
                        SELECT 1 FROM routine_events
                        WHERE routine_id = ? AND event_type = ? AND started_at = ?
                        """,
                        (target_routine_id, ev["event_type"], ev["started_at"]),
                    ).fetchone()
                    if ev_exists is None:
                        conn.execute(
                            """
                            INSERT INTO routine_events
                                (routine_id, event_type, started_at, ended_at,
                                 feed_type, amount_ml, side, diaper_type, notes,
                                 source, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                target_routine_id,
                                ev["event_type"],
                                ev["started_at"],
                                _row_val(ev, "ended_at"),
                                _row_val(ev, "feed_type"),
                                _row_val(ev, "amount_ml"),
                                _row_val(ev, "side"),
                                _row_val(ev, "diaper_type"),
                                _row_val(ev, "notes"),
                                _row_val(ev, "source", "manual"),
                                ev["created_at"],
                                ev["updated_at"],
                            ),
                        )

    # 13. daily_login_streaks — UNIQUE(device_id, child_id, date)
    if _table_exists(conn, "daily_login_streaks"):
        old_rows = conn.execute(
            "SELECT * FROM daily_login_streaks WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            conn.execute(
                """
                INSERT OR IGNORE INTO daily_login_streaks
                    (device_id, child_id, date, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (new_device, new_cid, old_r["date"], old_r["created_at"]),
            )

    # 14. habit_templates (UNIQUE(child_id, custom_name)) & habits_value_events
    if _table_exists(conn, "habit_templates") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM habit_templates WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            conn.execute(
                """
                INSERT OR IGNORE INTO habit_templates
                    (device_id, child_id, category, custom_name, is_active, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_device,
                    new_cid,
                    old_r["category"],
                    old_r["custom_name"],
                    _row_val(old_r, "is_active", 1),
                    old_r["created_at"],
                    old_r["updated_at"],
                ),
            )

    if _table_exists(conn, "habits_value_events") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM habits_value_events WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            ev_exists = conn.execute(
                """
                SELECT 1 FROM habits_value_events
                WHERE device_id = ? AND child_id = ?
                  AND category = ? AND habit_name = ?
                  AND status = ? AND device_timestamp = ?
                """,
                (
                    new_device,
                    new_cid,
                    old_r["category"],
                    old_r["habit_name"],
                    old_r["status"],
                    old_r["device_timestamp"],
                ),
            ).fetchone()
            if ev_exists is None:
                conn.execute(
                    """
                    INSERT INTO habits_value_events
                        (device_id, child_id, category, habit_name, status,
                         submitted_by, device_timestamp, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        new_cid,
                        old_r["category"],
                        old_r["habit_name"],
                        old_r["status"],
                        _row_val(old_r, "submitted_by", "parent"),
                        old_r["device_timestamp"],
                        old_r["created_at"],
                        old_r["updated_at"],
                    ),
                )

    # 15. child_missions — UNIQUE(child_id, local_date, mission_key)
    if _table_exists(conn, "child_missions") and new_cid > 0:
        mission_cols = _table_cols(conn, "child_missions")
        has_source = "source" in mission_cols
        old_rows = conn.execute(
            "SELECT * FROM child_missions WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            new_r = conn.execute(
                """
                SELECT * FROM child_missions
                WHERE child_id = ? AND local_date = ? AND mission_key = ?
                """,
                (new_cid, old_r["local_date"], old_r["mission_key"]),
            ).fetchone()
            if new_r is None:
                if has_source:
                    conn.execute(
                        """
                        INSERT INTO child_missions
                            (device_id, child_id, mission_key, local_date, status,
                             assigned_at, claimed_at, confirmed_at, parent_note, source)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            new_device,
                            new_cid,
                            old_r["mission_key"],
                            old_r["local_date"],
                            old_r["status"],
                            old_r["assigned_at"],
                            _row_val(old_r, "claimed_at"),
                            _row_val(old_r, "confirmed_at"),
                            _row_val(old_r, "parent_note"),
                            _row_val(old_r, "source"),
                        ),
                    )
                else:
                    conn.execute(
                        """
                        INSERT INTO child_missions
                            (device_id, child_id, mission_key, local_date, status,
                             assigned_at, claimed_at, confirmed_at, parent_note)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            new_device,
                            new_cid,
                            old_r["mission_key"],
                            old_r["local_date"],
                            old_r["status"],
                            old_r["assigned_at"],
                            _row_val(old_r, "claimed_at"),
                            _row_val(old_r, "confirmed_at"),
                            _row_val(old_r, "parent_note"),
                        ),
                    )
            else:
                old_rank = _MISSION_STATUS_RANK.get(old_r["status"] or "", 0)
                new_rank = _MISSION_STATUS_RANK.get(new_r["status"] or "", 0)
                best_status = old_r["status"] if old_rank > new_rank else new_r["status"]
                if has_source:
                    conn.execute(
                        """
                        UPDATE child_missions
                        SET status = ?,
                            claimed_at = COALESCE(claimed_at, ?),
                            confirmed_at = COALESCE(confirmed_at, ?),
                            parent_note = COALESCE(parent_note, ?),
                            source = COALESCE(source, ?)
                        WHERE id = ?
                        """,
                        (
                            best_status,
                            _row_val(old_r, "claimed_at"),
                            _row_val(old_r, "confirmed_at"),
                            _row_val(old_r, "parent_note"),
                            _row_val(old_r, "source"),
                            new_r["id"],
                        ),
                    )
                else:
                    conn.execute(
                        """
                        UPDATE child_missions
                        SET status = ?,
                            claimed_at = COALESCE(claimed_at, ?),
                            confirmed_at = COALESCE(confirmed_at, ?),
                            parent_note = COALESCE(parent_note, ?)
                        WHERE id = ?
                        """,
                        (
                            best_status,
                            _row_val(old_r, "claimed_at"),
                            _row_val(old_r, "confirmed_at"),
                            _row_val(old_r, "parent_note"),
                            new_r["id"],
                        ),
                    )

    # 16. child_licences (UNIQUE(child_id, level_key)) & child_scenario_answers
    if _table_exists(conn, "child_licences") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM child_licences WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            new_r = conn.execute(
                "SELECT * FROM child_licences WHERE child_id = ? AND level_key = ?",
                (new_cid, old_r["level_key"]),
            ).fetchone()
            if new_r is None:
                conn.execute(
                    """
                    INSERT INTO child_licences
                        (device_id, child_id, level_key, status,
                         granted_at, talked_at, next_review_date, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        new_cid,
                        old_r["level_key"],
                        old_r["status"],
                        _row_val(old_r, "granted_at"),
                        _row_val(old_r, "talked_at"),
                        _row_val(old_r, "next_review_date"),
                        old_r["created_at"],
                    ),
                )
            else:
                old_rank = _LICENCE_STATUS_RANK.get(old_r["status"] or "", 0)
                new_rank = _LICENCE_STATUS_RANK.get(new_r["status"] or "", 0)
                best_status = old_r["status"] if old_rank > new_rank else new_r["status"]
                conn.execute(
                    """
                    UPDATE child_licences
                    SET status = ?,
                        granted_at = COALESCE(granted_at, ?),
                        talked_at = COALESCE(talked_at, ?),
                        next_review_date = COALESCE(next_review_date, ?)
                    WHERE id = ?
                    """,
                    (
                        best_status,
                        _row_val(old_r, "granted_at"),
                        _row_val(old_r, "talked_at"),
                        _row_val(old_r, "next_review_date"),
                        new_r["id"],
                    ),
                )

    if _table_exists(conn, "child_scenario_answers") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM child_scenario_answers WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            ans_exists = conn.execute(
                """
                SELECT 1 FROM child_scenario_answers
                WHERE device_id = ? AND child_id = ?
                  AND scenario_key = ? AND answered_at = ? AND attempt = ?
                """,
                (
                    new_device,
                    new_cid,
                    old_r["scenario_key"],
                    old_r["answered_at"],
                    old_r["attempt"],
                ),
            ).fetchone()
            if ans_exists is None:
                conn.execute(
                    """
                    INSERT INTO child_scenario_answers
                        (device_id, child_id, scenario_key, level_key, choice_key,
                         outcome, attempt, answered_at, parent_alerted_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        new_cid,
                        old_r["scenario_key"],
                        old_r["level_key"],
                        old_r["choice_key"],
                        old_r["outcome"],
                        old_r["attempt"],
                        old_r["answered_at"],
                        _row_val(old_r, "parent_alerted_at"),
                    ),
                )

    # 17. family_agreements + agreement_clauses & child_screen_sessions
    if _table_exists(conn, "family_agreements") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM family_agreements WHERE device_id = ? AND child_id = ? ORDER BY id ASC",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            existing = conn.execute(
                """
                SELECT * FROM family_agreements
                WHERE device_id = ? AND child_id = ?
                  AND version = ? AND created_at = ?
                """,
                (new_device, new_cid, old_r["version"], old_r["created_at"]),
            ).fetchone()
            if existing is not None:
                continue
            status_to_insert = old_r["status"]
            if status_to_insert == "active":
                new_active = conn.execute(
                    """
                    SELECT id FROM family_agreements
                    WHERE device_id = ? AND child_id = ? AND status = 'active'
                    """,
                    (new_device, new_cid),
                ).fetchone()
                if new_active is not None:
                    status_to_insert = "archived"
            cur = conn.execute(
                """
                INSERT INTO family_agreements
                    (device_id, child_id, version, status,
                     signed_by_parent_at, signed_by_child_at, next_review_date, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_device,
                    new_cid,
                    old_r["version"],
                    status_to_insert,
                    _row_val(old_r, "signed_by_parent_at"),
                    _row_val(old_r, "signed_by_child_at"),
                    _row_val(old_r, "next_review_date"),
                    old_r["created_at"],
                ),
            )
            new_ag_id = cur.lastrowid
            if _table_exists(conn, "agreement_clauses"):
                clauses = conn.execute(
                    "SELECT * FROM agreement_clauses WHERE agreement_id = ? ORDER BY id ASC",
                    (old_r["id"],),
                ).fetchall()
                for cl in clauses:
                    conn.execute(
                        """
                        INSERT INTO agreement_clauses
                            (agreement_id, applies_to, clause_key, text_ar,
                             is_custom, sort_order, acknowledged_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            new_ag_id,
                            cl["applies_to"],
                            _row_val(cl, "clause_key"),
                            cl["text_ar"],
                            _row_val(cl, "is_custom", 0),
                            _row_val(cl, "sort_order", 0),
                            _row_val(cl, "acknowledged_at"),
                        ),
                    )

    if _table_exists(conn, "child_screen_sessions") and new_cid > 0:
        old_rows = conn.execute(
            "SELECT * FROM child_screen_sessions WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            sess_exists = conn.execute(
                """
                SELECT id FROM child_screen_sessions
                WHERE device_id = ? AND child_id = ?
                  AND surface = ? AND started_at = ?
                """,
                (new_device, new_cid, old_r["surface"], old_r["started_at"]),
            ).fetchone()
            if sess_exists is None:
                conn.execute(
                    """
                    INSERT INTO child_screen_sessions
                        (device_id, child_id, surface, local_date, tz_offset_minutes,
                         started_at, last_heartbeat_at, ended_at, ended_reason,
                         counted_seconds, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        new_cid,
                        old_r["surface"],
                        old_r["local_date"],
                        old_r["tz_offset_minutes"],
                        old_r["started_at"],
                        old_r["last_heartbeat_at"],
                        _row_val(old_r, "ended_at"),
                        _row_val(old_r, "ended_reason"),
                        old_r["counted_seconds"],
                        old_r["created_at"],
                    ),
                )

    # 18. coach_tips — UNIQUE(device_id, child_id, date)
    if _table_exists(conn, "coach_tips") and new_cid > 0:
        tip_cols = _table_cols(conn, "coach_tips")
        has_lang = "lang" in tip_cols
        old_rows = conn.execute(
            "SELECT * FROM coach_tips WHERE device_id = ? AND child_id = ?",
            (old_device, old_cid),
        ).fetchall()
        for old_r in old_rows:
            new_r = conn.execute(
                "SELECT * FROM coach_tips WHERE device_id = ? AND child_id = ? AND date = ?",
                (new_device, new_cid, old_r["date"]),
            ).fetchone()
            if new_r is None:
                if has_lang:
                    conn.execute(
                        """
                        INSERT INTO coach_tips
                            (device_id, child_id, date, domain, text, source,
                             shown_at, tapped_at, created_at, lang)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            new_device,
                            new_cid,
                            old_r["date"],
                            _row_val(old_r, "domain"),
                            old_r["text"],
                            _row_val(old_r, "source", "fallback"),
                            _row_val(old_r, "shown_at"),
                            _row_val(old_r, "tapped_at"),
                            old_r["created_at"],
                            _row_val(old_r, "lang"),
                        ),
                    )
                else:
                    conn.execute(
                        """
                        INSERT INTO coach_tips
                            (device_id, child_id, date, domain, text, source,
                             shown_at, tapped_at, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            new_device,
                            new_cid,
                            old_r["date"],
                            _row_val(old_r, "domain"),
                            old_r["text"],
                            _row_val(old_r, "source", "fallback"),
                            _row_val(old_r, "shown_at"),
                            _row_val(old_r, "tapped_at"),
                            old_r["created_at"],
                        ),
                    )
            elif _row_val(old_r, "tapped_at") and not _row_val(new_r, "tapped_at"):
                if has_lang:
                    conn.execute(
                        """
                        UPDATE coach_tips
                        SET domain = ?, text = ?, source = ?, shown_at = ?, tapped_at = ?, lang = ?
                        WHERE id = ?
                        """,
                        (
                            _row_val(old_r, "domain"),
                            _row_val(old_r, "text"),
                            _row_val(old_r, "source"),
                            _row_val(old_r, "shown_at"),
                            _row_val(old_r, "tapped_at"),
                            _row_val(old_r, "lang"),
                            new_r["id"],
                        ),
                    )
                else:
                    conn.execute(
                        """
                        UPDATE coach_tips
                        SET domain = ?, text = ?, source = ?, shown_at = ?, tapped_at = ?
                        WHERE id = ?
                        """,
                        (
                            _row_val(old_r, "domain"),
                            _row_val(old_r, "text"),
                            _row_val(old_r, "source"),
                            _row_val(old_r, "shown_at"),
                            _row_val(old_r, "tapped_at"),
                            new_r["id"],
                        ),
                    )

    return memory_touched


def _sync_device_scoped_rows(conn, old_device: str, new_device: str) -> None:
    """Idempotently and non-destructively copy/merge device-level settings and
    family-level (`child_id = 0`) rows from `old_device` to `new_device` without
    wiping or stealing `old_device`'s rows."""
    if old_device == new_device:
        return

    # Sync family-level (`child_id = 0`) marks/lessons/streaks
    _sync_child_scoped_rows(conn, old_device, 0, new_device, 0)

    # child_memory_settings — PRIMARY KEY (device_id)
    if _table_exists(conn, "child_memory_settings"):
        old_s = conn.execute(
            "SELECT * FROM child_memory_settings WHERE device_id = ?",
            (old_device,),
        ).fetchone()
        new_s = conn.execute(
            "SELECT * FROM child_memory_settings WHERE device_id = ?",
            (new_device,),
        ).fetchone()
        if old_s is not None:
            if new_s is None:
                conn.execute(
                    """
                    INSERT INTO child_memory_settings
                        (device_id, enabled, generation, tz_offset_minutes, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        old_s["enabled"],
                        old_s["generation"],
                        _row_val(old_s, "tz_offset_minutes"),
                        old_s["updated_at"],
                    ),
                )
            else:
                enabled = 0 if old_s["enabled"] == 0 else new_s["enabled"]
                generation = max(new_s["generation"] or 0, old_s["generation"] or 0)
                tz = (
                    new_s["tz_offset_minutes"]
                    if new_s["tz_offset_minutes"] is not None
                    else old_s["tz_offset_minutes"]
                )
                conn.execute(
                    """
                    UPDATE child_memory_settings
                    SET enabled = ?, generation = ?, tz_offset_minutes = ?
                    WHERE device_id = ?
                    """,
                    (enabled, generation, tz, new_device),
                )

    # program_settings — PRIMARY KEY (device_id)
    if _table_exists(conn, "program_settings"):
        old_p = conn.execute(
            "SELECT * FROM program_settings WHERE device_id = ?",
            (old_device,),
        ).fetchone()
        new_p = conn.execute(
            "SELECT * FROM program_settings WHERE device_id = ?",
            (new_device,),
        ).fetchone()
        if old_p is not None:
            if new_p is None:
                conn.execute(
                    """
                    INSERT INTO program_settings
                        (device_id, tz_offset_minutes, lang, ramadan_year,
                         ramadan_shift_days, ramadan_days, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        new_device,
                        _row_val(old_p, "tz_offset_minutes"),
                        _row_val(old_p, "lang"),
                        _row_val(old_p, "ramadan_year"),
                        _row_val(old_p, "ramadan_shift_days", 0),
                        _row_val(old_p, "ramadan_days"),
                        old_p["updated_at"],
                    ),
                )
            else:
                shift = (
                    old_p["ramadan_shift_days"]
                    if (new_p["ramadan_shift_days"] or 0) == 0
                    and (old_p["ramadan_shift_days"] or 0) != 0
                    else (new_p["ramadan_shift_days"] or 0)
                )
                conn.execute(
                    """
                    UPDATE program_settings
                    SET tz_offset_minutes = COALESCE(tz_offset_minutes, ?),
                        lang = COALESCE(lang, ?),
                        ramadan_year = COALESCE(ramadan_year, ?),
                        ramadan_shift_days = ?,
                        ramadan_days = COALESCE(ramadan_days, ?)
                    WHERE device_id = ?
                    """,
                    (
                        _row_val(old_p, "tz_offset_minutes"),
                        _row_val(old_p, "lang"),
                        _row_val(old_p, "ramadan_year"),
                        shift,
                        _row_val(old_p, "ramadan_days"),
                        new_device,
                    ),
                )


def _merge_legacy_device_data(conn, current_device_id: str, google_id: str) -> None:
    """Safely copy/merge children and progress from confirmed devices linked to
    the same Google account onto `current_device_id`.

    Invariants:
      1. Confirmed-only (`confirmed = 1` on BOTH `current_device_id` and
         `old_device`): an unconfirmed link (`confirmed = 0`) never pulls data
         from another device and is never pulled from — not even child names.
      2. Non-destructive & idempotent across multi-phone parents: never deletes
         or moves ownership away from `old_device`, so two phones belonging to
         the same parent never pull data back and forth on repeated links.
      3. Never deletes or overwrites any child on `current_device_id`: matching
         children (by normalized name) merge progress into the existing child;
         non-matching children are inserted alongside existing children.
      4. Atomic & production-schema safe: runs inside a single `BEGIN IMMEDIATE`
         transaction with full rollback on error, checking table and column
         existence against the live schema.
    """
    if not _table_exists(conn, "identity_links") or not _table_exists(conn, "child_profiles"):
        return
    if "confirmed" not in _table_cols(conn, "identity_links"):
        return

    caller_link = conn.execute(
        "SELECT confirmed FROM identity_links WHERE device_id = ? AND google_id = ?",
        (current_device_id, google_id),
    ).fetchone()
    if not caller_link or int(caller_link["confirmed"] or 0) != 1:
        return

    old_links = conn.execute(
        """
        SELECT device_id FROM identity_links
        WHERE google_id = ? AND device_id != ? AND COALESCE(confirmed, 0) = 1
        ORDER BY linked_at ASC, rowid ASC
        """,
        (google_id, current_device_id),
    ).fetchall()
    if not old_links:
        return

    if conn.in_transaction:
        conn.commit()

    conn.execute("BEGIN IMMEDIATE")
    try:
        profile_cols = _table_cols(conn, "child_profiles")
        has_birth_month = "birth_month" in profile_cols

        for old_link in old_links:
            old_device = old_link["device_id"]
            old_children = conn.execute(
                "SELECT * FROM child_profiles WHERE device_id = ? ORDER BY id ASC",
                (old_device,),
            ).fetchall()
            new_children = list(
                conn.execute(
                    "SELECT * FROM child_profiles WHERE device_id = ? ORDER BY id ASC",
                    (current_device_id,),
                ).fetchall()
            )

            _sync_device_scoped_rows(conn, old_device, current_device_id)

            if not old_children:
                continue

            # A child the parent erased on this phone is not brought back from
            # the other phone's copy — not even onto a child of the same name
            # added again here. A child created there after the erase is new.
            old_children = [
                c for c in old_children
                if not tombs.covers(_row_val(c, "created_at"), tombs.since(
                    conn, current_device_id, "child", tombs.child_key(c["name"])))
            ]
            if not old_children:
                continue

            claimed_new_ids: set[int] = set()
            child_id_map: dict[int, int] = {}

            for old_c in old_children:
                old_name = (old_c["name"] or "").strip().lower()
                old_age = (old_c["age_group"] or "").strip()

                # First try exact (name, age_group) match, then fallback to exact name match.
                # Never match by age_group alone and never overwrite a child with a different name.
                matching_new = None
                if old_name:
                    matching_new = next(
                        (
                            nc
                            for nc in new_children
                            if nc["id"] not in claimed_new_ids
                            and (nc["name"] or "").strip().lower() == old_name
                            and (nc["age_group"] or "").strip() == old_age
                        ),
                        None,
                    )
                    if matching_new is None:
                        matching_new = next(
                            (
                                nc
                                for nc in new_children
                                if nc["id"] not in claimed_new_ids
                                and (nc["name"] or "").strip().lower() == old_name
                            ),
                            None,
                        )

                if matching_new is not None:
                    target_cid = matching_new["id"]
                    claimed_new_ids.add(target_cid)
                    child_id_map[old_c["id"]] = target_cid
                    if has_birth_month:
                        conn.execute(
                            """
                            UPDATE child_profiles
                            SET gender = COALESCE(gender, ?),
                                avatar_emoji = COALESCE(avatar_emoji, ?),
                                birth_month = COALESCE(birth_month, ?)
                            WHERE id = ? AND device_id = ?
                            """,
                            (
                                _row_val(old_c, "gender"),
                                _row_val(old_c, "avatar_emoji"),
                                _row_val(old_c, "birth_month"),
                                target_cid,
                                current_device_id,
                            ),
                        )
                    else:
                        conn.execute(
                            """
                            UPDATE child_profiles
                            SET gender = COALESCE(gender, ?),
                                avatar_emoji = COALESCE(avatar_emoji, ?)
                            WHERE id = ? AND device_id = ?
                            """,
                            (
                                _row_val(old_c, "gender"),
                                _row_val(old_c, "avatar_emoji"),
                                target_cid,
                                current_device_id,
                            ),
                        )
                else:
                    if has_birth_month:
                        cur = conn.execute(
                            """
                            INSERT INTO child_profiles
                                (device_id, name, age_group, gender, avatar_emoji,
                                 birth_month, created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                current_device_id,
                                old_c["name"],
                                old_c["age_group"],
                                _row_val(old_c, "gender"),
                                _row_val(old_c, "avatar_emoji"),
                                _row_val(old_c, "birth_month"),
                                old_c["created_at"],
                                old_c["updated_at"],
                            ),
                        )
                    else:
                        cur = conn.execute(
                            """
                            INSERT INTO child_profiles
                                (device_id, name, age_group, gender, avatar_emoji,
                                 created_at, updated_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                current_device_id,
                                old_c["name"],
                                old_c["age_group"],
                                _row_val(old_c, "gender"),
                                _row_val(old_c, "avatar_emoji"),
                                old_c["created_at"],
                                old_c["updated_at"],
                            ),
                        )
                    target_cid = cur.lastrowid
                    claimed_new_ids.add(target_cid)
                    child_id_map[old_c["id"]] = target_cid

            # Build family sibling-order mappings for re-lettering `الطفل أ/ب/...`
            old_mapped_before = [(child_id_map[c["id"]], c["name"]) for c in old_children]
            old_fam = _to_family(old_mapped_before)
            after_fam = family_from_conn(conn, current_device_id)

            relettered_or_copied_memory = False
            for old_c in old_children:
                target_cid = child_id_map[old_c["id"]]
                if _sync_child_scoped_rows(
                    conn,
                    old_device,
                    old_c["id"],
                    current_device_id,
                    target_cid,
                    old_fam=old_fam,
                    after_fam=after_fam,
                ):
                    relettered_or_copied_memory = True

            if (
                relettered_or_copied_memory
                and old_fam.members
                and old_fam.members != after_fam.members
                and _table_exists(conn, "child_memory_settings")
            ):
                conn.execute(
                    "UPDATE child_memory_settings SET generation = generation + 1 WHERE device_id = ?",
                    (current_device_id,),
                )

        conn.commit()
    except Exception:
        conn.rollback()
        raise
