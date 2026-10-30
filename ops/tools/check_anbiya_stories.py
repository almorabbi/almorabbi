#!/usr/bin/env python3
"""«قصص الأنبياء من القرآن» — لا نقول عن نبيٍّ إلا ما قاله القرآن.

Why this guard exists (2026-10-25)
----------------------------------
The scripture guards answer one question: is a quoted ﴿verse﴾ the mushaf's, and
is a quoted hadith in the Sahihayn verbatim? A prophet's story fails in ways
they cannot see, because nothing in it is a *quote*:

  * a dialogue written for a prophet — «قال موسى: «…»» — reads as narration;
  * the Qur'an retold in other words passes as prose;
  * an Isra'iliyyat detail — the fish's name, three days in its belly, the
    town's name, a prophet's height — is just another noun in a sentence.

The maintainer's decision for the season (2026-10-25): no human reviewer, so the
documentation has to be strict and checkable. Every story in the series
`anbiya_quran` carries `ops/data/anbiya/<id>.sources.json`
(`ops/tools/anbiya_sources.py` writes it, read-only fetches only), and this
guard holds the story to it:

  1. sources — the file exists, its `content_sha256` is the story's current
     text, every field and sentence it documents is the story's current one,
     every page cites verses, every cited verse exists in
     `mobile/assets/data/quran.json` and its snapshot equals it word for word,
     every cited verse has its Muyassar snapshot;
  2. verses — every ﴿…﴾ on a page lies, whole words, inside one of that page's
     cited verses (the mushaf match itself is `scripture_scan`'s job);
  3. no speech but the Qur'an's — no «» / “” / "" quotation anywhere in the
     Arabic story: anyone's words are said only as the verse, in ﴿﴾;
  4. nothing the sources do not say — a number word, a time word (يوم، أيام،
     سنة…) or a proper name in the narration must occur in that field's own
     verses or Muyassar; and a deny-list of Isra'iliyyat that grows with the
     season (names the Qur'an does not give, durations, ages, physical
     descriptions of prophets) — in Arabic and in the English twin;
  5. fidelity — every sentence carries the verdict of two reviewers from two
     model families other than the author's (`ops/tools/anbiya_fidelity.py`),
     bound to the sentence AND its evidence by a sha; all must be "supported";
  6. the English twin — same series and pages, the same ﴿verses﴾ on each page,
     no quoted speech outside an "interpretation of the meaning"; and the app
     copies byte-identical to docs/.

Exit: 0 clean · 1 violations · 2 the guard itself is broken (self-tests failed,
or sources exist while the enumerator finds no story in the series — a guard
that reads nothing reports ✅, the worst outcome available here).

    python3 ops/tools/check_anbiya_stories.py            # the gate
    python3 ops/tools/check_anbiya_stories.py --self-test
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERIES = "anbiya_quran"
STORIES_AR = ROOT / "docs/stories.json"
STORIES_EN = ROOT / "docs/stories.en.json"
APP_COPIES = {STORIES_AR: ROOT / "mobile/assets/data/stories.json",
              STORIES_EN: ROOT / "mobile/assets/data/stories_en.json"}
SOURCES_DIR = ROOT / "ops/data/anbiya"
MUSHAF = ROOT / "mobile/assets/data/quran.json"
REVIEWERS = ("deepseek-v4-pro", "glm-5.2")   # two families, neither the author's
TAFSIR = "moyassar"

# ── text helpers (shared with anbiya_sources.py / anbiya_fidelity.py) ─────────
VERSE = re.compile(r"﴿([^﴾]*)﴾")
_MARKS = re.compile("[\u0610-\u061a\u064b-\u065f\u06d6-\u06ed\u08f0-\u08f3\u0640]")
_END = re.compile(r"[.!?؟…]+[»”\"'’]*(?=\s|$)")   # the narrator's own sentence split


def fold(text: str) -> str:
    """Letters only, spelling-insensitive: Uthmani and imla'i fold the same."""
    t = (text.replace("\u0649\u0670", "\u0649").replace("\u0670", "\u0627")
         .replace("\u0622", "\u0621\u0627").replace("\u0654", "\u0621"))
    t = _MARKS.sub("", t)
    t = re.sub("[أإؤئ]", "ء", t).replace("ٱ", "ا")
    return t.replace("ة", "ه").replace("ى", "ي")


