"""/methodology states what the Seerah stories are — and what they are not.

Season 2 «من السيرة النبوية» (2026-10-30): the Qur'an and the two Sahihs only,
every quote verbatim with its number, no picture of the Prophet ﷺ or a
companion, no invented dialogue — and no human reviewer. The page must say all
of it in both languages, under its own anchor, and claim no review it lacks.
"""
import re

from fastapi.testclient import TestClient


def _page() -> str:
    from app.main import app
    return TestClient(app).get("/methodology").text


def _section(page: str) -> str:
    start = page.index('<h2 id="seerah">')
    end = page.find("<h2", start + 1)
    return page[start:end if end > 0 else len(page)]


def test_seerah_section_has_its_own_anchor_once():
    page = _page()
    assert page.count('id="seerah"') == 1
    assert page.index('id="prophets"') < page.index('id="seerah"')


def test_seerah_section_states_its_sources_and_limits_in_arabic():
    sec = _section(_page())
    for phrase in ("من السيرة النبوية", "القرآن الكريم وصحيحَي البخاري ومسلم", "ولا مصدر لها غيرها",
                   "بنصّ الحديث", "رقم الحديث", "(صحيح البخاري ٦٢٠٣)", "فلا حوار مؤلَّف",
                   "ولا تُرسَم في صفحات القصص صورة النبيّ ﷺ ولا أحدٍ من صحابته",
                   "ولا يراجعها مراجع بشري", "شاركنا رأيك", "support@alsaba.cloud"):
        assert phrase in sec, phrase


def test_seerah_section_states_its_sources_and_limits_in_english():
    sec = _section(_page())
    assert '<section lang="en" dir="ltr">' in sec
    for phrase in ("From the Seerah", "the two Sahihs, al-Bukhari and Muslim", "no other source",
                   "the hadith's own words", "hadith number", "(Sahih al-Bukhari 6203)",
                   "no invented dialogue",
                   "Neither the Prophet ﷺ nor any of his companions is pictured",
                   "No human reviewer — and no one of religious learning — reads these stories",
                   "Share Your Feedback"):
        assert phrase in sec, phrase


def test_seerah_section_claims_no_review_it_does_not_have():
    sec = _section(_page())
    for claim in ("راجعها علماء", "بإشراف", "مراجَعة شرعية", "reviewed by scholars", "scholar-approved",
                  "approved by"):
        assert claim not in sec, claim
    # No other source is named as one of the stories' sources.
    for book in ("الترمذي", "أبي داود", "مسند أحمد", "Tirmidhi", "Abu Dawud", "Ibn Hisham", "ابن هشام"):
        assert book not in sec, book
    assert not re.search(r"\bhasan\b|\bda'?if\b", sec, re.I)
