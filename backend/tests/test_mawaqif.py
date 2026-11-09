"""«موقف بقرار» — the bank and GET /api/program/mawaqif (docs/MAWAQIF.md).

The scripture in the bank is checked by ops/tools/check_scripture_coverage.py
(the bank is a surface in ops/tools/content_surfaces.py); these tests hold the
shape the app renders and the promise contract: every step fits a follow-up
(≤ 120 characters, a known topic), and the English twin pairs item for item.
"""
import json
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.taxonomy import ORDERED_AGE_GROUPS
from app.routers.program import router as program_router
from app.services import child_memory as cm
from app.services import mawaqif

ROOT = Path(__file__).resolve().parents[2]
AR = ROOT / "knowledge_base/curriculum/mawaqif/mawaqif.json"
EN = ROOT / "knowledge_base/curriculum/i18n/en/mawaqif/mawaqif.json"


@pytest.fixture
def client():
    a = FastAPI()
    a.include_router(program_router, prefix="/api")
    with TestClient(a) as c:
        yield c


def _raw(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))["items"]


def test_every_item_is_served_in_both_languages():
    for lang, path in ((None, AR), ("en", EN)):
        raw = _raw(path)
        assert len(mawaqif.load(lang)) == len(raw) > 0, f"{path}: an item failed _valid"


def test_english_twin_pairs_item_for_item():
    ar, en = _raw(AR), _raw(EN)
    assert [i["id"] for i in ar] == [i["id"] for i in en]
    for a, e in zip(ar, en):
        assert (a["age_group"], a["topic"]) == (e["age_group"], e["topic"])
        assert [c["key"] for c in a["choices"]] == [c["key"] for c in e["choices"]]
        # The hadith is quoted in Arabic in both, with the same citation.
        assert a["evidence"]["text_ar"] == e["evidence"]["text_ar"]
        assert a["evidence"]["source"] == e["evidence"]["source"]
        assert e["evidence"].get("meaning"), e["id"]


@pytest.mark.parametrize("path", [AR, EN])
def test_steps_fit_a_followup(path):
    for item in _raw(path):
        assert item["topic"] in cm.FOLLOWUP_TOPICS, item["id"]
        assert len(item["step"]) <= 120, item["id"]
        assert item["age_group"] in ORDERED_AGE_GROUPS, item["id"]
        assert len({c["key"] for c in item["choices"]}) == 3, item["id"]


def test_ids_are_unique_and_name_their_band():
    ids = [i["id"] for i in _raw(AR)]
    assert len(ids) == len(set(ids))
    for item in _raw(AR):
        assert item["id"].startswith(f"mawqif_{item['age_group']}_"), item["id"]


def test_endpoint_serves_the_band(client):
    r = client.get("/api/program/mawaqif", params={"age_group": "7-9"})
    assert r.status_code == 200
    body = r.json()
    assert body["age_group"] == "7-9"
    assert [i["age_group"] for i in body["items"]] == ["7-9"]
    assert body["items"][0]["situation"]


def test_endpoint_english(client):
    r = client.get("/api/program/mawaqif", params={"age_group": "4-6", "lang": "en"})
    item = r.json()["items"][0]
    assert item["title"] == "The broken cup"
    assert item["evidence"]["meaning"]
    via_header = client.get("/api/program/mawaqif", params={"age_group": "4-6"},
                            headers={"Accept-Language": "en-GB,en;q=0.9"})
    assert via_header.json()["items"][0]["title"] == "The broken cup"


def test_band_without_steps_is_an_empty_list(client):
    r = client.get("/api/program/mawaqif", params={"age_group": "prenatal-1"})
    assert r.status_code == 200 and r.json()["items"] == []
    # The legacy alias resolves to its canonical band, not to a 422.
    assert client.get("/api/program/mawaqif", params={"age_group": "0-3"}).status_code == 200


def test_unknown_band_is_rejected(client):
    assert client.get("/api/program/mawaqif", params={"age_group": "99"}).status_code == 422
    assert client.get("/api/program/mawaqif").status_code == 422


def test_malformed_items_are_dropped(monkeypatch, tmp_path):
    bank = tmp_path / "mawaqif"
    bank.mkdir()
    good = _raw(AR)[0]
    bad = {**good, "id": "x", "choices": good["choices"][:2]}
    (bank / "mawaqif.json").write_text(
        json.dumps({"is_published": True, "items": [good, bad, "junk"]}), encoding="utf-8")
    monkeypatch.setattr(mawaqif, "BANK_DIR", bank)
    assert [i["id"] for i in mawaqif.load()] == [good["id"]]
    (bank / "mawaqif.json").write_text("{not json", encoding="utf-8")
    assert mawaqif.load() == []
    (bank / "mawaqif.json").write_text(
        json.dumps({"is_published": False, "items": [good]}), encoding="utf-8")
    assert mawaqif.load() == []