def words(text: str) -> list[str]:
    return re.findall(r"[ء-ي]+", fold(text))


def outside_verses(text: str) -> str:
    return VERSE.sub(" ", text)


def sentences(text: str) -> list[str]:
    """The narrator's sentences (gen_story_narration.sentences), trimmed."""
    out, start = [], 0
    for m in _END.finditer(text):
        out.append(text[start:m.end()])
        start = m.end()
    out.append(text[start:])
    return [s.strip() for s in out if s.strip()]


def fields_of(story: dict) -> list[tuple[str, str]]:
    """Every text the reader shows for this story, in a fixed order."""
    out = [("title", story.get("title", "")), ("description", story.get("description", ""))]
    for i, p in enumerate(story.get("pages", [])):
        out.append((f"pages[{i}].text", p.get("text", "")))
    pause = story.get("pause") or {}
    for k in ("question", "affirm", "nudge"):
        if pause.get(k):
            out.append((f"pause.{k}", pause[k]))
    for i, o in enumerate(pause.get("options") or []):
        out.append((f"pause.options[{i}]", o))
    for i, q in enumerate(story.get("discussionQuestions") or []):
        out.append((f"discussionQuestions[{i}]", q))
    for k in ("islamicValue", "actionChallenge"):
        if story.get(k):
            out.append((k, story[k]))
    return out


def content_sha(story: dict) -> str:
    return hashlib.sha256(json.dumps(fields_of(story), ensure_ascii=False).encode()).hexdigest()


# Narration in the strict sense — what is said ABOUT the story. Questions and
# challenges address the child (the deny-list and fidelity still cover them).
def is_narrative(path: str) -> bool:
    return path.startswith("pages[") or path in ("description", "pause.affirm", "pause.nudge")


def evidence_sha(sentence: str, refs: list[str], verses: dict, tafsir: dict) -> str:
    blob = json.dumps([sentence, sorted(refs), [verses.get(r, "") for r in sorted(refs)],
                       [tafsir.get(r, "") for r in sorted(refs)]], ensure_ascii=False)
    return hashlib.sha256(blob.encode()).hexdigest()


# ── lexicons ───────────────────────────────────────────────────────────────
def _fold_set(items: str) -> frozenset[str]:
    return frozenset(fold(w) for w in items.split())


NUMBER_WORDS = _fold_set(
    "واحد واحدة اثنان اثنين اثنتان اثنتين ثلاث ثلاثة أربع أربعة خمس خمسة ست ستة سبع سبعة "
    "ثمان ثماني ثمانية تسع تسعة عشر عشرة عشرون عشرين ثلاثون ثلاثين أربعون أربعين خمسون خمسين "
    "ستون ستين سبعون سبعين ثمانون ثمانين تسعون تسعين مائة مئة مائتان مائتين ألف ألفا ألفين آلاف ألوف "
    "مليون ملايين نصف ربع ثلث")
TIME_WORDS = _fold_set(
    "يوم يوما أيام أياما ليلة ليلتين ليال ليالي شهر شهرا أشهر شهور سنة سنتين سنوات سنين عام عاما "
    "أعوام ساعة ساعات أسبوع أسابيع دقيقة دقائق قرن قرون")
# Names a narration might carry. Any of them must be in the field's own verses or
# Muyassar; the ones the Qur'an never names are on the deny-list below as well.
PROPER_NAMES = _fold_set(
    "آدم نوح إدريس هود صالح إبراهيم إسماعيل إسحاق يعقوب يوسف لوط شعيب موسى هارون داود داوود "
    "سليمان أيوب يونس ذا ذي إلياس اليسع زكريا يحيى عيسى مريم محمد أحمد لقمان عزير طالوت جالوت "
    "فرعون هامان قارون آزر ذو القرنين يأجوج مأجوج إبليس جبريل ميكائيل هاروت ماروت "
    "مصر بابل مدين سبأ الأيكة ثمود عاد إرم الحجر الأحقاف طور سيناء الجودي يثرب مكة بكة "
    "نينوى الموصل العراق الشام فلسطين القدس كنعان دجلة الفرات النيل الأردن اليمن الحجاز "
    "متى بلقيس زليخا آسية هاجر سارة")
