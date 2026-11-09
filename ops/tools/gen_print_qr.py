#!/usr/bin/env python3
"""
gen_print_qr — the QR code printed at the foot of every printable sheet.

Writes frontend/assets/print/qr_<CODE>.svg: flat dark modules on a white
quiet zone, one <path>, error correction M, no logo. The URL is the landing
page with the sheet's campaign code, never Play: /go records the scan
(referral_clicks → ops/scripts/campaign_report.py) and hands Play
`referrer=ref_<CODE>` with the PR prefix's utm (backend/app/services/
attribution.py). The URL is also written into the SVG's <title>, which
backend/tests/test_print_pack.py checks against ops/data/campaign_codes.md.

Needs the `qrcode` package (not a backend dependency — the SVGs are committed):
    python3 -m venv /tmp/qrvenv && /tmp/qrvenv/bin/pip install qrcode==8.0
    /tmp/qrvenv/bin/python ops/tools/gen_print_qr.py
"""
from __future__ import annotations

from pathlib import Path

import qrcode
from qrcode.constants import ERROR_CORRECT_M

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "frontend" / "assets" / "print"
BASE = "https://tg-api.alsaba.cloud/go?ref="
CODES = {"PR01": "Ramadan pack (Arabic)", "PR02": "Ramadan pack (English)"}
BORDER = 4


def svg(url: str) -> str:
    qr = qrcode.QRCode(error_correction=ERROR_CORRECT_M, border=BORDER, box_size=1)
    qr.add_data(url)
    qr.make(fit=True)
    m = qr.get_matrix()            # includes the quiet zone
    n = len(m)
    path = "".join(f"M{x} {y}h1v1h-1z" for y, row in enumerate(m) for x, dark in enumerate(row) if dark)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {n} {n}" shape-rendering="crispEdges">'
            f"<title>{url}</title>"
            f'<rect width="{n}" height="{n}" fill="#fff"/><path fill="#0F3D36" d="{path}"/></svg>\n')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for code in CODES:
        (OUT / f"qr_{code}.svg").write_text(svg(BASE + code), encoding="utf-8")
        print(f"qr_{code}.svg ← {BASE}{code}")


if __name__ == "__main__":
    main()
