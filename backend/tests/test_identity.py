"""Tests for Google identity linking with token verification and safe cross-device merge.

Uses the same _AuthStubMiddleware pattern used in test_daily_routine.py.
"""
import json
import sqlite3
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
from httpx import Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.db.init_db import get_conn, init_db
from app.routers.identity import router as identity_router


@pytest.fixture(autouse=True)
def _cross_device_on(monkeypatch):
    """The merge tests below exercise the switched-on path; the default (off)
    is pinned by test_link_moves_no_data_while_cross_device_is_off."""
    monkeypatch.setenv("IDENTITY_CROSS_DEVICE", "1")


@pytest.fixture
def tmp_db(tmp_path, monkeypatch):
    db = tmp_path / "identity.db"
    monkeypatch.setenv("CONVERSATIONS_DB", str(db))
    init_db()
    return db


class _AuthStubMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, device_id: str = "test-device-identity"):
        super().__init__(app)
        self.device_id = device_id

    async def dispatch(self, request: Request, call_next):
        request.state.device_id = self.device_id
        return await call_next(request)


@pytest.fixture
def app(tmp_db):
    a = FastAPI()
    a.add_middleware(_AuthStubMiddleware)
    a.include_router(identity_router, prefix="/api")
    return a


@pytest.fixture
def client(app):
    with TestClient(app) as c:
        yield c


_WEB_CLIENT_ID = "620240456244-d7a3fd35ianuu34i1sobb0pj4ncttmdu.apps.googleusercontent.com"

_FAKE_TOKENINFO = {
    "iss": "https://accounts.google.com",
    "sub": "google-12345",
    "email": "parent@example.com",
    "email_verified": "true",
    "name": "Test Parent",
    "aud": _WEB_CLIENT_ID,
    "exp": "9999999999",
}


def test_link_google_requires_id_token(client):
    r = client.post("/api/identity/link-google", json={})
    assert r.status_code == 200
    assert r.json()["ok"] is False
    assert r.json()["error"] == "id_token_and_device_required"


def test_link_google_rejects_invalid_token(client):
    with patch(
        "app.routers.identity.httpx.AsyncClient.get",
        new_callable=AsyncMock,
        return_value=Response(400, text="Invalid token"),
    ):
        r = client.post(
            "/api/identity/link-google",
            json={"id_token": "bad.token.here"},
        )
    assert r.status_code == 200
    assert r.json()["ok"] is False
    assert r.json()["error"] == "invalid_google_id_token"


def test_link_google_success(client):
    with patch(
        "app.routers.identity.httpx.AsyncClient.get",
        new_callable=AsyncMock,
        return_value=Response(200, json=_FAKE_TOKENINFO),
    ):
        r = client.post(
            "/api/identity/link-google",
            json={"id_token": "valid.id.token"},
        )
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert body["google_id"] == "google-12345"
    assert body["email"] == "parent@example.com"

    # /identity/me now reports linked
    r2 = client.get("/api/identity/me")
    assert r2.status_code == 200
    assert r2.json()["linked"] is True


def test_link_google_rejects_non_google_issuer(client):
    payload = dict(_FAKE_TOKENINFO)
    payload["iss"] = "https://evil.com"
    with patch(
        "app.routers.identity.httpx.AsyncClient.get",
        new_callable=AsyncMock,
        return_value=Response(200, json=payload),
    ):
        r = client.post(
            "/api/identity/link-google",
            json={"id_token": "valid.id.token"},
        )
    assert r.json()["ok"] is False
    assert r.json()["error"] == "invalid_google_id_token"


def test_link_google_requires_sub_claim(client):
    payload = dict(_FAKE_TOKENINFO)
    payload.pop("sub")
    with patch(
        "app.routers.identity.httpx.AsyncClient.get",
        new_callable=AsyncMock,
        return_value=Response(200, json=payload),
    ):
        r = client.post(
            "/api/identity/link-google",
            json={"id_token": "valid.id.token"},
        )
    assert r.json()["ok"] is False
    assert r.json()["error"] == "invalid_google_id_token"