ARABIC_DENY = [  # (pattern on folded text, why) — Isra'iliyyat and invented detail
    (r"نينوي", "اسم بلد يونس ليس في القرآن"),
    (r"بلقيس", "اسم ملكة سبأ ليس في القرآن"),
    (r"زليخ|راعيل", "اسم امرأة العزيز ليس في القرآن"),
    (r"قطفير|اطفير|فوطيفار", "اسم العزيز ليس في القرآن"),
    (r"(?<![ء-ي])(?:كنعان|يام)(?![ء-ي])", "اسم ابن نوح ليس في القرآن"),
    (r"طاخيه|طاحيه|حرمي|جرمي|منذره", "اسم النملة ليس في القرآن"),
    (r"لوثيا|بهموت|نون(?:ا)?\s+اسم", "اسم الحوت ليس في القرآن"),
    (r"تارح|تارخ", "اسم والد إبراهيم في القرآن آزر"),
    (r"شمعون|يهوذا|روبيل|روبين|بنيامين", "أسماء إخوة يوسف ليست في القرآن"),
    (r"اصف\s+بن\s+برخيا|صخر\s+المارد", "اسم ليس في القرآن"),
    (r"(?:ثلاث|سبع|اربع|عشر)\w*\s+(?:ايام|يوما|ليال|ليالي|ساعات|سنين|سنوات)", "مدة لم يذكرها القرآن"),
    (r"اربعين\s+(?:يوما|ليله|سنه|عاما)|سبعين\s+(?:يوما|سنه|عاما)", "مدة لم يذكرها القرآن"),
    (r"(?:عمره|عمرها|من\s+العمر|في\s+سن)\s", "عُمرٌ لم يذكره القرآن"),
    (r"طويل\s+القامه|قصير\s+القامه|ابيض\s+البشره|اسمر\s+البشره|اشقر|جعد\s+الشعر|سبط\s+الشعر"
     r"|لحيته|ملامحه|حسن\s+الوجه|جميل\s+الوجه|وسيم|عيناه\s+(?:الواسعتان|الجميلتان)", "وصف خَلْقي للنبي"),
    (r"الحوت\s+الازرق|حوت\s+ازرق", "نوع الحوت لم يذكره القرآن"),
    (r"هاله\s+من\s+نور|نور\s+يخرج\s+من\s+وجه", "وصف غيبي مخترع"),
]
ENGLISH_DENY = [
    (r"\bNineveh\b", "a town the Qur'an does not name"),
    (r"\bBilqis\b|\bBalqis\b", "a name the Qur'an does not give"),
    (r"\bZula[iy]?kh?a\b|\bZuleikha\b", "a name the Qur'an does not give"),
    (r"\bPotiphar\b|\bQitfir\b", "a name the Qur'an does not give"),
    (r"\bCanaan\b|\bKan'?an\b|\bYam\b", "Noah's son is not named in the Qur'an"),
    (r"\bTerah\b", "Abraham's father is Azar in the Qur'an"),
    (r"\b(?:three|seven|forty|40|3|7)\s+(?:days|nights|years)\b", "a duration the Qur'an does not give"),
    (r"\bblue whale\b", "a species the Qur'an does not name"),
    (r"\b(?:tall|short|fair[- ]skinned|handsome)\s+(?:man|prophet)\b", "a physical description of a prophet"),
]
_PREFIXES = ("وال", "فال", "بال", "كال", "لل", "ال", "و", "ف", "ب", "ل", "ك")


def _bases(token: str) -> set[str]:
    out = {token}
    for p in _PREFIXES:
        if token.startswith(p) and len(token) - len(p) >= 2:
            out.add(token[len(p):])
            if p in ("و", "ف", "ب", "ك") and token[len(p):].startswith("ال") and len(token) - len(p) > 4:
                out.add(token[len(p) + 2:])
    # tanween alif / feminine endings the lexicons list without
    out |= {b[:-1] for b in list(out) if b.endswith("ا") and len(b) > 3}
    return out


def flagged_tokens(text: str, evidence: str) -> list[tuple[str, str]]:
    """(kind, word) for each number/time/name word in [text] that [evidence] never uses."""
    ev = set()
    for w in words(evidence):
        ev |= _bases(w)
    out = []
    for raw in re.findall(r"[\u0621-\u065f\u0670-\u06ed]+", outside_verses(text)):
        b = set().union(*(_bases(w) for w in words(raw))) if words(raw) else set()
        for kind, lex in (("رقم", NUMBER_WORDS), ("مدة/زمن", TIME_WORDS), ("اسم علم", PROPER_NAMES)):
            if b & lex and not (b & lex & ev):
                out.append((kind, _MARKS.sub("", raw)))
    for d in re.findall(r"[0-9٠-٩]+", outside_verses(text)):
        if d not in evidence:
            out.append(("رقم", d))
    return out


