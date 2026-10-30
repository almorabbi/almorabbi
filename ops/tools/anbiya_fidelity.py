#!/usr/bin/env python3
"""Fidelity review of a prophet's story, sentence by sentence — by two other model families.

    python3 ops/tools/anbiya_fidelity.py run anbiya_yunus_young      # judge what is unjudged
    python3 ops/tools/anbiya_fidelity.py run --all [--force]
    python3 ops/tools/anbiya_fidelity.py report --all                 # what is not supported, and why
    python3 ops/tools/anbiya_fidelity.py --series sira_sahih run --all  # season 2, «من السيرة النبوية»

The author of these stories is a Claude model. The plan (2026-10-25) has no
human reviewer, so every sentence is put to two reviewers of two *other*
families — deepseek-v4-pro and glm-5.2 on Ollama Cloud, through the very
client `review_en_parity.py` uses (same key handling: OLLAMA_API_KEY from the
environment or ~/projects/email-twin/.env, never printed; same 429 cool-down).

Each reviewer sees ONLY the sentence, the cited ayat (Uthmani, from the mushaf
file) and their التفسير الميسّر snapshot from `ops/data/anbiya/<id>.sources.json`,
and answers one question: does the sentence say anything about the story that
those texts do not say? A sentence is "supported" only when BOTH say so. The
verdict is stored on the sentence with a sha over the sentence and its evidence
(`check_anbiya_stories.evidence_sha`), so editing either voids it and the guard
asks again. An unsupported sentence is fixed or removed in the story by hand —
this tool never rewrites text.

The same review serves the Seerah season (`--series sira_sahih`, 2026-10-30):
the evidence there is the cited narrations of Sahih al-Bukhari / Muslim (their
display text in `ops/data/sira/<id>.sources.json`) plus any cited verse with its
Muyassar, and the house rule is "say about the Prophet ﷺ and his companions
only what the Qur'an and the two Sahihs say". One series, one profile: the
sources module, the guard's evidence sha, the prompt — the loop is shared.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anbiya_sources as SRC  # noqa: E402
import check_anbiya_stories as C  # noqa: E402
import check_sira_stories as CS  # noqa: E402
import review_en_parity as R  # noqa: E402
import sira_sources as SRC_SIRA  # noqa: E402

SYSTEM = """You are a strict auditor of children's stories about the prophets, written in Arabic \
from the Qur'an. The house rule: say about a prophet ONLY what the Qur'an says. The ONLY allowed \
sources are the cited Qur'anic verses and the cited Arabic tafsir (التفسير الميسّر) that are given \
to you. You know other tafsir and the Isra'iliyyat literature: do NOT accept anything from them.

Judge ONE sentence. Answer "unsupported" if the sentence states or clearly implies ANY of the \
following that the given verses/tafsir do not state or directly entail:
- a fact, event, sequence or cause ("then", "after that", "because") not in the sources;
- a name, number, place, duration, age, or physical description;
- a feeling, motive, thought or intention of any person or creature not in the sources;
- words attributed to anyone (prophet, people, animal) that are not the verbatim verse in ﴿﴾ \
(paraphrased or invented speech is unsupported; reporting that someone called/prayed/warned is \
fine when the sources say so);
- a promise of reward, or a comparison/ranking between prophets.
Minor simplification for children, synonyms, and leaving details out are fine. Text inside ﴿﴾ is \
verbatim Qur'an (already checked) and is always supported. A question or an instruction addressed \
to the child is "supported" unless it asserts something about the story or the prophet that the \
sources do not support. General good manners (e.g. "be gentle with ants") are supported if they do \
not claim to be in the story. Honorifics of respect (عليه السلام، عليهما السلام، ﷺ، تعالى) are \
always supported. You are told what part of the story the sentence is (narration, a question to the \
child, an answer option the child may pick, Noor's reply to the child): judge it as that part — an \
answer option is the child's own possible choice in today's life, not a claim about the prophet.

