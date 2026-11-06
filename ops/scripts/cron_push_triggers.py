#!/usr/bin/env python3
"""
ops/scripts/cron_push_triggers.py

Re-engagement push triggers — Phase 1.1 (schedule tuned in growth plan §4.2).
Runs as a VPS host cron, executing INSIDE the backend container (which has
firebase-admin + the DB). One run a day, UTC hour 17:
    0 17 * * * docker exec -w /app tg_backend python ops/scripts/cron_push_triggers.py >> /var/log/tg-push.log 2>&1

The 07 UTC run was dropped on 2026-08-13 with new_content_digest — see the
note at its deletion site. docs/OPS_RUNBOOK.md carries the authoritative
crontab table; both it and this line have to move together.

Needs env:
    FIREBASE_CREDENTIALS  (raw JSON) or backend/secrets/firebase-adminsdk.json
    TG_ADMIN_KEY          (unused here, but kept for symmetry)

Safe to run repeatedly: all sends are best-effort and idempotent-ish.

Before the pushes, every run also folds raw referral clicks older than seven
days into daily counts (fold_referral_clicks) — the only enforcement of that
retention. If it cannot run, the log gets an "ALERT referral-click-retention"
line and the run exits 2.

After them — in a `finally`, so on every run, whatever the hour and whatever
the pushes did — the privacy housekeeping (backend/app/services/retention.py)
deletes what the privacy policy says is no longer kept. If any step fails, the
log gets an "ALERT privacy-housekeeping" line and the run exits 1. With
--dry-run it deletes nothing and prints what it would delete.

The follow-up push («جرّبت النصيحة؟») is not here: it runs at 19:00 on each
family's own clock from the backend's in-process loop
(backend/app/services/followup_push.py). A single UTC hour is night from UTC+4
to UTC+8.
"""
import argparse
import sqlite3
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import NamedTuple, Optional

def _parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://localhost:8000")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--force", action="store_true",
        help="تجاهل بوابة الساعة — للتجربة خارج نافذة الستين دقيقة اليومية",
    )
    parser.add_argument(
        "--cap-days", type=int, default=3,
        help="لا تُرسل لجهاز وصلته دفعة خلال هذا العدد من الأيام",
    )
    return parser.parse_args(argv)


BASE_URL = "http://localhost:8000"
DRY_RUN = False
FORCE = False
CAP_DAYS = 3

# Ensure project root on path for app imports.
ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "backend"
sys.path.insert(0, str(BACKEND))

# ruff: noqa: E402
from app.db.init_db import db_path
from app.core.real_traffic import e2e_devices, real_device_sql
from app.services.family_actions import ACTION_SOURCES
from app.services.push_sender import recently_pushed_since, send_to_device


DB_PATH = db_path()


def _send(device_id: str, title: str, body: str, data: dict):
    if DRY_RUN:
        print(f"  [dry-run] would send to {device_id}: {title}  data={data}")
        return {"ok": True, "dry_run": True}
    return send_to_device(device_id, title, body, data)


def _query(sql: str, params: tuple = ()):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(sql, params).fetchall()
    conn.close()
    return rows


# _device_ids_with_tokens() removed 2026-08-11 along with its only caller.
# "every device that ever registered a token" is not an audience, and having
# the helper sitting there made it the path of least resistance for the next
# broadcast someone adds.


# ── Deep links ───────────────────────────────────────────────────────────
#
# The installed client reads `data['link']` (push_service.dart) and only
# understands four shapes: /go, /inbox, /l/{id}, /p/{id}. Sending anything
# else — as this file did with "route": "/paths" — makes the tap a no-op AND
# skips Analytics.pushTapped, which is why push_tapped has never once fired.
#
# We link to /p/{path_id} rather than /l/{lesson_id} on purpose:
# PathDetailScreen resolves the real active child (path_detail_screen.dart:78)
# and passes it on to the lesson (:129), so the completion button appears and
# lesson_opened fires. A bare /l/ link does neither until the client fix for
# the null childId ships and is widely adopted.