def denied(text: str, evidence: str, lang: str) -> list[str]:
    hits = []
    if lang == "ar":
        t, e = fold(outside_verses(text)), fold(evidence)
        for pat, why in ARABIC_DENY:
            for m in re.finditer(pat, t):
                if m.group(0) not in e:
                    hits.append(f"«{m.group(0)}» — {why}")
    else:
        for pat, why in ENGLISH_DENY:
            # A duration the Qur'an itself gives (﴿ثَلَٰثَ لَيَالٖ﴾, Maryam 10) is
            # allowed in English exactly when the Arabic twin field says a number
            # its own sources carry — [evidence] is then that number, else "".
            if why.startswith("a duration") and evidence:
                continue
            for m in re.finditer(pat, text, re.I):
                hits.append(f"“{m.group(0)}” — {why}")
    return hits


def sourced_numbers(text: str, evidence: str) -> str:
    """The number words of [text] (outside verses) that [evidence] also uses — "" if none."""
    ev = set()
    for w in words(evidence):
        ev |= _bases(w)
    found = [w for w in words(outside_verses(text)) if _bases(w) & NUMBER_WORDS & ev]
    return " ".join(found)


_CITE = re.compile(r"﴿([^﴾]*)﴾\s*[\[(]\s*(?:سورة\s+)?([^\]\[():\d٠-٩]{1,20}?)\s*[:：]\s*([0-9٠-٩]{1,3})\s*[\])]")


def _surah_number(name: str) -> int | None:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from check_quran_citations import ALIAS, SURAHS  # noqa: PLC0415
    n = name.strip()
    n = ALIAS.get(n, n)
    for cand in (n, n.removeprefix("ال"), "ال" + n):
        if cand in SURAHS:
            return SURAHS.index(cand) + 1
    return None


def miscited(text: str, quran: dict[str, str]) -> list[str]:
    """﴿verse﴾ [سورة: آية] whose cited place does not hold the verse — every surah,
    the one-letter ones (ص، ق، ن) included, which scripture_scan cannot read."""
    out = []
    for q, name, num in _CITE.findall(text):
        sn = _surah_number(name)
        ref = f"{sn}:{int(num.translate(str.maketrans('٠١٢٣٤٥٦٧٨٩', '0123456789')))}" if sn else None
        if ref is None or not verse_in(q, quran.get(ref, "")):
            out.append(f"﴿{q[:30]}…﴾ ليست في الموضع المذكور [{name.strip()}: {num}]")
    return out


# ── the Qur'an ─────────────────────────────────────────────────────────────
_mushaf_cache: dict | None = None


def mushaf() -> dict[str, str]:
    global _mushaf_cache
    if _mushaf_cache is None:
        raw = json.loads(MUSHAF.read_text(encoding="utf-8"))
        _mushaf_cache = {f"{a['chapter']}:{a['verse']}": a["text"] for ay in raw.values() for a in ay}
    return _mushaf_cache


def verse_in(quote: str, ayah: str) -> bool:
    """[quote] is a run of whole words of [ayah] (after folding)."""
    q = [w for w in (fold(x) for x in quote.split()) if w]
    a = [w for w in (fold(x) for x in ayah.split()) if w]
    return bool(q) and any(a[i:i + len(q)] == q for i in range(len(a) - len(q) + 1))


_REF = re.compile(r"^\d{1,3}:\d{1,3}$")
_SPEECH_QUOTES = re.compile(r"[«»“”\"]")


