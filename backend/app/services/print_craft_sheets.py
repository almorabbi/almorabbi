"""Render `/print/lantern-craft` — 3 artisan A4 Paper-Cut craft & fridge-map sheets.

Pure HTML + inline geometric SVG (no `<script>`, no external third-party URLs,
no `play.google.com` links so scanners go through `/go?ref=PR03` / `PR04`).
"""
from __future__ import annotations

from html import escape

_AR_DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
CRAFT_CODES = {"ar": "PR03", "en": "PR04"}

_COPY = {
    "ar": {
        "dir": "rtl",
        "brand": "المربّي",
        "prog": "عدّة رمضان الورقية",
        "title": "فانوس الورق والخريطة — المربّي",
        "intro": "٣ أوراق A4 للقصّ والتلوين وتعليق قناديل الأسرة الثلاثين بعيدًا عن الشاشات (نسخة ملوّنة وأخرى موفّرة للحبر).",
        "print": "اطبعوا العدّة",
        "ink_color": "ألوان نور والقناديل",
        "ink_bw": "توفير الحبر للتلوين",
        "other": "English",
        "sheet": "ورقة",
        "foot_t": "حمّلوا «المربّي» مجانًا",
        "foot_s": "بلا إعلانات ولا اشتراكات — امسحوا الرمز",
        "s1_t": "١) باترون فانوس المربّي ثلاثي الأبعاد (قصّ واطوِ وألصق)",
        "s1_sub": "قصّوا على الخط المتصل ✂، واطووا برفق على الخط المتقطّع، ثم ألصقوا الألسنة الأربعة ليلة الرؤية.",
        "s1_handle": "شريط المقبض العلوي — يُلصق في قمة السقف",
        "s1_steps": [
            "١. قصّ الخارجي المتصل ✂",
            "٢. اثنِ كل خط متقطّع إلى الداخل",
            "٣. ألصق الألسنة + ضَع ضوء بطارية آمنًا فقط (بلا لهب)",
        ],
        "s2_t": "٢) خريطة شارع القناديل الـ ٣٠ على باب الثلاجة",
        "s2_sub": "يلوّن الأطفال قنديلًا واحدًا كل ليلة مضت — بلا علامات خصم ولا مقارنة، فكل قنديل يضيء بركة.",
        "s2_names": "لأطفال أسرتنا: ________________________________________   رمضان: ١٤٤٨ هـ",
        "s2_p1": "العشر الأوائل",
        "s2_p2": "العشر الأواسط",
        "s2_p3": "العشر الأواخر (☾ بداية ليلة وترية)",
        "s3_t": "٣) بطاقات سفراء سفرة الإفطار وقصاصات الكلمات الطيبة",
        "s3_sub": "اقصص كل شارة وطوِها من الوسط لتقف أمام طبق الطفل وقت الإفطار، وقصّ قصاصات مرطبان الكلمات الطيبة.",
        "roles": [
            ("ساقي الماء والتمر", "أحضرُ التمر وأكواب الماء بأدب", "الاسم: ____________"),
            ("أمين البسملة والسفرة", "أرتّب السفرة وأذكّر بـ «بسم الله»", "الاسم: ____________"),
            ("حامل الدعاء والضيافة", "أجمع دعاء الأسرة قبل الأذان", "الاسم: ____________"),
            ("سفير الصدقة والإحسان", "أتابع صندوق العطاء وأبتسم لإخوتي", "الاسم: ____________"),
        ],
        "jar_head": "قصاصات مرطبان الكلمات الطيبة",
        "jar_note": "كلمة شكر أو دعوة جميلة من: ______________",
    },
    "en": {
        "dir": "ltr",
        "brand": "Al-Morabbi",
        "prog": "Ramadan Paper Craft Kit",
        "title": "3D Paper Lantern & Fridge Street — Al-Morabbi",
        "intro": "Three screen-free A4 craft sheets: a 3D paper-cut lantern net, the 30-lantern fridge street, and Iftar Ambassador cards.",
        "print": "Print the kit",
        "ink_color": "Noor Palette",
        "ink_bw": "Ink-Saver B&W",
        "other": "العربية",
        "sheet": "Sheet",
        "foot_t": "Get Al-Morabbi free",
        "foot_s": "No ads, no subscriptions — scan the code",
        "s1_t": "1) 3D Paper-Cut Lantern Pattern (Cut, Fold & Glue)",
        "s1_sub": "Cut along solid outlines ✂, fold gently on dashed lines, and glue the four side tabs together as a family craft.",
        "s1_handle": "Top carrying handle strip — glue across the lantern crown",
        "s1_steps": [
            "1. Cut solid lines ✂",
            "2. Crease dashed fold lines",
            "3. Glue tabs + place a safe battery LED tea-light only",
        ],
        "s2_t": "2) 30-Lantern Street Fridge Map",
        "s2_sub": "Children colour one lantern for each evening shared — zero red marks, zero guilt, every lantern shines.",
        "s2_names": "For our children: ____________________________________   Ramadan 1448",
        "s2_p1": "First Ten Nights",
        "s2_p2": "Middle Ten Nights",
        "s2_p3": "Last Ten Nights (☾ Odd-night evening)",
        "s3_t": "3) Iftar Table Ambassador Cards & Kind-Words Slips",
        "s3_sub": "Cut each card and fold in the middle to stand beside a child's plate, plus 8 slips for the family Kind-Words Jar.",
        "roles": [
            ("Water & Dates Steward", "I pass dates and water gently", "Name: ____________"),
            ("Bismillah & Table Guide", "I set cups neatly & remind Bismillah", "Name: ____________"),
            ("Dua & Welcome Host", "I invite family dua before Maghrib", "Name: ____________"),
            ("Charity & Kindness Lead", "I tend our charity box with a smile", "Name: ____________"),
        ],
        "jar_head": "Kind-Words Jar Slips",
        "jar_note": "A kind word or prayer from: ______________",
    },
}