Reply with JSON only: {"verdict": "supported" | "unsupported", "reason": "<one short sentence \
in English>", "unsupported_part": "<the exact words, or empty>"}"""


PROMPT_V = hashlib.sha256(SYSTEM.encode("utf-8")).hexdigest()[:12]

ROLES = [  # (field path prefix, what the reader is looking at)
    ("pages[", "narration of the story (a page the narrator reads aloud)"),
    ("title", "the story's title"),
    ("description", "the story's one-line description on the shelf"),
    ("pause.question", "a question Noor asks the child in the middle of the story"),
    ("pause.options", "an answer option the CHILD may pick to Noor's question — the child's own "
                      "possible choice in today's life, not a statement about the prophet or the story"),
    ("pause.affirm", "Noor's warm reply when the child picks the caring option"),
    ("pause.nudge", "Noor's gentle reply when the child picks the other option"),
    ("discussionQuestions", "a discussion question for parent and child after the story"),
    ("islamicValue", "the story's lesson line shown after the story"),
    ("actionChallenge", "a practical challenge for the child after the story"),
]


def role_of(path: str) -> str:
    return next(r for p, r in ROLES if path.startswith(p))


def _message(sentence: str, refs: list[str], verses: dict, tafsir: dict, title: str, path: str) -> str:
    ev = "\n".join(f"[{r}] الآية: {verses[r]}\n[{r}] الميسّر: {tafsir[r]}" for r in refs)
    return (f"Story: {title}\n\nSOURCES (the only allowed evidence):\n{ev}\n\n"
            f"THIS SENTENCE IS: {role_of(path)}\n\n"
            f"SENTENCE TO JUDGE:\n{sentence}\n\nJSON only.")


def _ask(model: str, msg: str, system: str = SYSTEM) -> dict:
    raw, _ = R.post(model, system, msg, timeout=300)
    try:
        out = R.parse_json(raw)
    except (ValueError, json.JSONDecodeError):
        return {"verdict": "error", "reason": f"unparseable: {raw[:120]}"}
    v = str(out.get("verdict", "")).strip().lower()
    return {"verdict": v if v in ("supported", "unsupported") else "error",
            "reason": str(out.get("reason", ""))[:400],
            "unsupported_part": str(out.get("unsupported_part", ""))[:200]}


# ── the Seerah season ─────────────────────────────────────────────────────
SYSTEM_SIRA = """You are a strict auditor of children's stories from the Seerah (the life of the \
Prophet Muhammad ﷺ), written in Arabic. The house rule: say about the Prophet ﷺ and his companions ONLY \
what the Qur'an and Sahih al-Bukhari / Sahih Muslim say. The ONLY allowed sources are the cited \
hadith texts (Arabic, with their chains of narrators) and any cited Qur'anic verse with its Arabic \
tafsir (التفسير الميسّر) that are given to you. You know the Seerah literature, other hadith books \
and popular retellings: do NOT accept anything from them (e.g. the spider, the doves, the tree or \
the snake at the cave; names or numbers they add).