# ── the check ──────────────────────────────────────────────────────────────
def check_story(ar: dict, src: dict | None, en: dict | None, quran: dict[str, str]) -> list[str]:
    sid = ar.get("id", "?")
    errs: list[str] = []
    if src is None:
        return [f"{sid}: لا ملف مصادر — python3 ops/tools/anbiya_sources.py fetch {sid}"]
    verses, tafsir = src.get("verses") or {}, src.get("tafsir") or {}
    if src.get("id") != sid:
        errs.append(f"{sid}: ملف المصادر لقصة أخرى ({src.get('id')})")
    if src.get("tafsir_source") != TAFSIR:
        errs.append(f"{sid}: مصدر التفسير ليس الميسّر ({src.get('tafsir_source')})")
    if src.get("content_sha256") != content_sha(ar):
        errs.append(f"{sid}: نص القصة تغيّر بعد توثيق مصادرها (sha) — أعد anbiya_sources.py fetch ثم المراجعة")

    for ref in sorted(set(verses) | set(tafsir)):
        if not _REF.match(ref) or ref not in quran:
            errs.append(f"{sid}: المرجع {ref} ليس آية في المصحف")
        elif verses.get(ref) != quran[ref]:
            errs.append(f"{sid}: لقطة الآية {ref} لا تطابق المصحف حرفًا بحرف")
        if not (tafsir.get(ref) or "").strip():
            errs.append(f"{sid}: لا نص ميسّر محفوظ للآية {ref}")

    documented = {f.get("path"): f for f in src.get("fields") or []}
    current = fields_of(ar)
    if [p for p, _ in current] != [f.get("path") for f in src.get("fields") or []]:
        errs.append(f"{sid}: حقول ملف المصادر ليست حقول القصة الحالية")
    for path, text in current:
        where = f"{sid} :: {path}"
        doc = documented.get(path)
        if doc is None:
            errs.append(f"{where}: غير موثَّق في ملف المصادر")
            continue
        refs = doc.get("refs") or []
        if path.startswith("pages[") and not refs:
            errs.append(f"{where}: صفحة بلا آيات مصدر")
        missing = [r for r in refs if r not in verses]
        if missing:
            errs.append(f"{where}: مراجع بلا لقطة آية: {', '.join(missing)}")
        evidence = " ".join(verses.get(r, "") + " " + tafsir.get(r, "") for r in refs)

        if _SPEECH_QUOTES.search(text):
            errs.append(f"{where}: اقتباس بين «» أو “” — كلام أي شخصية بنص الآية بين ﴿﴾ وحده")
        if path.startswith("pages["):
            for q in VERSE.findall(text):
                if not any(verse_in(q, quran.get(r, "")) for r in refs):
                    errs.append(f"{where}: ﴿{q[:40]}…﴾ ليست من آيات الصفحة ({', '.join(refs)})")
        else:
            for q in VERSE.findall(text):
                if not any(verse_in(q, quran.get(r, "")) for r in verses):
                    errs.append(f"{where}: ﴿{q[:40]}…﴾ ليست من آيات القصة")
        if is_narrative(path):
            for kind, w in flagged_tokens(text, evidence):
                errs.append(f"{where}: {kind} «{w}» ليس في آيات الحقل ولا في ميسّرها")
        for hit in denied(text, evidence, "ar"):
            errs.append(f"{where}: {hit}")
        for hit in miscited(text, quran):
            errs.append(f"{where}: {hit}")

        sents = doc.get("sentences") or []
        if [s.get("text") for s in sents] != sentences(text):
            errs.append(f"{where}: جمل ملف المصادر ليست جمل النص الحالي")
            continue
        for s in sents:
            srefs = s.get("refs") or []
            if path.startswith("pages[") and not srefs:
                errs.append(f"{where}: جملة بلا آيات: «{s['text'][:50]}»")
            if any(r not in refs for r in srefs):
                errs.append(f"{where}: جملة تستند إلى آية ليست من آيات الحقل: «{s['text'][:50]}»")
            fid = s.get("fidelity") or {}
            reviews = fid.get("reviews") or {}
            if fid.get("sha") != evidence_sha(s["text"], srefs, verses, tafsir):
                errs.append(f"{where}: حكم الأمانة لا يخص هذه الجملة بمصادرها الحالية: «{s['text'][:50]}»")
            elif fid.get("verdict") != "supported" or any(
                    (reviews.get(r) or {}).get("verdict") != "supported" for r in REVIEWERS):
                errs.append(f"{where}: جملة غير «مدعومة» عند المراجعَين: «{s['text'][:50]}»")

    if en is None:
        errs.append(f"{sid}: لا توأم إنجليزي")
    else:
        if en.get("series") != SERIES:
            errs.append(f"{sid} (en): بلا series {SERIES}")
        ep, ap = en.get("pages") or [], ar.get("pages") or []
        if len(ep) != len(ap):
            errs.append(f"{sid} (en): {len(ep)} صفحات مقابل {len(ap)}")
        for i, (a, e) in enumerate(zip(ap, ep)):
            if VERSE.findall(a.get("text", "")) != VERSE.findall(e.get("text", "")):
                errs.append(f"{sid} (en) pages[{i}]: آيات الصفحة ليست هي هي آيات العربي")
        ar_fields = dict(fields_of(ar))
        for path, text in fields_of(en):
            doc = documented.get(path) or {}
            ev = " ".join(verses.get(r, "") + " " + tafsir.get(r, "") for r in doc.get("refs") or [])
            for hit in denied(text, sourced_numbers(ar_fields.get(path, ""), ev), "en"):
                errs.append(f"{sid} (en) :: {path}: {hit}")
            for m in re.finditer(r"[“\"]", text):
                before = text[:m.start()]
                seg = before[before.rfind("﴾") + 1:] if "﴾" in before else None
                if seg is None or "interpretation of the meaning" not in seg.lower():
                    errs.append(f"{sid} (en) :: {path}: اقتباس كلامٍ خارج «interpretation of the meaning»")
                    break
    return errs


