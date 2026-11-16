"""Tests for the pre-Ramadan 2.0 creative suite («موسم رمضان الإبداعي»).

Covers:
  - SCHEMA_VERSION == 39 and `ramadan_marks.origin_hash` migration
  - `GET /api/children/{id}/ramadan/today` additive fields:
      * Sha'ban 10-day welcome prep (`shaban_prep`, `shaban_stations`)
      * Fawazir lantern tracking (`POST /api/programs/ramadan/fawazir`)
      * Shawwal 2-habit pledge (`PUT /api/programs/ramadan/pledge`)
      * Dual-parent `partner_lantern` with zero `device_id` leak
      * Eid greeting templates + optional `family_word`
  - `GET /print/lantern-craft` (`PR03` / `PR04`, `color` / `bw`) alongside intact `/print/ramadan`
"""
from __future__ import annotations

import json
import os
import re

import pytest
from fastapi.testclient import TestClient

from app.db.init_db import SCHEMA_VERSION, get_conn
from tests.device_proof_support import prove
from tests.programs_support import add_child, client, freeze


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for name in list(os.environ):
        if name.startswith(("RAMADAN_START_", "RAMADAN_DAYS_")) or name in (
            "PROGRAMS_AS_OF_ENABLED",
            "FAMILY_SHARING_ENABLED",
            "SESSION_MINT_ENFORCE",
        ):
            monkeypatch.delenv(name, raising=False)


def test_schema_version_39_and_origin_hash_column():
    assert SCHEMA_VERSION == 39
    conn = get_conn()
    try:
        cols = {r[1] for r in conn.execute("PRAGMA table_info(ramadan_marks)")}
        assert "origin_hash" in cols
    finally:
        conn.close()


def test_shaban_welcome_prep_appears_in_10_day_window_and_hides_earlier(monkeypatch):
    c = client()
    cid = add_child(c)

    # 15 days before start -> outside 10-day window
    freeze(monkeypatch, "2027-01-24T12:00:00")
    early_today = c.get(f"/api/children/{cid}/ramadan/today", params={"tz_offset_minutes": 180}).json()
    assert early_today["state"] == "upcoming"
    assert early_today["shaban_prep"] is None
    assert early_today["shaban_stations"] == []

    # 7 days before start -> day 4 station (days_left == 7)
    freeze(monkeypatch, "2027-02-01T12:00:00")
    ov = c.get("/api/programs", params={"tz_offset_minutes": 180, "lang": "en"}).json()
    assert ov["ramadan"]["shaban_prep_today"]["days_left"] == 7

    in_win = c.get(
        f"/api/children/{cid}/ramadan/today",
        params={"tz_offset_minutes": 180, "lang": "ar"},
    ).json()
    assert in_win["shaban_prep"]["days_left"] == 7
    assert len(in_win["shaban_stations"]) == 10
    assert [s["days_left"] for s in in_win["shaban_stations"]] == list(range(10, 0, -1))


