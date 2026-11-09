"""Check the hadith (and verses) an assistant answer quotes, before anyone reads it.

Production, 30 days to 2026-11-08, real devices: of 358 answers, 20 quoted a
hadith and 17 of those broke the app's rule — 9 cited Abu Dawud («مروا أولادكم
بالصلاة»), 7 quoted the Sahihayn with no citation, and 3 put words in the
Prophet's mouth ﷺ that are in no collection («لولا أنتم لم يغفر الله», a
garbled Muslim 2749). The content guards (`ops/tools/scripture_scan.py`) only
ran on pre-commit; the answer itself went out as the model wrote it.

The rule for answers (decided 2026-11-09):
  * Sahih al-Bukhari / Sahih Muslim, verbatim → kept; a missing or wrong
    citation is written in («صحيح البخاري — حديث ٦١١٤»).
  * The four Sunan, verbatim, graded sahih or hasan by al-Albani (as carried by
    the pinned hadith edition, `hadith_others_index.json.gz` → "albani") →
    kept, with «سنن أبي داود — حديث ٤٩٥، وصحّحه الألباني».
  * Anything else attributed to him ﷺ — a weaker grade, no grade, another book,
    or wording found nowhere — the sentence that carries it is removed.
  * A verse whose words are not the mushaf's is removed the same way; a wrong
    surah/ayah reference is corrected.
Authored content stays stricter (Sahihayn only) — the pre-commit guards are
unchanged.

The matching is the guards' own (one contiguous run inside one narration) and
mechanical, not a scholar's review — the methodology page says so.

The client replaces the streamed text with the `done` event's `reply_text`, so
repairing the final text repairs what the parent keeps; the answer cache stores
the repaired text too.
"""
from __future__ import annotations

import gzip
import json
import logging
import re
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

logger = logging.getLogger(__name__)

_ROOT = Path(__file__).resolve().parents[3]
_TOOLS = _ROOT / "ops" / "tools"

# al-Albani's grades, as the edition spells them, that keep a Sunan hadith.
# Isnad-only grades («Sahih Isnaad») judge the chain, not the hadith, and any
# grade naming a Companion's or Successor's saying (Mauquf/Maqtu) is not his
# speech ﷺ — both are left out on purpose.
_ACCEPT = {"Sahih", "Sahih Hadith", "Sahih Mutawatir", "Sahih Lighairihi", "Sahih Matn",
           "Hasan Sahih", "Hasan"}

_SUNAN_AR = {"أبو داود": "سنن أبي داود", "الترمذي": "جامع الترمذي",
             "النسائي": "سنن النسائي", "ابن ماجه": "سنن ابن ماجه"}
_SUNAN_EN = {"أبو داود": "Sunan Abi Dawud", "الترمذي": "Jami' at-Tirmidhi",
             "النسائي": "Sunan an-Nasa'i", "ابن ماجه": "Sunan Ibn Majah"}
_SAHIH_EN = {"البخاري": "Sahih al-Bukhari", "مسلم": "Sahih Muslim"}
_AR_NUM = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")

# A parenthesis right after the quote that already holds a (wrong or partial)
# citation is replaced rather than doubled.
_CITE_WORDS = re.compile(r"البخاري|مسلم|رواه|أخرجه|متفق|داود|الترمذي|النسائي|ماجه|أحمد|الطبراني|البيهقي"
                         r"|الحاكم|صحيح|سنن|Bukhari|Muslim|Dawud|Tirmidhi|Nasa|Majah|Ahmad|narrated",
                         re.IGNORECASE)
_SENT_END = re.compile(r"[.!؟?\n]")
_BULLET = re.compile(r"[ \t]*(?:[-*•▪◦]|\d+[.)]|[٠-٩]+[.)])[ \t]+")
_BULLET_ONLY = re.compile(r"^\s*(?:[-*•▪◦]|\d+[.)]|[٠-٩]+[.)])?\s*[،,:؛]?\s*$")