def test_link_google_rejects_wrong_audience(client):
    payload = dict(_FAKE_TOKENINFO)
    payload["aud"] = "wrong-client-id.apps.googleusercontent.com"
    with patch(
        "app.routers.identity.httpx.AsyncClient.get",
        new_callable=AsyncMock,
        return_value=Response(200, json=payload),
    ):
        r = client.post(
            "/api/identity/link-google",
            json={"id_token": "valid.id.token"},
        )
    assert r.json()["ok"] is False
    assert r.json()["error"] == "invalid_google_id_token"


def _link_with(client, payload, *, proven: bool = True):
    with (
        patch(
            "app.routers.identity.httpx.AsyncClient.get",
            new_callable=AsyncMock,
            return_value=Response(200, json=payload),
        ),
        patch(
            "app.routers.identity._link_confirmable",
            return_value=proven,
        ),
    ):
        return client.post("/api/identity/link-google", json={"id_token": "valid.id.token"})


def _make_client_for_device(device_id: str) -> TestClient:
    a = FastAPI()
    a.add_middleware(_AuthStubMiddleware, device_id=device_id)
    a.include_router(identity_router, prefix="/api")
    return TestClient(a)


def test_link_google_rejects_token_for_another_audience_even_if_we_requested_it(client):
    # `azp` names who asked for the token, not who it is for. The old check
    # accepted either field, so aud=someone-else + azp=us got through.
    payload = dict(_FAKE_TOKENINFO)
    payload["aud"] = "another-service.apps.googleusercontent.com"
    payload["azp"] = _WEB_CLIENT_ID
    r = _link_with(client, payload)
    assert r.json() == {"ok": False, "error": "invalid_google_id_token"}


def test_link_google_rejects_expired_token(client):
    payload = dict(_FAKE_TOKENINFO)
    payload["exp"] = "1000000000"          # 2001
    r = _link_with(client, payload)
    assert r.json() == {"ok": False, "error": "invalid_google_id_token"}


def test_unverified_email_is_not_stored(client):
    # Identity is the Google `sub`; the email is only what the account claims.
    # An address Google has not verified must not be recorded as the parent's.
    payload = dict(_FAKE_TOKENINFO)
    payload["email"] = "someone-else@example.com"
    payload["email_verified"] = "false"
    r = _link_with(client, payload)
    assert r.json()["ok"] is True
    assert r.json()["email"] == ""
    me = client.get("/api/identity/me").json()
    assert me["linked"] is True and me["email"] is None


def test_missing_email_verified_counts_as_unverified(client):
    payload = dict(_FAKE_TOKENINFO)
    payload.pop("email_verified")
    assert _link_with(client, payload).json()["email"] == ""


def test_jwt_style_boolean_email_verified_is_accepted(client):
    payload = dict(_FAKE_TOKENINFO)
    payload["email_verified"] = True
    assert _link_with(client, payload).json()["email"] == "parent@example.com"


# ── Requirement 1 + Legacy Vulnerability: confirmed=1 required on BOTH devices ──