def _load_sources(sid: str) -> dict | None:
    p = SOURCES_DIR / f"{sid}.sources.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def run(ar_list: list[dict], en_list: list[dict], load_src, quran) -> list[str]:
    en_by = {s.get("id"): s for s in en_list}
    errs = []
    for s in ar_list:
        if s.get("series") == SERIES:
            errs += check_story(s, load_src(s["id"]), en_by.get(s["id"]), quran)
    ar_ids = {s.get("id") for s in ar_list if s.get("series") == SERIES}
    for s in en_list:
        if s.get("series") == SERIES and s.get("id") not in ar_ids:
            errs.append(f"{s.get('id')} (en): في السلسلة بالإنجليزي وليس بالعربي")
    return errs


# ── self-tests: a clean fixture must pass, every mutation must be caught ─────
def _fixture() -> tuple[dict, dict, dict]:
    quran = mushaf()
    ref = "37:142"
    ar = {"id": "selftest_yunus", "title": "اختبار", "description": "قصة للاختبار.",
          "series": SERIES,
          "pages": [{"pageNumber": 1, "text": "فأُلقي يونسُ في البحر، فابتلعه الحوت. قال تعالى: ﴿فَٱلۡتَقَمَهُ ٱلۡحُوتُ﴾."}]}
    tafsir = {ref: "فأُلقي في البحر، فابتلعه الحوت، ويونس عليه السلام آتٍ بما يُلام عليه."}
    verses = {ref: quran[ref]}
    src = {"id": ar["id"], "tafsir_source": TAFSIR, "verses": verses, "tafsir": tafsir, "fields": []}
    for path, text in fields_of(ar):
        refs = [ref] if path.startswith("pages[") else []
        sents = []
        for t in sentences(text):
            sents.append({"text": t, "refs": refs, "fidelity": {
                "verdict": "supported", "reviews": {r: {"verdict": "supported"} for r in REVIEWERS},
                "sha": evidence_sha(t, refs, verses, tafsir)}})
        src["fields"].append({"path": path, "refs": refs, "sentences": sents})
    src["content_sha256"] = content_sha(ar)
    en = {"id": ar["id"], "series": SERIES, "title": "Test", "description": "A test.",
          "pages": [{"pageNumber": 1, "text": "Yunus was cast into the sea and the whale swallowed him. "
                     "Allah says: ﴿فَٱلۡتَقَمَهُ ٱلۡحُوتُ﴾ — interpretation of the meaning: \"Then the fish swallowed him.\""}]}
    return ar, src, en


def _edit_page(text: str):
    def f(ar, src, en):
        ar["pages"][0]["text"] = text
    return f


def _resign(ar: dict, src: dict) -> None:
    """Re-document after a mutation, as a careless author would — so only the
    rule under test can catch it (not the sha / sentence bookkeeping)."""
    verses, tafsir = src["verses"], src["tafsir"]
    src["fields"] = []
    for path, text in fields_of(ar):
        refs = list(verses) if path.startswith("pages[") else []
        src["fields"].append({"path": path, "refs": refs, "sentences": [
            {"text": t, "refs": refs, "fidelity": {
                "verdict": "supported", "reviews": {r: {"verdict": "supported"} for r in REVIEWERS},
                "sha": evidence_sha(t, refs, verses, tafsir)}} for t in sentences(text)]})
    src["content_sha256"] = content_sha(ar)


