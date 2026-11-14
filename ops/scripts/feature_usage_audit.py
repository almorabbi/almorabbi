#!/usr/bin/env python3
"""30-day feature usage & schema health audit (read-only, zero PII).

Audits every server-observable capability across `conversations.db` and
`sessions.db` to feed the 2.0.0 "keep / merge / hide" simplification table,
verifies whether family tables exist yet, measures `birth_month` vs static
`age_group` drift, checks live `cloud_budget` ledger state, and computes the
live `story_experiment` verdict.

Never prints device IDs, child names, emails, or question text.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict, is_dataclass
from datetime import date, datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
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

from app.core.real_traffic import e2e_devices, real_device_sql, real_session_sql, table_names  # noqa: E402
from app.services import programs_common, story_experiment  # noqa: E402

_MIN_QUESTION_CHARS = 12
_TIP_PREFIX = "بخصوص نصيحة اليوم"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _normalize_text(text: str | None) -> str:
    t = re.sub(r"[ـً-ْ]", "", text or "")
    return " ".join(t.split()).strip()


def _load_suggested_questions() -> set[str]:
    arb_path = _ROOT / "mobile" / "lib" / "l10n" / "app_ar.arb"
    if not arb_path.is_file():
        return set()
    try:
        data = json.loads(arb_path.read_text(encoding="utf-8"))
        return {
            _normalize_text(v)
            for k, v in data.items()
            if k.startswith("chatQ") and isinstance(v, str)
        }
    except Exception:
        return set()


def _connect_ro(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
    conn.row_factory = sqlite3.Row
    return conn


def _cols(conn: sqlite3.Connection, table: str) -> set[str]:
    return {r[1] for r in conn.execute(f'PRAGMA table_info("{table}")')}


def _count_window(
    conn: sqlite3.Connection,
    tables: set[str],
    table: str,
    *,
    ts_col: str | None = "created_at",
    cutoff_str: str,
    real_sql: str | None = None,
    has_device_id: bool = True,
    extra_where: str = "",
) -> dict[str, Any]:
    if table not in tables:
        return {"exists": False}
    cols = _cols(conn, table)
    where_all = ["1=1"]
    if real_sql:
        where_all.append(real_sql)
    if extra_where:
        where_all.append(extra_where)
    all_pred = " AND ".join(where_all)

    dev_expr = "COUNT(DISTINCT device_id)" if (has_device_id and "device_id" in cols) else "NULL"
    total_rows, total_devs = conn.execute(
        f'SELECT COUNT(*), {dev_expr} FROM "{table}" WHERE {all_pred}'
    ).fetchone()

    out: dict[str, Any] = {
        "exists": True,
        "all_time_rows": int(total_rows),
        "all_time_devices": int(total_devs) if total_devs is not None else None,
    }
    if ts_col and ts_col in cols:
        r30, d30 = conn.execute(
            f'SELECT COUNT(*), {dev_expr} FROM "{table}" '
            f'WHERE {all_pred} AND {ts_col} IS NOT NULL AND datetime({ts_col}) >= ?',
            (cutoff_str,),
        ).fetchone()
        out["window_rows"] = int(r30)
        out["window_devices"] = int(d30) if d30 is not None else None
    return out


def _serialize(obj: Any) -> Any:
    if is_dataclass(obj) and not isinstance(obj, type):
        return _serialize(asdict(obj))
    if isinstance(obj, dict):
        return {str(k): _serialize(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_serialize(v) for v in obj]
    return obj


def _audit_child_age_drift(
    conn: sqlite3.Connection,
    real_dev: str,
    today: date,
) -> dict[str, Any]:
    cols = _cols(conn, "child_profiles")
    has_bm = "birth_month" in cols
    rows = conn.execute(
        f"SELECT age_group, {'birth_month' if has_bm else 'NULL AS birth_month'} "
        f"FROM child_profiles WHERE {real_dev}"
    ).fetchall()
    total = len(rows)
    with_bm = 0
    mismatched = 0
    transitions: Counter[str] = Counter()
    band_counts: Counter[str] = Counter()

    for r in rows:
        static_band = (r[0] or "").strip()
        band_counts[static_band or "empty"] += 1
        bm = r[1]
        if not bm:
            continue
        months = programs_common.age_in_months(bm, today)
        if months is None:
            continue
        with_bm += 1
        computed = programs_common.band_for_age_months(months)
        # Legacy '0-3' maps naturally to 'prenatal-1' or '2-3', but any gap
        # where static != computed means static RAG/path filters disagree with programs!
        if static_band != computed:
            mismatched += 1
            transitions[f"{static_band} -> {computed}"] += 1

    return {
        "total_real_children": total,
        "with_birth_month": with_bm,
        "with_birth_month_share": round(with_bm / total, 4) if total else 0.0,
        "static_age_band_mismatches": mismatched,
        "mismatch_share_of_dated_children": round(mismatched / with_bm, 4) if with_bm else 0.0,
        "mismatch_transitions": dict(transitions.most_common(12)),
        "static_band_distribution": dict(band_counts),
    }


def _audit_conversations(
    conn: sqlite3.Connection,
    days: int,
    now: datetime,
) -> dict[str, Any]:
    tables = table_names(conn)
    e2e = e2e_devices(conn)
    real_dev = real_device_sql("device_id", e2e)
    real_sess = real_session_sql("session_id", e2e, tables)
    cutoff_str = (now - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
    cutoff_date = (now - timedelta(days=days)).date().isoformat()
    suggested = _load_suggested_questions()
    norm_tip_prefix = _normalize_text(_TIP_PREFIX)

    out: dict[str, Any] = {"days": days}

    # Population baseline
    pop: dict[str, Any] = {}
    if "child_profiles" in tables:
        pop["total_real_devices_with_child"] = conn.execute(
            f"SELECT COUNT(DISTINCT device_id) FROM child_profiles WHERE {real_dev}"
        ).fetchone()[0]
        pop["new_families_in_window"] = conn.execute(
            f"""
            SELECT COUNT(*) FROM (
                SELECT device_id, MIN(datetime(created_at)) AS first_created
                FROM child_profiles WHERE {real_dev}
                GROUP BY device_id
                HAVING MIN(datetime(created_at)) >= ?
            )
            """,
            (cutoff_str,),
        ).fetchone()[0]
        pop["child_age_audit"] = _audit_child_age_drift(conn, real_dev, now.date())

    if "push_tokens" in tables:
        for w in (14, days):
            w_str = (now - timedelta(days=w)).strftime("%Y-%m-%d %H:%M:%S")
            pop[f"active_push_devices_{w}d"] = conn.execute(
                f"SELECT COUNT(DISTINCT device_id) FROM push_tokens "
                f"WHERE datetime(updated_at) >= ? AND {real_dev}",
                (w_str,),
            ).fetchone()[0]
    out["population"] = pop

    # Section A: Assistant
    sec_a: dict[str, Any] = {
        "A3_chat_sessions": _count_window(
            conn, tables, "chat_sessions", cutoff_str=cutoff_str, real_sql=real_dev
        ),
    }
    if {"chat_messages", "chat_sessions"} <= tables:
        real_cs = real_device_sql("cs.device_id", e2e)
        msg_rows = conn.execute(
            f"""
            SELECT cs.device_id, cm.content
            FROM chat_messages cm
            JOIN chat_sessions cs ON cs.id = cm.session_id
            WHERE cm.role = 'user'
              AND datetime(cm.created_at) >= ?
              AND {real_cs}
            """,
            (cutoff_str,),
        ).fetchall()
        genuine_msgs = 0
        genuine_devs = set()
        all_user_devs = set()
        for dev, content in msg_rows:
            if dev:
                all_user_devs.add(dev)
            norm = _normalize_text(content)
            if (
                len(norm) >= _MIN_QUESTION_CHARS
                and norm not in suggested
                and not norm.startswith(norm_tip_prefix)
            ):
                genuine_msgs += 1
                if dev:
                    genuine_devs.add(dev)
        sec_a["A1_chat_questions_window"] = {
            "all_user_rows": len(msg_rows),
            "all_user_devices": len(all_user_devs),
            "genuine_rows": genuine_msgs,
            "genuine_devices": len(genuine_devs),
        }

    if "user_feedback" in tables:
        uf_cols = _cols(conn, "user_feedback")
        has_ts = "created_at" in uf_cols
        fb_rows = conn.execute(
            f"SELECT rating, COUNT(*) FROM user_feedback WHERE {real_sess} GROUP BY rating"
        ).fetchall()
        fb_w = (
            conn.execute(
                f"SELECT rating, COUNT(*) FROM user_feedback "
                f"WHERE {real_sess} AND datetime(created_at) >= ? GROUP BY rating",
                (cutoff_str,),
            ).fetchall()
            if has_ts
            else []
        )
        sec_a["A25_user_feedback"] = {
            "all_time_by_rating": {str(r[0]): int(r[1]) for r in fb_rows},
            "window_by_rating": {str(r[0]): int(r[1]) for r in fb_w},
        }
    out["section_a_conversations"] = sec_a

    # Section B: Curriculum & Stories
    sec_b: dict[str, Any] = {}
    if "lesson_progress" in tables:
        sec_b["B3_B12_lesson_started"] = _count_window(
            conn, tables, "lesson_progress", ts_col="started_at", cutoff_str=cutoff_str, real_sql=real_dev
        )
        sec_b["B3_B12_lesson_completed"] = _count_window(
            conn, tables, "lesson_progress", ts_col="completed_at", cutoff_str=cutoff_str,
            real_sql=real_dev, extra_where="status = 'completed'"
        )
    if "coach_tips" in tables:
        ct_cols = _cols(conn, "coach_tips")
        sec_b["B18_coach_tips_fetched"] = {
            "window_rows": conn.execute(
                f"SELECT COUNT(*) FROM coach_tips WHERE date >= ? AND {real_dev}", (cutoff_date,)
            ).fetchone()[0],
            "window_devices": conn.execute(
                f"SELECT COUNT(DISTINCT device_id) FROM coach_tips WHERE date >= ? AND {real_dev}",
                (cutoff_date,),
            ).fetchone()[0],
            "window_tapped_rows": (
                conn.execute(
                    f"SELECT COUNT(*) FROM coach_tips WHERE date >= ? AND tapped_at IS NOT NULL AND {real_dev}",
                    (cutoff_date,),
                ).fetchone()[0]
                if "tapped_at" in ct_cols
                else None
            ),
            "window_tapped_devices": (
                conn.execute(
                    f"SELECT COUNT(DISTINCT device_id) FROM coach_tips WHERE date >= ? AND tapped_at IS NOT NULL AND {real_dev}",
                    (cutoff_date,),
                ).fetchone()[0]
                if "tapped_at" in ct_cols
                else None
            ),
        }
    sec_b["B19_child_challenges"] = _count_window(
        conn, tables, "child_challenges", ts_col="started_at", cutoff_str=cutoff_str, real_sql=real_dev
    )
    if "story_events" in tables:
        sec_b["B24_story_events"] = _count_window(
            conn, tables, "story_events", ts_col="created_at", cutoff_str=cutoff_str, real_sql=real_dev
        )
        se_rows = [
            dict(r)
            for r in conn.execute(
                f"SELECT * FROM story_events WHERE datetime(created_at) >= ? AND {real_dev}",
                (cutoff_str,),
            ).fetchall()
        ]
        try:
            verdict_raw = story_experiment.verdict(se_rows)
            sec_b["B24_story_motion_verdict_window"] = _serialize(verdict_raw)
        except Exception as exc:  # noqa: BLE001
            sec_b["B24_story_motion_verdict_window"] = {"error": str(exc)}
    if "story_cache" in tables:
        sc_cols = _cols(conn, "story_cache")
        total_sc = conn.execute("SELECT COUNT(*) FROM story_cache").fetchone()[0]
        served_sum = (
            conn.execute("SELECT COALESCE(SUM(served_count), 0) FROM story_cache").fetchone()[0]
            if "served_count" in sc_cols
            else None
        )
        sec_b["B27_story_cache"] = {"total_stories": total_sc, "total_served_count": served_sum}
    out["section_b_conversations"] = sec_b

    # Section C: Children & Child Surface
    sec_c: dict[str, Any] = {}
    if {"routine_events", "child_daily_routines"} <= tables:
        real_cdr = real_device_sql("cdr.device_id", e2e)
        r_all, d_all = conn.execute(
            f"SELECT COUNT(*), COUNT(DISTINCT cdr.device_id) FROM routine_events re "
            f"JOIN child_daily_routines cdr ON cdr.id = re.routine_id WHERE {real_cdr}"
        ).fetchone()
        r_win, d_win = conn.execute(
            f"SELECT COUNT(*), COUNT(DISTINCT cdr.device_id) FROM routine_events re "
            f"JOIN child_daily_routines cdr ON cdr.id = re.routine_id "
            f"WHERE {real_cdr} AND datetime(re.created_at) >= ?",
            (cutoff_str,),
        ).fetchone()
        sec_c["C4_routine_events"] = {
            "all_time_rows": int(r_all), "all_time_devices": int(d_all),
            "window_rows": int(r_win), "window_devices": int(d_win),
        }
    sec_c["C5_habits_all"] = _count_window(
        conn, tables, "habits_value_events", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_c["C5_habits_non_worship"] = _count_window(
        conn, tables, "habits_value_events", cutoff_str=cutoff_str, real_sql=real_dev,
        extra_where="category IS NOT 'worship'"
    )
    sec_c["C5_habit_templates"] = _count_window(
        conn, tables, "habit_templates", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_c["C6_C7_child_screen_sessions"] = _count_window(
        conn, tables, "child_screen_sessions", ts_col="started_at", cutoff_str=cutoff_str, real_sql=real_dev
    )
    if "child_screen_sessions" in tables:
        sec_c["C6_C7_child_screen_sessions"]["window_counted_seconds"] = conn.execute(
            f"SELECT COALESCE(SUM(counted_seconds), 0) FROM child_screen_sessions "
            f"WHERE datetime(started_at) >= ? AND {real_dev}",
            (cutoff_str,),
        ).fetchone()[0]

    if "child_missions" in tables:
        cm_cols = _cols(conn, "child_missions")
        src_expr = "COALESCE(source, 'bank')" if "source" in cm_cols else "'bank'"
        by_src_all = conn.execute(
            f"SELECT {src_expr} AS src, status, COUNT(*), COUNT(DISTINCT device_id) "
            f"FROM child_missions WHERE {real_dev} GROUP BY src, status"
        ).fetchall()
        by_src_win = conn.execute(
            f"SELECT {src_expr} AS src, status, COUNT(*), COUNT(DISTINCT device_id) "
            f"FROM child_missions WHERE {real_dev} AND datetime(assigned_at) >= ? GROUP BY src, status",
            (cutoff_str,),
        ).fetchall()
        sec_c["C11_C12_C20_child_missions"] = {
            "all_time": [
                {"source": r[0], "status": r[1], "rows": int(r[2]), "devices": int(r[3])}
                for r in by_src_all
            ],
            "window": [
                {"source": r[0], "status": r[1], "rows": int(r[2]), "devices": int(r[3])}
                for r in by_src_win
            ],
        }
    sec_c["C14_family_agreements"] = _count_window(
        conn, tables, "family_agreements", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_c["C14_agreement_clauses"] = _count_window(
        conn, tables, "agreement_clauses", ts_col=None, cutoff_str=cutoff_str, has_device_id=False
    )
    sec_c["C15_child_licences"] = _count_window(
        conn, tables, "child_licences", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_c["C15_child_scenario_answers"] = _count_window(
        conn, tables, "child_scenario_answers", ts_col="answered_at", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_c["C16_child_web_claims"] = _count_window(
        conn, tables, "child_web_claims", ts_col=None, cutoff_str=cutoff_str, real_sql=real_dev
    )
    out["section_c_conversations"] = sec_c

    # Section D: Programs & Companion
    sec_d: dict[str, Any] = {}
    if "followups" in tables:
        f_cols = _cols(conn, "followups")
        src_expr = "COALESCE(source, 'chat')" if "source" in f_cols else "'chat'"
        f_all = conn.execute(
            f"SELECT {src_expr}, status, COUNT(*), COUNT(DISTINCT device_id) "
            f"FROM followups WHERE {real_dev} GROUP BY 1, 2"
        ).fetchall()
        f_win = conn.execute(
            f"SELECT {src_expr}, status, COUNT(*), COUNT(DISTINCT device_id) "
            f"FROM followups WHERE {real_dev} AND datetime(created_at) >= ? GROUP BY 1, 2",
            (cutoff_str,),
        ).fetchall()
        sec_d["D6_followups"] = {
            "all_time": [
                {"source": r[0], "status": r[1], "rows": int(r[2]), "devices": int(r[3])}
                for r in f_all
            ],
            "window": [
                {"source": r[0], "status": r[1], "rows": int(r[2]), "devices": int(r[3])}
                for r in f_win
            ],
        }
    sec_d["D7_weekly_plans"] = _count_window(
        conn, tables, "weekly_plans", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_d["D7_weekly_plan_marks"] = _count_window(
        conn, tables, "weekly_plan_marks", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_d["D8_child_facts"] = _count_window(
        conn, tables, "child_facts", cutoff_str=cutoff_str, real_sql=real_dev,
        extra_where="status = 'active'"
    )
    sec_d["D8_child_memory_settings"] = _count_window(
        conn, tables, "child_memory_settings", ts_col="updated_at", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_d["D9_ramadan_marks"] = _count_window(
        conn, tables, "ramadan_marks", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_d["D10_ramadan_fasting"] = _count_window(
        conn, tables, "ramadan_fasting", ts_col="updated_at", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_d["D11_prayer_journeys"] = _count_window(
        conn, tables, "prayer_journeys", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_d["D12_milestone_alerts"] = _count_window(
        conn, tables, "milestone_alerts", ts_col="claimed_at", cutoff_str=cutoff_str, real_sql=real_dev
    )
    sec_d["D_daily_login_streaks_dead"] = _count_window(
        conn, tables, "daily_login_streaks", cutoff_str=cutoff_str, real_sql=real_dev
    )
    out["section_d_conversations"] = sec_d

    # Section E & F
    sec_ef: dict[str, Any] = {
        "E1_referral_codes": _count_window(
            conn, tables, "referral_codes", cutoff_str=cutoff_str, real_sql=real_dev
        ),
        "E1_E3_referrals": _count_window(
            conn, tables, "referrals", cutoff_str=cutoff_str, real_sql=None, has_device_id=False
        ),
        "E3_referral_clicks": _count_window(
            conn, tables, "referral_clicks", ts_col="clicked_at", cutoff_str=cutoff_str, has_device_id=False
        ),
        "F3_identity_links": _count_window(
            conn, tables, "identity_links", ts_col="linked_at", cutoff_str=cutoff_str, real_sql=real_dev
        ),
        "F11_erased_devices": _count_window(
            conn, tables, "erased_devices", ts_col=None, cutoff_str=cutoff_str, has_device_id=False
        ),
        "F13_user_backups": _count_window(
            conn, tables, "user_backups", ts_col="updated_at", cutoff_str=cutoff_str, real_sql=real_dev
        ),
        "F14_donations": _count_window(
            conn, tables, "donations", cutoff_str=cutoff_str, has_device_id=False
        ),
        "F15_app_feedback": _count_window(
            conn, tables, "app_feedback", cutoff_str=cutoff_str, real_sql=real_dev
        ),
        "F15_feedback_replies": _count_window(
            conn, tables, "feedback_replies", cutoff_str=cutoff_str, real_sql=real_dev
        ),
        "F19_device_restore_keys": _count_window(
            conn, tables, "device_restore_keys", cutoff_str=cutoff_str, real_sql=real_dev
        ),
    }
    if "identity_links" in tables and "confirmed" in _cols(conn, "identity_links"):
        sec_ef["F3_identity_links"]["confirmed_rows"] = conn.execute(
            f"SELECT COUNT(*) FROM identity_links WHERE confirmed = 1 AND {real_dev}"
        ).fetchone()[0]
    if "device_restore_keys" in tables and "last_used_at" in _cols(conn, "device_restore_keys"):
        sec_ef["F19_device_restore_keys"]["used_rows"] = conn.execute(
            f"SELECT COUNT(*) FROM device_restore_keys WHERE last_used_at IS NOT NULL AND {real_dev}"
        ).fetchone()[0]
    out["section_ef_conversations"] = sec_ef

    # Schema inventory for Milestone 3 (Family Account)
    device_id_tables = []
    unique_child_or_device_indexes: dict[str, list[str]] = {}
    for tbl in sorted(tables):
        cols = _cols(conn, tbl)
        if "device_id" in cols:
            device_id_tables.append(tbl)
        idx_rows = conn.execute(f'PRAGMA index_list("{tbl}")').fetchall()
        u_list = []
        for idx in idx_rows:
            if idx[2]:  # unique
                idx_cols = [c[2] for c in conn.execute(f'PRAGMA index_info("{idx[1]}")').fetchall()]
                if any(c in ("device_id", "child_id") for c in idx_cols):
                    u_list.append(f"{idx[1]}({','.join(str(c) for c in idx_cols)})")
        if u_list:
            unique_child_or_device_indexes[tbl] = u_list

    out["schema_m3_readiness"] = {
        "has_families_table": "families" in tables,
        "has_family_members_table": "family_members" in tables,
        "total_tables_conversations_db": len(tables),
        "tables_with_device_id_count": len(device_id_tables),
        "tables_with_device_id": device_id_tables,
        "unique_indexes_on_device_or_child": unique_child_or_device_indexes,
    }
    return out


def _audit_sessions(
    conn: sqlite3.Connection,
    days: int,
    now: datetime,
) -> dict[str, Any]:
    tables = table_names(conn)
    cutoff_str = (now - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")

    out: dict[str, Any] = {
        "exists": True,
        "total_tables": len(tables),
        "A10_fiqh_intent_shadow_exists": "fiqh_intent_shadow" in tables,
        "A9_blocked_fiqh_log": _count_window(
            conn, tables, "blocked_fiqh_log", cutoff_str=cutoff_str, has_device_id=False
        ),
        "A18_answer_cache": _count_window(
            conn, tables, "answer_cache", cutoff_str=cutoff_str, has_device_id=False
        ),
        "B30_tafsir_cache": _count_window(
            conn, tables, "tafsir_cache", cutoff_str=cutoff_str, has_device_id=False
        ),
        "B36_bahouth_cache": _count_window(
            conn, tables, "bahouth_cache", cutoff_str=cutoff_str, has_device_id=False
        ),
        "llm_calls": _count_window(
            conn, tables, "llm_calls", ts_col="ts", cutoff_str=cutoff_str, has_device_id=False
        ),
        "sessions_logged": _count_window(
            conn, tables, "sessions", ts_col="ts", cutoff_str=cutoff_str, has_device_id=False
        ),
    }

    for tbl, key in (
        ("answer_cache", "A18_answer_cache"),
        ("tafsir_cache", "B30_tafsir_cache"),
        ("bahouth_cache", "B36_bahouth_cache"),
    ):
        if tbl in tables and "hit_count" in _cols(conn, tbl):
            out[key]["total_hit_count"] = conn.execute(
                f'SELECT COALESCE(SUM(hit_count), 0) FROM "{tbl}"'
            ).fetchone()[0]

    budget_tables = sorted(t for t in tables if t.startswith("cloud_budget_") or t == "llm_call_reservations")
    budget_info: dict[str, Any] = {
        "ledger_tables_present": budget_tables,
        "ledger_active": "cloud_budget_months" in tables,
    }
    if "cloud_budget_months" in tables:
        budget_info["cloud_budget_months_rows"] = conn.execute(
            "SELECT COUNT(*) FROM cloud_budget_months"
        ).fetchone()[0]
    if "cloud_budget_attempts" in tables:
        budget_info["cloud_budget_attempts_rows"] = conn.execute(
            "SELECT COUNT(*) FROM cloud_budget_attempts"
        ).fetchone()[0]
    out["A20_cloud_budget"] = budget_info
    return out


def run_audit(
    conversations_db: Path,
    sessions_db: Path | None = None,
    days: int = 30,
    now: datetime | None = None,
) -> dict[str, Any]:
    if not conversations_db.is_file():
        raise FileNotFoundError(f"conversations.db not found: {conversations_db}")
    now = now or _utcnow()

    conv_conn = _connect_ro(conversations_db)
    try:
        conv_data = _audit_conversations(conv_conn, days=days, now=now)
    finally:
        conv_conn.close()

    sess_path = sessions_db or Path(os.environ.get("SESSIONS_DB", str(conversations_db.parent / "sessions.db")))
    if sess_path.is_file():
        sess_conn = _connect_ro(sess_path)
        try:
            sess_data = _audit_sessions(sess_conn, days=days, now=now)
        finally:
            sess_conn.close()
    else:
        sess_data = {"exists": False}

    return {
        "audited_at_utc": now.isoformat() + "Z",
        "days": days,
        "conversations": conv_data,
        "sessions": sess_data,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="30-day feature usage audit (read-only).")
    ap.add_argument(
        "--conversations-db",
        default=os.environ.get("CONVERSATIONS_DB", str(_ROOT / "ops" / "conversations.db")),
        help="Path to conversations.db",
    )
    ap.add_argument(
        "--sessions-db",
        default=os.environ.get("SESSIONS_DB", ""),
        help="Path to sessions.db (defaults to sibling of conversations.db)",
    )
    ap.add_argument("--days", type=int, default=30, help="Lookback window in days")
    ap.add_argument("--json", action="store_true", help="Emit JSON output")
    args = ap.parse_args(argv)

    sess_arg = Path(args.sessions_db) if args.sessions_db else None
    try:
        report = run_audit(
            Path(args.conversations_db),
            sessions_db=sess_arg,
            days=args.days,
        )
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        pop = report["conversations"].get("population", {})
        print(f"=== Almorabbi {args.days}d Feature Usage Audit ({report['audited_at_utc']}) ===")
        print(
            f"Real families ever: {pop.get('total_real_devices_with_child')} | "
            f"New ({args.days}d): {pop.get('new_families_in_window')} | "
            f"Active push ({args.days}d): {pop.get(f'active_push_devices_{args.days}d')}"
        )
        print(f"Schema has families tables: {report['conversations']['schema_m3_readiness']['has_families_table']}")
        print(f"Tables with device_id: {report['conversations']['schema_m3_readiness']['tables_with_device_id_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