def test_unconfirmed_link_never_leaks_child_names_or_data_even_without_device_proofs_row(tmp_db):
    """Security invariant 1 (and fix for the legacy child-name leak):
    If an attacker uses a bare/unconfirmed session (`confirmed = 0`) to link a
    victim's `device_id` to the attacker's Google account — even when the victim
    device has NO row in `device_proofs` — and then links the attacker's own
    device with a proven session (`confirmed = 1`), zero data (not even child
    names in `child_profiles`) may be copied or moved from the victim device.
    Likewise, an unconfirmed session on a second device cannot pull child names
    or data from a confirmed family device.
    """
    victim_dev = "victim-family-no-proof-row"
    attacker_dev = "attacker-proven-phone"
    unconfirmed_caller_dev = "unconfirmed-caller-phone"

    conn = get_conn()
    try:
        vcid = conn.execute(
            """
            INSERT INTO child_profiles (device_id, name, age_group, gender, avatar_emoji, birth_month)
            VALUES (?, 'SecretVictimChild', '9-12', 'female', '🌸', '2015-05')
            """,
            (victim_dev,),
        ).lastrowid
        conn.execute(
            """
            INSERT INTO lesson_progress (device_id, child_id, path_id, lesson_id, status, score)
            VALUES (?, ?, 'p1', 'L-1', 'completed', 100)
            """,
            (victim_dev, vcid),
        )
        conn.execute(
            """
            INSERT INTO child_facts (device_id, child_id, category, fact)
            VALUES (?, ?, 'note', 'Private victim fact')
            """,
            (victim_dev, vcid),
        )
        conn.commit()
    finally:
        conn.close()

    # Step A: Attacker links victim_dev via an unconfirmed session (proven=False -> confirmed=0)
    with _make_client_for_device(victim_dev) as c_victim_bare:
        assert _link_with(c_victim_bare, _FAKE_TOKENINFO, proven=False).json()["ok"] is True

    # Step B: Attacker links their own device via a proven session (proven=True -> confirmed=1)
    with _make_client_for_device(attacker_dev) as c_attacker:
        assert _link_with(c_attacker, _FAKE_TOKENINFO, proven=True).json()["ok"] is True

    conn = get_conn()
    try:
        # Victim keeps all data; attacker gets NOTHING (not even child names!)
        victim_kids = conn.execute(
            "SELECT name FROM child_profiles WHERE device_id = ?", (victim_dev,)
        ).fetchall()
        attacker_kids = conn.execute(
            "SELECT name FROM child_profiles WHERE device_id = ?", (attacker_dev,)
        ).fetchall()
        assert [r["name"] for r in victim_kids] == ["SecretVictimChild"]
        assert attacker_kids == []
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM lesson_progress WHERE device_id = ?", (attacker_dev,)
            ).fetchone()[0]
            == 0
        )
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM child_facts WHERE device_id = ?", (attacker_dev,)
            ).fetchone()[0]
            == 0
        )

        # Step C: Suppose attacker_dev has its own child, and an unconfirmed caller
        # links to the same Google account (proven=False -> confirmed=0).
        conn.execute(
            "INSERT INTO child_profiles (device_id, name, age_group) VALUES (?, 'AttackerOwnChild', '6-8')",
            (attacker_dev,),
        )
        conn.commit()
    finally:
        conn.close()

    with _make_client_for_device(unconfirmed_caller_dev) as c_unconfirmed:
        assert _link_with(c_unconfirmed, _FAKE_TOKENINFO, proven=False).json()["ok"] is True

    conn = get_conn()
    try:
        # Unconfirmed caller does NOT receive AttackerOwnChild's name or data either
        unconfirmed_kids = conn.execute(
            "SELECT name FROM child_profiles WHERE device_id = ?", (unconfirmed_caller_dev,)
        ).fetchall()
        assert unconfirmed_kids == []
    finally:
        conn.close()


# ── Requirement 2: No back-and-forth tug-of-war between two parent phones ──


