"""/methodology states what the prophets' stories are — and what they are not.

The series has no human reviewer (the maintainer, 2026-10-25). The page must say so in
both languages, and must not claim a review the stories do not get.
"""
from fastapi.testclient import TestClient


def test_prophets_section_in_both_languages_and_no_reviewer_claim():
    from app.main import app
    page = TestClient(app).get("/methodology").text
    for phrase in ("قصص الأنبياء من القرآن", "التفسير الميسَّر", "فلا حوار مؤلَّف",
                   "ولا تُرسَم صورة نبيٍّ", "ولا يراجعها مراجع بشري", "شاركنا رأيك"):
        assert phrase in page, phrase
    for phrase in ("Prophets' stories from the Qur'an", "al-Muyassar tafsir", "no invented dialogue",
                   "No prophet and no one of his people is ever pictured",
                   "No human reviewer — and no one of religious learning — reads these stories", "Share Your Feedback"):
        assert phrase in page, phrase
    for claim in ("راجعها علماء", "بإشراف", "reviewed by scholars", "scholar-approved"):
        assert claim not in page, claim
