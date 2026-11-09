"""Baseline security headers on every response.

Until 2026-11-09 tg-api.alsaba.cloud answered with no security header at all
(no X-Content-Type-Options, X-Frame-Options, Referrer-Policy or CSP); only the
pages that reach visitors through analytics_nginx on alsaba.cloud (/seo,
/methodology) carried the headers nginx adds there. The values below match
nginx's so a page served both ways gets one consistent answer.

The CSP is deliberately a baseline, not a script allow-list: it forbids
framing by another site, <base> hijacking, plugins and cross-site form posts —
none of which any page here uses — and says nothing about scripts or styles.
The landing, /ui/, child-mode web and the content pages carry inline scripts
and styles; a script-src policy needs nonces across all of them, a change of
its own. A header a route already set wins (setdefault).

Pure ASGI, not BaseHTTPMiddleware: the assistant streams its answers (SSE),
and wrapping `send` only touches the response start — the body passes through
untouched. Registered outermost, so the 401 from AuthMiddleware and the 429
from the rate limiter carry the headers too.
"""
from __future__ import annotations

HEADERS: dict[bytes, bytes] = {
    b"x-content-type-options": b"nosniff",
    b"x-frame-options": b"SAMEORIGIN",
    b"referrer-policy": b"strict-origin-when-cross-origin",
    b"strict-transport-security": b"max-age=31536000",
    b"permissions-policy": b"camera=(), microphone=(), geolocation=(), payment=()",
    b"content-security-policy": b"frame-ancestors 'self'; base-uri 'self'; object-src 'none'; form-action 'self'",
}


class SecurityHeadersMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message):
            if message["type"] == "http.response.start":
                headers = list(message.get("headers") or [])
                present = {k.lower() for k, _ in headers}
                headers += [(k, v) for k, v in HEADERS.items() if k not in present]
                message = {**message, "headers": headers}
            await send(message)

        await self.app(scope, receive, send_with_headers)
