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