def test_two_confirmed_parent_phones_sync_idempotently_without_pulling_data_away(tmp_db):
    """Security/correctness invariant 2:
    When a parent has two confirmed phones (`dev1` and `dev2`) linked to the
    same Google account, linking `dev2` copies/merges family data onto `dev2`
    WITHOUT deleting or stealing `dev1`'s rows, and subsequent links in either
    direction (`dev1 -> dev2 -> dev1 -> dev2`) merge new progress idempotently
    without duplicating children or wiping either phone.
    """
    dev1 = "parent-phone-1"
    dev2 = "parent-phone-2"

    conn = get_conn()
    try:
        c1 = conn.execute(
            """
            INSERT INTO child_profiles (device_id, name, age_group, gender, avatar_emoji, birth_month)
            VALUES (?, 'Layla', '9-12', 'female', '🌟', '2015-04')
            """,
            (dev1,),
        ).lastrowid
        c2 = conn.execute(
            """
            INSERT INTO child_profiles (device_id, name, age_group, gender, avatar_emoji, birth_month)
            VALUES (?, 'Omar', '6-8', 'male', '🚀', '2018-09')
            """,
            (dev1,),
        ).lastrowid

        conn.execute(
            """
            INSERT INTO lesson_progress (device_id, child_id, path_id, lesson_id, status, score, completed_at)
            VALUES (?, ?, 'p1', 'L-101', 'completed', 90, '2026-09-01T10:00:00'),
                   (?, ?, 'p1', 'L-202', 'in_progress', 40, NULL)
            """,
            (dev1, c1, dev1, c2),
        )
        conn.execute(
            """
            INSERT INTO weekly_plans (device_id, child_id, iso_week, lang, plan_json, personal)
            VALUES (?, ?, '2026-W40', 'ar', ?, 1)
            """,
            (dev1, c1, json.dumps({"child_id": c1, "items": ["a"]})),
        )
        conn.execute(
            """
            INSERT INTO weekly_plan_marks (device_id, child_id, item_id, marked_on)
            VALUES (?, ?, 'lantern-1', '2026-09-28')
            """,
            (dev1, c1),
        )
        conn.execute(
            "INSERT INTO child_facts (device_id, child_id, category, fact, confidence) VALUES (?, ?, 'interest', 'Loves astronomy', 0.8)",
            (dev1, c1),
        )
        conn.execute(
            "INSERT INTO followups (device_id, child_id, strategy, topic, due_at, status) VALUES (?, ?, 'check_in', 'bedtime_reading', '2026-10-10', 'pending')",
            (dev1, c1),
        )
        conn.execute(
            "INSERT INTO program_children (child_id, device_id, reached_puberty) VALUES (?, ?, 1)",
            (c1, dev1),
        )
        conn.execute(
            "INSERT INTO ramadan_fasting (device_id, child_id, hijri_year, step_key) VALUES (?, ?, 1447, 'full_day')",
            (dev1, c1),
        )
        conn.execute(
            """
            INSERT INTO ramadan_marks (device_id, child_id, hijri_year, day, mark, value)
            VALUES (?, ?, 1447, 1, 'fasted', 'yes'),
                   (?, 0, 1447, 1, 'family_iftar', 'done')
            """,
            (dev1, c1, dev1),
        )
        conn.execute(
            "INSERT INTO prayer_journeys (device_id, child_id, track, stage, status, started_on) VALUES (?, ?, 'journey', 2, 'active', '2026-09-01')",
            (dev1, c1),
        )
        r_id = conn.execute(
            "INSERT INTO child_daily_routines (device_id, child_id, routine_date) VALUES (?, ?, '2026-10-01')",
            (dev1, c1),
        ).lastrowid
        conn.execute(
            "INSERT INTO routine_events (routine_id, event_type, started_at) VALUES (?, 'sleep', '2026-10-01T20:00:00')",
            (r_id,),
        )
        conn.commit()
    finally:
        conn.close()

    # Both phones link with confirmed=1
    with _make_client_for_device(dev1) as client1:
        assert _link_with(client1, _FAKE_TOKENINFO, proven=True).json()["ok"] is True
    with _make_client_for_device(dev2) as client2:
        assert _link_with(client2, _FAKE_TOKENINFO, proven=True).json()["ok"] is True

    conn = get_conn()
    try:
        # Both dev1 AND dev2 now have Layla and Omar! dev1 was NOT wiped!
        dev1_kids = {
            r["name"]: r["id"]
            for r in conn.execute(
                "SELECT id, name FROM child_profiles WHERE device_id = ?", (dev1,)
            ).fetchall()
        }
        dev2_kids = {
            r["name"]: r["id"]
            for r in conn.execute(
                "SELECT id, name FROM child_profiles WHERE device_id = ?", (dev2,)
            ).fetchall()
        }
        assert set(dev1_kids.keys()) == {"Layla", "Omar"}
        assert set(dev2_kids.keys()) == {"Layla", "Omar"}
        assert dev1_kids["Layla"] == c1
        dev2_layla = dev2_kids["Layla"]
        dev2_omar = dev2_kids["Omar"]
        assert dev2_layla != c1

        # Verify weekly_plans.plan_json on dev2 has child_id rewritten to dev2_layla
        plan_raw = conn.execute(
            "SELECT plan_json FROM weekly_plans WHERE device_id = ? AND child_id = ?",
            (dev2, dev2_layla),
        ).fetchone()["plan_json"]
        assert json.loads(plan_raw)["child_id"] == dev2_layla

        # Now dev1 finishes L-202 for Omar and logs a new routine event for Layla,
        # while dev2 upgrades Layla's L-101 score to 100 and answers the followup!
        conn.execute(
            "UPDATE lesson_progress SET status = 'completed', score = 95 WHERE device_id = ? AND child_id = ? AND lesson_id = 'L-202'",
            (dev1, c2),
        )
        conn.execute(
            "INSERT INTO routine_events (routine_id, event_type, started_at) VALUES (?, 'feed', '2026-10-01T22:00:00')",
            (r_id,),
        )
        conn.execute(
            "UPDATE lesson_progress SET score = 100 WHERE device_id = ? AND child_id = ? AND lesson_id = 'L-101'",
            (dev2, dev2_layla),
        )
        conn.execute(
            "UPDATE followups SET status = 'answered', outcome = 'worked', answered_at = '2026-10-02T10:00:00' WHERE device_id = ? AND child_id = ?",
            (dev2, dev2_layla),
        )
        conn.commit()
    finally:
        conn.close()

    # Re-link dev2, then re-link dev1, then re-link dev2 again (ping-pong test)
    with _make_client_for_device(dev2) as client2:
        assert _link_with(client2, _FAKE_TOKENINFO, proven=True).json()["ok"] is True
    with _make_client_for_device(dev1) as client1:
        assert _link_with(client1, _FAKE_TOKENINFO, proven=True).json()["ok"] is True
    with _make_client_for_device(dev2) as client2:
        assert _link_with(client2, _FAKE_TOKENINFO, proven=True).json()["ok"] is True

    conn = get_conn()
    try:
        # Still exactly 2 children on each phone (no duplicates created!)
        assert (
            conn.execute("SELECT COUNT(*) FROM child_profiles WHERE device_id = ?", (dev1,)).fetchone()[0]
            == 2
        )
        assert (
            conn.execute("SELECT COUNT(*) FROM child_profiles WHERE device_id = ?", (dev2,)).fetchone()[0]
            == 2
        )

        # Both phones have the upgraded L-101 score=100 and completed L-202 score=95
        for dev, layla_id, omar_id in [(dev1, c1, c2), (dev2, dev2_layla, dev2_omar)]:
            l101 = conn.execute(
                "SELECT status, score FROM lesson_progress WHERE device_id = ? AND child_id = ? AND lesson_id = 'L-101'",
                (dev, layla_id),
            ).fetchone()
            assert (l101["status"], l101["score"]) == ("completed", 100)

            l202 = conn.execute(
                "SELECT status, score FROM lesson_progress WHERE device_id = ? AND child_id = ? AND lesson_id = 'L-202'",
                (dev, omar_id),
            ).fetchone()
            assert (l202["status"], l202["score"]) == ("completed", 95)

            f_row = conn.execute(
                "SELECT status, outcome FROM followups WHERE device_id = ? AND child_id = ?",
                (dev, layla_id),
            ).fetchone()
            assert (f_row["status"], f_row["outcome"]) == ("answered", "worked")

            rout = conn.execute(
                "SELECT id FROM child_daily_routines WHERE device_id = ? AND child_id = ? AND routine_date = '2026-10-01'",
                (dev, layla_id),
            ).fetchone()
            evs = [
                r["event_type"]
                for r in conn.execute(
                    "SELECT event_type FROM routine_events WHERE routine_id = ? ORDER BY started_at ASC",
                    (rout["id"],),
                ).fetchall()
            ]
            assert evs == ["sleep", "feed"]

            facts = conn.execute(
                "SELECT fact FROM child_facts WHERE device_id = ? AND child_id = ?",
                (dev, layla_id),
            ).fetchall()
            assert [r["fact"] for r in facts] == ["Loves astronomy"]
    finally:
        conn.close()


