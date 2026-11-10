"""/print/ramadan — the «رمضان العائلة» program as sheets to print (A4).

Everything on the sheets is read from the program itself
(knowledge_base/curriculum/programs/ramadan_family.json and its English twin)
at request time, so a change to the program changes the sheets; nothing here is
new content. The only words of our own are the sheet furniture (titles of the
blanks, «اسم الطفل», the footer).

Each sheet carries the QR to /go?ref=PR01 (Arabic) or PR02 (English) — the PR
prefix in services/attribution.py, the codes in ops/data/campaign_codes.md,
the SVGs from ops/tools/gen_print_qr.py — so an install from a printed sheet
is counted (decision of 2026-11-09: free printable sheets from our own
content, the one idea taken from the Nabta teardown).

Not printed on purpose: the parent notes (they cite «الحديث المرفق» by id and
read as app text), and the free-text steps of challenges whose sheet is a
blank to fill — the sheet is the material the step asks for.
"""
from __future__ import annotations

from html import escape
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import HTMLResponse

from app.services import programs_common as pc
from app.services import ramadan_program as rp

router = APIRouter(tags=["print"])

_AR_DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")

# The short surahs of the family wird. A surah added to the program without a
# name here fails tests/test_print_pack.py, not a printed sheet.
SURAH_NAMES: dict[int, tuple[str, str]] = {
    1: ("الفاتحة", "Al-Fatihah"), 93: ("الضحى", "Ad-Duha"), 94: ("الشرح", "Ash-Sharh"),
    97: ("القدر", "Al-Qadr"), 102: ("التكاثر", "At-Takathur"), 103: ("العصر", "Al-Asr"),
    105: ("الفيل", "Al-Fil"), 106: ("قريش", "Quraysh"), 107: ("الماعون", "Al-Ma'un"),
    108: ("الكوثر", "Al-Kawthar"), 109: ("الكافرون", "Al-Kafirun"), 110: ("النصر", "An-Nasr"),
    112: ("الإخلاص", "Al-Ikhlas"), 113: ("الفلق", "Al-Falaq"), 114: ("الناس", "An-Nas"),
}
CODES = {"ar": "PR01", "en": "PR02"}

