"""The assistant's answers: hadith and verses checked before anyone reads them.

Production, 30 days to 2026-11-08 (real devices): 20 of 358 answers quoted a
hadith and 17 broke the rule — 9 cited Abu Dawud («مروا أولادكم بالصلاة»), 7
quoted the Sahihayn with no citation, 3 put words in the Prophet's mouth ﷺ
found in no collection («لولا أنتم لم يغفر الله»). The cases below are those,
plus the grades that decide a Sunan hadith (decision of 2026-11-09: sahih or
hasan by al-Albani stays, with its citation; anything weaker goes).
"""
from __future__ import annotations

import pytest

from app.services import hadith_guard as hg

pytestmark = pytest.mark.skipif(not hg.warm(), reason="hadith indexes not present")

SOURCES = "📚 المصادر: درس «الصلاة في البيت»"


def test_sunan_hadith_graded_sahih_keeps_its_citation_written_in():
    text = ("قال رسول الله ﷺ: «مروا أولادكم بالصلاة وهم أبناء سبع سنين» (رواه أبو داود). "
            "فابدأ معه بلطف.\n\n" + SOURCES)
    r = hg.guard(text, "ar")
    assert "«مروا أولادكم بالصلاة وهم أبناء سبع سنين» (سنن أبي داود — حديث ٤٩٥، وصحّحه الألباني)." in r.text
    assert "رواه أبو داود" not in r.text          # the bare attribution is replaced, not doubled
    assert r.text.endswith(SOURCES)
    assert (r.fixed, r.removed) == (1, 0)
    assert r.flag == "hadith_guard:fixed=1,removed=0"


def test_a_grade_of_hasan_reads_hassanahu(monkeypatch):
    monkeypatch.setattr(hg, "albani_grade", lambda book, n: "Hasan")
    r = hg.guard("قال ﷺ: «مروا أولادكم بالصلاة وهم أبناء سبع سنين». ابدأ بالقدوة.", "ar")
    assert "وحسّنه الألباني" in r.text


@pytest.mark.parametrize("quote", [
    "أكرموا أولادكم وأحسنوا أدبهم",               # Ibn Majah 3671 — Daif
    "ما نحل والد ولدا من نحل أفضل من أدب حسن",     # al-Tirmidhi 1952 — Daif
])
def test_sunan_hadith_graded_weak_is_removed(quote):
    text = f"- ابدأ بالقدوة.\n- قال رسول الله ﷺ: «{quote}». فاحرص على ذلك.\n- كافئه بكلمة طيبة.\n\n{SOURCES}"
    r = hg.guard(text, "ar")
    assert quote not in r.text
    assert "- ابدأ بالقدوة." in r.text and "- كافئه بكلمة طيبة." in r.text
    assert "- فاحرص على ذلك." in r.text          # the list item keeps its marker
    assert r.text.endswith(SOURCES)
    assert r.removed == 1


def test_sahihayn_hadith_without_a_citation_gets_one():
    r = hg.guard("وقال ﷺ: «ليس الشديد بالصرعة». فعلّم ابنك ضبط النفس.", "ar")
    assert "«ليس الشديد بالصرعة» (صحيح البخاري — حديث ٦١١٤)." in r.text
    assert (r.fixed, r.removed) == (1, 0)


def test_words_found_in_no_collection_are_removed():
    text = "لا تيأس من ابنك. قال النبي ﷺ: «لولا أنتم لم يغفر الله». وكن قريبًا منه.\n\n" + SOURCES
    r = hg.guard(text, "ar")
    assert "لولا أنتم" not in r.text
    assert "لا تيأس من ابنك." in r.text and "وكن قريبًا منه." in r.text
    assert r.text.endswith(SOURCES)


def test_an_answer_that_was_only_the_bad_quote_is_not_left_empty():
    r = hg.guard("قال رسول الله ﷺ: «علموا أولادكم الصلاة إذا بلغوا سبعا» وكن صبورًا.", "ar")
    assert r.removed == 1 and "علموا أولادكم" not in r.text
    assert r.text == hg._EMPTY_AR


def test_dhikr_taught_as_words_to_say_is_untouched():
    text = "علّمه أن يقول: «بسم الله» قبل الأكل، و«الحمد لله» بعده."
    r = hg.guard(text, "ar")
    assert r.text == text and not r.flag


def test_english_answer_gets_an_english_citation():
    r = hg.guard("The Prophet ﷺ said: «ليس الشديد بالصرعة». Teach self-control.", "en")
    assert "«ليس الشديد بالصرعة» (Sahih al-Bukhari 6114)." in r.text
    r = hg.guard("He ﷺ said: «مروا أولادكم بالصلاة وهم أبناء سبع سنين». Start gently.", "en")
    assert "(Sunan Abi Dawud 495, graded sahih by al-Albani)" in r.text


