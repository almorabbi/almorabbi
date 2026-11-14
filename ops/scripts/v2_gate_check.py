#!/usr/bin/env python3
"""Canonical 2.0.0 release gate evaluator — read-only, deterministic, zero PII.

Evaluates the four naming gates required before bumping the product version to
2.0.0:
  1. Three 2.0 headlines shipped (child-centric home, family account, visual
     unification).
  2. First-week parenting action (D7 >= 12% across 4 pooled matured weekly
     cohorts with >= 150 new real families).
  3. Identity lock (restore-key share >= 85% of active 14d devices AND
     SESSION_MINT_ENFORCE enabled).
  4. Zero unconsumed (`⚠️`) capabilities remaining in docs/catalog/FEATURES.md.

Opens SQLite strictly with `?mode=ro` and never emits device IDs, child names,
or question text.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


def _resolve_root() -> Path:
    if "__file__" in globals() and __file__ != "<stdin>":
        p = Path(__file__).resolve()
        if len(p.parents) >= 3:
            return p.parents[2]
    return Path.cwd()


_ROOT = _resolve_root()
_BACKEND = _ROOT / "backend"
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))
if str(_BACKEND) not in sys.path:
    sys.path.insert(1, str(_BACKEND))

from app.core.real_traffic import e2e_devices, real_device_sql, table_names  # noqa: E402
from app.services.family_actions import ACTION_SOURCES  # noqa: E402

_MIN_QUESTION_CHARS = 12
_TIP_PREFIX = "بخصوص نصيحة اليوم"
_CATALOG_ROW_RE = re.compile(r"^\|\s*([A-G]\d+)\s*\|(.+)\|\s*$")


def _load_bare_mint_module():
    path = _ROOT / "ops" / "tools" / "bare_mint_readiness.py"
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location("bare_mint_readiness", path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value)
        if dt.tzinfo is not None:
            dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
        return dt
    except ValueError:
        return None


def _normalize_text(text: str | None) -> str:
    t = re.sub(r"[ـً-ْ]", "", text or "")
    return " ".join(t.split()).strip()


def load_suggested_questions(arb_path: Path | None = None) -> set[str]:
    path = arb_path or (_ROOT / "mobile" / "lib" / "l10n" / "app_ar.arb")
    if not path.is_file():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return {
            _normalize_text(v)
            for k, v in data.items()
            if k.startswith("chatQ") and isinstance(v, str)
        }
    except Exception:
        return set()


def _columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {r[1] for r in conn.execute(f'PRAGMA table_info("{table}")')}


def _is_truthy(val: str | None) -> bool:
    return (val or "").strip().lower() in ("1", "true", "yes", "on")


def evaluate_gate1_headlines(
    conn: sqlite3.Connection | None,
    root: Path = _ROOT,
    env: dict[str, str] | None = None,
    overrides: dict[str, bool] | None = None,
) -> dict[str, Any]:
    """Check whether all three 2.0.0 headline deliverables are present."""
    env_map = env if env is not None else os.environ
    ovr = overrides or {}

    health_py = root / "backend" / "app" / "routers" / "health.py"
    health_txt = health_py.read_text(encoding="utf-8") if health_py.is_file() else ""

    child_home_widget = root / "mobile" / "lib" / "features" / "home" / "widgets" / "child_weekly_home.dart"
    child_centric_home = child_home_widget.is_file() or ("child_home_v2" in health_txt)

    tables = table_names(conn) if conn is not None else set()
    families_router = root / "backend" / "app" / "routers" / "families.py"
    family_account = (
        {"families", "family_members"} <= tables
        and families_router.is_file()
    )

    tokens_py = root / "mobile" / "lib" / "theme" / "design_tokens.dart"
    tokens_txt = tokens_py.read_text(encoding="utf-8") if tokens_py.is_file() else ""
    motion_resolved = (env_map.get("STORY_MOTION_MODE") or "").strip().lower() in ("motion", "static")
    visual_marker = (
        (root / "docs" / "catalog" / "VISUAL_UNIFICATION_2_0.md").is_file()
        or ("visual_unification_v2" in tokens_txt)
    )
    visual_unification = bool(visual_marker and motion_resolved)

    if "child_centric_home" in ovr:
        child_centric_home = bool(ovr["child_centric_home"])
    if "family_account" in ovr:
        family_account = bool(ovr["family_account"])
    if "visual_unification" in ovr:
        visual_unification = bool(ovr["visual_unification"])

    items = {
        "child_centric_home": child_centric_home,
        "family_account": family_account,
        "visual_unification": visual_unification,
    }
    return {
        "passed": all(items.values()),
        "items": items,
    }


def evaluate_gate2_d7_actions(
    conn: sqlite3.Connection,
    now: datetime | None = None,
    suggested_questions: set[str] | None = None,
) -> dict[str, Any]:
    """Compute 4-week pooled D7 parenting action rate and D1 return."""
    now = now or _utcnow()
    tables = table_names(conn)
    if "child_profiles" not in tables:
        return {"passed": False, "error": "no child_profiles table"}

    suggested = suggested_questions if suggested_questions is not None else load_suggested_questions()
    norm_tip_prefix = _normalize_text(_TIP_PREFIX)
    e2e = e2e_devices(conn)
    real_dev = real_device_sql("device_id", e2e)

    lookback_start = now - timedelta(days=42)
    lookback_str = lookback_start.strftime("%Y-%m-%d %H:%M:%S")

    # Identify each real device's onboarding timestamp t0 = MIN(datetime(created_at))
    cohort_rows = conn.execute(
        f"""
        SELECT device_id, MIN(datetime(created_at)) AS first_created
        FROM child_profiles
        WHERE created_at IS NOT NULL AND {real_dev}
        GROUP BY device_id
        HAVING MIN(datetime(created_at)) >= ?
        """,
        (lookback_str,),
    ).fetchall()

    devices_t0: dict[str, datetime] = {}
    for row in cohort_rows:
        dev = row[0]
        ts = _parse_ts(row[1])
        if dev and ts is not None:
            devices_t0[dev] = ts

    # Collect action timestamps per device separated by source kind.
    strict_source_tables = {
        "lesson_progress": ("started_at", "updated_at", "completed_at"),
        "habits_value_events": ("created_at",),
        "child_missions": ("assigned_at", "claimed_at", "confirmed_at"),
        "child_challenges": ("started_at",),
    }

    strict_events: dict[str, list[tuple[str, datetime]]] = defaultdict(list)
    extra_events: dict[str, list[tuple[str, datetime]]] = defaultdict(list)
    open_calendar_days: dict[str, set] = defaultdict(set)
    open_timestamps: dict[str, list[datetime]] = defaultdict(list)

    # 1) Genuine assistant user messages
    if {"chat_messages", "chat_sessions"} <= tables:
        real_cs = real_device_sql("cs.device_id", e2e)
        msg_rows = conn.execute(
            f"""
            SELECT cs.device_id, cm.content, datetime(cm.created_at) AS ts
            FROM chat_messages cm
            JOIN chat_sessions cs ON cs.id = cm.session_id
            WHERE cm.role = 'user'
              AND cs.device_id IS NOT NULL
              AND datetime(cm.created_at) >= ?
              AND {real_cs}
            """,
            (lookback_str,),
        ).fetchall()
        for dev, content, ts_raw in msg_rows:
            ts = _parse_ts(ts_raw)
            if ts is None:
                continue
            norm = _normalize_text(content)
            if (
                len(norm) >= _MIN_QUESTION_CHARS
                and norm not in suggested
                and not norm.startswith(norm_tip_prefix)
            ):
                strict_events[dev].append(("question", ts))
                open_calendar_days[dev].add(ts.date())
                open_timestamps[dev].append(ts)

    # 2) Other strict sources + extra ACTION_SOURCES
    cols_cache: dict[str, set[str]] = {}

    def _cols(tbl: str) -> set[str]:
        if tbl not in cols_cache:
            cols_cache[tbl] = _columns(conn, tbl) if tbl in tables else set()
        return cols_cache[tbl]

    for src in ACTION_SOURCES:
        cols = _cols(src.table)
        if src.column not in cols or "device_id" not in cols:
            continue
        is_strict = src.column in strict_source_tables.get(src.table, ())
        target_map = strict_events if is_strict else extra_events
        extra_sql = f" {src.where}" if src.where else ""
        rows = conn.execute(
            f"""
            SELECT device_id, datetime({src.column}) AS ts
            FROM "{src.table}"
            WHERE {src.column} IS NOT NULL
              AND datetime({src.column}) >= ?
              AND {real_dev}{extra_sql}
            """,
            (lookback_str,),
        ).fetchall()
        for dev, ts_raw in rows:
            ts = _parse_ts(ts_raw)
            if ts is None:
                continue
            target_map[dev].append((src.kind, ts))
            open_calendar_days[dev].add(ts.date())
            open_timestamps[dev].append(ts)

    # 3) Open signals for D1 (coach_tips, daily_login_streaks, chat_sessions)
    if "coach_tips" in tables:
        ct_cols = _cols("coach_tips")
        if {"device_id", "date"} <= ct_cols:
            has_created = "created_at" in ct_cols
            sel_ts = ", datetime(created_at) AS ts" if has_created else ", NULL AS ts"
            for r in conn.execute(
                f"SELECT device_id, date{sel_ts} FROM coach_tips "
                f"WHERE date >= ? AND {real_dev}",
                (lookback_start.date().isoformat(),),
            ).fetchall():
                dev, d_raw, ts_raw = r[0], r[1], r[2]
                try:
                    open_calendar_days[dev].add(datetime.fromisoformat(d_raw).date())
                except (TypeError, ValueError):
                    pass
                ts = _parse_ts(ts_raw)
                if ts is not None:
                    open_timestamps[dev].append(ts)

    if "daily_login_streaks" in tables:
        dls_cols = _cols("daily_login_streaks")
        if {"device_id", "date"} <= dls_cols:
            for dev, d_raw in conn.execute(
                f"SELECT DISTINCT device_id, date FROM daily_login_streaks "
                f"WHERE date >= ? AND {real_dev}",
                (lookback_start.date().isoformat(),),
            ).fetchall():
                try:
                    open_calendar_days[dev].add(datetime.fromisoformat(d_raw).date())
                except (TypeError, ValueError):
                    pass

    if "chat_sessions" in tables:
        for dev, ts_raw in conn.execute(
            f"SELECT device_id, datetime(created_at) FROM chat_sessions "
            f"WHERE device_id IS NOT NULL AND datetime(created_at) >= ? AND {real_dev}",
            (lookback_str,),
        ).fetchall():
            ts = _parse_ts(ts_raw)
            if ts is not None:
                open_timestamps[dev].append(ts)

    # Evaluate 4 pooled matured weeks: t0 in [now - 35d, now - 7d)
    pool_start = now - timedelta(days=35)
    pool_end = now - timedelta(days=7)

    pooled_devs = [dev for dev, t0 in devices_t0.items() if pool_start <= t0 < pool_end]
    strict_hits = 0
    all_hits = 0
    strict_by_kind: Counter[str] = Counter()
    d1_24_48h_hits = 0
    d1_cal_hits = 0

    for dev in pooled_devs:
        t0 = devices_t0[dev]
        t7 = t0 + timedelta(days=7)
        s_kinds = {k for k, ts in strict_events.get(dev, ()) if t0 <= ts < t7}
        e_kinds = {k for k, ts in extra_events.get(dev, ()) if t0 <= ts < t7}
        if s_kinds:
            strict_hits += 1
            for k in s_kinds:
                strict_by_kind[k] += 1
        if s_kinds or e_kinds:
            all_hits += 1
        t24 = t0 + timedelta(hours=24)
        t48 = t0 + timedelta(hours=48)
        if any(t24 <= ts < t48 for ts in open_timestamps.get(dev, ())):
            d1_24_48h_hits += 1
        if (t0.date() + timedelta(days=1)) in open_calendar_days.get(dev, set()):
            d1_cal_hits += 1

    n_pooled = len(pooled_devs)
    strict_rate = round(strict_hits / n_pooled, 4) if n_pooled else 0.0
    all_rate = round(all_hits / n_pooled, 4) if n_pooled else 0.0
    d1_24_48_rate = round(d1_24_48h_hits / n_pooled, 4) if n_pooled else 0.0
    d1_cal_rate = round(d1_cal_hits / n_pooled, 4) if n_pooled else 0.0

    # Also measure recent 14d D1 (t0 in [now - 16d, now - 2d)) for fresh signal
    d1_recent_start = now - timedelta(days=16)
    d1_recent_end = now - timedelta(days=2)
    recent_devs = [dev for dev, t0 in devices_t0.items() if d1_recent_start <= t0 < d1_recent_end]
    recent_d1_cal = sum(
        1 for dev in recent_devs if (devices_t0[dev].date() + timedelta(days=1)) in open_calendar_days.get(dev, set())
    )
    recent_d1_24_48 = sum(
        1
        for dev in recent_devs
        if any(
            (devices_t0[dev] + timedelta(hours=24)) <= ts < (devices_t0[dev] + timedelta(hours=48))
            for ts in open_timestamps.get(dev, ())
        )
    )

    # Weekly cohorts (6 rolling 7-day signup buckets ending at `now`)
    weekly_breakdown = []
    for k in range(6):
        w_end = now - timedelta(days=7 * k)
        w_start = w_end - timedelta(days=7)
        devs = [dev for dev, t0 in devices_t0.items() if w_start <= t0 < w_end]
        matured = w_end <= pool_end
        s_hit = sum(
            1
            for dev in devs
            if any(devices_t0[dev] <= ts < devices_t0[dev] + timedelta(days=7) for _, ts in strict_events.get(dev, ()))
        )
        a_hit = sum(
            1
            for dev in devs
            if any(
                devices_t0[dev] <= ts < devices_t0[dev] + timedelta(days=7)
                for _, ts in (strict_events.get(dev, []) + extra_events.get(dev, []))
            )
        )
        weekly_breakdown.append({
            "start": w_start.date().isoformat(),
            "end": w_end.date().isoformat(),
            "matured": matured,
            "new_families": len(devs),
            "strict_d7_hits": s_hit,
            "strict_d7_rate": round(s_hit / len(devs), 4) if devs else None,
            "all_d7_hits": a_hit,
            "all_d7_rate": round(a_hit / len(devs), 4) if devs else None,
        })

    passed = (n_pooled >= 150) and (strict_rate >= 0.12)
    return {
        "passed": passed,
        "window_start": pool_start.date().isoformat(),
        "window_end": pool_end.date().isoformat(),
        "eligible_families_4w": n_pooled,
        "min_required_families": 150,
        "target_rate": 0.12,
        "strict_d7_hits_4w": strict_hits,
        "strict_d7_rate_4w": strict_rate,
        "strict_hits_by_kind_4w": dict(strict_by_kind),
        "all_actions_d7_hits_4w": all_hits,
        "all_actions_d7_rate_4w": all_rate,
        "d1_return_4w_calendar_next_day": {
            "hits": d1_cal_hits,
            "eligible": n_pooled,
            "rate": d1_cal_rate,
        },
        "d1_return_4w_24_48h": {
            "hits": d1_24_48h_hits,
            "eligible": n_pooled,
            "rate": d1_24_48_rate,
        },
        "d1_return_recent_14d": {
            "eligible": len(recent_devs),
            "calendar_next_day_hits": recent_d1_cal,
            "calendar_next_day_rate": round(recent_d1_cal / len(recent_devs), 4) if recent_devs else None,
            "window_24_48h_hits": recent_d1_24_48,
            "window_24_48h_rate": round(recent_d1_24_48 / len(recent_devs), 4) if recent_devs else None,
        },
        "weekly_cohorts": weekly_breakdown,
    }


def evaluate_gate3_identity_lock(
    conn: sqlite3.Connection,
    env: dict[str, str] | None = None,
    days: int = 14,
    min_build: int = 122,
) -> dict[str, Any]:
    """Check restore-key coverage (>=85%), SESSION_MINT_ENFORCE, and token posture."""
    env_map = env if env is not None else os.environ
    session_mint_enforce = _is_truthy(env_map.get("SESSION_MINT_ENFORCE"))
    identity_cross_device = _is_truthy(env_map.get("IDENTITY_CROSS_DEVICE"))

    bm = _load_bare_mint_module()
    if bm is not None:
        mint_report = bm.report(conn, days=days, min_build=min_build)
    else:
        mint_report = {"error": "bare_mint_readiness module not found"}

    tables = table_names(conn)
    unexpired_by_kind: dict[str, int] = {}
    active_pre_v37_devices = 0
    active_bare_devices = 0
    identity_links_total = 0
    identity_links_confirmed = 0

    if "api_tokens" in tables:
        at_cols = _columns(conn, "api_tokens")
        kind_expr = "COALESCE(mint_kind, 'pre-v37')" if "mint_kind" in at_cols else "'pre-v37'"
        rows = conn.execute(
            f"""
            SELECT {kind_expr} AS kind, COUNT(*)
            FROM api_tokens
            WHERE expires_at IS NULL OR datetime(expires_at) > datetime('now')
            GROUP BY kind
            """
        ).fetchall()
        unexpired_by_kind = {k: n for k, n in rows}

        if "push_tokens" in tables and "mint_kind" in at_cols:
            window = f"-{int(days)} days"
            active_pre_v37_devices = conn.execute(
                """
                SELECT COUNT(DISTINCT p.device_id)
                FROM push_tokens p
                JOIN api_tokens t ON t.device_id = p.device_id
                WHERE p.updated_at >= datetime('now', ?)
                  AND (t.expires_at IS NULL OR datetime(t.expires_at) > datetime('now'))
                  AND t.mint_kind IS NULL
                """,
                (window,),
            ).fetchone()[0]
            active_bare_devices = conn.execute(
                """
                SELECT COUNT(DISTINCT p.device_id)
                FROM push_tokens p
                JOIN api_tokens t ON t.device_id = p.device_id
                WHERE p.updated_at >= datetime('now', ?)
                  AND (t.expires_at IS NULL OR datetime(t.expires_at) > datetime('now'))
                  AND t.mint_kind = 'bare'
                """,
                (window,),
            ).fetchone()[0]

    if "identity_links" in tables:
        il_cols = _columns(conn, "identity_links")
        identity_links_total = conn.execute("SELECT COUNT(*) FROM identity_links").fetchone()[0]
        if "confirmed" in il_cols:
            identity_links_confirmed = conn.execute(
                "SELECT COUNT(*) FROM identity_links WHERE confirmed = 1"
            ).fetchone()[0]

    share = mint_report.get("restore_key_share")
    passed = (share is not None and share >= 0.85) and session_mint_enforce

    return {
        "passed": passed,
        "target_restore_key_share": 0.85,
        "active_devices_14d": mint_report.get("active_devices", 0),
        "active_on_min_build": mint_report.get("active_on_min_build"),
        "active_with_restore_key": mint_report.get("active_with_restore_key"),
        "restore_key_share": share,
        "restore_keys_total": mint_report.get("restore_keys_total"),
        "session_mint_enforce": session_mint_enforce,
        "identity_cross_device": identity_cross_device,
        "security_posture_mismatch": bool(identity_cross_device and not session_mint_enforce),
        "unexpired_tokens_by_kind": unexpired_by_kind,
        "active_14d_devices_with_unexpired_pre_v37_token": active_pre_v37_devices,
        "active_14d_devices_with_unexpired_bare_token": active_bare_devices,
        "identity_links_total": identity_links_total,
        "identity_links_confirmed": identity_links_confirmed,
        "mints_per_day": mint_report.get("mints_per_day", {}),
    }


def evaluate_gate4_catalog(features_md_path: Path | None = None) -> dict[str, Any]:
    """Parse docs/catalog/FEATURES.md and return any capabilities marked ⚠️."""
    path = features_md_path or (_ROOT / "docs" / "catalog" / "FEATURES.md")
    if not path.is_file():
        return {"passed": False, "error": f"FEATURES.md not found at {path}"}

    total_rows = 0
    unconsumed: list[dict[str, str]] = []
    status_counts: Counter[str] = Counter()

    for line in path.read_text(encoding="utf-8").splitlines():
        m = _CATALOG_ROW_RE.match(line.strip())
        if not m:
            continue
        cap_id = m.group(1)
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 4:
            continue
        name = cells[1]
        status = cells[-1]
        total_rows += 1
        for marker in ("✅", "🟡", "⚠️", "❓"):
            if marker in status:
                status_counts[marker] += 1
        if "⚠️" in status:
            unconsumed.append({"id": cap_id, "name": name, "status": status})

    return {
        "passed": len(unconsumed) == 0,
        "total_catalog_rows": total_rows,
        "status_counts": dict(status_counts),
        "unconsumed_count": len(unconsumed),
        "unconsumed_ids": [item["id"] for item in unconsumed],
        "unconsumed": unconsumed,
    }


def run_all_gates(
    db_path: Path,
    features_md: Path | None = None,
    skip_catalog: bool = False,
    now: datetime | None = None,
    env: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Run all four 2.0.0 gates read-only and return structured results."""
    if not db_path.is_file():
        raise FileNotFoundError(f"Database not found: {db_path}")

    conn = sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
    try:
        gate1 = evaluate_gate1_headlines(conn, root=_ROOT, env=env)
        gate2 = evaluate_gate2_d7_actions(conn, now=now)
        gate3 = evaluate_gate3_identity_lock(conn, env=env)
    finally:
        conn.close()

    if skip_catalog:
        gate4: dict[str, Any] = {"passed": None, "skipped": True}
    else:
        gate4 = evaluate_gate4_catalog(features_md)

    evaluated_bools = [gate1["passed"], gate2["passed"], gate3["passed"]]
    if not skip_catalog:
        evaluated_bools.append(bool(gate4["passed"]))

    return {
        "evaluated_at_utc": (now or _utcnow()).isoformat() + "Z",
        "ready_for_v2_0_0": all(evaluated_bools) and not skip_catalog,
        "gates": {
            "gate1_headlines": gate1,
            "gate2_d7_action": gate2,
            "gate3_identity_lock": gate3,
            "gate4_zero_unconsumed": gate4,
        },
    }