def test_fawazir_lights_lantern_and_shawwal_pledge_validates_and_persists(monkeypatch):
    freeze(monkeypatch, "2027-03-02T19:00:00")  # Ramadan day 23
    c = client()
    cid = add_child(c)

    r_faw = c.post(
        "/api/programs/ramadan/fawazir",
        json={"day": 23, "done": True},
        params={"tz_offset_minutes": 0},
    )
    assert r_faw.status_code == 200, r_faw.text
    body = r_faw.json()
    assert 23 in body["fawazir_days_lit"]
    assert 23 in body["days_marked"]

    # Reject unknown habit key
    bad = c.put(
        "/api/programs/ramadan/pledge",
        json={"habit_keys": ["non_existent_habit"]},
        params={"tz_offset_minutes": 0},
    )
    assert bad.status_code == 422

    # Save 2 valid habits from ramadan_family.json
    today = c.get(f"/api/children/{cid}/ramadan/today", params={"tz_offset_minutes": 0}).json()
    allowed_keys = [h["key"] for h in today["keep_habits"] if h.get("key")]
    assert len(allowed_keys) >= 2
    pick = allowed_keys[:2]
    ok = c.put(
        "/api/programs/ramadan/pledge",
        json={"habit_keys": pick},
        params={"tz_offset_minutes": 0},
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["pledged_habits"] == pick

    # Day 28 family_word picked -> surfaced on today/eid payload for greeting card
    freeze(monkeypatch, "2027-03-07T19:00:00")
    mk_word = c.post(
        "/api/programs/ramadan/marks",
        json={"mark": "family_word", "day": 28, "done": True, "choice_index": 1},
        params={"tz_offset_minutes": 0},
    )
    assert mk_word.status_code == 200, mk_word.text

    freeze(monkeypatch, "2027-03-10T10:00:00")  # Eid
    eid_today = c.get(f"/api/children/{cid}/ramadan/today", params={"tz_offset_minutes": 0}).json()
    assert eid_today["state"] == "eid"
    assert eid_today["pledged_habits"] == pick
    assert 23 in eid_today["fawazir_days_lit"]
    assert len(eid_today["eid_greetings"]) == 6
    assert eid_today["family_word"] is not None


def _proven_user(tc: TestClient, dev_id: str, push_tok: str) -> dict:
    r = tc.post("/api/chat/sessions", json={"device_id": dev_id})
    assert r.status_code == 201, r.text
    hdr = {"Authorization": f"Bearer {r.json()['token']}"}
    prove(tc, hdr, push_token=push_tok)
    return hdr


def _age_cooldown(dev_id: str) -> None:
    conn = get_conn()
    try:
        conn.execute(
            "UPDATE push_tokens SET token_since = datetime(token_since, '-4 days') WHERE device_id = ?",
            (dev_id,),
        )
        conn.execute(
            "UPDATE device_proofs SET first_proven_at = datetime(first_proven_at, '-4 days') WHERE device_id = ?",
            (dev_id,),
        )
        conn.commit()
    finally:
        conn.close()


def test_partner_lantern_harmony_across_paired_parents_without_device_leak(monkeypatch):
    monkeypatch.setenv("FAMILY_SHARING_ENABLED", "1")
    monkeypatch.setenv("SESSION_MINT_ENFORCE", "1")
    freeze(monkeypatch, "2027-02-12T20:00:00")  # Ramadan day 5
    from app.main import app

    dev_mom = "secret-mom-device-111"
    dev_dad = "secret-dad-device-222"
    with TestClient(app) as tc:
        h_mom = _proven_user(tc, dev_mom, "push-mom-111")
        h_dad = _proven_user(tc, dev_dad, "push-dad-222")
        _age_cooldown(dev_mom)
        _age_cooldown(dev_dad)

        cid_mom = tc.post("/api/children", json={"name": "زيد", "age_group": "7-9"}, headers=h_mom).json()["id"]
        inv = tc.post("/api/families/invites", json={"role": "mother", "display_name": "أم زيد"}, headers=h_mom)
        assert inv.status_code == 200, inv.text
        code = inv.json()["code"]
        join = tc.post("/api/families/join", json={"code": code, "role": "father", "display_name": "أبو زيد"}, headers=h_dad)
        assert join.status_code == 200, join.text

        # Mother marks day 5 challenge_done
        mk = tc.post(
            "/api/programs/ramadan/marks",
            json={"mark": "challenge_done", "day": 5, "done": True},
            params={"tz_offset_minutes": 0},
            headers=h_mom,
        )
        assert mk.status_code == 200, mk.text

        # Father checks /api/programs & ramadan/today -> sees partner_lantern from Mother, zero device_id leak!
        ov = tc.get("/api/programs", params={"tz_offset_minutes": 0}, headers=h_dad)
        assert ov.status_code == 200, ov.text
        ov_json = ov.json()
        assert ov_json["ramadan"]["partner_lantern"]["day"] == 5
        assert ov_json["ramadan"]["partner_lantern"]["partner_role"] == "mother"
        assert ov_json["ramadan"]["partner_lantern"]["partner_name"] == "أم زيد"
        serialized_ov = json.dumps(ov_json, ensure_ascii=False)
        assert dev_mom not in serialized_ov and dev_dad not in serialized_ov

        # Resolve father's synced child id
        dad_children = tc.get("/api/children", headers=h_dad).json()["children"]
        assert dad_children and dad_children[0]["id"] != 0
        cid_dad = dad_children[0]["id"] if dad_children else cid_mom
        today = tc.get(f"/api/children/{cid_dad}/ramadan/today", params={"tz_offset_minutes": 0}, headers=h_dad).json()
        assert today["partner_lantern"]["day"] == 5
        assert today["partner_lantern"]["partner_role"] == "mother"
        serialized_today = json.dumps(today, ensure_ascii=False)
        assert dev_mom not in serialized_today and dev_dad not in serialized_today


def test_lantern_craft_printable_pack_bilingual_and_color_modes():
    from app.main import app

    with TestClient(app) as tc:
        # Original /print/ramadan remains intact with 12 sheets
        orig = tc.get("/print/ramadan?lang=ar")
        assert orig.status_code == 200
        assert len(re.findall(r'<section class="sheet', orig.text)) == 12

        # New /print/lantern-craft serves 3 A4 craft sheets with PR03 (ar) / PR04 (en)
        ar_color = tc.get("/print/lantern-craft?lang=ar&ink=color")
        assert ar_color.status_code == 200
        assert len(re.findall(r'<section class="sheet', ar_color.text)) == 3
        assert "qr_PR03.svg" in ar_color.text
        assert "<script" not in ar_color.text.lower()
        assert "play.google.com" not in ar_color.text

        en_bw = tc.get("/print/lantern-craft?lang=en&ink=bw")
        assert en_bw.status_code == 200
        assert len(re.findall(r'<section class="sheet', en_bw.text)) == 3
        assert "qr_PR04.svg" in en_bw.text
        assert "<script" not in en_bw.text.lower()
        assert "play.google.com" not in en_bw.text
