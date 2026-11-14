"""Unit tests for ops/scripts/feature_usage_audit.py (read-only, zero PII)."""
from __future__ import annotations

import importlib.util
import json
import sqlite3
from datetime import date, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "ops" / "scripts" / "feature_usage_audit.py"


def _load_mod():
    spec = importlib.util.spec_from_file_location("feature_usage_audit", SOURCE)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_audit_read_only_e2e_exclusion_and_missing_tables(tmp_path: Path, capsys) -> None:
    mod = _load_mod()
    conv_db = tmp_path / "conversations.db"
    with sqlite3.connect(conv_db) as conn:
        conn.executescript(
            """
            CREATE TABLE child_profiles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_id TEXT NOT NULL,
                name TEXT NOT NULL,
                age_group TEXT NOT NULL,
                birth_month TEXT,
                created_at TEXT NOT NULL
            );
            CREATE TABLE push_tokens (
                device_id TEXT UNIQUE,
                token TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE lesson_progress (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_id TEXT NOT NULL,
                child_id INTEGER NOT NULL,
                lesson_id TEXT NOT NULL,
                status TEXT NOT NULL,
                started_at TEXT,
                completed_at TEXT
            );
            INSERT INTO child_profiles(device_id, name, age_group, created_at)
            VALUES ('real-dev-secret-1', 'Zaid', '4-6', datetime('now', '-5 days'));
            INSERT INTO child_profiles(device_id, name, age_group, created_at)
            VALUES ('e2e-dev-1', 'E2E-Maestro', '4-6', datetime('now', '-5 days'));
            INSERT INTO child_profiles(device_id, name, age_group, created_at)
            VALUES ('eval-harness-dev-1', 'EvalChild', '4-6', datetime('now', '-5 days'));
            INSERT INTO lesson_progress(device_id, child_id, lesson_id, status, started_at, completed_at)
            VALUES ('real-dev-secret-1', 1, 'l1', 'completed', datetime('now', '-2 days'), datetime('now', '-2 days'));
            INSERT INTO lesson_progress(device_id, child_id, lesson_id, status, started_at, completed_at)
            VALUES ('e2e-dev-1', 2, 'l1', 'completed', datetime('now', '-2 days'), datetime('now', '-2 days'));
            """
        )

    before = conv_db.read_bytes()
    rc = mod.main(["--conversations-db", str(conv_db), "--days", "30", "--json"])
    assert rc == 0
    assert conv_db.read_bytes() == before

    raw_out = capsys.readouterr().out
    assert "real-dev-secret-1" not in raw_out
    assert "Zaid" not in raw_out

    data = json.loads(raw_out)
    assert data["sessions"]["exists"] is False
    pop = data["conversations"]["population"]
    assert pop["total_real_devices_with_child"] == 1
    assert data["conversations"]["section_b_conversations"]["B3_B12_lesson_completed"]["window_devices"] == 1
    assert data["conversations"]["section_d_conversations"]["D9_ramadan_marks"]["exists"] is False
    assert data["conversations"]["schema_m3_readiness"]["has_families_table"] is False
    assert data["conversations"]["schema_m3_readiness"]["tables_with_device_id_count"] == 3


def test_static_age_band_drift_detection(tmp_path: Path) -> None:
    mod = _load_mod()
    conv_db = tmp_path / "age.db"
    # Fix today = 2026-11-14:
    # 2021-06 -> 65 months (5 years) -> computed band '4-6'
    # 2018-01 -> 106 months (8 years) -> computed band '7-9'
    with sqlite3.connect(conv_db) as conn:
        conn.executescript(
            """
            CREATE TABLE child_profiles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_id TEXT NOT NULL,
                name TEXT NOT NULL,
                age_group TEXT NOT NULL,
                birth_month TEXT,
                created_at TEXT NOT NULL
            );
            INSERT INTO child_profiles(device_id, name, age_group, birth_month, created_at)
            VALUES ('d1', 'A', '2-3', '2021-06', '2025-01-01 00:00:00');
            INSERT INTO child_profiles(device_id, name, age_group, birth_month, created_at)
            VALUES ('d2', 'B', '4-6', '2021-06', '2026-01-01 00:00:00');
            INSERT INTO child_profiles(device_id, name, age_group, birth_month, created_at)
            VALUES ('d3', 'C', '7-9', NULL, '2026-01-01 00:00:00');
            """
        )

    res = mod.run_audit(conv_db, now=datetime(2026, 11, 14, 12, 0, 0))
    age = res["conversations"]["population"]["child_age_audit"]
    assert age["total_real_children"] == 3
    assert age["with_birth_month"] == 2
    assert age["static_age_band_mismatches"] == 1
    assert age["mismatch_transitions"] == {"2-3 -> 4-6": 1}


def test_sessions_db_ledger_and_caches(tmp_path: Path) -> None:
    mod = _load_mod()
    conv_db = tmp_path / "conversations.db"
    sess_db = tmp_path / "sessions.db"

    with sqlite3.connect(conv_db) as conn:
        conn.execute(
            "CREATE TABLE child_profiles (id INTEGER PRIMARY KEY, device_id TEXT, name TEXT, age_group TEXT, created_at TEXT)"
        )
    with sqlite3.connect(sess_db) as conn:
        conn.executescript(
            """
            CREATE TABLE answer_cache (id INTEGER PRIMARY KEY, created_at TEXT, hit_count INTEGER);
            CREATE TABLE tafsir_cache (id INTEGER PRIMARY KEY, created_at TEXT, hit_count INTEGER);
            CREATE TABLE bahouth_cache (id INTEGER PRIMARY KEY, created_at TEXT, hit_count INTEGER);
            CREATE TABLE cloud_budget_months (wallet TEXT, month TEXT);
            CREATE TABLE cloud_budget_attempts (id INTEGER PRIMARY KEY);
            CREATE TABLE llm_calls (id INTEGER PRIMARY KEY, ts TEXT);
            INSERT INTO answer_cache VALUES (1, datetime('now'), 5);
            INSERT INTO tafsir_cache VALUES (1, datetime('now'), 12);
            INSERT INTO cloud_budget_months VALUES ('deepseek', '2026-11');
            INSERT INTO llm_calls VALUES (1, datetime('now'));
            """
        )

    res = mod.run_audit(conv_db, sessions_db=sess_db, now=datetime(2026, 11, 14, 12, 0, 0))
    sess = res["sessions"]
    assert sess["exists"] is True
    assert sess["A10_fiqh_intent_shadow_exists"] is False
    assert sess["A18_answer_cache"]["total_hit_count"] == 5
    assert sess["B30_tafsir_cache"]["total_hit_count"] == 12
    assert sess["B36_bahouth_cache"]["all_time_rows"] == 0
    assert sess["A20_cloud_budget"]["ledger_active"] is True
    assert sess["A20_cloud_budget"]["cloud_budget_months_rows"] == 1
    assert sess["llm_calls"]["window_rows"] == 1
