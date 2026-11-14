"""Dual-parent family account service (م٣ / 1.3).

Security invariants:
  1. Hard gate: family sharing requires BOTH FAMILY_SHARING_ENABLED=1 AND
     SESSION_MINT_ENFORCE=1 ("لا مشاركة فوق هوية غير مقفولة").
  2. Dual-phone ownership proof: pairing, reconfirming, leaving, and
     deletion-confirmation routes require a proven, non-bare, cooldown-free
     device session (require_device_proof_irreversible + mint_kind check).
  3. Unvouched push-token change on either phone suspends that phone's
     membership (`confirmed = 0`) until re-confirmed on its new token.
  4. Never expose any `device_id` in API payloads; never sync child memory
     without a proven session; deletions never cross to a partner's phone
     without explicit confirmation on that partner's proven phone.
"""
from __future__ import annotations

import hashlib
import os
import re
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.db.init_db import get_conn
from app.routers import identity, privacy
from app.services import conversation_store as store
from app.services import device_twins, merge_tombstones as tombs

INVITE_TTL_MINUTES = 15
MAX_FAMILY_MEMBERS = 2
VALID_ROLES = ("parent", "mother", "father")
_INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_INVITE_LEN = 8
_TRUTHY = frozenset({"1", "true", "yes", "on"})


class FamilyError(Exception):
    """Domain error mapped cleanly by routers/families.py."""

    def __init__(self, status_code: int, code: str, message: str, message_en: str) -> None:
        super().__init__(code)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.message_en = message_en


def family_sharing_enabled() -> bool:
    """Enabled ONLY when FAMILY_SHARING_ENABLED=1 AND SESSION_MINT_ENFORCE=1."""
    flag = os.environ.get("FAMILY_SHARING_ENABLED", "").strip().lower() in _TRUTHY
    return bool(flag and device_twins.session_mint_enforced())


def session_eligible_for_family(token: Optional[str]) -> bool:
    """True when the bearer token is non-bare and post-v37 (`new`/`proof`/`restore`)."""
    if not token or store.token_is_bare(token):
        return False
    return store.token_mint_kind(token) in ("new", "proof", "restore")