_T = {
    "ar": {
        "dir": "rtl", "brand": "المربّي", "print": "اطبعوا الأوراق", "other": "English",
        "intro": "أوراق برنامج «رمضان العائلة» في تطبيق المربّي، جاهزة للطباعة على ورق A4. "
                 "اطبعوا ما تحتاجون منها، وعلّقوها حيث يراها الجميع.",
        "foot_t": "حمّلوا «المربّي» مجانًا", "foot_s": "بلا إعلانات ولا اشتراكات — امسحوا الرمز",
        "calendar": "تقويم التحديات العائلية", "phases": {"first_ten": "العشر الأوائل",
                                                       "middle_ten": "العشر الأواسط", "last_ten": "العشر الأواخر"},
        "day": "اليوم", "may_not": "إن تمّ الشهر",
        "wird": "ورد القرآن معًا", "wird_note": "سورة قصيرة تتكرّر يومين ليحفظها الصغار.",
        "days": "اليومان", "surah": "سورة", "verses": "الآيات", "juz": "ختمة الوالدين: جزء كل يوم",
        "ladder_for": "اسم الطفل", "child_band": "فئته العمرية", "no_fast": "لا صيام في هذا العمر",
        "safety": "سلامة الصيام", "doctor": "قبل أن يبدأ، استشيروا الطبيب إن كان عند الطفل:",
        "stop": "يفطر فورًا إذا ظهر:", "urgent": "اطلبوا الإسعاف إذا ظهر:",
        "intentions": "اسم", "intention": "نيّتي", "kind_word": "كلمة طيبة سمعتها", "from": "من",
        "charity_label": "صندوق صدقة عائلة", "thanks": "شكرًا لك يا", "draw": "ارسم هنا",
        "nights": "العشر الأواخر", "odd": "مساء هذا اليوم تبدأ ليلة وترية من العشر الأواخر.",
        "evidence": "الحديثان المرفقان", "recap_word": "كلمة رمضاننا", "promise": "وعد العائلة: نكمل بعد رمضان",
        "materials": "تحتاجون:", "minutes": "دقيقة", "sheet": "ورقة",
        "kid_lantern": "لوّنوا قنديلًا عند كل تحدٍّ تنجزونه معًا.",
        "kid_star": "لوّنوا نجمة لكل يوم قرأتم فيه معًا.",
        "kid_heart": "لوّن قلبك كلما وفيت بنيّتك.",
        "kid_night": "لوّنوا نجمة كل ليلة.",
        "kid_eid": "لوّنوا زينة العيد.",
        "kid_word": "لوّنوا كلمة رمضاننا.",
        "jar": "جرّتنا",
    },
    "en": {
        "dir": "ltr", "brand": "Al-Morabbi", "print": "Print the sheets", "other": "العربية",
        "intro": "The sheets of the «Family Ramadan» program in the Al-Morabbi app, ready to print on A4. "
                 "Print the ones you need and put them up where everyone can see them.",
        "foot_t": "Get Al-Morabbi free", "foot_s": "No ads, no subscriptions — scan the code",
        "calendar": "Calendar of family challenges", "phases": {"first_ten": "The first ten",
                                                              "middle_ten": "The middle ten", "last_ten": "The last ten"},
        "day": "Day", "may_not": "if the month completes",
        "wird": "Quran together", "wird_note": "A short surah repeated over two days, so the little ones learn it by heart.",
        "days": "Days", "surah": "Surah", "verses": "Verses", "juz": "Parents' khatm: one juz a day",
        "ladder_for": "Child's name", "child_band": "Age group", "no_fast": "No fasting at this age",
        "safety": "Fasting safely", "doctor": "Before starting, ask a doctor if the child has:",
        "stop": "Break the fast at once if you see:", "urgent": "Call emergency services if you see:",
        "intentions": "Name", "intention": "My intention", "kind_word": "A kind word I heard", "from": "From",
        "charity_label": "Charity box of the family", "thanks": "Thank you,", "draw": "Draw here",
        "nights": "The last ten", "odd": "This evening begins one of the odd nights of the last ten.",
        "evidence": "The two hadith referred to", "recap_word": "Our Ramadan word",
        "promise": "Our family promise: we carry on after Ramadan",
        "materials": "You need:", "minutes": "min", "sheet": "sheet",
        "kid_lantern": "Colour a lantern for each challenge you finish together.",
        "kid_star": "Colour a star for each day you read together.",
        "kid_heart": "Colour your heart each time you keep your intention.",
        "kid_night": "Colour a star each night.",
        "kid_eid": "Colour the Eid decorations.",
        "kid_word": "Colour our Ramadan word.",
        "jar": "Our jar",
    },
}

