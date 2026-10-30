#!/usr/bin/env python3
"""«من السيرة النبوية» — لا نروي عن النبيّ ﷺ ولا عن صحابته إلا ما في القرآن والصحيحين.

Why this guard exists (2026-10-30)
----------------------------------
Season 2 of the stories tells the Seerah. `check_anbiya_stories.py` holds a
prophet's story to the Qur'an alone and forbids every «» quotation; a Seerah
story is the opposite case — its heart is the hadith, quoted — and it fails in
its own ways, none of which the scripture guards see:

  * a famous detail that no sahih narration carries — the spider's web and
    the two doves at the cave, the tree at its mouth, the snake that bit Abu
    Bakr, a minbar "of three steps", the name of its carpenter or of the
    trunk — is just another noun in a sentence;
  * a quote can be the Sahihayn's words and still sit under the wrong number,
    or be two narrations stitched into one;
  * speech can be reported without quotes («قال أنس: …») — paraphrase dressed
    as narration, the thing the series promises never to do;
  * a number, a name or a place slips into the narration from memory.

The maintainer's decision (2026-10-30, no human reviewer): sources are ONLY the Qur'an
and Sahih al-Bukhari / Sahih Muslim. Every story in the series `sira_sahih`
carries `ops/data/sira/<id>.sources.json` (`ops/tools/sira_sources.py` writes
it, read-only fetches only), and this guard holds the story to it:

  1. sources — the file exists, its `content_sha256` is the story's current
     text, every field and sentence it documents is the story's current one,
     every page cites sources; every cited hadith is Bukhari/Muslim, its display
     text is the pinned edition's (its skeleton holds the hadith index entry the
     scripture guards use, built from the same edition), every cited verse is
     the mushaf's word for word with its Muyassar snapshot;
  2. quotes — every «» is followed, in its sentence, by a Sahihayn citation
     «(صحيح البخاري ٦٢٠٣)» whose number holds it verbatim as ONE run of ONE
     narration (`scripture_scan.sahihayn_holds`) — a stitched pair fails; the
     cited hadith is one of the field's own sources; no «» goes uncited, and
     no “” / "" in the Arabic;
  3. no unquoted speech — «قال/فقال/قالوا …:» is followed by «» or ﴿﴾;
  4. verses — every ﴿…﴾ lies, whole words, inside the field's cited verses;
  5. nothing the sources do not say — a number word, a time word or a proper
     name in the narration (outside «», ﴿﴾ and citations) occurs in that
     field's own evidence; a name introduced with «يقال له / اسمه» must be the
     evidence's; and a deny-list of famous non-sahih Seerah details, invented
     names, promises of reward and rankings — in Arabic and in the English twin;
  6. fidelity — every sentence carries the verdict of two reviewers from two
     model families other than the author's (`ops/tools/anbiya_fidelity.py
     --series sira_sahih`), bound to the sentence AND its evidence by a sha;
     all must be "supported";
  7. the English twin — same series and pages, the same ﴿verses﴾ per page, the
     same hadith citations per field («(Sahih al-Bukhari 6203)»), every English
     quotation either a cited hadith or inside an "interpretation of the
     meaning"; and the app copies byte-identical to docs/.

Exit: 0 clean · 1 violations · 2 the guard itself is broken (self-tests failed,
or sources exist while the enumerator finds no story in the series).

    python3 ops/tools/check_sira_stories.py            # the gate
    python3 ops/tools/check_sira_stories.py --self-test
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_anbiya_stories as A  # noqa: E402  — shared text helpers, mushaf, lexicons
import scripture_scan as SS  # noqa: E402
from check_hadith_citations import _AR_DIGITS, _narrations, skeleton  # noqa: E402

ROOT = A.ROOT
SERIES = "sira_sahih"
STORIES_AR, STORIES_EN, APP_COPIES = A.STORIES_AR, A.STORIES_EN, A.APP_COPIES
SOURCES_DIR = ROOT / "ops/data/sira"
REVIEWERS = A.REVIEWERS
TAFSIR = A.TAFSIR
# The display text of a hadith comes from the edition the hadith index was
# built from (build_hadith_index.py), pinned to one commit so it cannot drift.
EDITION = "fawazahmed0/hadith-api@df57907be35291c91ad6a6691180e22ca9920784"
EDITION_URL = "https://cdn.jsdelivr.net/gh/" + EDITION + "/editions/{ed}/{n}.json"
EDITIONS = {"البخاري": "ara-bukhari", "مسلم": "ara-muslim"}
BOOK_KEY = {"البخاري": "bukhari", "مسلم": "muslim"}
BOOK_OF = {v: k for k, v in BOOK_KEY.items()}

fold, words, sentences, fields_of, content_sha = A.fold, A.words, A.sentences, A.fields_of, A.content_sha
is_narrative, verse_in, mushaf, miscited, VERSE = A.is_narrative, A.verse_in, A.mushaf, A.miscited, A.VERSE

_HADITH_REF = re.compile(r"^(bukhari|muslim):(\d{1,5})$")
_VERSE_REF = re.compile(r"^\d{1,3}:\d{1,3}$")
QUOTE = re.compile(r"«([^«»]*)»")
CITE = re.compile(r"\(\s*صحيح\s+(البخاري|مسلم)\s*(?:[—\-–]\s*)?(?:حديث\s*)?([٠-٩0-9]{1,5})\s*\)")
AYAH_REF = re.compile(r"\[[^\]\[]{1,30}?[:：]\s*[0-9٠-٩]{1,3}\s*\]")
_SENT_END = re.compile(r"[.!?؟]")
_SPEECH = re.compile(r"(?<![ء-ي])[وف]?(?:قال|قالت|قالوا|يقول|تقول|يقولون)(?![ء-ي])([^.!?؟:«»﴿﴾]{0,60}?):")
EN_QUOTE = re.compile(r"“([^”]*)”|\"([^\"]*)\"")
EN_CITE = re.compile(r"\(\s*Sahih\s+(?:al-)?(Bukhari|Muslim)\s+(\d{1,5})\s*\)", re.I)


def ref_of(book: str, number: int | str) -> str:
    return f"{BOOK_KEY[book]}:{int(str(number).translate(_AR_DIGITS))}"


def is_hadith_ref(ref: str) -> bool:
    return bool(_HADITH_REF.match(ref))


def evidence_of(ref: str, doc: dict) -> str:
    """The text a sentence citing [ref] may rest on: the hadith's display text,
    or the verse with its Muyassar."""
    if is_hadith_ref(ref):
        return ((doc.get("hadith") or {}).get(ref) or {}).get("text", "")
    return (doc.get("verses") or {}).get(ref, "") + " " + (doc.get("tafsir") or {}).get(ref, "")


def evidence_sha(sentence: str, refs: list[str], doc: dict) -> str:
    rs = sorted(refs)
    blob = json.dumps([sentence, rs, [evidence_of(r, doc) for r in rs]], ensure_ascii=False)
    return hashlib.sha256(blob.encode()).hexdigest()


def blank(pattern: re.Pattern, text: str) -> str:
    """[text] with every match of [pattern] replaced by spaces of its length —
    positions stay where they were."""
    return pattern.sub(lambda m: " " * len(m.group(0)), text)


def narration_of(text: str) -> str:
    """What the narrator says in his own words: no «hadith», no ﴿verse﴾, no
    citation — those are checked against their sources directly."""
    for p in (QUOTE, VERSE, CITE, AYAH_REF):
        text = blank(p, text)
    return text


# ── lexicons ───────────────────────────────────────────────────────────────
# Season 1's names, minus three that are everyday words in a Seerah story
# («الذي» folds to a base «ذي»; «متى» is a question), plus the Seerah's own.
PROPER_NAMES = (A.PROPER_NAMES - A._fold_set("ذا ذي متى")) | A._fold_set(
    "أنس مالك جابر بكر الصديق عمير النجار عمرو عوف قريش المدينة ثور يثرب خديجة عائشة "
    "فاطمة عمر عثمان أسماء سراقة بلال حمزة العباس زيد حارثة معاذ هريرة مسعود عامر فهيرة "
    "الدغنة أريقط ميمون باقوم الحنانة ورقة نوفل حليمة آمنة المطلب")
NUMBER_WORDS, TIME_WORDS = A.NUMBER_WORDS, A.TIME_WORDS
_NUM_CANON = [(re.compile(r"^اثن(?:ان|ين|تان|تين)$"), "اثن"), (re.compile(r"^ثماني(?:ه)?$"), "ثمان")]


def _canon(w: str) -> str:
    """One spelling per number: «الاثنان» is «اثنين», «ثلاثة» is «ثلاث»."""
    for pat, root in _NUM_CANON:
        if pat.match(w):
            return root
    return w[:-1] if w.endswith("ه") and len(w) > 3 else w


def _bases(token: str) -> set[str]:
    return A._bases(token)


def _ev_bases(evidence: str) -> set[str]:
    out: set[str] = set()
    for w in words(evidence):
        out |= _bases(w)
    return out


def _numbers(bases: set[str]) -> set[str]:
    return {_canon(w) for w in bases if w in NUMBER_WORDS}


_NAME_INTRO = re.compile(r"(?<![ء-ي])(?:يقال|اسمه|اسمها|اسمهم|يدعي|تدعي|يسمي|تسمي|سمي)\s+(?:لهم|لها|له)?\s*([ء-ي\s]{2,60})")
_NAME_GLUE = A._fold_set("بن بنت ابن أبو أبي أبا أم بني بنو آل عبد")


def flagged_tokens(text: str, evidence: str) -> list[tuple[str, str]]:
    """(kind, word) for each number/time/name word in the narration of [text]
    that [evidence] never uses — and each word of a name introduced with
    «يقال له / اسمه» that the evidence does not carry."""
    ev = _ev_bases(evidence)
    ev_numbers = _numbers(ev)
    own = narration_of(text)
    out = []
    for raw in re.findall(r"[\u0621-\u065f\u0670-\u06ed]+", own):
        b = set().union(*(_bases(w) for w in words(raw))) if words(raw) else set()
        if _numbers(b) and not (_numbers(b) & ev_numbers):
            out.append(("رقم", A._MARKS.sub("", raw)))
        for kind, L in (("مدة/زمن", TIME_WORDS), ("اسم علم", PROPER_NAMES)):
            if b & L and not (b & L & ev):
                out.append((kind, A._MARKS.sub("", raw)))
    for d in re.findall(r"[0-9٠-٩]+", own):
        if d not in evidence and d.translate(_AR_DIGITS) not in evidence:
            out.append(("رقم", d))
    for m in _NAME_INTRO.finditer(fold(own)):
        for w in m.group(1).split()[:4]:
            if w in _NAME_GLUE or not w:
                continue
            if not (_bases(w) & ev):
                out.append(("اسم مُعرَّف به", w))
    return out


ARABIC_DENY = [  # (pattern on folded text, why) — famous Seerah details no sahih narration carries
    (r"عنكبوت|(?<![ء-ي])[وف]?نسج", "العنكبوت ونسجه على الغار — لم يثبت في الصحيحين"),
    (r"(?<![ء-ي])[وف]?(?:ال)?حمام(?:ه|تان|تين|ات)?(?![ء-ي])", "الحمامتان على باب الغار — لم يثبت في الصحيحين"),
    (r"شجر\S*(?:\s+\S+){0,6}\s+(?:باب|فم|مدخل)\s+الغار|(?:باب|فم|مدخل)\s+الغار(?:\s+\S+){0,6}\s+\S*شجر",
     "الشجرة على باب الغار — لم يثبت في الصحيحين"),
    (r"(?<![ء-ي])[وف]?(?:ال)?(?:حيه|حيات|[اء]فعي|[اء]فاعي|ثعبان|عقرب)(?![ء-ي])|لدغ|لسع",
     "الحيّة ولدغ أبي بكر في الغار — لم يثبت في الصحيحين"),
    (r"(?<![ء-ي])[وف]?(?:ال)?(?:جحر|جحور|ثقب|ثقوب)(?![ء-ي])", "سدّ أبي بكر جحور الغار — لم يثبت في الصحيحين"),
    (r"(?:ثلاث|ثلاثه)\s+(?:درجات|مراق|عتبات)|(?<![ء-ي])[وف]?(?:ال)?درج(?:ات|تين|تان)(?![ء-ي])|مراقي",
     "عدد درجات المنبر — ليس في روايات القصة المعتمدة هنا"),
    (r"(?<![ء-ي])(?:باقوم|باقول|ميمون|مينا|صباح|كلاب)(?![ء-ي])", "اسم صانع المنبر — لم يثبت في الصحيحين"),
    (r"الحنانه", "تسمية الجذع «الحنانة» — لم تثبت في الصحيحين"),
    (r"[اء]ريق[طد]", "اسم الدليل — لم يُسمَّ في الصحيحين"),
    (r"(?:مات|نفق|موت)\S*\s+(?:ال)?(?:نغير|نغر|طائر|عصفور)|(?:نغير|نغر|طائره|عصفور)\S*\s+(?:قد\s+)?(?:مات|نفق)",
     "موت النغير — لم يُذكر في الصحيحين"),
    (r"(?<![ء-ي])[وفب]?(?:ال)?(?:جنه|ثواب|[اء]جر|حسنات)(?![ء-ي])", "وعدٌ بالأجر أو الجنة — ليس من القصة"),
    (r"[اء]فضل\s+(?:الصحابه|ال[اء]نبيا[ءا]|الناس\s+بعد)|خير\s+الصحابه|[اء]عظم\s+من\s+(?:نبي|صحابي)",
     "مفاضلة بين الأنبياء أو الصحابة — ليست من القصة"),
]
ENGLISH_DENY = [
    (r"\bspiders?\b|\bcobwebs?\b|\bweb\b", "the spider's web at the cave is not in the Sahihayn"),
    (r"\bdoves?\b|\bpigeons?\b", "the doves at the cave are not in the Sahihayn"),
    (r"\btree\b[^.]{0,60}\bcave\b|\bcave\b[^.]{0,60}\btree\b", "a tree at the cave is not in the Sahihayn"),
    (r"\bsnakes?\b|\bserpents?\b|\bvipers?\b|\bscorpions?\b", "the snake in the cave is not in the Sahihayn"),
    (r"\bholes?\b[^.]{0,40}\bcave\b|\bcave\b[^.]{0,40}\bholes?\b", "blocking the cave's holes is not in the Sahihayn"),
    (r"\b(?:three|3|two|2)\s+steps\b|\bsteps of the minbar\b|\bminbar'?s?\s+steps\b",
     "the minbar's steps are not in the narrations used"),
    (r"\bUr[ae]yqit\b|\bUraiqit\b|\bBaqu?m\b|\bBaqoum\b|\bMaymun\b|\bHannana\b", "a name the Sahihayn do not give"),
    (r"\b(?:bird|sparrow|nughayr|nughair|nughar)\b[^.]{0,30}\bdied\b|\bdeath of (?:the|his) (?:bird|sparrow)\b",
     "the bird's death is not in the Sahihayn"),
    (r"\bParadise\b|\breward(?:ed|s)?\b|\bhasanat\b", "a promise of reward — not part of the story"),
    (r"\bbest of the (?:companions|prophets)\b|\bgreater than (?:any|the other)\b", "a ranking — not part of the story"),
]


def denied(text: str, evidence: str, lang: str) -> list[str]:
    hits = []
    if lang == "ar":
        t, e = fold(A.outside_verses(text)), fold(evidence)
        for pat, why in ARABIC_DENY:
            for m in re.finditer(pat, t):
                if m.group(0).strip() not in e:
                    hits.append(f"«{m.group(0).strip()}» — {why}")
    else:
        for pat, why in ENGLISH_DENY:
            for m in re.finditer(pat, text, re.I):
                hits.append(f"“{m.group(0)}” — {why}")
    return hits


# ── quotes ─────────────────────────────────────────────────────────────────
def quotes_with_citations(text: str) -> list[tuple[str, tuple[str, int] | None, str]]:
    """Each «quote» with the citation that governs it — the first «(صحيح …)»
    after it in its own sentence, with at most a few connecting words («قال:»)
    and other quotes between — and why there is none."""
    hidden = blank(QUOTE, text)   # sentence ends inside a quote do not end the sentence
    out = []
    for m in QUOTE.finditer(text):
        rest = hidden[m.end():]
        end = _SENT_END.search(rest)
        seg = rest[:end.start() if end else len(rest)]
        c = CITE.search(seg)
        if not c:
            out.append((m.group(1), None, "بلا إسناد في جملته"))
            continue
        between = re.findall(r"[ء-ي]+", seg[:c.start()])
        if len(between) > 4:
            out.append((m.group(1), None, f"الإسناد بعيد عنه ({len(between)} كلمات بينهما)"))
            continue
        out.append((m.group(1), (c.group(1), int(c.group(2).translate(_AR_DIGITS))), ""))
    return out


def unquoted_speech(text: str) -> list[str]:
    """«قال …:» followed by anything but «» or ﴿﴾ — reported words in the
    narrator's own wording."""
    hidden = blank(QUOTE, blank(VERSE, text))
    out = []
    for m in _SPEECH.finditer(hidden):
        nxt = text[m.end():].lstrip()[:1]
        if nxt not in ("«", "﴿"):
            out.append(text[m.start():m.end() + 30].strip())
    return out