def _n(lang: str, v: int | str) -> str:
    s = str(v)
    return s.translate(_AR_DIGITS) if lang == "ar" else s


def _e(s: str) -> str:
    return escape(s)


def _lantern_net_svg(lang: str, bw: bool) -> str:
    t = _COPY[lang]
    em = "#0F3D36" if bw else "#0F6B5C"
    panel = "#FFFFFF" if bw else "#E7F4F0"
    roof = "#FFFFFF" if bw else "#FBF1DE"
    gold = "#FFFFFF" if bw else "#F7C548"
    tab = "#F5F5F5" if bw else "#F6EFE2"
    stroke = "#0F3D36"

    parts: list[str] = []
    panel_w = 138
    x0 = 42
    # 4 geometric panels + sloped roof hoods + bottom fold base tabs + handle strip
    for idx in range(4):
        x = x0 + idx * panel_w
        cx = x + panel_w / 2
        # Roof hood trapezoid above panel (y: 44 -> 118)
        parts.append(
            f'<polygon points="{x + 36},44 {x + panel_w - 36},44 {x + panel_w},118 {x},118" '
            f'fill="{roof}" stroke="{stroke}" stroke-width="2"/>'
        )
        # Main body panel (y: 118 -> 346)
        dash_attr = 'stroke-dasharray="6 4"' if idx > 0 else ""
        parts.append(
            f'<rect x="{x}" y="118" width="{panel_w}" height="228" '
            f'fill="{panel}" stroke="{stroke}" stroke-width="2" {dash_attr}/>'
        )
        # Arched paper-cut window cutout inside each face
        parts.append(
            f'<path d="M{x + 26} 312 V206 C{x + 26} 162 {cx} 146 {cx} 146 '
            f'C{cx} 146 {x + panel_w - 26} 162 {x + panel_w - 26} 206 V312 Z" '
            f'fill="#fff" stroke="{em}" stroke-width="2.2" stroke-dasharray="4 3"/>'
        )
        if idx % 2 == 0:
            # Paper crescent motif inside alternating faces
            parts.append(
                f'<path d="M{cx - 4} 205 A26 26 0 1 0 {cx + 22} 245 A21 21 0 0 1 {cx - 4} 205 Z" '
                f'fill="{gold}" stroke="{stroke}" stroke-width="1.8"/>'
            )
        else:
            # Eight-point geometric star
            pts = (
                f"{cx},198 {cx + 7},215 {cx + 25},215 {cx + 11},226 "
                f"{cx + 16},244 {cx},234 {cx - 16},244 {cx - 11},226 "
                f"{cx - 25},215 {cx - 7},215"
            )
            parts.append(
                f'<polygon points="{pts}" fill="{gold}" stroke="{stroke}" stroke-width="1.8"/>'
            )
        # Bottom fold flap (y: 346 -> 384)
        parts.append(
            f'<polygon points="{x},346 {x + panel_w},346 {x + panel_w - 18},384 {x + 18},384" '
            f'fill="{tab}" stroke="{stroke}" stroke-width="1.6" stroke-dasharray="5 4"/>'
        )
        # Right-hand glue tab after panel 4 + roof tab per hood
        parts.append(
            f'<polygon points="{x + panel_w - 36},44 {x + panel_w},118 {x + panel_w - 12},118 '
            f'{x + panel_w - 44},48" fill="none" stroke="{stroke}" stroke-width="1" stroke-dasharray="3 3"/>'
        )

    # Outer side glue tab on far right
    rx = x0 + 4 * panel_w
    parts.append(
        f'<polygon points="{rx},128 {rx + 28},148 {rx + 28},326 {rx},344" '
        f'fill="{tab}" stroke="{stroke}" stroke-width="2"/>'
    )
    parts.append(
        f'<line x1="{rx}" y1="118" x2="{rx}" y2="346" stroke="{stroke}" stroke-width="2" stroke-dasharray="5 4"/>'
    )
    # Dashed fold horizontal line at roof neck y=118 and base y=346
    parts.append(
        f'<line x1="{x0}" y1="118" x2="{rx}" y2="118" stroke="{stroke}" stroke-width="2" stroke-dasharray="6 4"/>'
    )
    parts.append(
        f'<line x1="{x0}" y1="346" x2="{rx}" y2="346" stroke="{stroke}" stroke-width="2" stroke-dasharray="6 4"/>'
    )
    # Carrying handle strip (y: 412 -> 448)
    parts.append(
        f'<rect x="{x0}" y="412" width="{4 * panel_w}" height="34" rx="6" '
        f'fill="{gold}" stroke="{stroke}" stroke-width="2"/>'
    )
    parts.append(
        f'<text x="{x0 + 2 * panel_w}" y="434" text-anchor="middle" font-size="13" font-weight="800" fill="{stroke}">'
        f'{_e(t["s1_handle"])}</text>'
    )
    return (
        '<svg viewBox="0 0 680 462" width="100%" style="display:block;max-height:175mm">'
        f'{"".join(parts)}'
        "</svg>"
    )