_CSS = """
@font-face{font-family:Cairo;font-weight:400;font-display:swap;src:url(/ui/assets/fonts/cairo-regular.woff2) format("woff2")}
@font-face{font-family:Cairo;font-weight:800;font-display:swap;src:url(/ui/assets/fonts/cairo-extrabold.woff2) format("woff2")}
:root{--ink:#0F3D36;--em:#0F6B5C;--line:#9fb8b1}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Cairo,system-ui,sans-serif;color:var(--ink);background:#efe6d3;line-height:1.6}
.bar{max-width:210mm;margin:16px auto;padding:0 12px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
.bar p{flex:1 1 280px;font-size:15px}
.bar button,.bar a{font:inherit;font-weight:800;border:0;border-radius:999px;padding:8px 18px;cursor:pointer;
  background:var(--em);color:#fff;text-decoration:none}
.bar a{background:transparent;color:var(--em);border:2px solid var(--em)}
.sheet{background:#fff;width:210mm;max-width:100%;min-height:297mm;margin:0 auto 18px;padding:12mm;
  display:flex;flex-direction:column;box-shadow:0 2px 10px rgba(0,0,0,.12)}
.sh-head{display:flex;justify-content:space-between;font-size:12px;color:var(--em);font-weight:800;
  border-bottom:1.5px solid var(--ink);padding-bottom:4px;margin-bottom:10px}
h1{font-size:30px;font-weight:800;line-height:1.3}
h2{font-size:24px;font-weight:800;margin-bottom:6px}
h3{font-size:16px;font-weight:800;margin:10px 0 4px}
.sub{font-size:15px;margin-bottom:8px}
.body{flex:1;font-size:14px}
ul.check{list-style:none}
ul.check li{padding:3px 0;display:flex;gap:8px}
ul.check li::before{content:"";flex:none;width:14px;height:14px;border:1.5px solid var(--ink);border-radius:3px;margin-top:4px}
.grid{display:grid;grid-template-columns:repeat(5,1fr);gap:6px}
.cell{border:1.5px solid var(--ink);border-radius:8px;padding:4px 6px;min-height:25mm;display:flex;flex-direction:column;font-size:12.5px}
.cell b{font-size:15px}
.cell span{flex:1}
.cell i{font-style:normal;font-size:11px;color:var(--em)}
.phase{grid-column:1/-1;font-weight:800;color:var(--em);font-size:13px;margin-top:4px}
table{width:100%;border-collapse:collapse;font-size:13.5px}
td,th{border:1.2px solid var(--line);padding:5px 6px;text-align:start;vertical-align:top}
th{font-weight:800}
td.tick{width:18mm;white-space:nowrap}
.juz{display:grid;grid-template-columns:repeat(10,1fr);gap:4px;margin-top:6px}
.juz span{border:1.2px solid var(--ink);border-radius:4px;text-align:center;font-size:12px;padding:2px 0}
.steps{display:flex;flex-wrap:wrap;gap:6px 14px;margin-top:5px}
.step{display:inline-flex;gap:6px;align-items:center;font-weight:800}
.step::before{content:"";width:18px;height:18px;border:1.5px solid var(--ink);border-radius:50%}
.line{border-bottom:1.2px solid var(--line);height:9mm}
.cards{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.cut{border:1.5px dashed var(--ink);border-radius:10px;padding:8px;min-height:26mm;font-size:13px}
.cut.tall{min-height:60mm}
.label{border:3px double var(--ink);border-radius:14px;padding:18px;text-align:center;font-size:24px;font-weight:800;margin:10px 0}
.ev{border-inline-start:3px solid var(--em);padding:4px 10px;margin:6px 0;font-size:13.5px}
.ev small{display:block;color:var(--em)}
.sh-foot{display:flex;gap:10px;align-items:center;border-top:1.5px solid var(--ink);padding-top:6px;margin-top:8px}
.sh-foot img{width:24mm;height:24mm}
.sh-foot strong{display:block;font-size:15px}
.sh-foot span{display:block;font-size:12px}
.sh-foot .url{direction:ltr;unicode-bidi:embed;font-size:11px;color:var(--em)}
.small{font-size:12.5px}
.title-row{display:flex;align-items:center;justify-content:space-between;gap:10px}
.art{width:24mm;height:24mm;flex:none}
.cover{display:flex;gap:14px;align-items:center;margin-bottom:8px}
.cover .hero{width:58mm;height:58mm;flex:none}
.row{display:flex;gap:8px;align-items:center;justify-content:center;flex-wrap:wrap}
.deco{width:16mm;height:16mm}
.kid{font-weight:800;color:var(--em);font-size:14.5px;margin:2px 0 6px}
.ico{width:12mm;height:12mm;fill:#fff;stroke:var(--ink);stroke-width:2;stroke-linejoin:round;stroke-linecap:round;flex:none;vertical-align:middle}
.ico.xs{width:5mm;height:5mm}.ico.sm{width:7mm;height:7mm}.ico.md{width:10mm;height:10mm}.ico.lg{width:20mm;height:20mm}
.cell-ico{align-self:center;width:9mm;height:9mm}
.split{display:flex;gap:12px;align-items:center}.split ul{flex:1}
.jar{position:relative;flex:none;width:38mm;text-align:center}
.jar-ico{width:38mm;height:44mm;fill:#fff;stroke:var(--ink);stroke-width:2.2;stroke-linejoin:round}
.jar span{position:absolute;left:0;right:0;top:26mm;font-weight:800;font-size:13px}
.corners{display:flex;justify-content:space-between}.corners.low{margin-top:auto}
.cut.tall{display:flex;flex-direction:column}
.label{display:flex;align-items:center;justify-content:space-between;gap:10px}
ul.stars{list-style:none;display:flex;flex-direction:column;gap:5px}
ul.stars li{display:flex;gap:10px;align-items:center;font-size:14.5px}
.deco-row{margin:4px 0 10px}
.frame{border:3px double var(--ink);border-radius:16px;padding:10px 12px}
.words{display:flex;flex-wrap:wrap;gap:6px}
.word{border:1.5px solid var(--ink);border-radius:999px;padding:3px 12px;font-weight:800}
.tall-rows td{height:13mm;vertical-align:middle}
@page{size:A4;margin:0}
@media print{body{background:#fff}.bar{display:none}.sheet{box-shadow:none;margin:0;break-after:page;width:210mm;height:297mm;min-height:0}}
@media screen and (max-width:640px){.sheet{min-height:0;padding:16px}.grid{grid-template-columns:repeat(3,1fr)}.cards{grid-template-columns:1fr}}
"""