# ── Requirement 3: Never delete or overwrite any child registered on the new phone ──


def test_never_deletes_or_overwrites_child_registered_on_new_phone(tmp_db):
    """Security/correctness invariant 3:
    Even when the new phone has only a single freshly-created child with zero
    activity (or passive Home-screen caches), linking Google must NEVER delete
    or overwrite that child in `child_profiles`. Non-matching children from the
    old phone are inserted alongside it, matching children merge into the
    same-named child, and sibling placeholders (`الطفل أ/ب/ج`) are re-lettered
    accurately.
    """
    old_dev = "old-phone-with-siblings"
    new_dev = "new-phone-with-new-child"

    conn = get_conn()
    try:
        old_layla = conn.execute(
            """
            INSERT INTO child_profiles (device_id, name, age_group, gender, avatar_emoji, birth_month)
            VALUES (?, 'ليلى', '6-8', 'female', '🌟', '2018-04')
            """,
            (old_dev,),
        ).lastrowid
        old_omar = conn.execute(
            """
            INSERT INTO child_profiles (device_id, name, age_group, gender, avatar_emoji, birth_month)
            VALUES (?, 'عمر', '9-12', 'male', '🚀', '2015-09')
            """,
            (old_dev,),
        ).lastrowid

        # On old_dev: old_layla is الطفل أ (index 0), old_omar is الطفل ب (index 1)
        conn.execute(
            "INSERT INTO child_facts (device_id, child_id, category, fact, confidence) VALUES (?, ?, 'sibling', 'طفلي يغار من الطفل ب', 0.9)",
            (old_dev, old_layla),
        )
        conn.execute(
            "INSERT INTO child_facts (device_id, child_id, category, fact, confidence) VALUES (?, ?, 'sibling', 'طفلي يحب اللعب مع الطفل أ', 0.9)",
            (old_dev, old_omar),
        )
        conn.execute(
            "INSERT INTO followups (device_id, child_id, topic, strategy, status, due_at) VALUES (?, ?, 'sibling_rivalry', 'امدح طفلي أمام الطفل ب', 'pending', '2026-10-15')",
            (old_dev, old_layla),
        )
        conn.execute(
            "INSERT INTO lesson_progress (device_id, child_id, path_id, lesson_id, status, score) VALUES (?, ?, 'p1', 'L-1', 'completed', 100)",
            (old_dev, old_layla),
        )

        # On new_dev: parent registered 'زيد' (zero activity, only passive Home caches)
        new_zaid = conn.execute(
            """
            INSERT INTO child_profiles (device_id, name, age_group, gender, avatar_emoji)
            VALUES (?, 'زيد', '3-5', 'male', '🧸')
            """,
            (new_dev,),
        ).lastrowid
        conn.execute(
            "INSERT INTO weekly_plans (device_id, child_id, iso_week, lang, plan_json, personal) VALUES (?, ?, '2026-W41', 'ar', '{}', 0)",
            (new_dev, new_zaid),
        )
        conn.commit()
    finally:
        conn.close()

    with _make_client_for_device(old_dev) as c_old:
        assert _link_with(c_old, _FAKE_TOKENINFO, proven=True).json()["ok"] is True
    with _make_client_for_device(new_dev) as c_new:
        assert _link_with(c_new, _FAKE_TOKENINFO, proven=True).json()["ok"] is True

    conn = get_conn()
    try:
        children = conn.execute(
            "SELECT id, name, age_group, avatar_emoji FROM child_profiles WHERE device_id = ? ORDER BY id ASC",
            (new_dev,),
        ).fetchall()
        # 'زيد' (new_zaid) is preserved intact at index 0 (الطفل أ), followed by 'ليلى' (الطفل ب) and 'عمر' (الطفل ج)
        assert [r["name"] for r in children] == ["زيد", "ليلى", "عمر"]
        assert children[0]["id"] == new_zaid
        assert children[0]["age_group"] == "3-5"
        assert children[0]["avatar_emoji"] == "🧸"

        new_layla_id = children[1]["id"]
        new_omar_id = children[2]["id"]

        # Layla's lesson progress was copied to new_layla_id
        lp = conn.execute(
            "SELECT lesson_id, status, score FROM lesson_progress WHERE device_id = ? AND child_id = ?",
            (new_dev, new_layla_id),
        ).fetchone()
        assert (lp["lesson_id"], lp["status"], lp["score"]) == ("L-1", "completed", 100)

        # Sibling placeholders in copied facts/followups were re-lettered to match new_dev's order:
        # On new_dev: زيد = الطفل أ, ليلى = الطفل ب, عمر = الطفل ج
        layla_fact = conn.execute(
            "SELECT fact FROM child_facts WHERE device_id = ? AND child_id = ?",
            (new_dev, new_layla_id),
        ).fetchone()["fact"]
        omar_fact = conn.execute(
            "SELECT fact FROM child_facts WHERE device_id = ? AND child_id = ?",
            (new_dev, new_omar_id),
        ).fetchone()["fact"]
        layla_strategy = conn.execute(
            "SELECT strategy FROM followups WHERE device_id = ? AND child_id = ?",
            (new_dev, new_layla_id),
        ).fetchone()["strategy"]

        assert layla_fact == "طفلي يغار من الطفل ج"
        assert omar_fact == "طفلي يحب اللعب مع الطفل ب"
        assert layla_strategy == "امدح طفلي أمام الطفل ج"
    finally:
        conn.close()


