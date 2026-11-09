"""Security headers on every response (app/middleware/security_headers.py).

tg-api.alsaba.cloud served the landing and the API with none until 2026-11-09.
"""
from __future__ import annotations

from fastapi.testclient import TestClient
from starlette.applications import Starlette
from starlette.responses import PlainTextResponse, StreamingResponse
from starlette.routing import Route

from app.main import app
from app.middleware.security_headers import HEADERS, SecurityHeadersMiddleware

_EXPECTED = {k.decode(): v.decode() for k, v in HEADERS.items()}


def _assert_headers(resp):
    for name, value in _EXPECTED.items():
        assert resp.headers.get(name) == value, (resp.request.url.path, name, resp.headers.get(name))


def test_the_landing_and_the_api_carry_them():
    c = TestClient(app)
    for path in ("/", "/go?lang=en", "/methodology", "/privacy-policy", "/health"):
        _assert_headers(c.get(path))


def test_responses_the_inner_layers_refuse_carry_them_too():
    # AuthMiddleware answers this itself, before any route — outermost wins.
    r = TestClient(app).get("/api/children")
    assert r.status_code == 401
    _assert_headers(r)


def _mini(route_app):
    return TestClient(SecurityHeadersMiddleware(Starlette(routes=[Route("/", route_app)])))


def test_a_streamed_answer_streams_untouched():
    async def chunks():
        for part in ("event: token\ndata: أ\n\n", "event: token\ndata: ب\n\n", "event: done\ndata: {}\n\n"):
            yield part

    async def sse(request):
        return StreamingResponse(chunks(), media_type="text/event-stream")

    r = _mini(sse).get("/")
    assert r.text == "event: token\ndata: أ\n\nevent: token\ndata: ب\n\nevent: done\ndata: {}\n\n"
    _assert_headers(r)


def test_a_header_the_route_set_is_kept_not_doubled():
    async def own(request):
        return PlainTextResponse("x", headers={"X-Frame-Options": "DENY"})

    r = _mini(own).get("/")
    assert r.headers.get_list("x-frame-options") == ["DENY"]
    assert r.headers["x-content-type-options"] == "nosniff"
