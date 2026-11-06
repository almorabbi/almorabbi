import sqlite3
from datetime import datetime, timedelta
from unittest.mock import patch

import pytest

import ops.scripts.cron_push_triggers as cpt


@pytest.fixture
def mock_db(tmp_path, monkeypatch):
    db_file = tmp_path / "test.db"
    conn = sqlite3.connect(db_file)
    conn.execute(
        """
        CREATE TABLE child_profiles (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            name TEXT,
            age_group TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE push_tokens (
            device_id TEXT PRIMARY KEY,
            token TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE lesson_progress (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            lesson_id TEXT NOT NULL,
            completed_at TEXT
        )
        """
    )
    conn.commit()
    conn.close()

    monkeypatch.setattr(cpt, "DB_PATH", db_file)
    monkeypatch.setattr(cpt, "_AUDIENCE", None)
    return db_file


def test_first_lesson_activation_targeting(mock_db):
    now = datetime.utcnow()
    t_1h_ago = (now - timedelta(hours=1)).isoformat()
    t_5h_ago = (now - timedelta(hours=5)).isoformat()
    t_40h_ago = (now - timedelta(hours=40)).isoformat()

    conn = sqlite3.connect(mock_db)
    # Dev1: Registered 5h ago, has token, NO lesson progress -> SHOULD RECEIVE
    conn.execute("INSERT INTO push_tokens VALUES ('dev1', 'tok1')")
    conn.execute("INSERT INTO child_profiles VALUES ('c1', 'dev1', 'عمر', '4-6', ?, ?)", (t_5h_ago, t_5h_ago))

    # Dev2: Registered 1h ago (<2h) -> SHOULD NOT RECEIVE YET
    conn.execute("INSERT INTO push_tokens VALUES ('dev2', 'tok2')")
    conn.execute("INSERT INTO child_profiles VALUES ('c2', 'dev2', 'سارة', '2-3', ?, ?)", (t_1h_ago, t_1h_ago))

    # Dev3: Registered 40h ago (>36h) -> SHOULD NOT RECEIVE (streak_at_risk will handle)
    conn.execute("INSERT INTO push_tokens VALUES ('dev3', 'tok3')")
    conn.execute("INSERT INTO child_profiles VALUES ('c3', 'dev3', 'زين', '7-9', ?, ?)", (t_40h_ago, t_40h_ago))

    # Dev4: Registered 5h ago, but HAS lesson progress -> SHOULD NOT RECEIVE
    conn.execute("INSERT INTO push_tokens VALUES ('dev4', 'tok4')")
    conn.execute("INSERT INTO child_profiles VALUES ('c4', 'dev4', 'كريم', '4-6', ?, ?)", (t_5h_ago, t_5h_ago))
    conn.execute("INSERT INTO lesson_progress VALUES ('lp1', 'dev4', 'lesson_1', ?)", (t_5h_ago,))

    # Dev5: Registered 5h ago, no push token -> SHOULD NOT RECEIVE
    conn.execute("INSERT INTO child_profiles VALUES ('c5', 'dev5', 'يوسف', '4-6', ?, ?)", (t_5h_ago, t_5h_ago))

    conn.commit()
    conn.close()

    sent_pushes = []

    def mock_send(device_id, title, body, data):
        sent_pushes.append({"device_id": device_id, "title": title, "body": body, "data": data})
        return {"ok": True}

    with patch.object(cpt, "_send", side_effect=mock_send):
        # Test normal call
        sent_set = cpt.first_lesson_activation()
        assert sent_set == {"dev1"}
        assert len(sent_pushes) == 1
        push = sent_pushes[0]
        assert push["device_id"] == "dev1"
        assert "عمر" in push["body"]
        assert push["data"]["type"] == "first_lesson_activation"
        assert push["data"]["link"] == "/p/path_4-6_islamic_parenting_bond"

        # Test skip set respects frequency cap
        sent_pushes.clear()
        sent_set_skipped = cpt.first_lesson_activation(skip={"dev1"})
        assert sent_set_skipped == set()
        assert len(sent_pushes) == 0


# ── The audience: every open signal, windows a family can leave ─────────

NOW = datetime(2026, 11, 6, 17, 5)


class _Clock(datetime):
    @classmethod
    def utcnow(cls):
        return NOW


def _ago(**kw) -> str:
    return (NOW - timedelta(**kw)).strftime("%Y-%m-%d %H:%M:%S")


