#!/usr/bin/env python3
"""
check_scholar_quotes.py — «قال ابن القيم…»: هل لهذه النسبة سندٌ نراه؟
=====================================================================

النصوص التي يقرؤها الوالد (ملخّص وحدة المعرفة، ونص الدرس) تنسب أقوالًا وفتاوى
لأهل العلم: ابن القيم، ابن باز، السعدي، النووي… الحرّاس الشرعية تفحص الآية
والحديث بلفظهما؛ ولا شيء كان يسأل: **هل قال العالم هذا فعلًا؟** نسبةٌ مخترعة
إلى عالم معروف أخطر من نصيحة بلا نسبة — لأنها تستعير ثقته.

لكل نسبة في نصٍّ مُقدَّم، واحدٌ من أربعة أحكام:

  own_book   الوحدة مأخوذة من كتاب العالم نفسه (`source_meta.source_author`).
  in_source  اسمه مذكور في نص المصدر الذي لُخِّصت منه الوحدة (`text_original`،
             يُقرأ بالاتجاهين لأن بعض المستخرَج من PDF مقلوب) — النقل أمين
             لمصدره، والمصدر مسؤول عن نقله.
  verified   وُجد القول في كتاب للعالم على تراث (turath.io)، مسجَّلًا في
             `ops/data/scholar_quotes/verified.json` بالكتاب والصفحة والعبارة
             التي طابقت — مربوطًا ببصمة الجملة: تتغيّر الجملة ← يسقط التحقق.
  ✗          لا شيء مما سبق — مخالفة. الحل: يُتحقَّق منها (`verify`)، أو تُحذف
             النسبة، أو يُحذف القول. «يحتاج مراجعة بشرية» ليس خيارًا: لا مراجع.

«المصدر» لا يُقبل إن كان `text_original` صياغةً كُتبت للوحدة ثم وُقّعت باسم العالم
(«… — فتاوى ابن باز، حكم كذا.»): هكذا عاشت أربع «فتاوى» حتى 2026-11-09، وروابطها
الثلاثة إلى binbaz.org.sa كانت لفتاوى أخرى تمامًا (الإحرام من جدة، القيام للصلاة،
داعيةٌ يخشى ألا يعمل بما يقول). وتبقى ثغرة: البيانات الوصفية نفسها (`source_author`)
لا يتحقق منها هذا الفحص بلا شبكة.

المطابقة آلية: نافذةٌ متصلة من كلمات الجملة في كتابٍ مؤلّفه هذا العالم. الصياغة
بالمعنى قد لا تُطابَق — فعدم الوجدان ليس حكمًا بالاختلاق، لكنه يمنع النشر حتى
يُحسم. ووجدانها لا يعني أن الفهم صحيح؛ يعني أن الكلام في كتابه.

الشبكة: `verify` وحده يسأل تراث (API غير موثّق). مهذّبًا: طلب كل ٤ ثوانٍ،
ويتوقف عند 429 ويطبع Retry-After (التشغيلة تُستأنف من الكاش ولا تكرّر سؤالًا).
`check` (pre-commit و CI) بلا شبكة.

Exit (check): 0 سليم · 1 نسبة بلا سند · 2 الفحص نفسه معطّل
Exit (verify): 0 انتهى · 3 توقف عند حد الطلبات — أعد التشغيل بعد المدة المطبوعة

Usage:
    python3 ops/tools/check_scholar_quotes.py check
    python3 ops/tools/check_scholar_quotes.py report [--all]
    python3 ops/tools/check_scholar_quotes.py verify [--limit N]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UNITS = ROOT / "knowledge_base/units"
LESSONS = ROOT / "knowledge_base/curriculum/lessons"
VERIFIED = ROOT / "ops/data/scholar_quotes/verified.json"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "almorabbi-turath-search.json"
API = "https://api.turath.io/search"
UA = "almorabbi-kb-check/1.0 (+https://github.com/almorabbi/almorabbi)"
SPACING = 4.0

# الاسم كما يُكتب في النص المقدَّم · كما قد يرد في المصدر (بعد التطبيع) ·
# كما يكتبه تراث في `author_name`.
_A = r"(?<![ء-ي])(?:[وفب]?ل?)"
SCHOLARS: dict[str, tuple[str, tuple[str, ...], tuple[str, ...]]] = {
    "ابن القيم": (_A + r"ابن (?:ال)?قيم(?: الجوزية)?", ("ابن القيم", "ابن قيم", "قيم الجوزيه"), ("ابن القيم", "ابن قيم")),
    "ابن تيمية": (_A + r"ابن تيمي[ةه]", ("تيميه",), ("ابن تيمية",)),
    "ابن باز": (_A + r"(?:ابن|بن) باز", ("ابن باز", "بن باز"), ("ابن باز",)),
    "ابن عثيمين": (_A + r"(?:ابن )?(?:ال)?عثيمين", ("عثيمين",), ("عثيمين",)),
    "السعدي": (_A + r"(?:ال|ل)سعدي", ("السعدي",), ("السعدي",)),
    "ابن الجوزي": (_A + r"ابن الجوزي", ("الجوزي",), ("ابن الجوزي",)),
    "ابن حجر": (_A + r"ابن حجر", ("ابن حجر",), ("ابن حجر",)),
    "ابن رجب": (_A + r"ابن رجب", ("ابن رجب",), ("ابن رجب",)),
    "ابن كثير": (_A + r"ابن كثير", ("ابن كثير",), ("ابن كثير",)),
    "ابن عبد البر": (_A + r"ابن عبد ?البر", ("عبد البر", "عبدالبر"), ("ابن عبد البر",)),
    "ابن مفلح": (_A + r"ابن مفلح", ("ابن مفلح",), ("ابن مفلح",)),
    "النووي": (_A + r"(?:ال|ل)نووي", ("النووي",), ("النووي",)),
    "القرطبي": (_A + r"(?:ال|ل)قرطبي", ("القرطبي",), ("القرطبي",)),
    "الغزالي": (_A + r"(?:ال|ل)غزالي", ("الغزالي",), ("الغزالي",)),
    "الماوردي": (_A + r"(?:ال|ل)ماوردي", ("الماوردي",), ("الماوردي",)),
    "ابن خلدون": (_A + r"ابن خلدون", ("ابن خلدون",), ("ابن خلدون",)),
}
_NAME = re.compile("|".join(f"(?P<s{i}>{p}(?![ؐ-ًؚ-ٰٟ]*[ء-ي]))" for i, (p, _, _) in enumerate(SCHOLARS.values())))
_KEYS = list(SCHOLARS)

_TASHKEEL = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ]")
_SENT_END = re.compile(r"[.!؟?\n•]")
# «… — فتاوى ابن باز، حكم كذا.» / «— من فتاوى الشيخ …»: صياغةٌ موقَّعة، لا مصدر.
_SIGNED = re.compile(r"[—–-]\s*(?:من\s+)?(?:فتاوى|فتوى|كلام|قول)\s[^\n]{0,160}$")
# ما بين علامات التنصيص آيةٌ أو حديث — يوجد في كل تفسير وشرح، فلا يشهد لنسبة.
_QUOTED = re.compile(r"«[^»]*»|﴿[^﴾]*﴾|\"[^\"]*\"")
# كلمات النسبة نفسها لا تُبحث في كتاب العالم.
_FRAME = {"قال", "وقال", "يقول", "ويقول", "ذكر", "وذكر", "نقل", "ونقل", "عن", "أن", "إن", "رحمه",
          "الله", "الشيخ", "الإمام", "العلامة", "الحافظ", "يرى", "ويرى", "بحسب", "فتوى", "فتاوى",
          "المؤلف", "إلى", "كما", "بين", "بيّن", "أشار", "وأشار", "نبه", "ونبه", "في", "تفسيرها",
          "تفسيره", "سماحة", "رأي", "قول", "وقول", "ابن", "بن"}


def norm(s: str) -> str:
    s = _TASHKEEL.sub("", s or "")
    return s.translate(str.maketrans("أإآٱىة", "اااايه"))


def _words(s: str) -> list[str]:
    return re.findall(r"[ء-ي]+", _TASHKEEL.sub("", s))


@dataclass
class Attribution:
    file: str          # repo-relative
    scholar: str
    sentence: str
    support: str = ""  # own_book | in_source | verified | ""

    @property
    def key(self) -> str:
        return hashlib.sha1(f"{self.scholar}|{norm(self.sentence)}".encode()).hexdigest()[:16]


def find(text: str) -> list[tuple[str, str]]:
    """(scholar, sentence) for every attribution in `text`, one per scholar per sentence."""
    out: list[tuple[str, str]] = []
    for m in _NAME.finditer(text or ""):
        scholar = _KEYS[int(m.lastgroup[1:])]
        s = max(text.rfind(ch, 0, m.start()) for ch in ".!؟?\n•") + 1
        e = _SENT_END.search(text, m.end())
        sent = text[s:e.end() if e else len(text)].strip()
        if (scholar, sent) not in out:
            out.append((scholar, sent))
    return out


def _supported(scholar: str, unit: dict | None) -> str:
    if not unit:
        return ""
    # A paraphrase written for the unit and signed with the scholar's name is
    # neither his book nor a source — whatever source_meta says.
    if _SIGNED.search((unit.get("text_original") or "").strip()):
        return ""
    alts = [norm(a) for a in SCHOLARS[scholar][1]]
    author = norm((unit.get("source_meta") or {}).get("source_author", ""))
    if any(a in author for a in alts):
        return "own_book"
    src = norm(unit.get("text_original") or "")
    if src and any(a in src or a in src[::-1] for a in alts):
        return "in_source"
    return ""


def _strings(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _strings(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _strings(v)


def iter_attributions() -> list[Attribution]:
    verified = load_verified()
    out: list[Attribution] = []
    for p in sorted(UNITS.glob("*.json")):
        if p.name.endswith("__en.json"):
            continue
        unit = json.loads(p.read_text(encoding="utf-8"))
        for scholar, sent in find(unit.get("text_simplified") or ""):
            a = Attribution(str(p.relative_to(ROOT)), scholar, sent)
            a.support = _supported(scholar, unit) or ("verified" if a.key in verified else "")
            out.append(a)
    for p in sorted(LESSONS.glob("*.json")):
        lesson = json.loads(p.read_text(encoding="utf-8"))
        for text in _strings(lesson):
            for scholar, sent in find(text):
                a = Attribution(str(p.relative_to(ROOT)), scholar, sent)
                a.support = "verified" if a.key in verified else ""
                out.append(a)
    return out


def load_verified() -> dict:
    if not VERIFIED.exists():
        return {}
    return json.loads(VERIFIED.read_text(encoding="utf-8")).get("verified", {})


# ── self-tests ──────────────────────────────────────────────────────────────

def self_test() -> list[str]:
    errs: list[str] = []
    got = find("ابدأ بالقدوة. وقال ابن القيم رحمه الله: إن أكثر فساد الأولاد من قبل الآباء. ثم كافئه.")
    if got != [("ابن القيم", "وقال ابن القيم رحمه الله: إن أكثر فساد الأولاد من قبل الآباء.")]:
        errs.append(f"find: attribution sentence {got!r}")
    if [s for s, _ in find("كما ذكر الشيخ ابن عثيمين. وقال للنووي كلامًا. وذكره لابن باز.")] != ["ابن عثيمين", "النووي", "ابن باز"]:
        errs.append("find: prefixed names (للنووي / لابن باز) missed")
    if find("هذه قيمة عالية، وابنُ الجيران كثيرٌ ما يزورنا، والسعديّة مدينة.") :
        errs.append("find: matched a non-name (قيمة / كثير / السعدية)")
    if _supported("ابن القيم", {"source_meta": {"source_author": "ابن قيم الجوزية"}}) != "own_book":
        errs.append("support: own book not recognised")
    if _supported("ابن القيم", {"text_original": "...ميقلا نبا لاق دقو..."}) != "in_source":
        errs.append("support: reversed PDF source not read backwards")
    if _supported("ابن باز", {"text_original": "قال بعض أهل العلم"}):
        errs.append("support: a source without the name counted as support")
    signed = {"source_meta": {"source_author": "الشيخ عبدالعزيز بن باز"},
              "text_original": "الميل القلبي لا يؤاخذ عليه الإنسان. — فتاوى ابن باز، حكم التفكير بالحب."}
    if _supported("ابن باز", signed):
        errs.append("support: a paraphrase signed «— فتاوى ابن باز» counted as his book (the 2026-11-09 shape)")
    if any("يضحكون" in q for q in _queries(Attribution("x", "ابن كثير", "ثم قوله تعالى: ﴿فاليوم الذين آمنوا من الكفار يضحكون﴾ أي يوم القيامة كما بين ابن كثير."))):
        errs.append("queries: a verse inside ﴿﴾ was searched — it is in every tafsir")
    a, b = Attribution("x", "ابن باز", "يرى ابن باز كذا."), Attribution("x", "ابن باز", "يرى ابنُ باز كذا.")
    if a.key != b.key or a.key == Attribution("x", "ابن باز", "يرى ابن باز غير هذا.").key:
        errs.append("key: diacritics must not change it, words must")
    return errs


# ── commands ────────────────────────────────────────────────────────────────

FLOOR = 30   # live attributions on 2026-11-09: 47 — fewer than this means the enumerator broke


def cmd_check() -> int:
    try:
        errs = self_test()
    except Exception as exc:  # noqa: BLE001 — a crashing self-test is a broken guard, not a clean tree
        errs = [f"self_test crashed: {exc!r}"]
    if errs:
        print("⛔ self-tests:", *errs, sep="\n  ")
        return 2
    items = iter_attributions()
    if len(items) < FLOOR:
        print(f"⛔ only {len(items)} attributions found (floor {FLOOR}) — the enumerator stopped reading something")
        return 2
    bad = [a for a in items if not a.support]
    keys = {a.key for a in items}
    stale = [k for k in load_verified() if k not in keys]
    for a in bad:
        print(f"  ✗ {a.file} — {a.scholar}\n      {a.sentence[:160]}")
    if stale:
        print(f"  ⚠ {len(stale)} verified record(s) no longer match any sentence (edited or removed): {', '.join(stale)}")
    if bad:
        print(f"\n❌ {len(bad)} نسبة لعالم بلا سند (من {len(items)}). "
              "تحقّق منها: check_scholar_quotes.py verify — أو احذف النسبة أو القول.")
        return 1
    print(f"✅ {len(items)} نسبة لأهل العلم — كلها لها سند "
          f"({', '.join(f'{k} {sum(a.support == k for a in items)}' for k in ('own_book', 'in_source', 'verified'))})")
    return 0


def cmd_report(show_all: bool) -> int:
    for a in iter_attributions():
        if show_all or not a.support:
            print(f"{a.support or '✗':10} {a.scholar:12} {a.file}\n           {a.sentence[:150]}")
    return 0


class RateLimited(Exception):
    pass


def _search(cache: dict, q: str, precision: int) -> list[dict]:
    key = f"{precision}|{q}"
    if key in cache:
        return cache[key]
    time.sleep(SPACING)
    url = API + "?" + urllib.parse.urlencode({"q": q, "precision": precision})
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=30) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 429:
            raise RateLimited(e.headers.get("Retry-After", "?")) from e
        raise
    hits = []
    for x in data.get("data", []):
        meta = json.loads(x.get("meta") or "{}")
        hits.append({"book_id": x.get("book_id"), "book": meta.get("book_name"), "author": meta.get("author_name"),
                     "page": meta.get("page"), "vol": meta.get("vol")})
    cache[key] = hits
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
    return hits


def _queries(a: Attribution) -> list[str]:
    """Exact-phrase windows (turath precision=3) over the sentence's own words —
    quoted verses/hadith and the scholar's name left out. No proximity fallback:
    on 2026-11-09 «precision=2» matched framing words («واقرأ معه آيات سورة
    المطففين») on a page of Ibn Kathir's tafsir and called it a verification."""
    name_words = set(_words(a.scholar))
    w = [x for x in _words(_QUOTED.sub(" ، ", a.sentence)) if x not in name_words]
    for n in (5, 4):
        qs = [" ".join(w[i:i + n]) for i in range(0, len(w) - n + 1, 2)]
        qs = [q for q in qs if sum(x not in _FRAME for x in q.split()) >= 3]
        if qs:
            return qs[:6]
    return []