# ── Requirement 4: Atomicity (BEGIN IMMEDIATE / ROLLBACK) & Production Schema ──


def test_atomic_rollback_on_mid_merge_failure_leaves_database_untouched(tmp_db, monkeypatch):
    """Security/correctness invariant 4a:
    If any error occurs mid-merge inside `_merge_legacy_device_data`, the entire
    transaction rolls back atomically so `new_dev` does not end up with half-merged
    children or partial rows, while the `identity_links` row remains committed.
    """
    from app.routers import identity

    old_dev = "atomic-old-dev"
    new_dev = "atomic-new-dev"

    conn = get_conn()
    try:
        conn.execute(
            "INSERT INTO child_profiles (device_id, name, age_group) VALUES (?, 'Layla', '9-12')",
            (old_dev,),
        )
        conn.commit()
    finally:
        conn.close()

    with _make_client_for_device(old_dev) as c_old:
        assert _link_with(c_old, _FAKE_TOKENINFO, proven=True).json()["ok"] is True

    def boom(*args, **kwargs):
        raise RuntimeError("simulated mid-merge failure")

    monkeypatch.setattr(identity, "_sync_child_scoped_rows", boom)

    with _make_client_for_device(new_dev) as c_new:
        # _link_identity catches merge failure and keeps the link
        res = _link_with(c_new, _FAKE_TOKENINFO, proven=True)
        assert res.json()["ok"] is True

    conn = get_conn()
    try:
        # Because _sync_child_scoped_rows raised after child_profiles INSERT on new_dev,
        # the rollback must have undone the child_profiles INSERT on new_dev too!
        new_kids = conn.execute(
            "SELECT * FROM child_profiles WHERE device_id = ?", (new_dev,)
        ).fetchall()
        assert new_kids == []
        old_kids = conn.execute(
            "SELECT name FROM child_profiles WHERE device_id = ?", (old_dev,)
        ).fetchall()
        assert [r["name"] for r in old_kids] == ["Layla"]
    finally:
        conn.close()


