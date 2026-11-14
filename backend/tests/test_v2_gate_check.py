"""Unit tests for ops/scripts/v2_gate_check.py (read-only, zero PII)."""
from __future__ import annotations

import importlib.util
import json
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "ops" / "scripts" / "v2_gate_check.py"


def _load_mod():
    spec = importlib.util.spec_from_file_location("v2_gate_check", SOURCE)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _create_base_schema(conn: sqlite3.Connection) -> None:
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
        CREATE TABLE chat_sessions (
            id TEXT PRIMARY KEY,
            device_id TEXT,
            created_at TEXT NOT NULL
        );
        CREATE TABLE chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE lesson_progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            child_id INTEGER NOT NULL,
            lesson_id TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at TEXT,
            updated_at TEXT,
            completed_at TEXT
        );
        CREATE TABLE habits_value_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            child_id INTEGER NOT NULL,
            category TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE child_missions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            child_id INTEGER NOT NULL,
            mission_key TEXT NOT NULL,
            status TEXT NOT NULL,
            source TEXT,
            assigned_at TEXT,
            claimed_at TEXT,
            confirmed_at TEXT
        );
        CREATE TABLE child_challenges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            child_id INTEGER NOT NULL,
            started_at TEXT NOT NULL
        );
        CREATE TABLE followups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            child_id INTEGER NOT NULL,
            answered_at TEXT,
            created_at TEXT NOT NULL
        );
        CREATE TABLE coach_tips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            child_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            created_at TEXT
        );
        CREATE TABLE push_tokens (
            device_id TEXT UNIQUE,
            token TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            build_number INTEGER
        );
        CREATE TABLE device_restore_keys (
            device_id TEXT PRIMARY KEY,
            key_hash TEXT NOT NULL
        );
        CREATE TABLE api_tokens (
            token TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            expires_at TEXT,
            created_at TEXT NOT NULL,
            mint_kind TEXT
        );
        CREATE TABLE identity_links (
            device_id TEXT PRIMARY KEY,
            google_id TEXT NOT NULL,
            confirmed INTEGER
        );
        """
    )


def test_gate2_cohort_window_exclusions_and_sample_floor(tmp_path: Path) -> None:
    mod = _load_mod()
    db_path = tmp_path / "conv.db"
    now = datetime(2026, 11, 14, 12, 0, 0)
    t20 = now - timedelta(days=20)

    with sqlite3.connect(db_path) as conn:
        _create_base_schema(conn)
        # 1. Genuine question inside [t0, t0+7d) -> hits strict + all + D1 calendar
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
            ("secret-dev-q", "Ahmad", "4-6", t20.strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO chat_sessions(id, device_id, created_at) VALUES (?, ?, ?)",
            ("s-q", "secret-dev-q", t20.strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO chat_messages(session_id, role, content, created_at) VALUES (?, ?, ?, ?)",
            ("s-q", "user", "ابني يرفض النوم مبكرًا كيف أتصرف معه؟", (t20 + timedelta(days=2)).strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO coach_tips(device_id, child_id, date, created_at) VALUES (?, ?, ?, ?)",
            ("secret-dev-q", 1, (t20.date() + timedelta(days=1)).isoformat(), (t20 + timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S")),
        )

        # 2. Canned suggestion + short greeting -> NOT genuine question
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
            ("secret-dev-canned", "Sara", "4-6", t20.strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO chat_sessions(id, device_id, created_at) VALUES (?, ?, ?)",
            ("s-c", "secret-dev-canned", t20.strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO chat_messages(session_id, role, content, created_at) VALUES (?, ?, ?, ?)",
            ("s-c", "user", "بخصوص نصيحة اليوم عن الصبر الطويل", (t20 + timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO chat_messages(session_id, role, content, created_at) VALUES (?, ?, ?, ?)",
            ("s-c", "user", "السلام", (t20 + timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S")),
        )

        # 3. Late lesson at day 8 -> outside 7d window
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
            ("secret-dev-late", "Omar", "7-9", t20.strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO lesson_progress(device_id, child_id, lesson_id, status, started_at) VALUES (?, ?, ?, ?, ?)",
            ("secret-dev-late", 3, "l1", "in_progress", (t20 + timedelta(days=8)).strftime("%Y-%m-%d %H:%M:%S")),
        )

        # 4. Followup-only -> counts in all_actions, NOT strict_5_sources
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
            ("secret-dev-fu", "Lina", "4-6", t20.strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO followups(device_id, child_id, answered_at, created_at) VALUES (?, ?, ?, ?)",
            ("secret-dev-fu", 4, (t20 + timedelta(days=3)).strftime("%Y-%m-%d %H:%M:%S"), t20.strftime("%Y-%m-%d %H:%M:%S")),
        )

        # 5. Excluded: young (<7d), old (>35d), E2E-Maestro, eval-harness-
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
            ("dev-young", "Y", "4-6", (now - timedelta(days=3)).strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
            ("dev-old", "O", "4-6", (now - timedelta(days=40)).strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
            ("dev-e2e", "E2E-Maestro", "4-6", t20.strftime("%Y-%m-%d %H:%M:%S")),
        )
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
            ("eval-harness-item1", "Eval", "4-6", t20.strftime("%Y-%m-%d %H:%M:%S")),
        )

    conn = sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        res = mod.evaluate_gate2_d7_actions(conn, now=now, suggested_questions=set())
    finally:
        conn.close()

    assert res["eligible_families_4w"] == 4
    assert res["strict_d7_hits_4w"] == 1
    assert res["strict_d7_rate_4w"] == 0.25
    assert res["all_actions_d7_hits_4w"] == 2
    assert res["d1_return_4w_calendar_next_day"]["hits"] == 1
    # Must fail when N < 150 even though rate is 25%
    assert res["passed"] is False


def test_gate2_passes_at_150_families_and_12_percent(tmp_path: Path) -> None:
    mod = _load_mod()
    db_path = tmp_path / "conv150.db"
    now = datetime(2026, 11, 14, 12, 0, 0)
    t15 = now - timedelta(days=15)

    with sqlite3.connect(db_path) as conn:
        _create_base_schema(conn)
        for i in range(150):
            dev = f"dev-{i:03d}"
            conn.execute(
                "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, ?)",
                (dev, "Child", "4-6", t15.strftime("%Y-%m-%d %H:%M:%S")),
            )
            if i < 18:
                conn.execute(
                    "INSERT INTO lesson_progress(device_id, child_id, lesson_id, status, started_at) VALUES (?, ?, ?, ?, ?)",
                    (dev, i + 1, "l1", "completed", (t15 + timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S")),
                )

    conn = sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        res = mod.evaluate_gate2_d7_actions(conn, now=now, suggested_questions=set())
    finally:
        conn.close()

    assert res["eligible_families_4w"] == 150
    assert res["strict_d7_hits_4w"] == 18
    assert res["strict_d7_rate_4w"] == 0.12
    assert res["passed"] is True


def test_gate3_identity_lock_and_security_mismatch(tmp_path: Path) -> None:
    mod = _load_mod()
    db_path = tmp_path / "id.db"
    with sqlite3.connect(db_path) as conn:
        _create_base_schema(conn)
        for i in range(20):
            dev = f"secret-d-{i}"
            conn.execute(
                "INSERT INTO push_tokens(device_id, token, updated_at, build_number) VALUES (?, ?, datetime('now'), ?)",
                (dev, f"tok-{i}", 126),
            )
            if i < 17:  # 17 / 20 = 85%
                conn.execute(
                    "INSERT INTO device_restore_keys(device_id, key_hash) VALUES (?, ?)",
                    (dev, f"h-{i}"),
                )
        conn.execute(
            "INSERT INTO api_tokens(token, device_id, session_id, expires_at, created_at, mint_kind) VALUES (?, ?, ?, datetime('now', '+5 days'), datetime('now'), NULL)",
            ("t-pre", "secret-d-0", "s0"),
        )
        conn.execute(
            "INSERT INTO api_tokens(token, device_id, session_id, expires_at, created_at, mint_kind) VALUES (?, ?, ?, datetime('now', '+5 days'), datetime('now'), 'bare')",
            ("t-bare", "secret-d-1", "s1"),
        )
        conn.execute(
            "INSERT INTO identity_links(device_id, google_id, confirmed) VALUES (?, ?, ?)",
            ("secret-d-0", "g0", 1),
        )

    conn = sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True)
    try:
        res_fail = mod.evaluate_gate3_identity_lock(
            conn,
            env={"SESSION_MINT_ENFORCE": "", "IDENTITY_CROSS_DEVICE": "1"},
        )
        assert res_fail["restore_key_share"] == 0.85
        assert res_fail["passed"] is False
        assert res_fail["security_posture_mismatch"] is True
        assert res_fail["unexpired_tokens_by_kind"] == {"pre-v37": 1, "bare": 1}
        assert res_fail["active_14d_devices_with_unexpired_pre_v37_token"] == 1
        assert res_fail["active_14d_devices_with_unexpired_bare_token"] == 1
        assert res_fail["identity_links_confirmed"] == 1

        res_pass = mod.evaluate_gate3_identity_lock(
            conn,
            env={"SESSION_MINT_ENFORCE": "1", "IDENTITY_CROSS_DEVICE": "1"},
        )
        assert res_pass["passed"] is True
        assert res_pass["security_posture_mismatch"] is False
    finally:
        conn.close()


def test_gate4_catalog_parser_synthetic_and_real(tmp_path: Path) -> None:
    mod = _load_mod()
    syn = tmp_path / "FEATURES.md"
    syn.write_text(
        "\n".join([
            "| # | القدرة | ما تفعل | أين | الحالة |",
            "|---|---|---|---|---|",
            "| A1 | سؤال | نص | هنا | ✅ |",
            "| B17 | ميت | نص | هنا | ⚠️ بلا عميل |",
        ]),
        encoding="utf-8",
    )
    r_syn = mod.evaluate_gate4_catalog(syn)
    assert r_syn["passed"] is False
    assert r_syn["unconsumed_ids"] == ["B17"]

    real_res = mod.evaluate_gate4_catalog(ROOT / "docs" / "catalog" / "FEATURES.md")
    assert real_res["passed"] is False
    assert real_res["unconsumed_ids"] == ["B17", "B20", "B37", "F13", "G18"]


def test_cli_is_read_only_and_hides_device_ids(tmp_path: Path, capsys) -> None:
    mod = _load_mod()
    db_path = tmp_path / "cli.db"
    with sqlite3.connect(db_path) as conn:
        _create_base_schema(conn)
        conn.execute(
            "INSERT INTO child_profiles(device_id, name, age_group, created_at) VALUES (?, ?, ?, datetime('now', '-10 days'))",
            ("ultra-secret-device-id-999", "SecretChild", "4-6"),
        )
    before = db_path.read_bytes()
    rc = mod.main(["--db", str(db_path), "--json"])
    assert rc == 0
    assert db_path.read_bytes() == before
    out = capsys.readouterr().out
    assert "ultra-secret-device-id-999" not in out
    assert "SecretChild" not in out
    parsed = json.loads(out)
    assert parsed["ready_for_v2_0_0"] is False