def hadith_snapshot_ok(book: str, number: int, display: str) -> bool:
    """The display text is the pinned edition's: its skeleton holds the hadith
    index entry for that number (the index was built from the same edition)."""
    books, _, _ = SS.corpora()
    sk = skeleton(display)
    return bool(sk) and any(n and n in sk for n in _narrations(books.get(book, {}).get(str(number), [])))


_REF_ANY = re.compile(r"^(?:bukhari|muslim):\d{1,5}$|^\d{1,3}:\d{1,3}$")


# ── the check ──────────────────────────────────────────────────────────────
def check_story(ar: dict, src: dict | None, en: dict | None, quran: dict[str, str]) -> list[str]:
    sid = ar.get("id", "?")
    errs: list[str] = []
    if not src:
        return [f"{sid}: لا ملف مصادر — backend/.venv/bin/python ops/tools/sira_sources.py fetch {sid}"]
    hadith, verses, tafsir = src.get("hadith") or {}, src.get("verses") or {}, src.get("tafsir") or {}
    if src.get("id") != sid:
        errs.append(f"{sid}: ملف المصادر لقصة أخرى ({src.get('id')})")
    if verses and src.get("tafsir_source") != TAFSIR:
        errs.append(f"{sid}: مصدر التفسير ليس الميسّر ({src.get('tafsir_source')})")
    if src.get("content_sha256") != content_sha(ar):
        errs.append(f"{sid}: نص القصة تغيّر بعد توثيق مصادرها (sha) — أعد sira_sources.py fetch ثم المراجعة")

    for ref, h in sorted(hadith.items()):
        m = _HADITH_REF.match(ref)
        if not m:
            errs.append(f"{sid}: المرجع {ref} ليس حديثًا من الصحيحين")
            continue
        book = BOOK_OF[m.group(1)]
        if h.get("book") != book or h.get("number") != int(m.group(2)):
            errs.append(f"{sid}: بيانات الحديث {ref} لا تطابق مرجعه")
        if h.get("edition") != EDITION:
            errs.append(f"{sid}: نص الحديث {ref} ليس من الطبعة المثبّتة ({h.get('edition')})")
        if not hadith_snapshot_ok(book, int(m.group(2)), h.get("text", "")):
            errs.append(f"{sid}: نص الحديث {ref} المحفوظ لا يطابق {book} {m.group(2)} في فهرس الصحيحين")
    for ref in sorted(set(verses) | set(tafsir)):
        if not _VERSE_REF.match(ref) or ref not in quran:
            errs.append(f"{sid}: المرجع {ref} ليس آية في المصحف")
        elif verses.get(ref) != quran[ref]:
            errs.append(f"{sid}: لقطة الآية {ref} لا تطابق المصحف حرفًا بحرف")
        if not (tafsir.get(ref) or "").strip():
            errs.append(f"{sid}: لا نص ميسّر محفوظ للآية {ref}")
    known = set(hadith) | set(verses)

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
            errs.append(f"{where}: صفحة بلا مصادر")
        bad = [r for r in refs if not _REF_ANY.match(r) or r not in known]
        if bad:
            errs.append(f"{where}: مراجع بلا لقطة مصدر: {', '.join(bad)}")
        evidence = " ".join(evidence_of(r, src) for r in refs)

        # quotes: every «» is cited, held verbatim by that number, and documented
        if re.search(r"[“”\"]", text):
            errs.append(f"{where}: اقتباس بين “” — الحديث بين «» وحده")
        if text.count("«") != text.count("»"):
            errs.append(f"{where}: علامات «» غير متوازنة")
        for q, cite, why in quotes_with_citations(text):
            if cite is None:
                errs.append(f"{where}: «{q[:40]}» {why} — كل اقتباس يتبعه «(صحيح البخاري …)»")
                continue
            book, num = cite
            if not SS.sahihayn_holds(book, num, SS._fragments(q)):
                errs.append(f"{where}: «{q[:40]}» ليس لفظ {book} {num} متصلًا في رواية واحدة")
            if ref_of(book, num) not in refs:
                errs.append(f"{where}: «{q[:40]}» مُسنَد إلى {book} {num} وليس من مصادر الحقل")
        for c in CITE.finditer(text):
            if ref_of(c.group(1), c.group(2)) not in refs:
                errs.append(f"{where}: إسناد ({c.group(1)} {c.group(2)}) ليس من مصادر الحقل")
        for s in unquoted_speech(text):
            errs.append(f"{where}: كلام منقول بغير نصّه بين «»: «{s}…»")

        # verses
        field_verses = [r for r in refs if not is_hadith_ref(r)] if path.startswith("pages[") else list(verses)
        for q in VERSE.findall(text):
            if not any(verse_in(q, quran.get(r, "")) for r in field_verses):
                errs.append(f"{where}: ﴿{q[:40]}…﴾ ليست من آيات {'الصفحة' if path.startswith('pages[') else 'القصة'}")
        for hit in miscited(text, quran):
            errs.append(f"{where}: {hit}")

        # nothing the sources do not say
        if is_narrative(path):
            for kind, w in flagged_tokens(text, evidence):
                errs.append(f"{where}: {kind} «{w}» ليس في مصادر الحقل")
        for hit in denied(text, evidence, "ar"):
            errs.append(f"{where}: {hit}")

        sents = doc.get("sentences") or []
        if [s.get("text") for s in sents] != sentences(text):
            errs.append(f"{where}: جمل ملف المصادر ليست جمل النص الحالي")
            continue
        for s in sents:
            srefs = s.get("refs") or []
            if path.startswith("pages[") and not srefs:
                errs.append(f"{where}: جملة بلا مصدر: «{s['text'][:50]}»")
            if any(r not in refs for r in srefs):
                errs.append(f"{where}: جملة تستند إلى مصدر ليس من مصادر الحقل: «{s['text'][:50]}»")
            fid = s.get("fidelity") or {}
            reviews = fid.get("reviews") or {}
            if fid.get("sha") != evidence_sha(s["text"], srefs, src):
                errs.append(f"{where}: حكم الأمانة لا يخص هذه الجملة بمصادرها الحالية: «{s['text'][:50]}»")
            elif fid.get("verdict") != "supported" or any(
                    (reviews.get(r) or {}).get("verdict") != "supported" for r in REVIEWERS):
                errs.append(f"{where}: جملة غير «مدعومة» عند المراجعَين: «{s['text'][:50]}»")

    errs += check_english(ar, en, documented, src)
    return errs