def _lantern_street_svg(lang: str, bw: bool) -> str:
    t = _COPY[lang]
    em = "#0F3D36" if bw else "#0F6B5C"
    odd_fill = "#FFFFFF" if bw else "#FFF5D6"
    norm_fill = "#FFFFFF"
    gold = "#0F3D36" if bw else "#D49B1A"
    odd_nights = {20, 22, 24, 26, 28}

    cells: list[str] = []
    phases = [
        (0, 10, t["s2_p1"]),
        (10, 20, t["s2_p2"]),
        (20, 30, t["s2_p3"]),
    ]
    for start, end, label in phases:
        cells.append(f'<div class="m-phase">{_e(label)}</div><div class="m-row">')
        for day in range(start + 1, end + 1):
            is_odd = day in odd_nights
            bg = odd_fill if is_odd else norm_fill
            bd = gold if is_odd else em
            cres = " ☾" if is_odd else ""
            cells.append(
                f'<div class="m-cell" style="background:{bg};border-color:{bd}">'
                '<svg viewBox="0 0 48 56" class="m-svg" aria-hidden="true">'
                f'<circle cx="24" cy="7" r="2.5" fill="none" stroke="{bd}" stroke-width="2"/>'
                f'<path d="M14 17C14 12.5 20 11 24 8.5C28 11 34 12.5 34 17Z" fill="none" stroke="{bd}" stroke-width="2"/>'
                f'<path d="M15 19H33L37 31L31 44H17L11 31Z" fill="#fff" stroke="{bd}" stroke-width="2.2"/>'
                f'<path d="M18 46H30L28 51H20Z" fill="none" stroke="{bd}" stroke-width="2"/>'
                "</svg>"
                f'<b>{_n(lang, day)}{cres}</b>'
                "</div>"
            )
        cells.append("</div>")
    return "".join(cells)