def cmd_verify(limit: int | None) -> int:
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    doc = json.loads(VERIFIED.read_text(encoding="utf-8")) if VERIFIED.exists() else {"verified": {}}
    todo = [a for a in iter_attributions() if not a.support][:limit]
    found = 0
    try:
        for a in todo:
            hit = None
            for q in _queries(a):
                for h in _search(cache, q, 3):
                    if any(t in (h.get("author") or "") for t in SCHOLARS[a.scholar][2]):
                        hit = (q, 3, h)
                        break
                if hit:
                    break
            if hit:
                q, prec, h = hit
                doc["verified"][a.key] = {"file": a.file, "scholar": a.scholar, "sentence": a.sentence,
                                          "book": h["book"], "book_id": h["book_id"], "vol": h["vol"],
                                          "page": h["page"], "matched": q, "precision": prec,
                                          "checked": date.today().isoformat()}
                found += 1
            print(f"{'✓' if hit else '✗'} {a.scholar} — {a.file}\n    {a.sentence[:140]}"
                  + (f"\n    → {hit[2]['book']} ج{hit[2]['vol']} ص{hit[2]['page']}" if hit else ""))
    except RateLimited as e:
        print(f"\n⏸ turath: 429 — Retry-After {e} ثانية. الكاش محفوظ؛ أعد التشغيل بعدها.")
        _save(doc)
        return 3
    _save(doc)
    print(f"\n{found}/{len(todo)} وُجدت في كتب أصحابها.")
    return 0


def _save(doc: dict) -> None:
    VERIFIED.parent.mkdir(parents=True, exist_ok=True)
    doc["verified"] = dict(sorted(doc["verified"].items()))
    doc.setdefault("note", "Scholar attributions found on turath.io in a book by that scholar — "
                           "mechanical match of a contiguous run of the sentence's words; see "
                           "ops/tools/check_scholar_quotes.py. Keyed by the sentence's fingerprint.")
    VERIFIED.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    r = sub.add_parser("report")
    r.add_argument("--all", action="store_true")
    v = sub.add_parser("verify")
    v.add_argument("--limit", type=int)
    args = ap.parse_args()
    if args.cmd == "check":
        return cmd_check()
    if args.cmd == "report":
        return cmd_report(args.all)
    return cmd_verify(args.limit)


if __name__ == "__main__":
    sys.exit(main())
