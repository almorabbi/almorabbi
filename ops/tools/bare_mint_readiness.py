"""Is it safe to close the bare mint yet? Read-only, counts only.

SESSION_MINT_ENFORCE (routers/chat.py) moves a session minted for a known
device with no proof to a new, empty device. A reinstall restored from a phone
backup brings its family back only if the backup carries a restore key
(services/restore_keys.py) — that is, if the install that was backed up ran a
build that asks for one (1.0.77+, build 122). This prints, from the
conversations database:

  * active devices (a push registration in the last --days) and how many of
    them hold a restore key, and how many run build ≥ --min-build;
  * sessions minted per day by kind (new / proof / restore / bare / pre-v37),
    over the same window — every `bare` is either a reinstall that the
    enforcement would start over, or someone else claiming that device.

Flip SESSION_MINT_ENFORCE (and IDENTITY_CROSS_DEVICE with it) when the share
of active devices holding a key is high enough that the bare mints left are
worth the trade. Never prints a device id.

    python3 ops/tools/bare_mint_readiness.py [--db PATH] [--days 14] [--min-build 122]
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _has(conn, table: str, column: str | None = None) -> bool:
    if conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                    (table,)).fetchone() is None:
        return False
    return column is None or column in {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}


def report(conn: sqlite3.Connection, days: int = 14, min_build: int = 122) -> dict:
    window = f"-{int(days)} days"
    out: dict = {"days": days, "min_build": min_build}
    if not _has(conn, "push_tokens"):
        return {**out, "error": "no push_tokens table"}
    active = conn.execute(
        "SELECT COUNT(*) FROM push_tokens WHERE updated_at >= datetime('now', ?)", (window,)
    ).fetchone()[0]
    out["active_devices"] = active
    if _has(conn, "push_tokens", "build_number"):
        out["active_on_min_build"] = conn.execute(
            "SELECT COUNT(*) FROM push_tokens WHERE updated_at >= datetime('now', ?) "
            "AND build_number >= ?", (window, min_build)).fetchone()[0]
    if _has(conn, "device_restore_keys"):
        out["active_with_restore_key"] = conn.execute(
            "SELECT COUNT(*) FROM push_tokens p JOIN device_restore_keys k "
            "ON k.device_id = p.device_id WHERE p.updated_at >= datetime('now', ?)",
            (window,)).fetchone()[0]
        out["restore_keys_total"] = conn.execute(
            "SELECT COUNT(*) FROM device_restore_keys").fetchone()[0]
    if _has(conn, "api_tokens", "mint_kind"):
        rows = conn.execute(
            "SELECT date(created_at) AS day, COALESCE(mint_kind, 'pre-v37') AS kind, COUNT(*) "
            "FROM api_tokens WHERE created_at >= datetime('now', ?) GROUP BY day, kind "
            "ORDER BY day", (window,)).fetchall()
        per_day: dict[str, dict[str, int]] = {}
        for day, kind, n in rows:
            per_day.setdefault(day, {})[kind] = n
        out["mints_per_day"] = per_day
    if active and "active_with_restore_key" in out:
        out["restore_key_share"] = round(out["active_with_restore_key"] / active, 3)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default=os.environ.get("CONVERSATIONS_DB",
                                                   str(ROOT / "ops" / "conversations.db")))
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--min-build", type=int, default=122)
    args = ap.parse_args(argv)
    path = Path(args.db)
    if not path.is_file():
        print(f"no database at {path}", file=sys.stderr)
        return 2
    conn = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
    try:
        r = report(conn, args.days, args.min_build)
    finally:
        conn.close()
    if "error" in r:
        print(r["error"], file=sys.stderr)
        return 2
    print(f"window: last {r['days']} days")
    print(f"active devices:            {r['active_devices']}")
    if "active_on_min_build" in r:
        print(f"  on build ≥ {r['min_build']}:          {r['active_on_min_build']}")
    if "active_with_restore_key" in r:
        share = r.get("restore_key_share")
        print(f"  holding a restore key:   {r['active_with_restore_key']}"
              + (f"  ({share:.1%})" if share is not None else ""))
    if "mints_per_day" in r:
        print("mints per day (new / proof / restore / bare / pre-v37):")
        for day, kinds in r["mints_per_day"].items():
            print(f"  {day}  " + "  ".join(
                f"{k}={kinds.get(k, 0)}" for k in ("new", "proof", "restore", "bare", "pre-v37")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