# Line drawings for children to colour in: white fill, ink stroke, so they
# print light. The lantern is mobile/assets/svg/icons/lantern.svg's geometry
# and the crescent is Noor's (mobile/assets/svg/STYLE.md), drawn as outlines.
_ICONS = (
    '<svg width="0" height="0" style="position:absolute" aria-hidden="true">'
    '<symbol id="i-lantern" viewBox="0 0 48 48"><circle cx="24" cy="7.5" r="2.6"/>'
    '<path d="M14.5 17.5C14.5 13.5 20 12.5 24 9.5C28 12.5 33.5 13.5 33.5 17.5Z"/>'
    '<path d="M16 19.5H32L35 27L31 35H17L13 27Z"/>'
    '<path d="M24 22.5C21.5 25.5 22 29 24 30.5C26 29 26.5 25.5 24 22.5Z"/>'
    '<path d="M18 37H30L28 41.5H20Z"/></symbol>'
    '<symbol id="i-star" viewBox="0 0 48 48"><path d="M24 4.5L29.1 17 42.5 18 32.3 26.7 35.5 39.8 24 32.7 12.5 39.8 15.7 26.7 5.5 18 18.9 17Z"/></symbol>'
    '<symbol id="i-heart" viewBox="0 0 48 48"><path d="M24 40C10 30 6 22 10 15.5C13.5 10 20.5 10.5 24 16C27.5 10.5 34.5 10 38 15.5C42 22 38 30 24 40Z"/></symbol>'
    '<symbol id="i-crescent" viewBox="0 0 48 48"><path d="M23.9 13.9A12.5 12.5 0 1 0 35.5 31.2A10.6 10.6 0 0 1 23.9 13.9Z"/></symbol>'
    '<symbol id="i-balloon" viewBox="0 0 48 48"><ellipse cx="24" cy="18" rx="11" ry="13"/><path d="M21.5 31H26.5L24 34Z"/>'
    '<path d="M24 34C21 38 27 41 24 46" fill="none"/></symbol>'
    '<symbol id="i-coin" viewBox="0 0 48 48"><circle cx="24" cy="24" r="15"/><circle cx="24" cy="24" r="10"/></symbol>'
    '<symbol id="i-jar" viewBox="0 0 120 140"><rect x="30" y="8" width="60" height="14" rx="4"/><path d="M36 22H84V32H36Z"/>'
    '<path d="M30 32C14 40 12 56 12 74V116C12 128 22 134 34 134H86C98 134 108 128 108 116V74C108 56 106 40 90 32Z"/>'
    '<rect x="30" y="70" width="60" height="30" rx="6" stroke-dasharray="4 3"/></symbol>'
    "</svg>"
)


def _i(name: str, cls: str = "ico") -> str:
    return f'<svg class="{cls}" aria-hidden="true"><use href="#i-{name}"/></svg>'


def _art(path: str, cls: str = "art") -> str:
    """Our paper-cut art (mobile/assets/svg, served under /assets)."""
    return f'<img class="{cls}" src="/assets/svg/{path}" alt="">'


def _n(lang: str, value) -> str:
    s = str(value)
    return s.translate(_AR_DIGITS) if lang == "ar" else s


def _e(s) -> str:
    return escape(str(s or ""))