# One curated entry path per age band. Deliberately hand-picked: the generic
# listing sorts by (age_group, domain, id), i.e. alphabetical domain, which is
# not a content decision and would greet a returning parent with whatever
# domain happens to sort first.
STARTER_PATHS = {
    "prenatal-1": "path_0-3_islamic_parenting_attachment",
    "0-3": "path_0-3_islamic_parenting_attachment",
    "2-3": "path_2-3_islamic_attachment",
    "4-6": "path_4-6_islamic_parenting_bond",
    "7-9": "path_7-9_islamic_parenting_akhlaq",
    "10-12": "path_10-12_islamic_parenting_identity",
    "13-15": "path_13-15_islamic_parenting_teen_identity",
    "16-18": "path_16-18_islamic_parenting_adult_faith",
}

# Unwinds to the home tab, where the daily tip already lives.
HOME_LINK = "/go"


def _deep_link_for(age_group: str | None) -> str:
    """A tappable destination for this device, falling back to home."""
    path_id = STARTER_PATHS.get((age_group or "").strip())
    return f"/p/{path_id}" if path_id else HOME_LINK


# ── Who each device is, and when we last saw it ─────────────────────────
#
# Measured 2026-11-06 (14 days, real devices): 6,624 streak_at_risk pushes to
# 2,243 devices — 98% of everything this cron sent — and 65% of them went to a
# device not seen in the app for over 60 days. Idle was read from
# lesson_progress alone, so a parent who asked the assistant, ticked a plan
# step or read the daily tip that morning was "at risk" too (180 sends), and
# a lapsed device met the condition every evening forever (CAP_DAYS only
# spaced it out). GA4 over 30 days: 2% of FCM notifications opened, 64%
# dismissed, 218 app_remove against 318 first_open. Every message went out in
# Arabic — with «الحين» and «دلوقتي» in it — to the 27% of families who use the
# app in English.
#
# So the audience is now built once per run from every open signal, each
# kind has a window it can leave, re-engagement stops after a fixed number of
# tries per absence, and the copy follows the family's language.

# Rows written as a calendar date (one per day the app was opened) count as the
# END of that day: reading 2026-11-05 as 00:00 would make a parent who opened
# the app at 22:00 look 41 hours idle at the next evening's run.
_DAY_END = "datetime({col}, '+1 day', '-1 second')"

# (table, SQL expression of a moment the family was in the app). Missing tables
# or columns are skipped, not fatal — the same rule as family_actions.
_SEEN_DAYS = (("daily_login_streaks", "date"), ("coach_tips", "date"))
_SEEN_MOMENTS = (("chat_sessions", "updated_at"), ("push_tokens", "updated_at"))

# The kinds that try to bring a lapsed family back. A follow-up or a feedback
# reply is something the family asked for; it does not count as nagging.
_REENGAGE_KINDS = ("streak_at_risk", "win_back")

NUDGE_AFTER = timedelta(hours=36)
NUDGE_UNTIL = timedelta(days=7)        # after a week the gentle nudge stops …
WIN_BACK_UNTIL = timedelta(days=60)    # … and win_back stops for good here
WIN_BACK_MAX = 2                       # win_backs per absence
REENGAGE_MAX = 4                       # every re-engagement push per absence
WIN_BACK_GAP = timedelta(days=7)       # between two re-engagement pushes
NEW_FAMILY = timedelta(hours=42)       # day 0 and day 1 belong to the new-family pushes


class Device(NamedTuple):
    device_id: str
    first_created: datetime            # the device's first child profile
    last_seen: datetime                # latest open signal (never before first_created)
    lang: str                          # 'ar' | 'en'
    child_name: str                    # the most recently touched child ('' if none)
    age_group: Optional[str]
    has_lesson: bool
    reengaged: tuple                   # datetimes of re-engagement pushes since last_seen
    win_backs: int                     # win_back pushes since last_seen


_AUDIENCE: Optional[list] = None


def _ts(value) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value))
    except ValueError:
        return None


def _columns(conn: sqlite3.Connection, table: str) -> set:
    return {r[1] for r in conn.execute(f"PRAGMA table_info('{table}')")}


def _lang(value: Optional[str]) -> str:
    v = (value or "").strip().lower()
    if v.startswith("ar"):
        return "ar"
    return "en" if v else "ar"


