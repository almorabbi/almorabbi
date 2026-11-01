"""bare_mint_readiness.py: counts only, read-only, never a device id."""
import importlib.util
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "ops/tools/bare_mint_readiness.py"


def utility():
    spec = importlib.util.spec_from_file_location("bare_mint_readiness", SOURCE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _db(path: Path) -> None:
    with sqlite3.connect(path) as c:
        c.executescript("""
            CREATE TABLE push_tokens (device_id TEXT UNIQUE, token TEXT, updated_at TEXT,
                                      build_number INTEGER);
            CREATE TABLE device_restore_keys (device_id TEXT PRIMARY KEY, key_hash TEXT);
            CREATE TABLE api_tokens (token TEXT, device_id TEXT, created_at TEXT,
                                     mint_kind TEXT);
            INSERT INTO push_tokens VALUES ('secret-dev-a', 't1', datetime('now'), 122);
            INSERT INTO push_tokens VALUES ('secret-dev-b', 't2', datetime('now'), 120);
            INSERT INTO push_tokens VALUES ('secret-dev-c', 't3', datetime('now', '-30 days'), 122);
            INSERT INTO device_restore_keys VALUES ('secret-dev-a', 'h');
            INSERT INTO api_tokens VALUES ('x', 'secret-dev-a', datetime('now'), 'bare');
            INSERT INTO api_tokens VALUES ('y', 'secret-dev-b', datetime('now'), NULL);
            INSERT INTO api_tokens VALUES ('z', 'secret-dev-b', datetime('now'), 'restore');
        """)


def test_counts_active_devices_keys_and_mints(tmp_path):
    p = tmp_path / "c.db"
    _db(p)
    conn = sqlite3.connect(p)
    r = utility().report(conn, days=14, min_build=122)
    conn.close()
    assert r["active_devices"] == 2
    assert r["active_on_min_build"] == 1
    assert r["active_with_restore_key"] == 1
    assert r["restore_key_share"] == 0.5
    (day,) = r["mints_per_day"]
    assert r["mints_per_day"][day] == {"bare": 1, "pre-v37": 1, "restore": 1}


def test_prints_no_device_id_and_opens_read_only(tmp_path, capsys):
    p = tmp_path / "c.db"
    _db(p)
    before = p.read_bytes()
    assert utility().main(["--db", str(p)]) == 0
    out = capsys.readouterr().out
    assert "secret-dev" not in out and "active devices" in out
    assert p.read_bytes() == before


def test_a_missing_database_is_an_error(tmp_path):
    assert utility().main(["--db", str(tmp_path / "none.db")]) == 2