def _li(items) -> str:
    return "".join(f"<li>{_e(x)}</li>" for x in items)


def _challenge(doc: dict, day: int) -> dict:
    return next(d for d in doc["days"] if d["day"] == day)["family_challenge"]


def _sheet(lang: str, idx: int, total: int, program: str, title: str, body: str, art: str = "") -> str:
    t, code = _T[lang], CODES[lang]
    return (f'<section class="sheet"><header class="sh-head"><span>{_e(t["brand"])} · {_e(program)}</span>'
            f'<span>{_e(t["sheet"])} {_n(lang, idx)}/{_n(lang, total)}</span></header>'
            f'<div class="title-row"><h2>{_e(title)}</h2>{_art(art) if art else ""}</div><div class="body">{body}</div>'
            f'<footer class="sh-foot"><img src="/ui/assets/print/qr_{code}.svg" alt="QR — /go?ref={code}">'
            f'<div><strong>{_e(t["foot_t"])}</strong><span>{_e(t["foot_s"])}</span>'
            f'<span class="url">tg-api.alsaba.cloud/go?ref={code}</span></div></footer></section>')


def _pages(doc: dict, lang: str) -> list[tuple[str, str, str]]:
    """(title, body, art) per sheet."""
    t = _T[lang]
    out: list[tuple[str, str, str]] = []
    k = doc["kickoff"]
    lanterns = "".join(_art("icons/lantern.svg", "deco") for _ in range(3))
    out.append((k["title"], f'<div class="cover">{_art("noor/noor_happy.svg", "hero")}<div><h1>{_e(doc["title"])}</h1>'
                            f'<p class="sub">{_e(doc["subtitle"])}</p><div class="row">{lanterns}</div></div></div>'
                            f'<p>{_e(k["text"])}</p><h3>{_e(k["title"])}</h3><ul class="check">{_li(k["setup_steps"])}</ul>'
                            f'<h3>{_e(t["child_band"])}</h3><p>{_e(doc["bands"]["text"])}</p>', ""))
    # calendar — a lantern to colour for every day
    cells, phase = [], None
    for d in doc["days"]:
        if d["phase"] != phase:
            phase = d["phase"]
            cells.append(f'<div class="phase">{_i("crescent", "ico sm")} {_e(t["phases"].get(phase, phase))}</div>')
        extra = f'<i>{_e(t["may_not"])}</i>' if d.get("may_not_occur") else ""
        cells.append(f'<div class="cell"><b>{_n(lang, d["day"])}</b><span>{_e(d["family_challenge"]["title"])}</span>'
                     f'{extra}{_i("lantern", "ico cell-ico")}</div>')
    out.append((t["calendar"], f'<p class="kid">{_e(t["kid_lantern"])}</p><div class="grid">{"".join(cells)}</div>',
                "icons/lantern.svg"))
    # wird — a star to colour for every day
    rows, seen = [], []
    for d in doc["days"]:
        q = (d.get("quran") or {}).get("together")
        if not q:
            continue
        key = (q["surah"], q["from"], q["to"])
        if seen and seen[-1][0] == key:
            seen[-1][1].append(d["day"])
        else:
            seen.append((key, [d["day"]]))
    for (surah, a, b), days in seen:
        name = SURAH_NAMES[surah][0 if lang == "ar" else 1]
        rows.append(f'<tr><td>{"، ".join(_n(lang, x) for x in days) if lang == "ar" else ", ".join(map(str, days))}</td>'
                    f'<td>{_e(t["surah"])} {_e(name)}</td><td>{_n(lang, a)}–{_n(lang, b)}</td>'
                    f'<td class="tick">{"".join(_i("star", "ico sm") for _ in days)}</td></tr>')
    juz = "".join(f"<span>{_n(lang, i)}</span>" for i in range(1, 31))
    out.append((t["wird"], f'<p class="sub">{_e(t["wird_note"])}</p><p class="kid">{_e(t["kid_star"])}</p>'
                           f'<table><tr><th>{_e(t["days"])}</th><th>{_e(t["surah"])}</th><th>{_e(t["verses"])}</th>'
                           f'<th></th></tr>{"".join(rows)}</table>'
                           f'<h3>{_e(t["juz"])}</h3><div class="juz">{juz}</div>', "noor/noor_reading.svg"))
    # ladder — one row per age group, the steps as circles to colour in; each
    # step's full text is in the app (on paper it overflowed the page).
    fl = doc["fasting_ladder"]
    rows = []
    for band, spec in fl["bands"].items():
        steps = "".join(f'<span class="step">{_e(st["label"])}</span>' for st in spec["steps"])
        rows.append(f'<tr><th>{_n(lang, band)}</th><td><span class="small">{_e(spec["summary"])}</span>'
                    f'<div class="steps">{steps}</div></td></tr>')
    who = (f'<p style="margin:8px 0"><b>{_e(t["ladder_for"])}:</b> ____________________ '
           f'<b>{_e(t["child_band"])}:</b> ________</p>')
    out.append((fl["title"], f'<ul class="check small">{_li(fl["principles"][:2])}</ul>{who}'
                             f'<table><tr><th>{_e(t["child_band"])}</th><th></th></tr>{"".join(rows)}</table>{who}',
                "art/milestone_first_fast.svg"))
    # safety — for the parents; no drawings
    out.append((t["safety"], f'<h3>{_e(t["doctor"])}</h3><ul class="check">{_li(fl["doctor_first"])}</ul>'
                             f'<h3>{_e(t["stop"])}</h3><ul class="check">{_li(fl["stop_signs"])}</ul><p>{_e(fl["stop_action"])}</p>'
                             f'<h3>{_e(t["urgent"])}</h3><ul class="check">{_li(fl["urgent_signs"])}</ul><p>{_e(fl["urgent_action"])}</p>', ""))
    # day 1 — intentions board, a heart for each person
    c1 = _challenge(doc, 1)
    board = "".join(f'<tr><td style="width:35%">{_i("heart", "ico sm")} {_e(t["intentions"])}:</td>'
                    f'<td>{_e(t["intention"])}:</td></tr>' for _ in range(7))
    out.append((c1["title"], f'<ul class="check small">{_li(c1["steps"])}</ul><p class="kid">{_e(t["kid_heart"])}</p>'
                             f'<table style="margin-top:6px" class="tall-rows">{board}</table>', "noor/noor_tender.svg"))
    # day 5 — kind words: the jar to colour, then the slips
    c5 = _challenge(doc, 5)
    slips = "".join(f'<div class="cut">{_i("star", "ico xs")} {_e(t["kind_word"])}:<div class="line"></div>{_e(t["from"])}:</div>'
                    for _ in range(8))
    jar = f'<div class="jar">{_i("jar", "jar-ico")}<span>{_e(t["jar"])}</span></div>'
    out.append((c5["title"], f'<div class="split"><ul class="check small">{_li(c5["steps"])}</ul>{jar}</div>'
                             f'<div class="cards" style="margin-top:8px">{slips}</div>', ""))
    # day 6 — the charity box label (the box itself is the step)
    c6 = _challenge(doc, 6)
    label = (f'<div class="label">{_i("coin", "ico md")}<div>{_e(t["charity_label"])}<br>__________</div>'
             f'{_i("heart", "ico md")}</div>')
    out.append((c6["title"], label * 3, "icons/gift.svg"))
    # day 23 — thank-you cards with stars to colour
    c23 = _challenge(doc, 23)
    corner = _i("star", "ico xs")
    cards = "".join(f'<div class="cut tall"><div class="corners">{corner}{corner}</div>{_e(t["thanks"])} ____________'
                    f'<br><span class="small">{_e(t["draw"])}</span><div class="corners low">{_i("heart", "ico xs")}{corner}</div></div>'
                    for _ in range(4))
    out.append((c23["title"], f'<ul class="check small">{_li(c23["steps"])}</ul><div class="cards" style="margin-top:8px">{cards}</div>',
                "icons/envelope.svg"))
    # the last ten (from day 20: its evening is the night of the 21st) — a star each night
    nights = []
    for d in doc["days"]:
        if d["day"] < 20:
            continue
        mark = " ☾" if d.get("odd_night") else ""
        extra = f' <i class="small">({_e(t["may_not"])})</i>' if d.get("may_not_occur") else ""
        nights.append(f'<li>{_i("star", "ico md")}<span><b>{_e(t["day"])} {_n(lang, d["day"])}{mark}</b> — '
                      f'{_e(d["family_challenge"]["title"])}{extra}</span></li>')
    out.append((t["nights"], f'<p class="kid">{_e(t["kid_night"])}</p><ul class="stars">{"".join(nights)}</ul>'
                             f'<p class="small">☾ {_e(t["odd"])}</p>', "noor/noor_sleepy.svg"))
    # eid — decorations to colour, then the day
    eid = doc["eid"]
    ev = {e["id"]: e for e in doc["evidence"]}
    cites = "".join(f'<div class="ev"><span lang="ar" dir="rtl">«{_e(ev[i]["text_ar"])}»</span>'
                    + (f'<br>{_e(ev[i].get("meaning"))}' if lang == "en" and ev[i].get("meaning") else "")
                    + f'<small>{_e(ev[i]["source"])}</small></div>'
                    for i in eid.get("evidence_ids", []) if i in ev)
    deco = "".join(_i(n, "ico lg") for n in ("balloon", "lantern", "star", "lantern", "balloon"))
    out.append((eid["title"], f'<p class="kid">{_e(t["kid_eid"])}</p><div class="row deco-row">{deco}</div>'
                              f'<ul class="check">{_li(eid["activities"])}</ul><h3>{_e(t["evidence"])}</h3>{cites}',
                "noor/noor_happy.svg"))
    # recap — framed, the family word to colour
    rc = doc["recap"]
    rows = []
    for m in rc["metrics"]:
        if m.get("choices"):
            words = "".join(f'<span class="word">{_e(c)}</span>' for c in m["choices"])
            rows.append(f'<tr><td>{_e(m["label"])}<br><span class="small">{_e(t["kid_word"])}</span></td>'
                        f'<td><div class="words">{words}</div></td></tr>')
        else:
            mx = f' / {_n(lang, m["max"])}' if m.get("max") else ""
            rows.append(f'<tr><td>{_e(m["label"])}</td><td>______{mx}</td></tr>')
    habits = "".join(f'<li><b>{_e(h["title"])}</b> — {_e(h["text"])}</li>' for h in doc["after_ramadan"]["keep_habits"])
    stars = "".join(_i("star", "ico sm") for _ in range(7))
    out.append((rc["card_title"], f'<div class="frame"><div class="row">{stars}</div><table>{"".join(rows)}</table>'
                                  f'<h3>{_e(t["promise"])}</h3><ul class="check">{habits}</ul><div class="row">{stars}</div></div>',
                "noor/noor_happy.svg"))
    return out