# Names the onboarding pre-fills or a parent types instead of a name. «اليوم
# الثاني مع طفلي» reads as the app talking about its own child; these get the
# unnamed copy. Production, 2026-11-06: «طفلي» is on 3,576 profiles.
_NOT_A_NAME = {"طفلي", "طفلتي", "ابني", "ابنتي", "بنتي", "ولدي", "طفل", "طفلة",
               "my child", "child", "baby", "kid", "test child", "no username required"}
_NAME_TRIM = " .،,!?؟-_:؛;\"'«»()"


def _display_name(name: Optional[str]) -> str:
    """A child's name fit for a notification title, or '' for the unnamed copy:
    no placeholders, nothing with digits or slashes (a birth date typed into
    the name field), nothing longer than a name."""
    n = " ".join((name or "").split()).strip(_NAME_TRIM)
    if not n or n.casefold() in _NOT_A_NAME or len(n) > 20:
        return ""
    if any(ch.isdigit() or ch in "/\\@#" for ch in n):
        return ""
    return n


def _audience() -> list:
    """Every device holding a push token and at least one child profile —
    read once per run (the triggers below share it)."""
    global _AUDIENCE
    if _AUDIENCE is not None:
        return _AUDIENCE
    conn = sqlite3.connect(DB_PATH)
    try:
        cols = {t: _columns(conn, t) for t in (
            "push_tokens", "child_profiles", "lesson_progress", "coach_tips",
            "followups", "push_sends", "chat_sessions", "daily_login_streaks",
            *(s.table for s in ACTION_SOURCES))}
        if not {"device_id", "token"} <= cols["push_tokens"] or "device_id" not in cols["child_profiles"]:
            _AUDIENCE = []
            return _AUDIENCE

        # The eval harness and the emulator E2E gate write to this database
        # too; their installs are not families (app/core/real_traffic.py).
        real = real_device_sql("device_id", e2e_devices(conn))
        tokens = {r[0] for r in conn.execute(
            f"SELECT device_id FROM push_tokens WHERE token IS NOT NULL AND token != '' AND {real}")}

        first: dict = {}
        latest: dict = {}
        for dev, created, updated, name, age in conn.execute(
                "SELECT device_id, datetime(created_at), datetime(COALESCE(updated_at, created_at)), "
                "name, age_group FROM child_profiles WHERE device_id IS NOT NULL"):
            if dev not in tokens:
                continue
            c = _ts(created)
            if c is None:
                continue
            if dev not in first or c < first[dev]:
                first[dev] = c
            u = _ts(updated) or c
            if dev not in latest or u >= latest[dev][0]:
                latest[dev] = (u, _display_name(name), age)

        seen: dict = {d: c for d, c in first.items()}

        def bump(sql: str) -> None:
            for dev, moment in conn.execute(sql):
                t = _ts(moment)
                if dev in seen and t is not None and t > seen[dev]:
                    seen[dev] = t

        for table, col in _SEEN_DAYS:
            if {"device_id", col} <= cols[table]:
                bump(f"SELECT device_id, MAX({_DAY_END.format(col=col)}) FROM {table} GROUP BY device_id")
        for table, col in _SEEN_MOMENTS:
            if {"device_id", col} <= cols[table]:
                bump(f"SELECT device_id, MAX(datetime({col})) FROM {table} GROUP BY device_id")
        for src in ACTION_SOURCES:
            if {"device_id", src.column} <= cols[src.table]:
                bump(f"SELECT device_id, MAX(datetime({src.column})) FROM {src.table} GROUP BY device_id")

        has_lesson = (
            {r[0] for r in conn.execute("SELECT DISTINCT device_id FROM lesson_progress")}
            if "device_id" in cols["lesson_progress"] else set())

        lang: dict = {}
        for table, order in (("followups", "rowid"), ("coach_tips", "date, rowid")):
            if {"device_id", "lang"} <= cols[table]:   # coach_tips last: it wins
                for dev, lg in conn.execute(
                        f"SELECT device_id, lang FROM {table} WHERE lang IS NOT NULL ORDER BY {order}"):
                    lang[dev] = lg

        sends: dict = {}
        if {"device_id", "kind", "sent_at"} <= cols["push_sends"]:
            marks = ",".join("?" * len(_REENGAGE_KINDS))
            for dev, kind, at in conn.execute(
                    f"SELECT device_id, kind, datetime(sent_at) FROM push_sends "
                    f"WHERE kind IN ({marks}) AND sent_at >= datetime('now', '-120 days')",
                    _REENGAGE_KINDS):
                t = _ts(at)
                if t is not None:
                    sends.setdefault(dev, []).append((kind, t))
    finally:
        conn.close()

    out = []
    for dev, c in first.items():
        last = seen[dev]
        mine = sorted((k, t) for k, t in sends.get(dev, []) if t > last)
        _, name, age = latest[dev]
        out.append(Device(
            device_id=dev, first_created=c, last_seen=last, lang=_lang(lang.get(dev)),
            child_name=name, age_group=age, has_lesson=dev in has_lesson,
            reengaged=tuple(sorted(t for _, t in mine)),
            win_backs=sum(1 for k, _ in mine if k == "win_back")))
    _AUDIENCE = out
    return out