def test_merge_compatible_with_production_schema_fixture(tmp_path):
    """Security/correctness invariant 4b:
    Verify `_merge_legacy_device_data` runs cleanly against the exact production
    schema snapshot (`backend/tests/fixtures/prod_device_tables_2026-10-04.sql`)
    where newer tables/columns (`birth_month`, `child_missions.source`,
    `weekly_plan_marks`, `program_children`, etc.) do not exist.
    """
    from app.routers.identity import _merge_legacy_device_data

    fixture_sql = (
        Path(__file__).resolve().parent / "fixtures" / "prod_device_tables_2026-10-04.sql"
    ).read_text(encoding="utf-8")

    db_path = tmp_path / "prod_fixture.db"
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        conn.executescript(fixture_sql)

        # 1. Before `confirmed` column exists on `identity_links`, merge fails closed cleanly
        conn.execute(
            "INSERT INTO parent_identities (google_id, email) VALUES ('g-prod', 'p@example.com')"
        )
        conn.execute(
            "INSERT INTO identity_links (device_id, google_id) VALUES ('prod-dev-1', 'g-prod'), ('prod-dev-2', 'g-prod')"
        )
        c1 = conn.execute(
            "INSERT INTO child_profiles (device_id, name, age_group, gender, avatar_emoji) VALUES ('prod-dev-1', 'Salma', '6-8', 'female', '🌙')"
        ).lastrowid
        conn.execute(
            "INSERT INTO lesson_progress (device_id, child_id, path_id, lesson_id, status, score) VALUES ('prod-dev-1', ?, 'p1', 'L-1', 'completed', 95)",
            (c1,),
        )
        conn.execute(
            "INSERT INTO child_missions (device_id, child_id, mission_key, local_date, status) VALUES ('prod-dev-1', ?, 'm1', '2026-10-04', 'confirmed')",
            (c1,),
        )
        conn.execute(
            "INSERT INTO child_licences (device_id, child_id, level_key, status) VALUES ('prod-dev-1', ?, 'stranger', 'granted')",
            (c1,),
        )
        conn.execute(
            "INSERT INTO coach_tips (device_id, child_id, date, text, tapped_at, lang) VALUES ('prod-dev-1', ?, '2026-10-04', 'Tip', '2026-10-04T10:00:00', 'ar')",
            (c1,),
        )
        conn.commit()

        _merge_legacy_device_data(conn, "prod-dev-2", "g-prod")
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM child_profiles WHERE device_id = 'prod-dev-2'"
            ).fetchone()[0]
            == 0
        )

        # 2. Add `confirmed` column (as v29+ migration does) and mark both confirmed=1
        conn.execute("ALTER TABLE identity_links ADD COLUMN confirmed INTEGER NOT NULL DEFAULT 0")
        conn.execute("UPDATE identity_links SET confirmed = 1")
        conn.commit()

        _merge_legacy_device_data(conn, "prod-dev-2", "g-prod")

        prod2_child = conn.execute(
            "SELECT id, name, age_group, avatar_emoji FROM child_profiles WHERE device_id = 'prod-dev-2'"
        ).fetchone()
        assert prod2_child is not None
        assert prod2_child["name"] == "Salma"
        c2 = prod2_child["id"]

        assert (
            conn.execute(
                "SELECT status, score FROM lesson_progress WHERE device_id = 'prod-dev-2' AND child_id = ?",
                (c2,),
            ).fetchone()["score"]
            == 95
        )
        assert (
            conn.execute(
                "SELECT status FROM child_missions WHERE device_id = 'prod-dev-2' AND child_id = ?",
                (c2,),
            ).fetchone()["status"]
            == "confirmed"
        )
        assert (
            conn.execute(
                "SELECT status FROM child_licences WHERE device_id = 'prod-dev-2' AND child_id = ?",
                (c2,),
            ).fetchone()["status"]
            == "granted"
        )
        assert (
            conn.execute(
                "SELECT text FROM coach_tips WHERE device_id = 'prod-dev-2' AND child_id = ?",
                (c2,),
            ).fetchone()["text"]
            == "Tip"
        )
    finally:
        conn.close()