@dataclass
class GuardResult:
    text: str
    hadith: int = 0        # hadith claims seen
    quran: int = 0         # verse quotations seen
    fixed: int = 0         # citations written in or corrected
    removed: int = 0       # sentences removed
    available: bool = True

    @property
    def flag(self) -> str:
        """For the session log; empty when nothing was touched."""
        if not (self.fixed or self.removed):
            return ""
        return f"hadith_guard:fixed={self.fixed},removed={self.removed}"


@lru_cache(maxsize=1)
def _scanner():
    """scripture_scan with its corpora loaded, or None (logged once) when the
    tools or indexes are absent — the bare image in CI has no ops/data."""
    try:
        if str(_TOOLS) not in sys.path:
            sys.path.insert(0, str(_TOOLS))
        import scripture_scan  # noqa: PLC0415
        scripture_scan.corpora()
        scripture_scan._blobs()
        return scripture_scan
    # SystemExit too: the guards' loaders `sys.exit(2)` on a missing index (a
    # CLI's way to fail), and inside the server that would end the boot.
    except (Exception, SystemExit) as exc:  # noqa: BLE001
        logger.error("hadith guard unavailable — answers go out unchecked: %r", exc)
        return None


@lru_cache(maxsize=1)
def _albani() -> dict[str, dict[str, str]]:
    ss = _scanner()
    if ss is None:
        return {}
    try:
        with gzip.open(ss.OTHERS_INDEX, "rt", encoding="utf-8") as f:
            return json.load(f).get("albani", {})
    except (Exception, SystemExit) as exc:  # noqa: BLE001
        logger.error("hadith guard: al-Albani grades unavailable: %r", exc)
        return {}


def warm() -> bool:
    """Load the corpora now (at startup), not on the first answer."""
    return _scanner() is not None and bool(_albani())


def albani_grade(book: str, number: str | int) -> str:
    return _albani().get(book, {}).get(str(number), "")


def _citation(ss, f, lang: str) -> str | None:
    """The citation that keeps this hadith, or None when it must go."""
    if not f.where:
        return None
    book, num = f.where[0], str(f.where[1])
    if not f.other:
        if lang == "ar":
            return ss.cite(book, int(num))
        return f"{_SAHIH_EN.get(book, book)} {num}"
    grade = albani_grade(book, num)
    if book not in _SUNAN_AR or grade not in _ACCEPT:
        return None
    hasan = grade == "Hasan"
    if lang == "ar":
        verb = "وحسّنه" if hasan else "وصحّحه"
        return f"{_SUNAN_AR[book]} — حديث {num.translate(_AR_NUM)}، {verb} الألباني"
    return f"{_SUNAN_EN[book]} {num}, graded {'hasan' if hasan else 'sahih'} by al-Albani"


def _sentence(text: str, start: int, end: int) -> tuple[int, int]:
    """The sentence around [start, end): back to the previous terminator, on to
    the next one (a newline stays, so the list around it keeps its shape)."""
    s = max(text.rfind(ch, 0, start) for ch in ".!؟?\n") + 1
    if s == 0 or text[s - 1] == "\n":       # keep a list item's marker
        bullet = _BULLET.match(text, s)
        if bullet:
            s = bullet.end()
    m = _SENT_END.search(text, end)
    if m is None:
        return s, len(text)
    e = m.start() if text[m.start()] == "\n" else m.end()
    return s, e


def _paren_after(text: str, end: int) -> tuple[int, int] | None:
    """A parenthesis opening within two spaces after the quote, if it holds a citation."""
    m = re.match(r"\s{0,2}\(([^()\n]{0,120})\)", text[end:])
    if m and _CITE_WORDS.search(m.group(1)):
        return end + m.start(), end + m.end()
    return None


def _tidy(text: str) -> str:
    lines = []
    for line in text.split("\n"):
        if line.strip() and _BULLET_ONLY.match(line):
            continue            # a list marker whose sentence was removed
        line = re.sub(r"[ \t]{2,}", " ", line).rstrip()
        lines.append(line[1:] if line.startswith(" ") and not line.startswith("  ") else line)
    out = "\n".join(lines)
    out = re.sub(r"\n{3,}", "\n\n", out)
    return out.strip()