def test_a_second_pass_changes_nothing():
    once = hg.guard("قال ﷺ: «مروا أولادكم بالصلاة وهم أبناء سبع سنين». وقال ﷺ: «ليس الشديد "
                    "بالصرعة». ابدأ بالقدوة.", "ar")
    twice = hg.guard(once.text, "ar")
    assert twice.text == once.text and not twice.flag


def test_a_verse_with_the_wrong_reference_is_corrected():
    r = hg.guard("قال تعالى: ﴿وَقُل رَّبِّ زِدْنِي عِلْمًا﴾ [البقرة: ١١٤]، فشجّعه على السؤال.", "ar")
    assert "[طه: ١١٤]" in r.text and r.fixed == 1


def test_words_presented_as_a_verse_that_are_not_the_mushaf_are_removed():
    r = hg.guard("ابدأ بالحوار. قال تعالى: ﴿وعلموا أولادكم الرفق في كل أمر﴾. ثم اسأله عن يومه.", "ar")
    assert "الرفق في كل أمر" not in r.text
    assert "ابدأ بالحوار." in r.text and "ثم اسأله عن يومه." in r.text


def test_no_quotation_no_change():
    text = "اجلس مع ابنك عشر دقائق كل مساء، واسأله عن أجمل ما في يومه.\n\n" + SOURCES
    r = hg.guard(text, "ar")
    assert r.text == text and not r.flag


def test_missing_indexes_leave_the_answer_as_it_was(monkeypatch):
    monkeypatch.setattr(hg, "_scanner", lambda: None)
    text = "قال النبي ﷺ: «لولا أنتم لم يغفر الله»."
    r = hg.guard(text, "ar")
    assert r.text == text and r.available is False


# ── through the real /draft route ───────────────────────────────────────────

@pytest.fixture()
def client(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient

    from app.db.init_db import init_db
    from app.main import app
    from app.routers import assistant
    from app.services import answer_cache, fiqh_guard
    from app.config.guardrails_loader import load_guardrails_config

    monkeypatch.setenv("CONVERSATIONS_DB", str(tmp_path / "t.db"))
    monkeypatch.setattr(fiqh_guard, "_log_block", lambda *a, **k: None)
    init_db()
    app.state.guardrails_config = load_guardrails_config()

    async def _classify(q):
        return ["development"], ""

    async def _no_ayah(_q):
        return None

    async def _reply(*a, **k):
        return ("ابدأ بالقدوة. قال رسول الله ﷺ: «مروا أولادكم بالصلاة وهم أبناء سبع سنين». "
                "وقال ﷺ: «لولا أنتم لم يغفر الله». وكافئه بكلمة طيبة.")

    unit = {"unit_id": "u1", "document": "passage: نصيحة تربوية", "rerank_score": 1.0,
            "metadata": {"domain": "development", "reference_info": "مرجع", "age_group": "7-9"}}
    monkeypatch.setattr(assistant, "_classify_and_rewrite", _classify)
    monkeypatch.setattr(assistant, "resolve_ayah_reference", _no_ayah)
    monkeypatch.setattr(assistant, "_ensure_index", lambda: None)
    monkeypatch.setattr(assistant, "retrieve_hybrid", lambda **k: [unit])
    monkeypatch.setattr(assistant, "log_retrieval", lambda *a, **k: None)
    monkeypatch.setattr(assistant, "generate_reply", _reply)
    monkeypatch.setattr(answer_cache, "lookup", lambda *a, **k: None)
    monkeypatch.setattr(answer_cache, "store", lambda *a, **k: None)
    logged = []
    monkeypatch.setattr(assistant, "log_session", lambda **kw: logged.append(kw))
    c = TestClient(app)
    c.logged = logged
    return c


def test_draft_answer_is_repaired_before_it_is_returned(client):
    tok = client.post("/api/chat/sessions", json={"device_id": "dev-hguard-1"}).json()["token"]
    body = client.post("/api/assistant/draft", headers={"Authorization": f"Bearer {tok}"}, json={
        "age_group": "7-9", "severity": "خفيف", "message_text": "متى أبدأ تعليم ابني الصلاة؟"}).json()
    text = body["reply_text"]
    assert "(سنن أبي داود — حديث ٤٩٥، وصحّحه الألباني)" in text
    assert "لولا أنتم" not in text
    assert "ابدأ بالقدوة." in text and "وكافئه بكلمة طيبة." in text
    assert any("hadith_guard:fixed=1,removed=1" in (kw.get("flag") or "") for kw in client.logged)