def _craft_sheet(lang: str, idx: int, title: str, subtitle: str, body: str) -> str:
    t = _COPY[lang]
    code = CRAFT_CODES[lang]
    return (
        f'<section class="sheet">'
        f'<header class="sh-head"><span>{_e(t["brand"])} · {_e(t["prog"])}</span>'
        f'<span>{_e(t["sheet"])} {_n(lang, idx)}/{_n(lang, 3)}</span></header>'
        f'<h2>{_e(title)}</h2><p class="sub">{_e(subtitle)}</p>'
        f'<div class="body">{body}</div>'
        f'<footer class="sh-foot"><img src="/ui/assets/print/qr_{code}.svg" alt="QR — /go?ref={code}">'
        f'<div><strong>{_e(t["foot_t"])}</strong><span>{_e(t["foot_s"])}</span>'
        f'<span class="url">tg-api.alsaba.cloud/go?ref={code}</span></div></footer></section>'
    )


def render_lantern_craft(lang: str = "ar", ink: str = "color") -> str:
    """Render the 3 printable A4 sheets for `/print/lantern-craft`."""
    lang = "en" if lang == "en" else "ar"
    bw = ink == "bw"
    t = _COPY[lang]
    em = "#0F3D36" if bw else "#0F6B5C"
    soft = "#FFFFFF" if bw else "#FBF1DE"

    # Sheet 1: 3D paper-cut lantern pattern + instructions
    steps_html = "".join(f'<span class="step-pill">{_e(s)}</span>' for s in t["s1_steps"])
    s1_body = f'{_lantern_net_svg(lang, bw)}<div class="steps-row">{steps_html}</div>'

    # Sheet 2: 30-lantern street fridge map
    s2_body = f'<div class="names-box">{_e(t["s2_names"])}</div>{_lantern_street_svg(lang, bw)}'

    # Sheet 3: 4 Foldable Iftar Ambassador table tent cards + 8 Kind-Words jar slips
    tent_cards = "".join(
        f'<div class="tent"><div class="tent-back">{_e(role)}</div>'
        f'<div class="tent-fold">- - - - - - - - - - - - -</div>'
        f'<div class="tent-front"><strong>{_e(role)}</strong>'
        f'<span>{_e(desc)}</span><small>{_e(who)}</small></div></div>'
        for role, desc, who in t["roles"]
    )
    slips = "".join(
        f'<div class="slip"><span>★ {_e(t["jar_note"])}</span><div class="line"></div></div>'
        for _ in range(8)
    )
    s3_body = (
        f'<div class="tents">{tent_cards}</div>'
        f'<h3>{_e(t["jar_head"])}</h3>'
        f'<div class="slips">{slips}</div>'
    )

    sheets = "".join([
        _craft_sheet(lang, 1, t["s1_t"], t["s1_sub"], s1_body),
        _craft_sheet(lang, 2, t["s2_t"], t["s2_sub"], s2_body),
        _craft_sheet(lang, 3, t["s3_t"], t["s3_sub"], s3_body),
    ])

    color_href = f'/print/lantern-craft?lang={lang}&ink=color'
    bw_href = f'/print/lantern-craft?lang={lang}&ink=bw'
    other_href = f'/print/lantern-craft?lang={"ar" if lang == "en" else "en"}&ink={"bw" if bw else "color"}'

    css = (
        '@font-face{font-family:Cairo;font-weight:400;font-display:swap;src:url(/ui/assets/fonts/cairo-regular.woff2) format("woff2")}'
        '@font-face{font-family:Cairo;font-weight:800;font-display:swap;src:url(/ui/assets/fonts/cairo-extrabold.woff2) format("woff2")}'
        f':root{{--ink:#0F3D36;--em:{em};--soft:{soft};--line:#9fb8b1}}'
        '*{box-sizing:border-box;margin:0;padding:0}'
        'body{font-family:Cairo,system-ui,sans-serif;color:var(--ink);background:#efe6d3;line-height:1.5}'
        '.bar{max-width:210mm;margin:14px auto;padding:0 12px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}'
        '.bar p{flex:1 1 260px;font-size:14.5px}'
        '.bar button,.bar a{font:inherit;font-weight:800;border-radius:999px;padding:7px 16px;text-decoration:none;cursor:pointer}'
        '.bar button{border:0;background:var(--em);color:#fff}'
        '.bar a{background:transparent;color:var(--em);border:2px solid var(--em)}'
        '.bar a.active{background:var(--soft)}'
        '.sheet{background:#fff;width:210mm;max-width:100%;min-height:297mm;margin:0 auto 18px;padding:12mm;display:flex;flex-direction:column;box-shadow:0 2px 10px rgba(0,0,0,.12)}'
        '.sh-head{display:flex;justify-content:space-between;font-size:12px;color:var(--em);font-weight:800;border-bottom:1.5px solid var(--ink);padding-bottom:4px;margin-bottom:8px}'
        'h2{font-size:21px;font-weight:800;margin-bottom:4px}h3{font-size:15px;font-weight:800;margin:10px 0 6px}'
        '.sub{font-size:13.5px;margin-bottom:8px}.body{flex:1}'
        '.steps-row{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}'
        '.step-pill{flex:1 1 160px;border:1.5px solid var(--ink);border-radius:10px;padding:6px 10px;font-size:12.5px;font-weight:800;background:var(--soft)}'
        '.names-box{border:1.8px solid var(--ink);border-radius:10px;padding:8px 12px;margin-bottom:8px;font-weight:800;background:var(--soft);font-size:13.5px}'
        '.m-phase{font-weight:800;font-size:13px;color:var(--em);margin:6px 0 4px}'
        '.m-row{display:grid;grid-template-columns:repeat(5,1fr);gap:6px}'
        '.m-cell{border:1.6px solid var(--ink);border-radius:10px;padding:5px;text-align:center;display:flex;flex-direction:column;align-items:center;min-height:22mm}'
        '.m-svg{width:13mm;height:15mm}.m-cell b{font-size:13px;margin-top:2px}'
        '.tents{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:8px}'
        '.tent{border:2px solid var(--ink);border-radius:12px;padding:8px;text-align:center;background:var(--soft)}'
        '.tent-back{font-size:12px;opacity:.65;transform:rotate(180deg);padding-bottom:6px}'
        '.tent-fold{font-size:10px;letter-spacing:2px;color:var(--em);margin:2px 0}'
        '.tent-front strong{display:block;font-size:15px;color:var(--em)}.tent-front span{display:block;font-size:12.5px;margin:2px 0}.tent-front small{display:block;font-size:12px;margin-top:6px}'
        '.slips{display:grid;grid-template-columns:1fr 1fr;gap:6px}'
        '.slip{border:1.5px dashed var(--ink);border-radius:8px;padding:7px 9px;min-height:17mm;font-size:12px}'
        '.line{border-bottom:1.2px solid var(--line);height:7mm}'
        '.sh-foot{display:flex;gap:10px;align-items:center;border-top:1.5px solid var(--ink);padding-top:6px;margin-top:8px}'
        '.sh-foot img{width:22mm;height:22mm}.sh-foot strong{display:block;font-size:14px}.sh-foot span{display:block;font-size:11.5px}.sh-foot .url{direction:ltr;unicode-bidi:embed;color:var(--em)}'
        '@page{size:A4;margin:0}@media print{body{background:#fff}.bar{display:none}.sheet{box-shadow:none;margin:0;break-after:page;width:210mm;height:297mm;min-height:0}}'
    )
    return (
        f'<!doctype html><html lang="{lang}" dir="{t["dir"]}"><head><meta charset="utf-8">'
        f'<meta name="viewport" content="width=device-width,initial-scale=1">'
        f'<title>{_e(t["title"])}</title><style>{css}</style></head><body>'
        f'<div class="bar"><p>{_e(t["intro"])}</p>'
        f'<button type="button" onclick="window.print()">{_e(t["print"])}</button>'
        f'<a href="{color_href}" class="{"active" if not bw else ""}">{_e(t["ink_color"])}</a>'
        f'<a href="{bw_href}" class="{"active" if bw else ""}">{_e(t["ink_bw"])}</a>'
        f'<a href="{other_href}" lang="{"ar" if lang == "en" else "en"}">{_e(t["other"])}</a>'
        f'</div>{sheets}</body></html>'
    )