def _unsupported(ar, src, en):
    s = src["fields"][2]["sentences"][0]
    s["fidelity"]["verdict"] = "unsupported"
    s["fidelity"]["reviews"]["glm-5.2"]["verdict"] = "unsupported"


def _stale(ar, src, en):
    ar["pages"][0]["text"] = ar["pages"][0]["text"].replace("البحر", "البحر العميق")


def _bad_snapshot(ar, src, en):
    src["verses"]["37:142"] = src["verses"]["37:142"].replace("ٱلۡحُوتُ", "ٱلۡبَحۡرُ")


def _en_quote(ar, src, en):
    en["pages"][0]["text"] = 'Yunus said, "I will go." ' + en["pages"][0]["text"]


def _en_missing_verse(ar, src, en):
    en["pages"][0]["text"] = "Yunus was cast into the sea and the whale swallowed him."


def _en_deny(ar, src, en):
    en["pages"][0]["text"] += " He stayed there three days."


def _no_sources(ar, src, en):
    src.clear()


def _miscite(ar, src, en):
    ar["islamicValue"] = "﴿فَٱلۡتَقَمَهُ ٱلۡحُوتُ﴾ [ص: ٤٤]"


MUTATIONS = [  # (what must be caught, mutation, re-sign after it?, a word the report must carry)
    ("حوار مؤلَّف بين «»", _edit_page("قال يونسُ: «سأذهب». فأُلقي يونسُ في البحر، فابتلعه الحوت."), True, "اقتباس"),
    ("رقم ليس في الآيات", _edit_page("فأُلقي يونسُ في البحر، فابتلعه الحوت، فبقي في بطنه ثلاثة أيام."), True, "رقم «ثلاثة»"),
    ("اسم ممنوع", _edit_page("خرج يونسُ من نينوى، فأُلقي في البحر، فابتلعه الحوت."), True, "اسم بلد يونس"),
    ("اسم علم ليس في المصادر", _edit_page("فأُلقي يونسُ في البحر، فابتلعه الحوت، وموسى ينظر."), True, "اسم علم «وموسى»"),
    ("وصف خَلْقي", _edit_page("وكان يونسُ طويلَ القامة، فأُلقي في البحر، فابتلعه الحوت."), True, "وصف خَلْقي"),
    ("آية ليست من آيات الصفحة", _edit_page("فابتلعه الحوت: ﴿قُلۡ هُوَ ٱللَّهُ أَحَدٌ﴾."), True, "ليست من آيات الصفحة"),
    ("نص تغيّر بعد التوثيق", _stale, False, "(sha)"),
    ("جملة غير مدعومة", _unsupported, False, "غير «مدعومة»"),
    ("لقطة آية محرّفة", _bad_snapshot, False, "لا تطابق المصحف"),
    ("ملف مصادر مفقود", _no_sources, False, "لا ملف مصادر"),
    ("اقتباس في الإنجليزي", _en_quote, False, "interpretation of the meaning"),
    ("آية ناقصة في الإنجليزي", _en_missing_verse, False, "آيات الصفحة ليست"),
    ("مدة في الإنجليزي", _en_deny, False, "three days"),
    ("إحالة لسورة بحرف واحد غلط", _miscite, True, "ليست في الموضع المذكور"),
]