def check_english(ar: dict, en: dict | None, documented: dict, src: dict) -> list[str]:
    sid = ar.get("id", "?")
    if en is None:
        return [f"{sid}: لا توأم إنجليزي"]
    errs = []
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
        where = f"{sid} (en) :: {path}"
        a_text = ar_fields.get(path, "")
        a_cites = sorted((b, int(n.translate(_AR_DIGITS))) for b, n in CITE.findall(a_text))
        e_cites = sorted(({"bukhari": "البخاري", "muslim": "مسلم"}[b.lower()], int(n))
                         for b, n in EN_CITE.findall(text))
        if a_cites != e_cites:
            errs.append(f"{where}: أسانيد الإنجليزي {e_cites} ليست أسانيد العربي {a_cites}")
        for hit in denied(text, "", "en"):
            errs.append(f"{where}: {hit}")
        hidden = blank(VERSE, text)
        for m in EN_QUOTE.finditer(hidden):
            before = hidden[:m.start()]
            seg = before[text[:m.start()].rfind("﴾") + 1:] if "﴾" in text[:m.start()] else None
            if seg is not None and "interpretation of the meaning" in seg.lower():
                continue
            rest = hidden[m.end():]
            end = re.search(r"[.!?](?=\s|$)", blank(EN_QUOTE, rest))
            c = EN_CITE.search(rest[:end.start() if end else len(rest)])
            if not c:
                errs.append(f"{where}: اقتباس بلا «(Sahih al-Bukhari …)» ولا «interpretation of the meaning»: "
                            f"“{(m.group(1) or m.group(2) or '')[:40]}”")
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
_H = "bukhari:3653"
_P1 = ("قال أبو بكر للنبيّ ﷺ وهما في الغار: «لَوْ أَنَّ أَحَدَهُمْ نَظَرَ تَحْتَ قَدَمَيْهِ لأَبْصَرَنَا» "
       "(صحيح البخاري ٣٦٥٣).")
