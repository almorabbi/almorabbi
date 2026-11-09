"""/print/ramadan — the Ramadan program as A4 sheets (routers/print_pack.py).

Free printable sheets from our own content, decided 2026-11-09. They are read
from the program at request time, so these tests pin that every day, every
surah of the wird and every safety line reaches paper, and that each sheet
carries its language's registered QR code.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.routers import print_pack as pp
from app.services import attribution as at
from app.services import programs_common as pc

_ROOT = Path(__file__).resolve().parents[2]
_REGISTRY = (_ROOT / "ops" / "data" / "campaign_codes.md").read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def client():
    return TestClient(app)


@pytest.mark.parametrize("lang,url", [("ar", "/print/ramadan"), ("en", "/print/ramadan?lang=en")])
def test_every_day_surah_and_safety_line_reaches_paper(client, lang, url):
    r = client.get(url)
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    html = r.text
    doc = pc.load_program("ramadan_family", lang)
    assert html.count('class="sheet"') == 12
    for d in doc["days"]:
        assert pp._e(d["family_challenge"]["title"]) in html, d["day"]
    for d in doc["days"]:
        q = (d.get("quran") or {}).get("together")
        if q:
            assert pp._e(pp.SURAH_NAMES[q["surah"]][0 if lang == "ar" else 1]) in html
    fl = doc["fasting_ladder"]
    for line in fl["doctor_first"] + fl["stop_signs"] + fl["urgent_signs"] + [fl["stop_action"], fl["urgent_action"]]:
        assert pp._e(line) in html, line[:40]
    for band in fl["bands"].values():
        for step in band["steps"]:
            assert pp._e(step["label"]) in html
    ev = {e["id"]: e for e in doc["evidence"]}
    for i in doc["eid"]["evidence_ids"]:
        assert pp._e(ev[i]["text_ar"]) in html and pp._e(ev[i]["source"]) in html


def test_every_surah_of_the_wird_has_a_name():
    for lang in ("ar", "en"):
        for d in pc.load_program("ramadan_family", lang)["days"]:
            q = (d.get("quran") or {}).get("together")
            assert not q or q["surah"] in pp.SURAH_NAMES, (lang, d["day"], q)


@pytest.mark.parametrize("lang,url", [("ar", "/print/ramadan"), ("en", "/print/ramadan?lang=en")])
def test_each_sheet_carries_its_languages_registered_qr(client, lang, url):
    code = pp.CODES[lang]
    assert at.is_campaign_code(code)
    assert f"| `{code}` |" in _REGISTRY
    html = client.get(url).text
    assert html.count(f'src="/ui/assets/print/qr_{code}.svg"') == 12
    svg = client.get(f"/ui/assets/print/qr_{code}.svg")
    assert svg.status_code == 200
    title = re.search(r"<title>([^<]+)</title>", svg.text).group(1)
    assert title == f"https://tg-api.alsaba.cloud/go?ref={code}"
    # no Play link of its own: the QR and the footer go through /go, which counts the scan
    assert "play.google.com" not in html


def test_nothing_loads_from_a_third_party(client):
    for url in ("/print/ramadan", "/print/ramadan?lang=en"):
        html = client.get(url).text
        assert not re.search(r'<(?:link|script|img|iframe)[^>]+(?:src|href)="(?:https?:)?//', html), url
        assert "<script" not in html  # the print button is an onclick, nothing else runs


def test_the_parent_notes_stay_in_the_app(client):
    html = client.get("/print/ramadan").text
    doc = pc.load_program("ramadan_family", "ar")
    assert not any(pp._e(d["parent_note"]["text"]) in html for d in doc["days"] if d.get("parent_note"))
