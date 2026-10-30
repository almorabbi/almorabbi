#!/usr/bin/env python3
"""Document a prophet's story against its sources — read-only fetches, no text generated.

    backend/.venv/bin/python ops/tools/anbiya_sources.py fetch anbiya_yunus_young
    backend/.venv/bin/python ops/tools/anbiya_sources.py fetch --all
    backend/.venv/bin/python ops/tools/anbiya_sources.py fetch <id> --refs spec.json   # authoring
    python3 ops/tools/anbiya_sources.py show <id>                                       # side by side

Writes `ops/data/anbiya/<id>.sources.json` for a story in the series
`anbiya_quran` (docs/stories.json), the file `check_anbiya_stories.py` holds
the story to:

  * `verses`  — every cited ayah, copied from mobile/assets/data/quran.json
                (the mushaf the scripture guards use), word for word;
  * `tafsir`  — the التفسير الميسّر text of every cited ayah, fetched through
                backend/app/services/tafsir_service.py (Tafsir MCP, source
                "moyassar", cache off so the snapshot is the source's own), with
                `fetched_at` per ayah. A snapshot is kept on later runs (the story
                was written from it) unless `--refresh`;
  * `fields`  — every text of the story (title, pages, pause, questions…), its
                cited ayat, and per sentence (the narrator's own split) the ayat it
                rests on plus the fidelity verdict (anbiya_fidelity.py writes it);
  * `content_sha256` — the story's text as documented. Editing the story voids it.

Per-sentence refs are the author's: given once with `--refs` (a JSON object
{"<id>": {"<field path>": {"refs": [...], "sentences": {"<sentence>": [...]}}}}),
then carried over for every sentence whose text did not change. A verdict is
carried over only while the sentence AND its evidence are the ones it judged.
Nothing here writes story text — it reads the story, the mushaf and the tafsir.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_anbiya_stories as C  # noqa: E402

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


def _sort_refs(refs) -> list[str]:
    return sorted(set(refs), key=lambda r: tuple(int(x) for x in r.split(":")))


async def _fetch_tafsir(refs: list[str]) -> dict[str, dict]:
    os.environ["TAFSIR_CACHE_ENABLED"] = "false"   # the source's own text, not a cached copy
    sys.path.insert(0, str(ROOT / "backend"))
    try:
        from app.services.tafsir_service import fetch_tafsir  # noqa: PLC0415
    except ImportError as exc:
        sys.exit(f"❌ tafsir_service لا يُستورد ({exc}) — شغّل بـ backend/.venv/bin/python")
    out = {}
    for ref in refs:
        s, a = (int(x) for x in ref.split(":"))
        r = (await fetch_tafsir(s, a, [C.TAFSIR]))[0]
        if not r.ok:
            sys.exit(f"❌ الميسّر لم يُجلب للآية {ref} ({r.error}) — لا توثيق ناقص")
        out[ref] = {"text": r.text.strip(), "attribution": r.attribution,
                    "fetched_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    return out


def build(sid: str, spec: dict | None, refresh: bool) -> dict:
    story = _story(sid)
    old = _old(sid)
    old_fields = {f["path"]: f for f in old.get("fields") or []}
    spec = (spec or {}).get(sid) or {}
    fields = C.fields_of(story)

    plan = []
    for path, text in fields:
        given, prev = spec.get(path) or {}, old_fields.get(path) or {}
        refs = given.get("refs") or prev.get("refs")
        if not refs and path.startswith("pages["):
            sys.exit(f"❌ {sid} :: {path} بلا آيات مصدر — أعطها في --refs")
        prev_sent = {s["text"]: s for s in prev.get("sentences") or []}
        plan.append((path, text, refs, given.get("sentences") or {}, prev_sent))
    story_refs = _sort_refs(r for _, _, refs, _, _ in plan for r in (refs or []))
    plan = [(p, t, refs or story_refs, g, ps) for p, t, refs, g, ps in plan]

    quran = C.mushaf()
    verses = {}
    for ref in story_refs:
        if ref not in quran:
            sys.exit(f"❌ {ref} ليست آية في mobile/assets/data/quran.json")
        verses[ref] = quran[ref]

    tafsir_old = {} if refresh else (old.get("tafsir_meta") or {})
    tafsir_old = {r: {**m, "text": (old.get("tafsir") or {}).get(r, "")}
                  for r, m in tafsir_old.items() if (old.get("tafsir") or {}).get(r)}
    need = [r for r in story_refs if r not in tafsir_old]
    fetched = asyncio.run(_fetch_tafsir(need)) if need else {}
    tafsir_all = {**tafsir_old, **fetched}
    tafsir = {r: tafsir_all[r]["text"] for r in story_refs}
    meta = {r: {k: v for k, v in tafsir_all[r].items() if k != "text"} for r in story_refs}

    out_fields = []
    for path, text, refs, given_sent, prev_sent in plan:
        sents = []
        for t in C.sentences(text):
            srefs = given_sent.get(t) or (prev_sent.get(t) or {}).get("refs") or refs
            bad = [r for r in srefs if r not in refs]
            if bad:
                sys.exit(f"❌ {sid} :: {path}: جملة تستند إلى {bad} وليست من آيات الحقل")
            entry = {"text": t, "refs": _sort_refs(srefs)}
            fid = (prev_sent.get(t) or {}).get("fidelity")
            if fid and fid.get("sha") == C.evidence_sha(t, entry["refs"], verses, tafsir):
                entry["fidelity"] = fid
            sents.append(entry)
        out_fields.append({"path": path, "refs": _sort_refs(refs), "sentences": sents})

    return {
        "id": sid, "series": C.SERIES,
        "about": ("مصادر القصة: الآيات من mobile/assets/data/quran.json، والتفسير الميسّر "
                  "(مجمع الملك فهد) عبر Tafsir MCP. كتبته ops/tools/anbiya_sources.py — "
                  "جلب للقراءة فقط، لا توليد نص. والحكم لكل جملة من anbiya_fidelity.py."),
        "tafsir_source": C.TAFSIR,
        "content_sha256": C.content_sha(story),
        "refs": story_refs,
        "verses": verses,
        "tafsir": tafsir,
        "tafsir_meta": meta,
        "fields": out_fields,
    }


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
        print(f"✓ {sid}: {len(doc['refs'])} آية · {n} جملة · محكوم عليها {judged}")
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
    f.add_argument("--refresh", action="store_true", help="re-fetch Muyassar even when a snapshot exists")
    s = sub.add_parser("show")
    s.add_argument("ids", nargs="+")
    args = ap.parse_args()
    return {"fetch": cmd_fetch, "show": cmd_show}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