_E1 = ("Abu Bakr said to the Prophet ﷺ while they were in the cave: “If one of them looked beneath his "
       "feet, he would see us.” (Sahih al-Bukhari 3653)")


def _fixture() -> tuple[dict, dict, dict]:
    quran = mushaf()
    books, _, _ = SS.corpora()
    display = "حَدَّثَنَا " + " ".join(_narrations(books["البخاري"]["3653"]))   # skeleton-true stand-in
    ar = {"id": "selftest_ghar", "title": "اختبار", "description": "قصة للاختبار.", "series": SERIES,
          "pages": [{"pageNumber": 1, "text": _P1},
                    {"pageNumber": 2, "text": "فقال له: ﴿لَا تَحۡزَنۡ إِنَّ ٱللَّهَ مَعَنَاۖ﴾."}]}
    src = {"id": ar["id"], "series": SERIES, "tafsir_source": TAFSIR,
           "hadith": {_H: {"book": "البخاري", "number": 3653, "text": display, "edition": EDITION}},
           "verses": {"9:40": quran["9:40"]},
           "tafsir": {"9:40": "إذ يقول لصاحبه أبي بكر لما رأى منه الخوف عليه: لا تحزن إن الله معنا بنصره."}}
    _resign(ar, src)
    en = {"id": ar["id"], "series": SERIES, "title": "Test", "description": "A test.",
          "pages": [{"pageNumber": 1, "text": _E1},
                    {"pageNumber": 2, "text": "He said to him: ﴿لَا تَحۡزَنۡ إِنَّ ٱللَّهَ مَعَنَاۖ﴾ — "
                                              "interpretation of the meaning: \"Do not grieve; Allah is with us.\""}]}
    return ar, src, en


