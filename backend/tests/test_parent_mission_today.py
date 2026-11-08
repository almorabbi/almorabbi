"""Today's mission from the parent's side — no handover needed.

Production, 28 days to 2026-11-08, real devices only: 4 bank missions were
confirmed. The only road ran through child mode (PIN, handover, the child's
claim, the evening list). These endpoints let the parent read today's card
and press «عملها» once the child did it.

Two older rules stay pinned here:
  * reading mints nothing (today_mission's docstring: 0 claims against 86
    assignments when the parent's screen minted), and
  * the child's own row is the authority when it exists.
"""
from __future__ import annotations

from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.db.init_db import get_conn
from app.services import child_budget
from app.services import child_missions as cm
from app.services import family_actions


@pytest.fixture
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


def _auth(client, device: str) -> dict:
    tok = client.post("/api/chat/sessions", json={"device_id": device}).json()["token"]
    return {"Authorization": f"Bearer {tok}"}


def _child(client, h, name: str = "سالم", age: str = "7-9") -> int:
    r = client.post("/api/children", json={"name": name, "age_group": age}, headers=h)
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def _rows(cid: int) -> list[dict]:
    conn = get_conn()
    try:
        return [dict(r) for r in conn.execute(
            "SELECT * FROM child_missions WHERE child_id = ?", (cid,)).fetchall()]
    finally:
        conn.close()


def _today() -> str:
    return child_budget.local_date_for(datetime.now(timezone.utc), 0)


def _preview(client, h, cid) -> dict:
    r = client.get(f"/api/children/{cid}/mission/today?tz_offset_minutes=0", headers=h)
    assert r.status_code == 200, r.text
    return r.json()["mission"]


def _done(client, h, cid, key, note=None):
    return client.post(f"/api/children/{cid}/mission/today/done", headers=h,
                       json={"mission_key": key, "note": note, "tz_offset_minutes": 0})


def test_reading_the_card_writes_nothing(client):
    h = _auth(client, "dev-pm-read")
    cid = _child(client, h)
    first = _preview(client, h, cid)
    assert first["mission_key"] and first["title_ar"]
    assert first["mission_id"] is None and first["status"] == "preview"
    again = _preview(client, h, cid)
    assert again["mission_key"] == first["mission_key"]
    assert _rows(cid) == []


def test_the_preview_is_the_card_the_child_would_get(client):
    h = _auth(client, "dev-pm-same")
    cid = _child(client, h)
    preview = _preview(client, h, cid)
    device = _device_of(cid)
    child_card = cm.today_mission(device, cid, "7-9", _today())
    assert child_card["mission_key"] == preview["mission_key"]


def _device_of(cid: int) -> str:
    conn = get_conn()
    try:
        return conn.execute("SELECT device_id FROM child_profiles WHERE id = ?",
                            (cid,)).fetchone()["device_id"]
    finally:
        conn.close()


def test_done_writes_one_confirmed_row_and_is_idempotent(client):
    h = _auth(client, "dev-pm-done")
    cid = _child(client, h)
    key = _preview(client, h, cid)["mission_key"]
    r = _done(client, h, cid, key, note="أحسنت يا بطل")
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "confirmed"
    again = _done(client, h, cid, key)
    assert again.status_code == 200 and again.json()["mission_id"] == r.json()["mission_id"]
    rows = _rows(cid)
    assert len(rows) == 1
    assert rows[0]["status"] == "confirmed" and rows[0]["parent_note"] == "أحسنت يا بطل"
    assert rows[0]["claimed_at"] is None
    # The card now reads as done, for the parent and for the child's surface.
    assert _preview(client, h, cid)["status"] == "confirmed"
    assert cm.today_mission(rows[0]["device_id"], cid, "7-9", _today())["status"] == "confirmed"


def test_the_note_reaches_the_child_as_praise(client):
    h = _auth(client, "dev-pm-praise")
    cid = _child(client, h)
    key = _preview(client, h, cid)["mission_key"]
    _done(client, h, cid, key, note="فخورون بك")
    assert cm.recent_praise(cid)["note"] == "فخورون بك"


def test_the_childs_own_row_wins(client):
    h = _auth(client, "dev-pm-child-first")
    cid = _child(client, h)
    device = _device_of(cid)
    child_card = cm.today_mission(device, cid, "7-9", _today())
    cm.claim(cid, child_card["mission_id"])
    preview = _preview(client, h, cid)
    assert preview["mission_id"] == child_card["mission_id"]
    assert preview["status"] == "claimed"
    # Even a stale key from an older screen settles the child's row, not a second one.
    other = next(m["id"] for m in cm.load_missions("7-9")
                 if m["id"] != child_card["mission_key"])
    r = _done(client, h, cid, other)
    assert r.status_code == 200 and r.json()["mission_id"] == child_card["mission_id"]
    rows = _rows(cid)
    assert len(rows) == 1 and rows[0]["status"] == "confirmed"
    # …and it leaves the evening list.
    assert cm.pending_for_device(device) == []


def test_an_expired_card_is_not_revived(client):
    h = _auth(client, "dev-pm-expired")
    cid = _child(client, h)
    device = _device_of(cid)
    card = cm.today_mission(device, cid, "7-9", _today())
    conn = get_conn()
    try:
        conn.execute("UPDATE child_missions SET status = 'expired' WHERE id = ?",
                     (card["mission_id"],))
        conn.commit()
    finally:
        conn.close()
    r = _done(client, h, cid, card["mission_key"])
    assert r.status_code == 409


def test_a_key_outside_the_bank_is_refused(client):
    h = _auth(client, "dev-pm-bad-key")
    cid = _child(client, h)
    assert _done(client, h, cid, "not_a_mission").status_code == 404
    assert _rows(cid) == []


def test_another_device_cannot_read_or_settle(client):
    h = _auth(client, "dev-pm-owner")
    cid = _child(client, h)
    key = _preview(client, h, cid)["mission_key"]
    stranger = _auth(client, "dev-pm-stranger")
    assert client.get(f"/api/children/{cid}/mission/today",
                      headers=stranger).status_code == 404
    assert _done(client, stranger, cid, key).status_code == 404
    assert _rows(cid) == []


def test_a_band_without_a_bank_has_no_card(client):
    h = _auth(client, "dev-pm-nobank")
    cid = _child(client, h, age="2-3")
    assert _preview(client, h, cid) is None


def test_the_tap_lights_todays_lantern(client):
    h = _auth(client, "dev-pm-lantern")
    cid = _child(client, h)
    key = _preview(client, h, cid)["mission_key"]
    device = _device_of(cid)
    assert not any(a["kind"] == "mission"
                   for a in family_actions.family_week(device, tz_offset_minutes=0)["acts"])
    _done(client, h, cid, key)
    week = family_actions.family_week(device, tz_offset_minutes=0)
    assert week["lit_this_week"]
    assert any(a["kind"] == "mission" and a["child_id"] == cid for a in week["acts"])