# What is left when every sentence of an answer was an unverifiable quotation.
_EMPTY_AR = ("حذفتُ من إجابتي نصًّا نُسب إلى النبي ﷺ لم أجده بلفظه في كتب الحديث المعتمدة. "
             "أعد طرح سؤالك بصيغة أخرى، وسأجيبك بما ثبت.")
_EMPTY_EN = ("I removed a saying attributed to the Prophet ﷺ that I could not find, word for word, "
             "in the recognised hadith collections. Please ask again in other words and I will answer "
             "with what is established.")


def guard(text: str, lang: str = "ar") -> GuardResult:
    """Repair `text` under the rule above. Never raises; on any internal error
    the text comes back unchanged (and the error is logged)."""
    if not text or not re.search(r"[ء-ي]", text):
        return GuardResult(text)
    ss = _scanner()
    if ss is None:
        return GuardResult(text, available=False)
    lang = "ar" if lang == "ar" else "en"
    try:
        findings = [f for f in ss.scan_text(text) if f.span]
    except Exception as exc:  # noqa: BLE001
        logger.warning("hadith guard scan failed: %s", exc)
        return GuardResult(text)
    res = GuardResult(text)
    res.hadith = sum(f.kind == "hadith" for f in findings)
    res.quran = sum(f.kind == "quran" for f in findings)

    # Edits as (start, end, replacement); removals win over fixes they cover.
    removals: list[tuple[int, int]] = []
    fixes: list[tuple[int, int, str, int]] = []     # (start, end, replacement, finding)
    sources_at = text.find("📚")
    for i, f in enumerate(findings):
        if f.verdict == "ok":
            continue
        start, end = f.span
        if f.kind == "quran":
            if f.where:          # the words are the mushaf's; the reference is wrong
                ref = ss.AYAH_CITE.search(text[end:end + 60])
                if ref:
                    name = ss.SURAHS[f.where[0] - 1]
                    n = str(f.where[1]).translate(_AR_NUM) if lang == "ar" else str(f.where[1])
                    fixes.append((end + ref.start(2), end + ref.end(2), n, i))
                    fixes.append((end + ref.start(1), end + ref.end(1), name, i))
                    continue
            removals.append(_sentence(text, start, end))
            continue
        citation = _citation(ss, f, lang)
        if citation is None:
            removals.append(_sentence(text, start, end))
            continue
        paren = _paren_after(text, end)
        if paren:
            if text[paren[0]:paren[1]] != f" ({citation})":     # already right: nothing to do
                fixes.append((paren[0], paren[1], f" ({citation})", i))
        else:
            fixes.append((end, end, f" ({citation})", i))

    # Never cut into the sources line.
    if sources_at >= 0:
        removals = [(s, min(e, sources_at)) for s, e in removals if s < sources_at]
    removals.sort()
    merged: list[list[int]] = []
    for s, e in removals:
        if merged and s <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], e)
        else:
            merged.append([s, e])
    fixes = [x for x in fixes if not any(s <= x[0] < e or s < x[1] <= e for s, e in merged)]
    res.removed = len(merged)
    res.fixed = len({x[3] for x in fixes})

    edits = [(s, e, "") for s, e in merged] + [x[:3] for x in fixes]
    out = text
    for s, e, rep in sorted(edits, key=lambda x: (x[0], x[1]), reverse=True):
        out = out[:s] + rep + out[e:]
    res.text = _tidy(out) if merged else out
    body = res.text.split("📚", 1)[0]
    if merged and not re.search(r"[^\W\d_]{2,}", body):     # nothing left to read
        res.text = _EMPTY_AR if lang == "ar" else _EMPTY_EN
    if res.fixed or res.removed:
        logger.info("hadith guard: %d hadith, %d verses → fixed %d, removed %d",
                    res.hadith, res.quran, res.fixed, res.removed)
    return res