def _resign(ar: dict, src: dict) -> None:
    """Re-document after a mutation, as a careless author would — so only the
    rule under test can catch it (not the sha / sentence bookkeeping)."""
    src["fields"] = []
    for path, text in fields_of(ar):
        refs = [_H] if path == "pages[0].text" else ["9:40"] if path == "pages[1].text" else [_H, "9:40"]
        src["fields"].append({"path": path, "refs": refs, "sentences": [
            {"text": t, "refs": refs, "fidelity": {
                "verdict": "supported", "reviews": {r: {"verdict": "supported"} for r in REVIEWERS},
                "sha": evidence_sha(t, refs, src)}} for t in sentences(text)]})
    src["content_sha256"] = content_sha(ar)


def _page(text: str, i: int = 0):
    def f(ar, src, en):
        ar["pages"][i]["text"] = text
    return f


def _unsupported(ar, src, en):
    s = src["fields"][2]["sentences"][0]
    s["fidelity"]["verdict"] = "unsupported"
    s["fidelity"]["reviews"]["glm-5.2"]["verdict"] = "unsupported"


def _stale(ar, src, en):
    ar["pages"][0]["text"] = ar["pages"][0]["text"].replace("وهما في الغار", "وهما في الغار ليلًا")


def _bad_hadith(ar, src, en):
    src["hadith"][_H]["text"] = src["hadith"][_H]["text"].replace("نظر", "رأى")


