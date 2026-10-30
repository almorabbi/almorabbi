#!/usr/bin/env python3
"""Document a Seerah story against its sources — read-only fetches, no text generated.

    backend/.venv/bin/python ops/tools/sira_sources.py fetch sira_ghar_young
    backend/.venv/bin/python ops/tools/sira_sources.py fetch --all
    backend/.venv/bin/python ops/tools/sira_sources.py fetch <id> --refs spec.json   # authoring
    python3 ops/tools/sira_sources.py show <id>                                       # side by side

Writes `ops/data/sira/<id>.sources.json` for a story in the series `sira_sahih`
(docs/stories.json), the file `check_sira_stories.py` holds the story to:

  * `hadith`  — every cited narration of Sahih al-Bukhari / Sahih Muslim: book,
                number, and its display text from the pinned edition
                (`check_sira_stories.EDITION` — the one ops/data/hadith_index.json.gz
                was built from), with the URL and `fetched_at`. A download whose
                text does not hold the index entry for that number is refused;
  * `verses`  — every cited ayah, copied from mobile/assets/data/quran.json, word
                for word, and `tafsir` its التفسير الميسّر through
                backend/app/services/tafsir_service.py (source "moyassar", cache
                off), with `fetched_at` per ayah;
  * `fields`  — every text of the story, its sources, and per sentence (the
                narrator's own split) the sources it rests on plus the fidelity
                verdict (`anbiya_fidelity.py --series sira_sahih` writes it);
  * `content_sha256` — the story's text as documented. Editing the story voids it.

Refs are «bukhari:3653», «muslim:1631» or «9:40». Per-field / per-sentence refs
are the author's: given once with `--refs` (a JSON object {"<id>": {"<field
path>": {"refs": [...], "sentences": {"<sentence>": [...]}}}}), then carried over
for every sentence whose text did not change. A field with no refs of its own
(title, questions…) rests on all of the story's sources. A snapshot is kept on
later runs (the story was written from it) unless `--refresh`; a verdict is kept
only while the sentence AND its evidence are the ones it judged.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anbiya_sources as AS  # noqa: E402  — the Muyassar fetch is the same one
import check_sira_stories as C  # noqa: E402

ROOT = C.ROOT


def _story(sid: str) -> dict:
    for s in json.loads(C.STORIES_AR.read_text(encoding="utf-8")):
        if s.get("id") == sid:
            if s.get("series") != C.SERIES:
                sys.exit(f"❌ {sid} ليست في السلسلة {C.SERIES}")
            return s
    sys.exit(f"❌ لا قصة بالمعرّف {sid} في docs/stories.json")


def _path(sid: str) -> Path:
    return C.SOURCES_DIR / f"{sid}.sources.json"


def _old(sid: str) -> dict:
    p = _path(sid)
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _sort_refs(refs) -> list[str]:
    def key(r: str):
        m = C._HADITH_REF.match(r)
        return (1, m.group(1), int(m.group(2))) if m else (0, "", *(int(x) for x in r.split(":")))
    return sorted(set(refs), key=key)


def fetch_hadith(ref: str) -> dict:
    """The display text of one narration from the pinned edition — refused
    unless it holds the hadith index entry for that number."""
    m = C._HADITH_REF.match(ref)
    if not m:
        sys.exit(f"❌ {ref} ليس مرجع حديث (bukhari:N أو muslim:N)")
    book, n = C.BOOK_OF[m.group(1)], int(m.group(2))
    url = C.EDITION_URL.format(ed=C.EDITIONS[book], n=n)
    with urllib.request.urlopen(url, timeout=60) as r:  # noqa: S310 — a pinned https URL
        data = json.loads(r.read().decode("utf-8"))
    hs = [h for h in data.get("hadiths") or [] if h.get("hadithnumber") == n]
    if len(hs) != 1 or not str(hs[0].get("text") or "").strip():
        sys.exit(f"❌ {ref}: الطبعة لم تُرجع حديثًا واحدًا بهذا الرقم")
    text = str(hs[0]["text"]).strip()
    if not C.hadith_snapshot_ok(book, n, text):
        sys.exit(f"❌ {ref}: النص المنزَّل لا يطابق {book} {n} في فهرس الصحيحين — لا توثيق")
    return {"book": book, "number": n, "text": text, "edition": C.EDITION, "url": url,
            "reference": hs[0].get("reference"), "fetched_at": _now()}


def build(sid: str, spec: dict | None, refresh: bool) -> dict:
    story = _story(sid)
    old = _old(sid)
    old_fields = {f["path"]: f for f in old.get("fields") or []}
    spec = (spec or {}).get(sid) or {}

    plan = []
    for path, text in C.fields_of(story):
        given, prev = spec.get(path) or {}, old_fields.get(path) or {}
        refs = given.get("refs") or prev.get("refs")
        if not refs and path.startswith("pages["):
            sys.exit(f"❌ {sid} :: {path} بلا مصادر — أعطها في --refs")
        # every hadith a field cites is one of its sources, whatever the spec says
        cited = [C.ref_of(b, n) for b, n in C.CITE.findall(text)]
        if refs and any(r not in refs for r in cited):
            sys.exit(f"❌ {sid} :: {path}: يستشهد بـ{[r for r in cited if r not in refs]} وليس في مصادره")
        prev_sent = {s["text"]: s for s in prev.get("sentences") or []}
        plan.append((path, text, refs, given.get("sentences") or {}, prev_sent))
    story_refs = _sort_refs(r for _, _, refs, _, _ in plan for r in (refs or []))
    plan = [(p, t, refs or story_refs, g, ps) for p, t, refs, g, ps in plan]

    hadith_old = {} if refresh else (old.get("hadith") or {})
    hadith = {r: hadith_old[r] if r in hadith_old else fetch_hadith(r)
              for r in story_refs if C.is_hadith_ref(r)}

    quran = C.mushaf()
    verse_refs = [r for r in story_refs if not C.is_hadith_ref(r)]
    verses = {}
    for ref in verse_refs:
        if ref not in quran:
            sys.exit(f"❌ {ref} ليست آية في mobile/assets/data/quran.json")
        verses[ref] = quran[ref]
    tafsir_old = {} if refresh else (old.get("tafsir_meta") or {})
    tafsir_old = {r: {**m, "text": (old.get("tafsir") or {}).get(r, "")}
                  for r, m in tafsir_old.items() if (old.get("tafsir") or {}).get(r)}
    need = [r for r in verse_refs if r not in tafsir_old]
    os.environ["TAFSIR_CACHE_ENABLED"] = "false"
    fetched = asyncio.run(AS._fetch_tafsir(need)) if need else {}
    tafsir_all = {**tafsir_old, **fetched}
    tafsir = {r: tafsir_all[r]["text"] for r in verse_refs}
    meta = {r: {k: v for k, v in tafsir_all[r].items() if k != "text"} for r in verse_refs}

    doc = {
        "id": sid, "series": C.SERIES,
        "about": ("مصادر القصة: الأحاديث من صحيح البخاري ومسلم بنصّها في الطبعة المثبّتة "
                  f"({C.EDITION}) — وهي التي بُني منها فهرس الصحيحين — والآيات من "
                  "mobile/assets/data/quran.json، والتفسير الميسّر (مجمع الملك فهد) عبر Tafsir MCP. "
                  "كتبته ops/tools/sira_sources.py — جلب للقراءة فقط، لا توليد نص. "
                  "والحكم لكل جملة من anbiya_fidelity.py --series sira_sahih."),
        "tafsir_source": C.TAFSIR if verses else None,
        "content_sha256": C.content_sha(story),
        "refs": story_refs,
        "hadith": hadith,
        "verses": verses,
        "tafsir": tafsir,
        "tafsir_meta": meta,
    }
    out_fields = []
    for path, text, refs, given_sent, prev_sent in plan:
        sents = []
        for t in C.sentences(text):
            srefs = given_sent.get(t) or (prev_sent.get(t) or {}).get("refs") or refs
            bad = [r for r in srefs if r not in refs]
            if bad:
                sys.exit(f"❌ {sid} :: {path}: جملة تستند إلى {bad} وليست من مصادر الحقل")
            entry = {"text": t, "refs": _sort_refs(srefs)}
            fid = (prev_sent.get(t) or {}).get("fidelity")
            if fid and fid.get("sha") == C.evidence_sha(t, entry["refs"], doc):
                entry["fidelity"] = fid
            sents.append(entry)
        out_fields.append({"path": path, "refs": _sort_refs(refs), "sentences": sents})
    doc["fields"] = out_fields
    return doc


def write(sid: str, doc: dict) -> None:
    C.SOURCES_DIR.mkdir(parents=True, exist_ok=True)
    _path(sid).write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def cmd_fetch(args) -> int:
    ids = args.ids
    if args.all:
        ids = [s["id"] for s in json.loads(C.STORIES_AR.read_text(encoding="utf-8"))
               if s.get("series") == C.SERIES]
    if not ids:
        sys.exit("❌ اذكر قصة أو --all")
    spec = json.loads(Path(args.refs).read_text(encoding="utf-8")) if args.refs else None
    for sid in ids:
        doc = build(sid, spec, args.refresh)
        write(sid, doc)
        n = sum(len(f["sentences"]) for f in doc["fields"])
        judged = sum(1 for f in doc["fields"] for s in f["sentences"] if s.get("fidelity"))
        print(f"✓ {sid}: {len(doc['hadith'])} حديث · {len(doc['verses'])} آية · {n} جملة · محكوم عليها {judged}")
    return 0


def cmd_show(args) -> int:
    for sid in args.ids:
        doc = _old(sid)
        for f in doc.get("fields") or []:
            print(f"\n── {f['path']}  [{', '.join(f['refs'])}]")
            for s in f["sentences"]:
                v = (s.get("fidelity") or {}).get("verdict", "—")
                print(f"   [{v}] {s['text']}  ← {', '.join(s['refs'])}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fetch")
    f.add_argument("ids", nargs="*")
    f.add_argument("--all", action="store_true")
    f.add_argument("--refs", help="authoring spec: per-field / per-sentence refs")
    f.add_argument("--refresh", action="store_true", help="re-fetch hadith and Muyassar even when a snapshot exists")
    s = sub.add_parser("show")
    s.add_argument("ids", nargs="+")
    args = ap.parse_args()
    return {"fetch": cmd_fetch, "show": cmd_show}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