def render(doc: dict, lang: str) -> str:
    t = _T[lang]
    pages = _pages(doc, lang)
    sheets = "".join(_sheet(lang, i, len(pages), doc["title"], title, body, art)
                     for i, (title, body, art) in enumerate(pages, 1))
    other = "/print/ramadan" if lang == "en" else "/print/ramadan?lang=en"
    return (f'<!doctype html><html lang="{lang}" dir="{t["dir"]}"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{_e(doc["title"])} — {_e(t["brand"])}</title>'
            f'<meta name="description" content="{_e(t["intro"])}"><style>{_CSS}</style></head><body>'
            f'<div class="bar"><p>{_e(t["intro"])}</p><button type="button" onclick="window.print()">{_e(t["print"])}</button>'
            f'<a href="{other}" lang="{"ar" if lang == "en" else "en"}">{_e(t["other"])}</a></div>{_ICONS}'
            f"{sheets}</body></html>")


@router.get("/print/ramadan", response_class=HTMLResponse, include_in_schema=False)
def ramadan_sheets(lang: Optional[str] = Query(None)) -> HTMLResponse:
    lang = "en" if (lang or "").lower().startswith("en") else "ar"
    try:
        doc = pc.load_program(rp.PROGRAM, lang)
    except Exception as exc:  # noqa: BLE001 — a missing program file is a 503, not a 500 trace
        raise HTTPException(status_code=503, detail="program unavailable") from exc
    return HTMLResponse(render(doc, lang), headers={"Cache-Control": "public, max-age=3600"})