def self_test() -> str | None:
    quran = mushaf()
    ar, src, en = _fixture()
    errs = check_story(ar, src, en, quran)
    if errs:
        return f"القصة السليمة رُفضت: {errs[0]}"
    for what, mutate, resign, mark in MUTATIONS:
        a, s, e = copy.deepcopy(ar), copy.deepcopy(src), copy.deepcopy(en)
        mutate(a, s, e)
        if resign:
            _resign(a, s)
        got = check_story(a, s or None, e, quran)
        if not any(mark in g for g in got):  # caught, and for the right reason
            return f"لم تُرصد الطفرة: {what}" + (f" (رُصد غيرها: {got[0]})" if got else "")
    # a duration the verse gives: allowed in English only beside its sourced Arabic
    if denied("for three nights", sourced_numbers("ثلاث ليال", "ثلاث ليال سويا"), "en"):
        return "مدة من الآية نفسها رُفضت في الإنجليزي"
    if not denied("for three nights", sourced_numbers("ليال", "ثلاث ليال"), "en"):
        return "مدة بلا عدد مُسنَد في العربي قُبلت في الإنجليزي"
    if miscited("﴿إِنَّا وَجَدۡنَٰهُ صَابِرٗاۚ﴾ [ص: ٤٤]", quran) or not miscited("﴿فَٱلۡتَقَمَهُ ٱلۡحُوتُ﴾ [الصافات: ١٤٣]", quran):
        return "فحص الإحالة لا يعمل"
    # the lexicon helpers themselves
    if flagged_tokens("بقي ثلاثةَ أيامٍ", "") == [] or flagged_tokens("إلى مائةِ ألفٍ", "إلى مائة ألف") != []:
        return "معجم الأرقام لا يعمل"
    if not verse_in("وَهُمۡ لَا يَشۡعُرُونَ", mushaf()["27:18"]) or verse_in("لَا يَشۡعُرُ", mushaf()["27:18"]):
        return "مطابقة الآية بالكلمات الكاملة لا تعمل"
    return None


def main(argv: list[str]) -> int:
    print("\n" + "=" * 67)
    print("  ANBIYA — لا نقول عن نبيٍّ إلا ما قاله القرآن")
    print("=" * 67)
    try:
        why = self_test()
    except Exception as exc:  # noqa: BLE001 — a crashing self-test is a broken guard
        why = f"{type(exc).__name__}: {exc}"
    if why:
        print(f"\n🔴  SELF-TEST: {why} — الفحص لاغٍ.\n")
        return 2
    print(f"  self-tests: قصة سليمة ✓ · {len(MUTATIONS)} طفرة مرصودة ✓")
    if "--self-test" in argv:
        return 0

    ar_list = json.loads(STORIES_AR.read_text(encoding="utf-8"))
    en_list = json.loads(STORIES_EN.read_text(encoding="utf-8")) if STORIES_EN.exists() else []
    series = [s for s in ar_list if s.get("series") == SERIES]
    documented = sorted(SOURCES_DIR.glob("*.sources.json")) if SOURCES_DIR.exists() else []
    if documented and not series:
        print(f"\n🔴  {len(documented)} ملف مصادر ولا قصة واحدة في السلسلة — المعدِّد لم يعد يقرأ القصص.\n")
        return 2
    # the mutations again, on a real story this time
    if series:
        real = copy.deepcopy(series[0])
        real["pages"][0]["text"] += " قال: «لن أعود»."
        if not check_story(real, _load_sources(real["id"]), None, mushaf()):
            print("\n🔴  طفرة على قصة حقيقية لم تُرصد — الفحص لاغٍ.\n")
            return 2

    errors = run(ar_list, en_list, _load_sources, mushaf())
    orphans = [p.name for p in documented
               if p.name.removesuffix(".sources.json") not in {s["id"] for s in series}]
    errors += [f"{o}: ملف مصادر لقصة ليست في السلسلة" for o in orphans]
    for docs, app in APP_COPIES.items():
        if app.exists() and docs.exists() and app.read_bytes() != docs.read_bytes():
            errors.append(f"{app.relative_to(ROOT)} ليست مطابقة بايتًا ببايت لـ {docs.relative_to(ROOT)}")

    n_sent = sum(len(f.get("sentences") or []) for s in series
                 for f in (_load_sources(s["id"]) or {}).get("fields") or [])
    print(f"  القصص في السلسلة: {len(series)} · جمل موثّقة: {n_sent}")
    if errors:
        print(f"\n🔴  {len(errors)} مخالفة:")
        for e in errors[:60]:
            print(f"     ✗ {e}")
        if len(errors) > 60:
            print(f"     … و{len(errors) - 60} أخرى")
        print("\n" + "=" * 67)
        print("  ❌  قصة نبيٍّ فيها ما لا تسنده آياتها وتفسيرها الميسّر — لا يجوز الدفع.")
        print("=" * 67 + "\n")
        return 1
    print("\n" + "=" * 67)
    print("  ✅  ANBIYA OK — كل جملة موثّقة بآياتها وميسّرها ومراجَعة بعائلتين")
    print("  (فحص آلي ومراجعة نماذج — ليس مراجعة بشرية ولا إجازة شرعية)")
    print("=" * 67 + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