Judge ONE sentence. Answer "unsupported" if the sentence states or clearly implies ANY of the \
following that the given sources do not state or directly entail:
- a fact, event, sequence or cause ("then", "after that", "because") not in the sources;
- a name, number, place, duration, age, or physical description;
- a feeling, motive, thought or intention of any person or thing not in the sources;
- words attributed to anyone that are not verbatim the cited hadith (between «» followed by its \
citation) or the verse (in ﴿﴾); or a quote attributed to the wrong speaker — check WHO says the \
quoted words in the hadith text (a narrator of the chain is not the companion);
- a promise of reward, or a comparison/ranking between prophets or companions.
Text inside «» followed by «(صحيح البخاري N)» has been checked by machine to be the verbatim wording \
of that hadith: judge only whether its attribution (who said it, to whom, when) and its framing \
match the sources. Text inside ﴿﴾ is verbatim Qur'an (already checked) and is always supported. A \
short plain-language explanation of a word (after «أي:», or «X: meaning») is supported when it is the \
word's ordinary dictionary meaning and adds no fact about the story. Minor simplification for \
children, synonyms, and leaving details out are fine. A question or an instruction addressed to the \
child is "supported" unless it asserts something about the story that the sources do not support. \
General good manners are supported if they do not claim to be in the story. Honorifics of respect \
(ﷺ، صلى الله عليه وسلم، رضي الله عنه/عنهما، عليه السلام، تعالى) are always supported. You are told what \
part of the story the sentence is (narration, a question to the child, an answer option the child \
may pick, Noor's reply to the child): judge it as that part — an answer option is the child's own \
possible choice in today's life, not a claim about the Prophet ﷺ.

Reply with JSON only: {"verdict": "supported" | "unsupported", "reason": "<one short sentence \
in English>", "unsupported_part": "<the exact words, or empty>"}"""


def _message_sira(sentence: str, refs: list[str], doc: dict, title: str, path: str) -> str:
    ev = []
    for r in refs:
        if CS.is_hadith_ref(r):
            h = doc["hadith"][r]
            ev.append(f"[{r}] صحيح {h['book']} {h['number']}: {h['text']}")
        else:
            ev.append(f"[{r}] الآية: {doc['verses'][r]}\n[{r}] الميسّر: {doc['tafsir'][r]}")
    return (f"Story: {title}\n\nSOURCES (the only allowed evidence):\n" + "\n".join(ev) + "\n\n"
            f"THIS SENTENCE IS: {role_of(path)}\n\n"
            f"SENTENCE TO JUDGE:\n{sentence}\n\nJSON only.")


PROFILES = {  # series → (sources module, evidence sha, message, system prompt)
    C.SERIES: (SRC, lambda t, refs, doc: C.evidence_sha(t, refs, doc["verses"], doc["tafsir"]),
               lambda t, refs, doc, title, path: _message(t, refs, doc["verses"], doc["tafsir"], title, path),
               SYSTEM),
    CS.SERIES: (SRC_SIRA, CS.evidence_sha, _message_sira, SYSTEM_SIRA),
}
PROMPT_VERSIONS = {series: (PROMPT_V if series == C.SERIES else
                            hashlib.sha256(p[3].encode("utf-8")).hexdigest()[:12])
                   for series, p in PROFILES.items()}


def run(sid: str, force: bool, workers: int, series: str = C.SERIES) -> tuple[int, int, list]:
    src_mod, ev_sha, message, system = PROFILES[series]
    prompt_v = PROMPT_VERSIONS[series]
    doc = src_mod._old(sid)
    if not doc:
        sys.exit(f"❌ {sid}: لا ملف مصادر — {Path(src_mod.__file__).name} fetch {sid}")
    story = src_mod._story(sid)
    if doc.get("content_sha256") != C.content_sha(story):
        sys.exit(f"❌ {sid}: ملف المصادر لا يطابق النص الحالي — أعد {Path(src_mod.__file__).name} fetch أولًا")
    jobs = []
    for f in doc["fields"]:
        for s in f["sentences"]:
            sha = ev_sha(s["text"], s["refs"], doc)
            fid = s.get("fidelity") or {}
            if not force and fid.get("sha") == sha and fid.get("prompt_version") == prompt_v and all(
                    (fid.get("reviews") or {}).get(m, {}).get("verdict") in ("supported", "unsupported")
                    for m in C.REVIEWERS):
                continue
            jobs.append((f["path"], s, sha))

    def judge(job):
        path, s, sha = job
        msg = message(s["text"], s["refs"], doc, story["title"], path)
        reviews = {m: _ask(m, msg, system) for m in C.REVIEWERS}
        ok = all(r["verdict"] == "supported" for r in reviews.values())
        s["fidelity"] = {"verdict": "supported" if ok else "unsupported", "reviews": reviews,
                         "sha": sha, "date": date.today().isoformat(),
                         "reviewers": list(C.REVIEWERS), "prompt_version": prompt_v}
        return path, s

    R.set_concurrency(workers)
    try:
        with ThreadPoolExecutor(max_workers=workers) as ex:
            list(ex.map(judge, jobs))
    finally:
        # The shared Ollama quota can close mid-story (UsageCapError): keep the
        # verdicts already given — each is bound to its sentence by its sha —
        # so the next run asks only for what is missing.
        src_mod.write(sid, doc)
    bad = [(f["path"], s) for f in doc["fields"] for s in f["sentences"]
           if (s.get("fidelity") or {}).get("verdict") != "supported"]
    return len(jobs), sum(len(f["sentences"]) for f in doc["fields"]), bad


def _ids(args) -> list[str]:
    if args.all:
        return [s["id"] for s in json.loads(C.STORIES_AR.read_text(encoding="utf-8"))
                if s.get("series") == args.series]
    return args.ids


def report(bad: list, sid: str) -> None:
    for path, s in bad:
        print(f"  ✗ {sid} :: {path}\n    «{s['text']}»")
        for m, r in ((s.get("fidelity") or {}).get("reviews") or {}).items():
            if r.get("verdict") != "supported":
                print(f"      {m}: {r.get('verdict')} — {r.get('reason')} [{r.get('unsupported_part')}]")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--series", choices=sorted(PROFILES), default=C.SERIES)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("run", "report"):
        p = sub.add_parser(name)
        p.add_argument("ids", nargs="*")
        p.add_argument("--all", action="store_true")
        if name == "run":
            p.add_argument("--force", action="store_true")
            p.add_argument("--workers", type=int, default=3)
    args = ap.parse_args()
    total_bad = 0
    for sid in _ids(args):
        if args.cmd == "run":
            asked, n, bad = run(sid, args.force, args.workers, args.series)
            print(f"{'✓' if not bad else '✗'} {sid}: {n} جملة · سُئل عن {asked} · غير مدعومة {len(bad)}")
        else:
            doc = PROFILES[args.series][0]._old(sid)
            bad = [(f["path"], s) for f in doc.get("fields") or [] for s in f["sentences"]
                   if (s.get("fidelity") or {}).get("verdict") != "supported"]
            print(f"{sid}: غير مدعومة {len(bad)}")
        report(bad, sid)
        total_bad += len(bad)
    return 1 if total_bad else 0


if __name__ == "__main__":
    sys.exit(main())