def _no_sources(ar, src, en):
    src.clear()


def _en_uncited(ar, src, en):
    en["pages"][0]["text"] = en["pages"][0]["text"].replace(" (Sahih al-Bukhari 3653)", "")


def _en_wrong(ar, src, en):
    en["pages"][0]["text"] = en["pages"][0]["text"].replace("3653", "3654")


def _en_deny(ar, src, en):
    en["pages"][0]["text"] += " A spider wove its web over the mouth of the cave."


def _en_missing_verse(ar, src, en):
    en["pages"][1]["text"] = "He said to him: do not grieve, Allah is with us."


def _verse_bad(ar, src, en):
    ar["pages"][1]["text"] = "فقال له: ﴿قُلۡ هُوَ ٱللَّهُ أَحَدٌ﴾."


MUTATIONS = [  # (what must be caught, mutation, re-sign after it?, a word the report must carry)
    ("اقتباس بلا إسناد", _page(_P1.replace(" (صحيح البخاري ٣٦٥٣)", "")), True, "بلا إسناد"),
    ("رقم حديث خطأ", _page(_P1.replace("٣٦٥٣", "٣٦٥٤")), True, "ليس لفظ البخاري 3654"),
    ("اقتباس ملفَّق من موضعين", _page("قال أبو بكر: «لَوْ أَنَّ أَحَدَهُمْ نَظَرَ تَحْتَ قَدَمَيْهِ مَا ظَنُّكَ يَا أَبَا بَكْرٍ» "
                                      "(صحيح البخاري ٣٦٥٣)."), True, "متصلًا في رواية واحدة"),
    ("اقتباس بعيد عن إسناده", _page("قال أبو بكر: «لَوْ أَنَّ أَحَدَهُمْ نَظَرَ تَحْتَ قَدَمَيْهِ لأَبْصَرَنَا» وكان ذلك "
                                    "وهما معًا في الغار في الليل (صحيح البخاري ٣٦٥٣)."), True, "الإسناد بعيد"),
    ("إسناد ليس من مصادر الحقل", _page(_P1.replace("٣٦٥٣", "٦٢٠٣")), True, "ليس من مصادر الحقل"),
    ("كلام منقول بلا «»", _page("فقال أبو بكر: لو نظر أحدهم إلى قدميه لرآنا. " + _P1), True, "بغير نصّه"),
    ("اقتباس بين “”", _page(_P1.replace("«", "“").replace("»", "”")), True, "“”"),
    ("رقم ليس في المصادر", _page(_P1 + " فمكثا في الغار سبع ليال."), True, "رقم «سبع»"),
    ("اسم علم ليس في المصادر", _page(_P1 + " وكان معهما عامر."), True, "اسم علم «عامر»"),
    ("اسم مخترَع بـ«يقال له»", _page(_P1 + " وكان معهما رجلٌ يقال له سالم."), True, "اسم مُعرَّف به"),
    ("العنكبوت", _page(_P1 + " ونسج العنكبوت على باب الغار."), True, "العنكبوت"),
    ("الحمامتان", _page(_P1 + " وباضت حمامتان عند الغار."), True, "الحمامتان"),
    ("الحية", _page(_P1 + " ولدغت أبا بكر حيّةٌ في الغار."), True, "الحيّة"),
    ("درجات المنبر", _page(_P1 + " وصنعوا له منبرًا من ثلاث درجات."), True, "درجات المنبر"),
    ("اسم الدليل", _page(_P1 + " وكان دليلهما عبد الله بن أريقط."), True, "اسم الدليل"),
    ("وعد بالأجر", _page(_P1 + " ومن صدّق صاحبه دخل الجنة."), True, "وعدٌ بالأجر"),
    ("آية ليست من آيات الصفحة", _verse_bad, True, "ليست من آيات الصفحة"),
    ("نص تغيّر بعد التوثيق", _stale, False, "(sha)"),
    ("جملة غير مدعومة", _unsupported, False, "غير «مدعومة»"),
    ("نص حديث محرَّف في المصادر", _bad_hadith, False, "لا يطابق البخاري 3653"),
    ("ملف مصادر مفقود", _no_sources, False, "لا ملف مصادر"),
    ("حديث إنجليزي بلا إسناد", _en_uncited, False, "أسانيد الإنجليزي"),
    ("رقم خطأ في الإنجليزي", _en_wrong, False, "أسانيد الإنجليزي"),
    ("العنكبوت في الإنجليزي", _en_deny, False, "spider"),
    ("آية ناقصة في الإنجليزي", _en_missing_verse, False, "آيات الصفحة ليست"),
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
        if resign and s:
            _resign(a, s)
        got = check_story(a, s or None, e, quran)
        if not any(mark in g for g in got):  # caught, and for the right reason
            return f"لم تُرصد الطفرة: {what}" + (f" (رُصد غيرها: {got[0]})" if got else "")
    # the helpers on their own
    if not unquoted_speech("وقال أنس: أحسبه فطيمًا.") or unquoted_speech("وقال أنس: «كان» (صحيح البخاري ٦٢٠٣)."):
        return "فحص الكلام المنقول لا يعمل"
    if flagged_tokens("ولجأ الاثنان إلى الغار.", "ثاني اثنين") or not flagged_tokens("ولجأ الثلاثة.", "ثاني اثنين"):
        return "معجم الأعداد لا يعمل"
    if flagged_tokens("قال: «عشر سنين» (صحيح البخاري ٦٠٣٨).", ""):
        return "الاقتباس والإسناد لا يُعدّان سردًا"
    if denied("الذي كان في الغار حيًّا، وفي حيٍّ من الأحياء", "", "ar"):
        return "قائمة المنع ترفض «حيّ» بمعنى الحيّ من الناس"
    return None


def main(argv: list[str]) -> int:
    print("\n" + "=" * 67)
    print("  SIRA — لا نروي عن النبيّ ﷺ إلا ما في القرآن والصحيحين")
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
    if series:   # the mutations again, on a real story this time
        real = copy.deepcopy(series[0])
        real["pages"][0]["text"] += " قال: «نسج العنكبوت على الغار»."
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
    n_q = sum(len(QUOTE.findall(t)) for s in series for _, t in fields_of(s))
    print(f"  القصص في السلسلة: {len(series)} · جمل موثّقة: {n_sent} · اقتباسات حديث: {n_q}")
    if errors:
        print(f"\n🔴  {len(errors)} مخالفة:")
        for e in errors[:60]:
            print(f"     ✗ {e}")
        if len(errors) > 60:
            print(f"     … و{len(errors) - 60} أخرى")
        print("\n" + "=" * 67)
        print("  ❌  قصة من السيرة فيها ما لا تسنده مصادرها — لا يجوز الدفع.")
        print("=" * 67 + "\n")
        return 1
    print("\n" + "=" * 67)
    print("  ✅  SIRA OK — كل اقتباس بلفظ الصحيحين ورقمه، وكل جملة موثّقة ومراجَعة بعائلتين")
    print("  (فحص آلي ومراجعة نماذج — ليس مراجعة بشرية ولا إجازة شرعية)")
    print("=" * 67 + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