# ── Copy ─────────────────────────────────────────────────────────────────
#
# Arabic in plain فصحى (the app's register — never a dialect), English for
# every family that uses the app in English. Nothing that is not true of this
# family: no «سلسلتك» to someone who never had a streak, no «درس جديد» when the
# lesson is the one they left, no minute counts the lessons do not keep.
# (title_named, title_plain, body_named, body_plain) per kind and language.
TEXT = {
    "first_lesson_activation": {
        "ar": ("خطوتك الأولى مع {name} 🌟", "خطوتك الأولى مع طفلك 🌟",
               "أعددنا لـ{name} أول درس تطبيقي، وهو قصير — ابدأ به الآن.",
               "أعددنا لطفلك أول درس تطبيقي، وهو قصير — ابدأ به الآن."),
        "en": ("Your first step with {name} 🌟", "Your first step with your child 🌟",
               "{name}'s first practical lesson is ready — a short one to begin with.",
               "Your child's first practical lesson is ready — a short one to begin with."),
    },
    "day_two": {
        "ar": ("اليوم الثاني مع {name} 🌱", "اليوم الثاني مع طفلك 🌱",
               "خطوة صغيرة اليوم تُثبّت ما بدأته أمس.",
               "خطوة صغيرة اليوم تُثبّت ما بدأته أمس."),
        "en": ("Day two with {name} 🌱", "Day two with your child 🌱",
               "One small step today builds on what you started yesterday.",
               "One small step today builds on what you started yesterday."),
    },
    "streak_at_risk": {
        "ar": ("رحلة {name} مستمرة 🤍", "رحلتك التربوية مستمرة 🤍",
               "درس قصير يكمل ما بدأته، في الوقت الذي يناسبك.",
               "درس قصير يكمل ما بدأته، في الوقت الذي يناسبك."),
        "en": ("{name}'s journey continues 🤍", "Your parenting journey continues 🤍",
               "A short lesson picks up where you left off, whenever suits you.",
               "A short lesson picks up where you left off, whenever suits you."),
    },
    "win_back": {
        "ar": ("اشتقنا إليك 🤍", "اشتقنا إليك 🤍",
               "طريق {name} ونصيحة اليوم في انتظارك متى عدت.",
               "نصيحة اليوم في انتظارك متى عدت."),
        "en": ("We miss you 🤍", "We miss you 🤍",
               "{name}'s path and today's tip are here whenever you're ready.",
               "Today's tip is here whenever you're ready."),
    },
}


def _copy(kind: str, dev: Device) -> tuple:
    t_named, t_plain, b_named, b_plain = TEXT[kind][dev.lang]
    name = dev.child_name
    if name:
        return t_named.format(name=name), b_named.format(name=name)
    return t_plain, b_plain


def _push(kind: str, dev: Device) -> None:
    title, body = _copy(kind, dev)
    _send(device_id=dev.device_id, title=title, body=body,
          data={"type": kind, "link": _deep_link_for(dev.age_group)})


def _recently_pushed() -> set:
    """Devices already pushed within CAP_DAYS — the frequency cap.

    Without this, "one push a day" still means a permanently-lapsed device is
    nudged every single evening forever: streak_at_risk fires on >36h idle and
    win_back on >5 days idle, and neither condition ever stops being true for
    someone who has stopped using the app. Halving the volume does not change
    that; remembering what we already sent does.

    Three days is a starting value, not a measured one — CAP_DAYS is a flag and
    the run logs how many devices it filtered, so it can be tightened against
    numbers in a month rather than guessed at twice.
    """
    cutoff = (datetime.utcnow() - timedelta(days=CAP_DAYS)).isoformat()
    return recently_pushed_since(cutoff)