def suspend_device_family_membership(conn: sqlite3.Connection, device_id: str) -> int:
    """An unvouched push-token change suspends confirmed membership until reconfirmed."""
    try:
        cur = conn.execute(
            "UPDATE family_members SET confirmed = 0, updated_at = datetime('now') "
            "WHERE device_id = ? AND confirmed = 1",
            (device_id,),
        )
        return cur.rowcount
    except sqlite3.Error:
        return 0


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _fmt_dt(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def _fmt_iso_z(ts: str) -> str:
    return ts.replace(" ", "T") + ("Z" if not ts.endswith("Z") else "")


def _clean_role(role_label: Optional[str]) -> str:
    val = (role_label or "parent").strip().lower()
    if val not in VALID_ROLES:
        raise FamilyError(
            422,
            "invalid_role",
            "اختر صفة صالحة (أم / أب / ولي أمر).",
            "Choose a valid role (mother, father, or parent).",
        )
    return val


def _clean_name(display_name: Optional[str]) -> Optional[str]:
    cleaned = " ".join((display_name or "").split()).strip()
    return cleaned[:40] if cleaned else None


def _normalize_code(raw: Optional[str]) -> str:
    return re.sub(r"[^A-Z0-9]", "", (raw or "").upper())


def _hash_code(normalized: str) -> str:
    return hashlib.sha256(f"tg_fam:{normalized}".encode("utf-8")).hexdigest()


def _generate_code() -> tuple[str, str]:
    raw = "".join(secrets.choice(_INVITE_ALPHABET) for _ in range(_INVITE_LEN))
    return f"{raw[:4]}-{raw[4:]}", _hash_code(raw)


def _member_payload(row: sqlite3.Row) -> dict:
    return {
        "role": row["role_label"],
        "display_name": row["display_name"],
        "confirmed": bool(row["confirmed"]),
        "joined_at": row["joined_at"],
    }


def _active_partner_row(conn: sqlite3.Connection, family_id: int, device_id: str) -> Optional[sqlite3.Row]:
    return conn.execute(
        """
        SELECT * FROM family_members
        WHERE family_id = ? AND device_id != ? AND status = 'active'
        ORDER BY id ASC LIMIT 1
        """,
        (family_id, device_id),
    ).fetchone()


def sync_pair_between_devices(
    conn: sqlite3.Connection,
    dev_a: str,
    dev_b: str,
    *,
    include_memory_for_a: bool,
    include_memory_for_b: bool,
) -> None:
    """Bidirectional non-destructive merge inside an open `BEGIN IMMEDIATE` tx."""
    if dev_a == dev_b:
        return
    identity._merge_device_pair_in_tx(
        conn,
        dev_b,
        dev_a,
        sync_memory=include_memory_for_a,
        sync_settings=False,
    )
    identity._merge_device_pair_in_tx(
        conn,
        dev_a,
        dev_b,
        sync_memory=include_memory_for_b,
        sync_settings=False,
    )


def sync_for_device_if_active(
    device_id: str,
    *,
    include_memory: bool = False,
    session_token: Optional[str] = None,
) -> bool:
    """Synchronize caller with their confirmed partner if both are active & confirmed."""
    if not device_id or not family_sharing_enabled():
        return False
    if session_token is not None and not session_eligible_for_family(session_token):
        return False

    conn = get_conn()
    try:
        row = conn.execute(
            "SELECT family_id, confirmed, status FROM family_members WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        if row is None or row["status"] != "active" or int(row["confirmed"] or 0) != 1:
            return False
        partner = _active_partner_row(conn, row["family_id"], device_id)
        if partner is None or int(partner["confirmed"] or 0) != 1:
            return False

        conn.execute("BEGIN IMMEDIATE")
        me_again = conn.execute(
            "SELECT family_id, confirmed, status FROM family_members WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        partner_again = (
            _active_partner_row(conn, me_again["family_id"], device_id)
            if me_again is not None
            else None
        )
        if (
            me_again is None
            or me_again["status"] != "active"
            or int(me_again["confirmed"] or 0) != 1
            or partner_again is None
            or int(partner_again["confirmed"] or 0) != 1
        ):
            conn.rollback()
            return False
        sync_pair_between_devices(
            conn,
            device_id,
            partner_again["device_id"],
            include_memory_for_a=include_memory,
            include_memory_for_b=include_memory,
        )
        conn.commit()
        return True
    except Exception:
        if conn.in_transaction:
            conn.rollback()
        raise
    finally:
        conn.close()


def get_family_status(
    device_id: str,
    *,
    include_memory: bool = False,
    allow_sync: bool = True,
) -> dict:
    enabled = family_sharing_enabled()
    if not enabled:
        return {
            "enabled": False,
            "in_family": False,
            "self_member": None,
            "partner": None,
            "active_invite": None,
            "pending_deletion_requests": [],
        }

    if allow_sync:
        sync_for_device_if_active(device_id, include_memory=include_memory)

    conn = get_conn()
    try:
        me = conn.execute(
            "SELECT * FROM family_members WHERE device_id = ? AND status = 'active'",
            (device_id,),
        ).fetchone()
        if me is None:
            return {
                "enabled": True,
                "in_family": False,
                "self_member": None,
                "partner": None,
                "active_invite": None,
                "pending_deletion_requests": [],
            }
        partner = _active_partner_row(conn, me["family_id"], device_id)
        now_str = _fmt_dt(_utcnow())
        invite = conn.execute(
            """
            SELECT expires_at FROM family_invites
            WHERE family_id = ? AND device_id = ? AND claimed_at IS NULL AND expires_at > ?
            ORDER BY id DESC LIMIT 1
            """,
            (me["family_id"], device_id, now_str),
        ).fetchone()
        del_rows = conn.execute(
            """
            SELECT id, child_name, created_at FROM family_deletion_requests
            WHERE family_id = ? AND device_id != ? AND status = 'pending'
            ORDER BY id ASC
            """,
            (me["family_id"], device_id),
        ).fetchall()
        return {
            "enabled": True,
            "in_family": True,
            "self_member": _member_payload(me),
            "partner": _member_payload(partner) if partner is not None else None,
            "active_invite": (
                {"has_active": True, "expires_at": _fmt_iso_z(invite["expires_at"])}
                if invite is not None
                else None
            ),
            "pending_deletion_requests": [
                {
                    "id": r["id"],
                    "child_name": r["child_name"],
                    "created_at": r["created_at"],
                }
                for r in del_rows
            ],
        }
    finally:
        conn.close()


def _require_enabled() -> None:
    if not family_sharing_enabled():
        raise FamilyError(
            403,
            "family_sharing_locked",
            "مشاركة الأسرة غير متاحة بعد؛ يجب تفعيل قفل الهوية أولًا.",
            "Family sharing is locked until identity lock enforcement is enabled.",
        )


def create_invite(
    device_id: str,
    *,
    role_label: Optional[str] = "parent",
    display_name: Optional[str] = None,
) -> dict:
    _require_enabled()
    role = _clean_role(role_label)
    name = _clean_name(display_name)
    now = _utcnow()
    expires = now + timedelta(minutes=INVITE_TTL_MINUTES)
    code_display, code_hash = _generate_code()

    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        me = conn.execute(
            "SELECT * FROM family_members WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        if me is None:
            cur = conn.execute("INSERT INTO families DEFAULT VALUES")
            family_id = cur.lastrowid
            conn.execute(
                """
                INSERT INTO family_members (family_id, device_id, role_label, display_name, status, confirmed)
                VALUES (?, ?, ?, ?, 'active', 1)
                """,
                (family_id, device_id, role, name),
            )
        else:
            family_id = me["family_id"]
            if me["status"] != "active":
                raise FamilyError(409, "member_inactive", "العضوية غير نشطة.", "Membership is inactive.")
            active_count = conn.execute(
                "SELECT COUNT(*) FROM family_members WHERE family_id = ? AND status = 'active'",
                (family_id,),
            ).fetchone()[0]
            if active_count >= MAX_FAMILY_MEMBERS:
                raise FamilyError(
                    409,
                    "family_full",
                    "تضمّ هذه الأسرة والدَين بالفعل.",
                    "This family already has two parents connected.",
                )
            conn.execute(
                """
                UPDATE family_members
                SET confirmed = 1, role_label = ?, display_name = COALESCE(?, display_name),
                    updated_at = datetime('now')
                WHERE device_id = ?
                """,
                (role, name, device_id),
            )

        conn.execute(
            "DELETE FROM family_invites WHERE device_id = ? AND claimed_at IS NULL",
            (device_id,),
        )
        expires_str = _fmt_dt(expires)
        conn.execute(
            """
            INSERT INTO family_invites (family_id, device_id, code_hash, expires_at)
            VALUES (?, ?, ?, ?)
            """,
            (family_id, device_id, code_hash, expires_str),
        )
        conn.commit()
        return {
            "ok": True,
            "code": code_display,
            "expires_at": _fmt_iso_z(expires_str),
            "ttl_minutes": INVITE_TTL_MINUTES,
        }
    except Exception:
        if conn.in_transaction:
            conn.rollback()
        raise
    finally:
        conn.close()


def join_by_invite(
    device_id: str,
    code: str,
    *,
    role_label: Optional[str] = "parent",
    display_name: Optional[str] = None,
) -> dict:
    _require_enabled()
    normalized = _normalize_code(code)
    if len(normalized) != _INVITE_LEN:
        raise FamilyError(
            422,
            "invalid_invite_code",
            "أدخل رمز الدعوة المكوّن من 8 خانات.",
            "Enter the 8-character family invite code.",
        )
    role = _clean_role(role_label)
    name = _clean_name(display_name)
    code_hash = _hash_code(normalized)
    now_str = _fmt_dt(_utcnow())

    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        existing_me = conn.execute(
            "SELECT * FROM family_members WHERE device_id = ? AND status = 'active'",
            (device_id,),
        ).fetchone()
        if existing_me is not None:
            raise FamilyError(
                409,
                "already_in_family",
                "هذا الهاتف مرتبط بأسرة بالفعل. غادرها أولًا للانضمام لأسرة أخرى.",
                "This phone is already part of a family. Leave first before joining another.",
            )

        invite = conn.execute(
            "SELECT * FROM family_invites WHERE code_hash = ?",
            (code_hash,),
        ).fetchone()
        if invite is None or invite["claimed_at"] is not None:
            raise FamilyError(
                404,
                "invite_not_found",
                "رمز الدعوة غير صالح أو تم استخدامه بالفعل.",
                "This invite code is invalid or has already been used.",
            )
        if invite["expires_at"] <= now_str:
            raise FamilyError(
                410,
                "invite_expired",
                "انتهت صلاحية رمز الدعوة. اطلب رمزًا جديدًا.",
                "This invite code has expired. Ask for a fresh one.",
            )
        issuer_id = invite["device_id"]
        if issuer_id == device_id:
            raise FamilyError(
                400,
                "self_invite",
                "لا يمكن ربط الهاتف بنفسه.",
                "A phone cannot accept its own family invite.",
            )

        issuer = conn.execute(
            "SELECT * FROM family_members WHERE family_id = ? AND device_id = ?",
            (invite["family_id"], issuer_id),
        ).fetchone()
        if issuer is None or issuer["status"] != "active" or int(issuer["confirmed"] or 0) != 1:
            raise FamilyError(
                409,
                "invite_unavailable",
                "هاتف مُرسِل الدعوة يحتاج إلى إعادة توثيق قبل الربط.",
                "The inviting phone needs to re-confirm before pairing.",
            )

        active_count = conn.execute(
            "SELECT COUNT(*) FROM family_members WHERE family_id = ? AND status = 'active'",
            (invite["family_id"],),
        ).fetchone()[0]
        if active_count >= MAX_FAMILY_MEMBERS:
            raise FamilyError(
                409,
                "family_full",
                "تضمّ هذه الأسرة والدَين بالفعل.",
                "This family already has two parents connected.",
            )

        claim = conn.execute(
            "UPDATE family_invites SET claimed_at = datetime('now') WHERE id = ? AND claimed_at IS NULL",
            (invite["id"],),
        )
        if claim.rowcount != 1:
            raise FamilyError(
                409,
                "invite_not_found",
                "رمز الدعوة غير صالح أو تم استخدامه بالفعل.",
                "This invite code is invalid or has already been used.",
            )

        conn.execute(
            """
            INSERT INTO family_members (family_id, device_id, role_label, display_name, status, confirmed)
            VALUES (?, ?, ?, ?, 'active', 1)
            """,
            (invite["family_id"], device_id, role, name),
        )
        sync_pair_between_devices(
            conn,
            issuer_id,
            device_id,
            include_memory_for_a=True,
            include_memory_for_b=True,
        )
        conn.commit()
    except Exception:
        if conn.in_transaction:
            conn.rollback()
        raise
    finally:
        conn.close()

    return get_family_status(device_id, include_memory=True, allow_sync=False)


def reconfirm_member(device_id: str) -> dict:
    _require_enabled()
    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        me = conn.execute(
            "SELECT * FROM family_members WHERE device_id = ? AND status = 'active'",
            (device_id,),
        ).fetchone()
        if me is None:
            raise FamilyError(404, "not_in_family", "لست عضوًا في أسرة.", "You are not in a family.")
        conn.execute(
            "UPDATE family_members SET confirmed = 1, updated_at = datetime('now') WHERE device_id = ?",
            (device_id,),
        )
        conn.commit()
    except Exception:
        if conn.in_transaction:
            conn.rollback()
        raise
    finally:
        conn.close()
    return get_family_status(device_id, include_memory=True, allow_sync=True)


def leave_family(device_id: str) -> dict:
    _require_enabled()
    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        me = conn.execute(
            "SELECT family_id FROM family_members WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        if me is None:
            raise FamilyError(404, "not_in_family", "لست عضوًا في أسرة.", "You are not in a family.")
        family_id = me["family_id"]
        conn.execute("DELETE FROM family_invites WHERE device_id = ?", (device_id,))
        conn.execute("DELETE FROM family_deletion_requests WHERE family_id = ?", (family_id,))
        conn.execute("DELETE FROM family_members WHERE device_id = ?", (device_id,))
        remaining = conn.execute(
            "SELECT COUNT(*) FROM family_members WHERE family_id = ?",
            (family_id,),
        ).fetchone()[0]
        if remaining == 0:
            conn.execute("DELETE FROM families WHERE id = ?", (family_id,))
        conn.commit()
    except Exception:
        if conn.in_transaction:
            conn.rollback()
        raise
    finally:
        conn.close()
    return {"ok": True, "left": True}


def request_child_deletion(device_id: str, child_name: str) -> dict:
    _require_enabled()
    cleaned_name = " ".join((child_name or "").split()).strip()
    child_key = tombs.child_key(cleaned_name)
    if not child_key:
        raise FamilyError(422, "child_name_required", "اسم الطفل مطلوب.", "Child name is required.")

    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        me = conn.execute(
            "SELECT family_id, confirmed, status FROM family_members WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        if me is None or me["status"] != "active" or int(me["confirmed"] or 0) != 1:
            raise FamilyError(403, "family_member_unconfirmed", "يجب توثيق عضوية الأسرة أولًا.", "Confirmed family membership required.")
        partner = _active_partner_row(conn, me["family_id"], device_id)
        if partner is None:
            raise FamilyError(404, "no_partner", "لا يوجد والد آخر مرتبط بهذه الأسرة.", "No partner parent connected to this family.")
        cur = conn.execute(
            """
            INSERT INTO family_deletion_requests (family_id, device_id, target_child_key, child_name, status)
            VALUES (?, ?, ?, ?, 'pending')
            """,
            (me["family_id"], device_id, child_key, cleaned_name),
        )
        req_id = cur.lastrowid
        conn.commit()
        return {"ok": True, "request_id": req_id, "child_name": cleaned_name, "status": "pending"}
    except Exception:
        if conn.in_transaction:
            conn.rollback()
        raise
    finally:
        conn.close()


def _load_pending_deletion_for_partner(conn: sqlite3.Connection, device_id: str, request_id: int) -> sqlite3.Row:
    me = conn.execute(
        "SELECT family_id, confirmed, status FROM family_members WHERE device_id = ?",
        (device_id,),
    ).fetchone()
    if me is None or me["status"] != "active" or int(me["confirmed"] or 0) != 1:
        raise FamilyError(403, "family_member_unconfirmed", "يجب توثيق عضوية الأسرة أولًا.", "Confirmed family membership required.")
    req = conn.execute(
        "SELECT * FROM family_deletion_requests WHERE id = ? AND family_id = ?",
        (request_id, me["family_id"]),
    ).fetchone()
    if req is None or req["status"] != "pending":
        raise FamilyError(404, "deletion_request_not_found", "طلب الحذف غير موجود أو مُنفّذ.", "Deletion request not found or already resolved.")
    if req["device_id"] == device_id:
        raise FamilyError(403, "cannot_self_confirm", "لا يؤكّد طلب الحذف إلا الطرف الآخر.", "Only the partner parent may confirm this deletion.")
    return req


def confirm_child_deletion(device_id: str, request_id: int) -> dict:
    _require_enabled()
    conn = get_conn()
    try:
        req = _load_pending_deletion_for_partner(conn, device_id, request_id)
        target_key = req["target_child_key"]
        matching_ids = [
            r["id"]
            for r in conn.execute(
                "SELECT id, name FROM child_profiles WHERE device_id = ?",
                (device_id,),
            ).fetchall()
            if tombs.child_key(r["name"]) == target_key
        ]
    finally:
        conn.close()

    erased_count = 0
    for cid in matching_ids:
        privacy.erase_child(device_id, cid)
        erased_count += 1

    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            "UPDATE family_deletion_requests SET status = 'confirmed', resolved_at = datetime('now') WHERE id = ?",
            (request_id,),
        )
        conn.commit()
    except Exception:
        if conn.in_transaction:
            conn.rollback()
        raise
    finally:
        conn.close()

    return {"ok": True, "request_id": request_id, "status": "confirmed", "erased_children": erased_count}


def dismiss_child_deletion(device_id: str, request_id: int) -> dict:
    _require_enabled()
    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        _load_pending_deletion_for_partner(conn, device_id, request_id)
        conn.execute(
            "UPDATE family_deletion_requests SET status = 'dismissed', resolved_at = datetime('now') WHERE id = ?",
            (request_id,),
        )
        conn.commit()
    except Exception:
        if conn.in_transaction:
            conn.rollback()
        raise
    finally:
        conn.close()

    return {"ok": True, "request_id": request_id, "status": "dismissed"}