def test_link_moves_no_data_while_cross_device_is_off(tmp_db, monkeypatch):
    """Default: a confirmed link pulls nothing from the other phone, because
    confirmed=1 is obtainable for a device id one does not hold (PR #175
    security review, 2026-10-27)."""
    monkeypatch.delenv("IDENTITY_CROSS_DEVICE", raising=False)
    conn = get_conn()
    try:
        conn.execute(
            "INSERT INTO child_profiles (device_id, name, age_group) VALUES ('victim-phone', 'سالم', '6-8')")
        conn.execute("INSERT INTO parent_identities (google_id) VALUES ('g-x')")
        conn.execute(
            "INSERT INTO identity_links (device_id, google_id, linked_at, confirmed) "
            "VALUES ('victim-phone', 'g-x', datetime('now'), 1)")
        conn.commit()
    finally:
        conn.close()

    from app.routers import identity

    assert identity._link_identity("attacker-phone", "g-x", "", "", confirmed=True)

    conn = get_conn()
    try:
        assert conn.execute(
            "SELECT COUNT(*) FROM child_profiles WHERE device_id = 'attacker-phone'").fetchone()[0] == 0
        assert conn.execute(
            "SELECT confirmed FROM identity_links WHERE device_id = 'attacker-phone'").fetchone()[0] == 1
    finally:
        conn.close()
