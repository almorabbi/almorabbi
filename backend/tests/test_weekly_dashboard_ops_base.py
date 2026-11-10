"""The weekly dashboard reads LLM metrics from the app it runs inside.

Through the public URL Cloudflare banned Python-urllib (403, error 1010) and
the Friday report showed «مقاييس LLM: ⚠️ HTTP Error 403» (2026-11-06).
"""
from ops.scripts import weekly_dashboard as wd


def test_default_base_is_the_local_app(monkeypatch):
    seen = {}

    class _Resp:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self):
            return b'{"ok": true}'

    def fake_urlopen(req, timeout=0):
        seen["url"] = req.full_url
        seen["token"] = req.headers.get("X-ops-token")
        return _Resp()

    monkeypatch.delenv("TG_API_BASE", raising=False)
    monkeypatch.setenv("TG_OPS_METRICS_TOKEN", "t0k")
    monkeypatch.setattr(wd.urllib.request, "urlopen", fake_urlopen)
    assert wd._fetch_ops_metrics() == {"ok": True}
    assert seen["url"] == "http://127.0.0.1:8000/api/stats/ops-llm"
    assert seen["token"] == "t0k"


def test_an_explicit_base_still_wins(monkeypatch):
    seen = {}

    def fake_urlopen(req, timeout=0):
        seen["url"] = req.full_url
        raise OSError("offline")

    monkeypatch.setenv("TG_API_BASE", "https://example.invalid")
    monkeypatch.setenv("TG_OPS_METRICS_TOKEN", "t0k")
    monkeypatch.setattr(wd.urllib.request, "urlopen", fake_urlopen)
    assert "error" in wd._fetch_ops_metrics()
    assert seen["url"].startswith("https://example.invalid/")


def test_hadith_guard_section_counts_the_week_from_the_session_log(tmp_path, monkeypatch):
    import sqlite3
    from datetime import datetime, timedelta, timezone



    db = tmp_path / "sessions.db"
    conn = sqlite3.connect(db)
    conn.execute("CREATE TABLE sessions (id TEXT PRIMARY KEY, ts TEXT, domain TEXT, behavior_type TEXT,"
                 " age_group TEXT, severity TEXT, mode TEXT, needs_human_review INTEGER,"
                 " reply_length INTEGER, retrieved_count INTEGER, flag TEXT)")
    now = datetime.now(timezone.utc)
    rows = [("a", now, "hadith_guard:fixed=1,removed=0"),
            ("b", now, "completed_after_disconnect,hadith_guard:fixed=0,removed=2"),
            ("c", now, ""),
            ("d", now - timedelta(days=9), "hadith_guard:fixed=5,removed=5")]
    for rid, ts, flag in rows:
        conn.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                     (rid, ts.isoformat(), "d", "", "", "", "llm_generated", 0, 10, 1, flag))
    conn.commit()
    conn.close()
    monkeypatch.setattr(wd, "_SESSIONS_DB", db)
    hg = wd._hadith_guard_stats()
    assert hg == {"turns": 3, "touched": 2, "fixed": 1, "removed": 2}
    lines = wd._hadith_lines(hg)
    assert "إجابات عدّلها الحارس: 2 من 3" in lines[1]