def first_lesson_activation(skip: set | None = None) -> set:
    """Families whose first child was added 2–36h ago and who have not opened
    a single lesson: point them at the first one."""
    skip = skip or set()
    now = datetime.utcnow()
    sent: set = set()
    for dev in _audience():
        if dev.device_id in skip or dev.has_lesson:
            continue
        if not (now - timedelta(hours=36) <= dev.first_created <= now - timedelta(hours=2)):
            continue
        _push("first_lesson_activation", dev)
        sent.add(dev.device_id)
    return sent


def day_two(skip: set | None = None) -> set:
    """Families who started a lesson on their first day and have not been back
    for 12h, on their second evening. 69% of new families act on day 0 and
    ~88% are not seen on day 1 (cohorts 21 Sep – 19 Oct) — and until this,
    nothing reached them until streak_at_risk on the third evening."""
    skip = skip or set()
    now = datetime.utcnow()
    sent: set = set()
    for dev in _audience():
        if dev.device_id in skip or not dev.has_lesson:
            continue
        if not (now - NEW_FAMILY <= dev.first_created <= now - timedelta(hours=18)):
            continue
        if dev.last_seen > now - timedelta(hours=12):
            continue
        _push("day_two", dev)
        sent.add(dev.device_id)
    return sent


def streak_at_risk(skip: set | None = None) -> set:
    """The gentle nudge: not seen for 36h–7 days. (The kind keeps its old
    name so push_sends and the reports read across the change; the copy no
    longer mentions a streak.) At most two per absence."""
    skip = skip or set()
    now = datetime.utcnow()
    sent: set = set()
    for dev in _audience():
        if dev.device_id in skip or dev.first_created > now - NEW_FAMILY:
            continue
        idle = now - dev.last_seen
        if not (NUDGE_AFTER <= idle < NUDGE_UNTIL) or len(dev.reengaged) >= 2:
            continue
        _push("streak_at_risk", dev)
        sent.add(dev.device_id)
    return sent


def win_back(skip: set | None = None) -> set:
    """Not seen for 7–60 days: at most WIN_BACK_MAX win_backs and REENGAGE_MAX
    re-engagement pushes in all per absence, a week apart. Then silence until
    the family opens the app again — which resets the count."""
    skip = skip or set()
    now = datetime.utcnow()
    sent: set = set()
    for dev in _audience():
        if dev.device_id in skip:
            continue
        idle = now - dev.last_seen
        if not (NUDGE_UNTIL <= idle < WIN_BACK_UNTIL):
            continue
        if dev.win_backs >= WIN_BACK_MAX or len(dev.reengaged) >= REENGAGE_MAX:
            continue
        if dev.reengaged and now - dev.reengaged[-1] < WIN_BACK_GAP:
            continue
        _push("win_back", dev)
        sent.add(dev.device_id)
    return sent


# Grep-able in /var/log/tg-push.log: printed whenever the fold could not run.
RETENTION_ALERT = "ALERT referral-click-retention"


def _load_compactor():
    from app.services.attribution import compact_referral_clicks
    return compact_referral_clicks


def fold_referral_clicks(dry_run: bool = False) -> int | None:
    """Daily housekeeping that needs no cron of its own: raw referral clicks
    (IP + user agent) older than a week fold into per-code daily counts.

    This is the only thing that enforces that seven-day retention, so it runs
    before the pushes and a failure here is loud: an ALERT line on stderr and,
    from main(), a non-zero exit — never a silent skip. The import is guarded
    because ops/scripts reaches the host by `git reset` alone while the backend
    is baked into the image; a deploy that stops between the two leaves this
    script newer than its backend, and the pushes must still go out.
    Returns the number of rows folded, or None when the fold could not run.
    """
    try:
        compact = _load_compactor()
    except ImportError as e:
        print(f"{RETENTION_ALERT}: the backend predates compact_referral_clicks ({e}); "
              "raw IP/user-agent rows are NOT being expired", file=sys.stderr, flush=True)
        return None
    try:
        folded = compact(dry_run=dry_run)
    except Exception as e:  # noqa: BLE001
        print(f"{RETENTION_ALERT}: compaction failed ({type(e).__name__}: {e}); "
              "raw IP/user-agent rows are NOT being expired", file=sys.stderr, flush=True)
        return None
    verb = "would fold" if dry_run else "folded"
    print(f"  -> referral clicks: {verb} {folded} raw rows into daily counts")
    return folded