@pytest.fixture
def full_db(tmp_path, monkeypatch):
    """The production shapes of every table the audience reads."""
    db_file = tmp_path / "full.db"
    conn = sqlite3.connect(db_file)
    conn.executescript(
        """
        CREATE TABLE child_profiles (id TEXT PRIMARY KEY, device_id TEXT, name TEXT,
            age_group TEXT, created_at TEXT, updated_at TEXT);
        CREATE TABLE push_tokens (device_id TEXT PRIMARY KEY, token TEXT, updated_at TEXT);
        CREATE TABLE lesson_progress (id TEXT, device_id TEXT, lesson_id TEXT,
            started_at TEXT, completed_at TEXT, updated_at TEXT);
        CREATE TABLE daily_login_streaks (device_id TEXT, child_id TEXT, date TEXT);
        CREATE TABLE coach_tips (device_id TEXT, date TEXT, lang TEXT);
        CREATE TABLE push_sends (id INTEGER PRIMARY KEY, device_id TEXT, kind TEXT,
            sent_at TEXT);
        """
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr(cpt, "DB_PATH", db_file)
    monkeypatch.setattr(cpt, "_AUDIENCE", None)
    monkeypatch.setattr(cpt, "datetime", _Clock)
    return db_file


def _family(db, dev, *, created, name="عمر", age="4-6", lesson_at=None, token_at=None):
    conn = sqlite3.connect(db)
    conn.execute("INSERT INTO push_tokens VALUES (?, 'tok', ?)", (dev, token_at or created))
    conn.execute("INSERT INTO child_profiles VALUES (?, ?, ?, ?, ?, ?)",
                 (f"c-{dev}", dev, name, age, created, created))
    if lesson_at:
        conn.execute("INSERT INTO lesson_progress VALUES (?, ?, 'l1', ?, NULL, ?)",
                     (f"lp-{dev}", dev, lesson_at, lesson_at))
    conn.commit()
    conn.close()


def _exec(db, sql, *params):
    conn = sqlite3.connect(db)
    conn.execute(sql, params)
    conn.commit()
    conn.close()


def _capture():
    sent = []

    def fake(device_id, title, body, data):
        sent.append({"device_id": device_id, "title": title, "body": body, "data": data})
        return {"ok": True}
    return sent, fake


def test_a_family_seen_today_is_not_at_risk_even_without_a_lesson(full_db):
    # The old query read lesson_progress alone: a parent who opened the app
    # yesterday evening, but whose last lesson was ten days ago, was nudged.
    _family(full_db, "seen", created=_ago(days=30), lesson_at=_ago(days=10))
    _exec(full_db, "INSERT INTO daily_login_streaks VALUES ('seen', 'c', ?)",
          (NOW - timedelta(days=1)).strftime("%Y-%m-%d"))
    _family(full_db, "idle", created=_ago(days=30), lesson_at=_ago(days=3))
    sent, fake = _capture()
    with patch.object(cpt, "_send", side_effect=fake):
        assert cpt.streak_at_risk() == {"idle"}


def test_a_calendar_day_counts_as_its_end(full_db):
    # Opened the app on day D (stored as a date). At 17:05 on D+1 that is at
    # most ~41h ago only if read as 00:00 — it must not be "36h idle".
    _family(full_db, "d", created=_ago(days=30), lesson_at=_ago(days=10))
    _exec(full_db, "INSERT INTO coach_tips VALUES ('d', ?, 'ar')",
          (NOW - timedelta(days=1)).strftime("%Y-%m-%d"))
    assert cpt._audience()[0].last_seen == datetime(2026, 11, 5, 23, 59, 59)


def test_nudge_window_and_its_per_absence_limit(full_db):
    _family(full_db, "d3", created=_ago(days=30), lesson_at=_ago(days=3))
    _family(full_db, "d1", created=_ago(days=30), lesson_at=_ago(hours=20))
    _family(full_db, "d9", created=_ago(days=30), lesson_at=_ago(days=9))
    _family(full_db, "tired", created=_ago(days=30), lesson_at=_ago(days=6))
    for days in (4, 2):  # two nudges already in this absence
        _exec(full_db, "INSERT INTO push_sends (device_id, kind, sent_at) VALUES "
              "('tired', 'streak_at_risk', ?)", _ago(days=days))
    sent, fake = _capture()
    with patch.object(cpt, "_send", side_effect=fake):
        assert cpt.streak_at_risk() == {"d3"}


def test_new_families_are_left_to_the_new_family_pushes(full_db):
    _family(full_db, "new", created=_ago(hours=40), lesson_at=_ago(hours=39))
    with patch.object(cpt, "_send", side_effect=_capture()[1]):
        assert cpt.streak_at_risk() == set()


def test_win_back_stops_after_a_fixed_number_of_tries(full_db):
    _family(full_db, "fresh", created=_ago(days=40), lesson_at=_ago(days=20))
    _family(full_db, "nagged", created=_ago(days=40), lesson_at=_ago(days=20))
    for days in (17, 14, 11, 8):  # the old cron: every three days
        _exec(full_db, "INSERT INTO push_sends (device_id, kind, sent_at) VALUES "
              "('nagged', 'streak_at_risk', ?)", _ago(days=days))
    _family(full_db, "twice", created=_ago(days=60), lesson_at=_ago(days=30))
    for days in (20, 10):
        _exec(full_db, "INSERT INTO push_sends (device_id, kind, sent_at) VALUES "
              "('twice', 'win_back', ?)", _ago(days=days))
    _family(full_db, "recent", created=_ago(days=40), lesson_at=_ago(days=20))
    _exec(full_db, "INSERT INTO push_sends (device_id, kind, sent_at) VALUES "
          "('recent', 'win_back', ?)", _ago(days=3))
    _family(full_db, "gone", created=_ago(days=200), lesson_at=_ago(days=90))
    sent, fake = _capture()
    with patch.object(cpt, "_send", side_effect=fake):
        assert cpt.win_back() == {"fresh"}


def test_coming_back_resets_the_count(full_db):
    # Four pushes during an earlier absence; the family came back 9 days ago.
    _family(full_db, "back", created=_ago(days=60), lesson_at=_ago(days=9))
    for days in (30, 25, 20, 15):
        _exec(full_db, "INSERT INTO push_sends (device_id, kind, sent_at) VALUES "
              "('back', 'win_back', ?)", _ago(days=days))
    with patch.object(cpt, "_send", side_effect=_capture()[1]):
        assert cpt.win_back() == {"back"}


def test_day_two_reaches_the_family_that_started_and_did_not_return(full_db):
    _family(full_db, "gone", created=_ago(hours=30), lesson_at=_ago(hours=29))
    _family(full_db, "here", created=_ago(hours=30), lesson_at=_ago(hours=2))
    _family(full_db, "nolesson", created=_ago(hours=30))
    _family(full_db, "old", created=_ago(days=5), lesson_at=_ago(days=4))
    sent, fake = _capture()
    with patch.object(cpt, "_send", side_effect=fake):
        assert cpt.day_two() == {"gone"}
    assert sent[0]["data"] == {"type": "day_two", "link": "/p/path_4-6_islamic_parenting_bond"}
    assert "عمر" in sent[0]["title"]


def test_the_copy_follows_the_family_language(full_db):
    _family(full_db, "en", created=_ago(days=30), name="Sara", lesson_at=_ago(days=3))
    _exec(full_db, "INSERT INTO coach_tips VALUES ('en', ?, 'en')", _ago(days=4)[:10])
    _family(full_db, "ar", created=_ago(days=30), name="", lesson_at=_ago(days=3))
    sent, fake = _capture()
    with patch.object(cpt, "_send", side_effect=fake):
        cpt.streak_at_risk()
    by = {s["device_id"]: s for s in sent}
    assert by["en"]["title"] == "Sara's journey continues 🤍"
    assert by["ar"]["title"] == "رحلتك التربوية مستمرة 🤍"


def test_one_push_per_device_per_run(full_db, monkeypatch):
    # A brand-new family with no lesson qualifies for activation only; the
    # chain in main() must not hand it a second push.
    _family(full_db, "new", created=_ago(hours=20))
    _family(full_db, "idle", created=_ago(days=30), lesson_at=_ago(days=3))
    monkeypatch.setattr(cpt, "fold_referral_clicks", lambda dry_run=False: 0)
    monkeypatch.setattr(cpt, "privacy_housekeeping", lambda dry_run=False: True)
    monkeypatch.setattr(cpt, "_recently_pushed", lambda: set())
    sent, fake = _capture()
    with patch.object(cpt, "_send", side_effect=fake):
        assert cpt.main([]) == 0
    kinds = sorted((s["device_id"], s["data"]["type"]) for s in sent)
    assert kinds == [("idle", "streak_at_risk"), ("new", "first_lesson_activation")]


_DIALECT = ("دلوقتي", "الحين", "ياخد", "مشتاقين", "ادخل", "عايز", "بتاع")
_ARABIC = __import__("re").compile(r"[\u0600-\u06FF]")


def test_copy_is_plain_fusha_and_english_carries_no_arabic():
    for kind, langs in cpt.TEXT.items():
        assert set(langs) == {"ar", "en"}, kind
        for text in langs["ar"]:
            assert not any(w in text for w in _DIALECT), (kind, text)
            assert "سلسلت" not in text and "درس جديد" not in text, (kind, text)
        for text in langs["en"]:
            assert not _ARABIC.search(text), (kind, text)


def test_placeholders_and_junk_are_not_names():
    assert cpt._display_name("  رغد. ") == "رغد"
    for junk in ("طفلي", "My child", "يحيى شهر 4/يوم 12/عام 2026", "", None, "a" * 25):
        assert cpt._display_name(junk) == "", junk


def test_e2e_installs_get_no_pushes(full_db):
    _family(full_db, "e2e", created=_ago(days=30), name="E2E-Maestro", lesson_at=_ago(days=3))
    _family(full_db, "twin", created=_ago(days=30), name="", lesson_at=_ago(days=3))
    _exec(full_db, "UPDATE push_tokens SET token = 'shared' WHERE device_id IN ('e2e', 'twin')")
    _family(full_db, "real", created=_ago(days=30), lesson_at=_ago(days=3))
    with patch.object(cpt, "_send", side_effect=_capture()[1]):
        assert cpt.streak_at_risk() == {"real"}