def _print_human(report: dict[str, Any]) -> None:
    g = report["gates"]
    g1 = g["gate1_headlines"]
    g2 = g["gate2_d7_action"]
    g3 = g["gate3_identity_lock"]
    g4 = g["gate4_zero_unconsumed"]

    print(f"=== Almorabbi 2.0.0 Gate Check ({report['evaluated_at_utc']}) ===")
    print(f"OVERALL READY FOR 2.0.0: {'YES' if report['ready_for_v2_0_0'] else 'NO'}\n")

    print(f"[Gate 1] Headlines shipped: {'PASS' if g1['passed'] else 'FAIL'}")
    for k, v in g1["items"].items():
        print(f"  - {k}: {'YES' if v else 'NO'}")

    print(f"\n[Gate 2] First-week parenting action (D7 >= 12%, N >= 150): {'PASS' if g2['passed'] else 'FAIL'}")
    if "error" in g2:
        print(f"  error: {g2['error']}")
    else:
        print(
            f"  4w matured window {g2['window_start']} .. {g2['window_end']}: "
            f"N={g2['eligible_families_4w']} real families"
        )
        print(
            f"  Strict 5 sources: {g2['strict_d7_hits_4w']}/{g2['eligible_families_4w']} "
            f"({g2['strict_d7_rate_4w']:.1%}) | by kind: {g2['strict_hits_by_kind_4w']}"
        )
        print(
            f"  All ACTION_SOURCES: {g2['all_actions_d7_hits_4w']}/{g2['eligible_families_4w']} "
            f"({g2['all_actions_d7_rate_4w']:.1%})"
        )
        d1c = g2["d1_return_4w_calendar_next_day"]
        d1w = g2["d1_return_4w_24_48h"]
        print(
            f"  D1 (4w): calendar_next_day={d1c['hits']}/{d1c['eligible']} ({d1c['rate']:.1%}) | "
            f"24-48h={d1w['hits']}/{d1w['eligible']} ({d1w['rate']:.1%})"
        )

    print(f"\n[Gate 3] Identity lock (restore_key >= 85% + SESSION_MINT_ENFORCE): {'PASS' if g3['passed'] else 'FAIL'}")
    share_str = f"{g3['restore_key_share']:.1%}" if g3["restore_key_share"] is not None else "n/a"
    print(
        f"  active_14d={g3['active_devices_14d']}, with_restore_key={g3['active_with_restore_key']} ({share_str}), "
        f"SESSION_MINT_ENFORCE={g3['session_mint_enforce']}, IDENTITY_CROSS_DEVICE={g3['identity_cross_device']}"
    )
    print(
        f"  unexpired tokens={g3['unexpired_tokens_by_kind']}, "
        f"active_pre_v37_devices={g3['active_14d_devices_with_unexpired_pre_v37_token']}, "
        f"identity_links={g3['identity_links_total']} (confirmed={g3['identity_links_confirmed']})"
    )

    if g4.get("skipped"):
        print("\n[Gate 4] Catalog unconsumed items: SKIPPED (--skip-catalog)")
    else:
        print(f"\n[Gate 4] Zero unconsumed capabilities in FEATURES.md: {'PASS' if g4['passed'] else 'FAIL'}")
        print(f"  total={g4.get('total_catalog_rows')}, unconsumed={g4.get('unconsumed_count')} {g4.get('unconsumed_ids')}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Evaluate 2.0.0 naming gates (read-only).")
    ap.add_argument(
        "--db",
        default=os.environ.get("CONVERSATIONS_DB", str(_ROOT / "ops" / "conversations.db")),
        help="Path to conversations.db",
    )
    ap.add_argument(
        "--features-md",
        default=str(_ROOT / "docs" / "catalog" / "FEATURES.md"),
        help="Path to docs/catalog/FEATURES.md",
    )
    ap.add_argument("--skip-catalog", action="store_true", help="Skip Gate 4 FEATURES.md check")
    ap.add_argument("--json", action="store_true", help="Emit JSON output")
    args = ap.parse_args(argv)

    try:
        report = run_all_gates(
            Path(args.db),
            features_md=Path(args.features_md),
            skip_catalog=args.skip_catalog,
        )
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        _print_human(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