# Grep-able in /var/log/tg-push.log: printed whenever the housekeeping failed.
HOUSEKEEPING_ALERT = "ALERT privacy-housekeeping"


def privacy_housekeeping(dry_run: bool = False) -> bool:
    """Retention the privacy policy promises (backend/app/services/retention.py),
    once a day, here rather than as a side effect of traffic — no cron line of
    its own. With `dry_run` nothing is deleted and the counts are printed.

    Never raises: it runs in main()'s `finally`, and an exception there would
    hide whatever the pushes raised. A failure is an ALERT line on stderr and a
    False return (exit 1) — never a silent skip.
    """
    try:
        from app.services.retention import has_errors, run_housekeeping
    except ImportError as e:
        # Same skew as the fold's: ops/scripts can be newer than the image.
        print(f"{HOUSEKEEPING_ALERT}: the backend predates the retention module ({e}); "
              "nothing was deleted", file=sys.stderr, flush=True)
        return False
    try:
        results = run_housekeeping(dry_run=dry_run)
    except Exception as e:  # noqa: BLE001
        print(f"{HOUSEKEEPING_ALERT}: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
        return False
    verb = "would delete" if dry_run else "deleted"
    print(f"  -> privacy housekeeping ({verb}): "
          + ", ".join(f"{k}={v}" for k, v in results.items()))
    if has_errors(results):
        failed = ", ".join(k for k, v in results.items()
                           if isinstance(v, str) and v.startswith("error"))
        print(f"{HOUSEKEEPING_ALERT}: failed steps: {failed}", file=sys.stderr, flush=True)
        return False
    return True


def main(argv=None) -> int:
    global BASE_URL, DRY_RUN, FORCE, CAP_DAYS, _AUDIENCE
    args = _parse_args(argv)
    _AUDIENCE = None
    BASE_URL = args.base_url.rstrip("/")
    DRY_RUN = args.dry_run
    FORCE = args.force
    CAP_DAYS = args.cap_days

    hour = datetime.utcnow().hour
    print(f"[{datetime.utcnow().isoformat()}] cron_push_triggers starting (UTC hour={hour})")

    # Retention first, whatever the hour and whatever the pushes do next.
    folded = fold_referral_clicks(dry_run=DRY_RUN)

    # Evening re-engagement at 17 UTC (≈20:00 القاهرة والرياض — بعد المغرب،
    # وليس 23:00/منتصف الليل كما كانت 20 UTC). One push per device per day, and
    # at most one per CAP_DAYS days.
    #
    # --force exists because without it this is only testable inside a
    # sixty-minute window once a day: --dry-run printed nothing at any other
    # hour, which made "did the change work?" unanswerable until tomorrow.
    housekeeping_ok = False
    try:
        if FORCE or 17 <= hour < 18:
            skip = _recently_pushed()
            print(f"  -> first_lesson_activation + day_two + streak_at_risk + win_back "
                  f"(deduped, {len(skip)} capped)")
            done = set(skip)
            for trigger in (first_lesson_activation, day_two, streak_at_risk, win_back):
                got = trigger(skip=done) or set()
                print(f"     {trigger.__name__}: {len(got)}")
                done |= got
        else:
            print("  -> outside the 17 UTC window; no pushes (use --force to test)")
    finally:
        # Every run, whatever the hour and whatever the pushes did or raised
        # (PR #26 review F8): retention does not wait on re-engagement.
        housekeeping_ok = privacy_housekeeping(dry_run=DRY_RUN)

    print("done")
    if folded is None:
        return 2            # the referral-click fold could not run (ALERT above)
    return 0 if housekeeping_ok else 1


if __name__ == "__main__":
    sys.exit(main())
