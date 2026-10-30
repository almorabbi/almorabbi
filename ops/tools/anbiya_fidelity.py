#!/usr/bin/env python3
"""Fidelity review of a prophet's story, sentence by sentence — by two other model families.

    python3 ops/tools/anbiya_fidelity.py run anbiya_yunus_young      # judge what is unjudged
    python3 ops/tools/anbiya_fidelity.py run --all [--force]
    python3 ops/tools/anbiya_fidelity.py report --all                 # what is not supported, and why

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
import review_en_parity as R  # noqa: E402

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


def _ask(model: str, msg: str) -> dict:
    raw, _ = R.post(model, SYSTEM, msg, timeout=300)
    try:
        out = R.parse_json(raw)
    except (ValueError, json.JSONDecodeError):
        return {"verdict": "error", "reason": f"unparseable: {raw[:120]}"}
    v = str(out.get("verdict", "")).strip().lower()
    return {"verdict": v if v in ("supported", "unsupported") else "error",
            "reason": str(out.get("reason", ""))[:400],
            "unsupported_part": str(out.get("unsupported_part", ""))[:200]}


def run(sid: str, force: bool, workers: int) -> tuple[int, int, list]:
    doc = SRC._old(sid)
    if not doc:
        sys.exit(f"❌ {sid}: لا ملف مصادر — anbiya_sources.py fetch {sid}")
    story = SRC._story(sid)
    if doc.get("content_sha256") != C.content_sha(story):
        sys.exit(f"❌ {sid}: ملف المصادر لا يطابق النص الحالي — أعد anbiya_sources.py fetch أولًا")
    verses, tafsir = doc["verses"], doc["tafsir"]
    jobs = []
    for f in doc["fields"]:
        for s in f["sentences"]:
            sha = C.evidence_sha(s["text"], s["refs"], verses, tafsir)
            fid = s.get("fidelity") or {}
            if not force and fid.get("sha") == sha and fid.get("prompt_version") == PROMPT_V and all(
                    (fid.get("reviews") or {}).get(m, {}).get("verdict") in ("supported", "unsupported")
                    for m in C.REVIEWERS):
                continue
            jobs.append((f["path"], s, sha))

    def judge(job):
        path, s, sha = job
        msg = _message(s["text"], s["refs"], verses, tafsir, story["title"], path)
        reviews = {m: _ask(m, msg) for m in C.REVIEWERS}
        ok = all(r["verdict"] == "supported" for r in reviews.values())
        s["fidelity"] = {"verdict": "supported" if ok else "unsupported", "reviews": reviews,
                         "sha": sha, "date": date.today().isoformat(),
                         "reviewers": list(C.REVIEWERS), "prompt_version": PROMPT_V}
        return path, s

    R.set_concurrency(workers)
    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(judge, jobs))
    SRC.write(sid, doc)
    bad = [(f["path"], s) for f in doc["fields"] for s in f["sentences"]
           if (s.get("fidelity") or {}).get("verdict") != "supported"]
    return len(jobs), sum(len(f["sentences"]) for f in doc["fields"]), bad


def _ids(args) -> list[str]:
    if args.all:
        return [s["id"] for s in json.loads(C.STORIES_AR.read_text(encoding="utf-8"))
                if s.get("series") == C.SERIES]
    return args.ids


def report(bad: list, sid: str) -> None:
    for path, s in bad:
        print(f"  ✗ {sid} :: {path}\n    «{s['text']}»")
        for m, r in ((s.get("fidelity") or {}).get("reviews") or {}).items():
            if r.get("verdict") != "supported":
                print(f"      {m}: {r.get('verdict')} — {r.get('reason')} [{r.get('unsupported_part')}]")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
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
            asked, n, bad = run(sid, args.force, args.workers)
            print(f"{'✓' if not bad else '✗'} {sid}: {n} جملة · سُئل عن {asked} · غير مدعومة {len(bad)}")
        else:
            doc = SRC._old(sid)
            bad = [(f["path"], s) for f in doc.get("fields") or [] for s in f["sentences"]
                   if (s.get("fidelity") or {}).get("verdict") != "supported"]
            print(f"{sid}: غير مدعومة {len(bad)}")
        report(bad, sid)
        total_bad += len(bad)
    return 1 if total_bad else 0


if __name__ == "__main__":
    sys.exit(main())
