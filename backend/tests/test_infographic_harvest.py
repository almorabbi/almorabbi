"""scripts/generate_missing_infographics.py — the harvest must finish and remember.

Until 2026-09-29 the task list was saved only after the LAST poll; ~35 dead
tasks outran the cron's `timeout 600` every day, so no drop decision ever
survived. These tests pin: persistence after every poll, a clean budget exit,
and pruning of old / failed / thrice-erroring tasks. No CLI is ever called —
poll() and download() are replaced.
"""
import importlib.util
import json
import sys
import types
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]

# These test repo-level scripts/ (the NotebookLM pipeline). The deploy gate runs
# pytest inside the backend image, which does not ship scripts/ — skip there.
pytestmark = pytest.mark.skipif(
    not (REPO / "scripts" / "cron_gen_en_media.sh").exists(),
    reason="scripts/ not present (backend-only image)",
)

SCRIPT = REPO / "scripts" / "generate_missing_infographics.py"


@pytest.fixture
def gmi(tmp_path, monkeypatch):
    monkeypatch.setattr(sys, "argv", ["generate_missing_infographics.py"])
    spec = importlib.util.spec_from_file_location("gmi_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    data = tmp_path / "ops" / "data"
    monkeypatch.setattr(mod, "STATE_FILE", data / "infographic_tasks.json")
    monkeypatch.setattr(mod, "ERRORS_FILE", data / "infographic_poll_errors.json")
    monkeypatch.setattr(mod, "META_FILE", data / "infographic_task_meta.json")
    monkeypatch.setattr(mod, "INFO_DIR", tmp_path / "infographics")
    monkeypatch.setattr(mod, "INDEX_PATH", tmp_path / "lesson_index.json")
    monkeypatch.setattr(mod, "BLOCKED_PATH", tmp_path / "blocked.json")
    monkeypatch.setattr(mod, "LANG", "en")
    # never reach a real NotebookLM from a test: "unreadable" = do not filter
    monkeypatch.setattr(mod, "live_source_ids", lambda nb: None)
    return mod


def _disk(mod):
    return (json.loads(mod.STATE_FILE.read_text()),
            json.loads(mod.ERRORS_FILE.read_text()),
            json.loads(mod.META_FILE.read_text()))


class Killed(Exception):
    """Stands in for `timeout` killing the process mid-loop."""


def test_decisions_are_persisted_after_each_poll(gmi, monkeypatch):
    state = {"a@en": "task-a", "b@en": "task-b", "c@en": "task-c"}
    errors = {"a@en": 2, "b@en": 2, "c@en": 2}
    meta = {"a@en": {"first_seen": 1000, "last_polled": 1},
            "b@en": {"first_seen": 1000, "last_polled": 2},
            "c@en": {"first_seen": 1000, "last_polled": 3}}
    calls = []

    def poll(task_id):
        calls.append(task_id)
        if len(calls) == 2:
            raise Killed
        return "error"

    monkeypatch.setattr(gmi, "poll", poll)
    with pytest.raises(Killed):
        gmi.harvest(state, errors, meta, lambda *a: None,
                    budget_seconds=0, max_age_days=0, wall=lambda: 2000)
    on_disk, errs, m = _disk(gmi)
    # the third strike on task-a survived the "kill" during task-b's poll
    assert "a@en" not in on_disk and "a@en" not in errs and "a@en" not in m
    assert on_disk == {"b@en": "task-b", "c@en": "task-c"}
    assert errs == {"b@en": 2, "c@en": 2}
    # atomic writes leave no temp files behind
    assert not list(gmi.STATE_FILE.parent.glob(".*.tmp.*"))


def test_budget_stops_cleanly_and_reports_what_is_left(gmi, monkeypatch, capsys):
    state = {f"l{i}@en": f"t{i}" for i in range(5)}
    state["ar_only"] = "t-ar"  # another language's task is never polled
    t = {"now": 0.0}

    def poll(task_id):
        t["now"] += 100
        return "in_progress"

    monkeypatch.setattr(gmi, "poll", poll)
    downloaded, left = gmi.harvest(state, {}, {}, lambda *a: None,
                                   budget_seconds=250, max_age_days=7,
                                   clock=lambda: t["now"], wall=lambda: 5000)
    assert (downloaded, left) == (0, 2)  # polls at t=0,100,200; stop at 300
    out = capsys.readouterr().out
    assert "2 task(s) left unpolled" in out
    on_disk, _errs, meta = _disk(gmi)
    assert on_disk == state
    polled = [k for k, v in meta.items() if "last_polled" in v]
    assert len(polled) == 3
    assert "ar_only" not in meta


def test_budget_rotates_least_recently_polled_first(gmi, monkeypatch):
    state = {"old@en": "t-old", "new@en": "t-new", "never@en": "t-never"}
    meta = {"old@en": {"first_seen": 0, "last_polled": 10},
            "new@en": {"first_seen": 0, "last_polled": 99}}
    seen = []
    monkeypatch.setattr(gmi, "poll", lambda tid: seen.append(tid) or "in_progress")
    gmi.harvest(state, {}, meta, lambda *a: None, budget_seconds=0,
                max_age_days=0, wall=lambda: 100)
    assert seen == ["t-never", "t-old", "t-new"]


def test_pruning_by_age_errors_and_failure(gmi, monkeypatch):
    day = 86400
    now = 100 * day
    state = {"stale@en": "t-stale", "young@en": "t-young", "dead@en": "t-dead",
             "failed@en": "t-failed", "done_old@en": "t-done"}
    errors = {"dead@en": 2}
    meta = {"stale@en": {"first_seen": now - 8 * day},
            "young@en": {"first_seen": now - 1 * day},
            "dead@en": {"first_seen": now},
            "failed@en": {"first_seen": now},
            "done_old@en": {"first_seen": now - 30 * day}}
    status = {"t-stale": "in_progress", "t-young": "in_progress",
              "t-dead": "error", "t-failed": "failed", "t-done": "completed"}
    monkeypatch.setattr(gmi, "poll", lambda tid: status[tid])
    monkeypatch.setattr(gmi, "download", lambda tid, lid: None)  # download fails
    gmi.harvest(state, errors, meta, lambda *a: None, budget_seconds=0,
                max_age_days=7, wall=lambda: now)
    on_disk, errs, m = _disk(gmi)
    # a completed task whose download failed is retried, never aged out
    assert on_disk == {"young@en": "t-young", "done_old@en": "t-done"}
    assert errs == {}
    assert set(m) == {"young@en", "done_old@en"}


def test_completed_task_is_downloaded_and_removed(gmi, monkeypatch):
    state = {"x@en": "t-x"}
    attached = []
    monkeypatch.setattr(gmi, "poll", lambda tid: "completed")
    monkeypatch.setattr(gmi, "download", lambda tid, lid: {"id": tid})
    downloaded, left = gmi.harvest(state, {}, {}, lambda lid, a: attached.append(lid),
                                   budget_seconds=0, max_age_days=7)
    assert (downloaded, left) == (1, 0)
    assert attached == ["x"]
    assert _disk(gmi)[0] == {}


def test_harvest_only_main_exits_zero_when_budget_is_spent(gmi, monkeypatch, capsys):
    gmi.STATE_FILE.parent.mkdir(parents=True)
    gmi.STATE_FILE.write_text(json.dumps({"a@en": "t-a", "b@en": "t-b"}))
    gmi.INDEX_PATH.write_text(json.dumps({"lessons": []}))
    t = {"now": 0.0}

    def poll(task_id):
        t["now"] += 1000
        return "in_progress"

    fake_time = types.SimpleNamespace(monotonic=lambda: t["now"], time=lambda: 5000.0,
                                      sleep=lambda s: None)
    monkeypatch.setattr(gmi, "time", fake_time)
    monkeypatch.setattr(gmi, "poll", poll)
    monkeypatch.setattr(sys, "argv", ["x", "--lang", "en", "--harvest-only",
                                      "--budget-seconds", "10"])
    assert gmi.main() in (None, 0)
    out = capsys.readouterr().out
    assert "1 not polled this run (budget)" in out
    assert json.loads(gmi.STATE_FILE.read_text()) == {"a@en": "t-a", "b@en": "t-b"}


def test_trigger_only_run_does_not_touch_index_or_commit(gmi, monkeypatch, capsys):
    """Regression for daily empty commits: queuing --no-wait tasks (triggered > 0)
    with zero downloaded/recovered assets must NOT rewrite lesson_index.json or
    create a git commit that only bumps metadata.updated_at.
    """
    gmi.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    initial_index = {
        "metadata": {
            "updated_at": "2026-09-29T00:00:00Z",
            "coverage": {"infographics": "0/2"},
        },
        "lessons": [
            {"lesson_id": "L1", "assets": {}},
            {"lesson_id": "L2", "assets": {}},
        ],
    }
    raw_before = json.dumps(initial_index, indent=2)
    gmi.INDEX_PATH.write_text(raw_before, encoding="utf-8")

    monkeypatch.setattr(gmi, "reverse_source_map", lambda: {"L1": "src-1", "L2": "src-2"})
    monkeypatch.setattr(
        gmi,
        "missing_infographic_lessons",
        lambda: [{"lesson_id": "L1"}, {"lesson_id": "L2"}],
    )
    monkeypatch.setattr(gmi, "existing_asset", lambda lesson: None)
    monkeypatch.setattr(gmi, "trigger", lambda lesson, src: f"task-{lesson['lesson_id']}")

    git_calls = []
    monkeypatch.setattr(
        gmi.subprocess,
        "run",
        lambda cmd, *a, **kw: git_calls.append(cmd),
    )
    fake_time = types.SimpleNamespace(
        monotonic=lambda: 0.0,
        time=lambda: 12345.0,
        sleep=lambda s: None,
    )
    monkeypatch.setattr(gmi, "time", fake_time)
    monkeypatch.setattr(sys, "argv", ["x", "--lang", "en", "--limit", "2"])

    assert gmi.main() in (None, 0)
    out = capsys.readouterr().out
    assert "Triggered this run: 2 (+0 recovered from disk)" in out
    assert "Nothing new to register — skipping commit." in out
    assert git_calls == []
    assert gmi.INDEX_PATH.read_text(encoding="utf-8") == raw_before
    on_disk, _errs, _meta = _disk(gmi)
    assert on_disk == {"L1@en": "task-L1", "L2@en": "task-L2"}


def test_harvest_only_zero_downloads_does_not_dirty_index(gmi, monkeypatch):
    gmi.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    gmi.STATE_FILE.write_text(json.dumps({"L1@en": "t-1"}))
    initial_index = {
        "metadata": {"updated_at": "2026-09-29T00:00:00Z"},
        "lessons": [{"lesson_id": "L1", "assets": {}}],
    }
    raw_before = json.dumps(initial_index, indent=2)
    gmi.INDEX_PATH.write_text(raw_before, encoding="utf-8")

    monkeypatch.setattr(gmi, "poll", lambda tid: "in_progress")
    git_calls = []
    monkeypatch.setattr(gmi.subprocess, "run", lambda cmd, *a, **kw: git_calls.append(cmd))
    monkeypatch.setattr(sys, "argv", ["x", "--lang", "en", "--harvest-only"])

    assert gmi.main() in (None, 0)
    assert git_calls == []
    assert gmi.INDEX_PATH.read_text(encoding="utf-8") == raw_before


def test_downloaded_and_recovered_assets_commit_exact_registered_count(gmi, monkeypatch):
    gmi.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    gmi.STATE_FILE.write_text(json.dumps({"L1@en": "t-1"}))
    initial_index = {
        "metadata": {"updated_at": "2026-09-29T00:00:00Z"},
        "lessons": [
            {"lesson_id": "L1", "assets": {}},
            {"lesson_id": "L2", "assets": {}},
            {"lesson_id": "L3", "assets": {}},
        ],
    }
    gmi.INDEX_PATH.write_text(json.dumps(initial_index, indent=2), encoding="utf-8")

    monkeypatch.setattr(gmi, "poll", lambda tid: "completed")
    monkeypatch.setattr(
        gmi,
        "download",
        lambda tid, lid: {
            "id": f"{tid}_infographic",
            "file": f"docs/lesson_assets/infographics/{lid}.png",
            "language": "en",
        },
    )
    monkeypatch.setattr(gmi, "reverse_source_map", lambda: {"L2": "src-2", "L3": "src-3"})
    monkeypatch.setattr(
        gmi,
        "missing_infographic_lessons",
        lambda: [{"lesson_id": "L2"}, {"lesson_id": "L3"}],
    )
    monkeypatch.setattr(
        gmi,
        "existing_asset",
        lambda lesson: (
            {
                "id": "recov2_infographic",
                "file": "docs/lesson_assets/infographics/L2.png",
                "language": "en",
            }
            if lesson["lesson_id"] == "L2"
            else None
        ),
    )
    monkeypatch.setattr(gmi, "trigger", lambda lesson, src: "task-L3")

    git_calls = []
    monkeypatch.setattr(gmi.subprocess, "run", lambda cmd, *a, **kw: git_calls.append(cmd))
    fake_time = types.SimpleNamespace(
        monotonic=lambda: 0.0,
        time=lambda: 12345.0,
        sleep=lambda s: None,
    )
    monkeypatch.setattr(gmi, "time", fake_time)
    monkeypatch.setattr(sys, "argv", ["x", "--lang", "en"])

    assert gmi.main() in (None, 0)
    updated = json.loads(gmi.INDEX_PATH.read_text(encoding="utf-8"))
    assert updated["metadata"]["coverage"]["infographics"] == "2/3"
    assert updated["metadata"]["updated_at"] != "2026-09-29T00:00:00Z"
    commit_cmds = [c for c in git_calls if c[:2] == ["git", "commit"]]
    assert len(commit_cmds) == 1
    assert "register 2 NotebookLM infographics" in commit_cmds[0][-1]


def test_completed_harvest_for_already_registered_lesson_does_not_commit(gmi, monkeypatch):
    """If an in-flight task finishes (`completed`), downloads, and calls `attach()`,
    but that lesson's infographic for `--lang` is already in `lesson_index.json`
    (e.g. from an earlier disk recovery), `harvest()` must not increment
    `downloaded` and `_commit()` must not create a metadata-only commit."""
    gmi.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    gmi.STATE_FILE.write_text(json.dumps({"L1@en": "t-dup"}))
    initial_index = {
        "metadata": {"updated_at": "2026-09-29T00:00:00Z"},
        "lessons": [
            {
                "lesson_id": "L1",
                "assets": {
                    "infographics": [
                        {
                            "id": "t-dup_infographic",
                            "file": "docs/lesson_assets/infographics/en/L1.png",
                            "language": "en",
                        }
                    ]
                },
            }
        ],
    }
    raw_before = json.dumps(initial_index, indent=2) + "\n"
    gmi.INDEX_PATH.write_text(raw_before, encoding="utf-8")

    monkeypatch.setattr(gmi, "poll", lambda tid: "completed")
    monkeypatch.setattr(
        gmi,
        "download",
        lambda tid, lid: {
            "type": "infographic",
            "id": f"{tid}_infographic",
            "file": f"docs/lesson_assets/infographics/en/{lid}.png",
            "language": "en",
        },
    )

    git_calls = []
    monkeypatch.setattr(gmi.subprocess, "run", lambda cmd, *a, **kw: git_calls.append(cmd))
    monkeypatch.setattr(sys, "argv", ["x", "--lang", "en", "--harvest-only"])

    assert gmi.main() in (None, 0)
    assert git_calls == []
    assert gmi.INDEX_PATH.read_text(encoding="utf-8") == raw_before
    assert json.loads(gmi.STATE_FILE.read_text()) == {}


def test_secondary_notebook_id_from_source_map_is_passed_to_cli(gmi, tmp_path, monkeypatch):
    """Lessons whose source_to_lesson.json entry has a 4th element (v[3]) live on
    the overflow notebook; trigger(), poll(), and download() must pass that
    notebook ID via `-n` instead of the default NOTEBOOK_ID.
    """
    src_map = tmp_path / "source_to_lesson.json"
    secondary_nb = "a43c7a15-c5e0-46d0-9049-94c4d1a06030"
    src_map.write_text(
        json.dumps(
            {
                "src-primary": ["6-9", "topic", "L_primary"],
                "src-overflow": ["13-15", "topic", "L_overflow", secondary_nb],
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(gmi, "SRC_MAP_PATH", src_map)
    gmi.INFO_DIR.mkdir(parents=True, exist_ok=True)

    seen_notebooks = []

    def fake_run(args, timeout):
        nb_idx = args.index("-n") + 1
        seen_notebooks.append((args[0], args[nb_idx]))
        if args[0] == "generate":
            return 0, "Started: 11111111-2222-3333-4444-555555555555", ""
        if args[0] == "artifact":
            return 0, json.dumps({"status": "completed"}), ""
        if args[0] == "download":
            out_path = Path(args[2])
            out_path.write_bytes(b"x" * 15_000)
            return 0, "Artifact: Overflow Title (latest)", ""
        return 1, "", "unexpected"

    monkeypatch.setattr(gmi, "_run", fake_run)

    # 1. trigger on overflow lesson uses secondary_nb; primary uses NOTEBOOK_ID
    tid_overflow = gmi.trigger({"lesson_id": "L_overflow", "title": "T"}, "src-overflow")
    tid_primary = gmi.trigger({"lesson_id": "L_primary", "title": "T"}, "src-primary")
    assert tid_overflow == "11111111-2222-3333-4444-555555555555"
    assert tid_primary == "11111111-2222-3333-4444-555555555555"
    assert seen_notebooks[:2] == [
        ("generate", secondary_nb),
        ("generate", gmi.NOTEBOOK_ID),
    ]

    # 2. harvest poll + download on overflow lesson uses secondary_nb
    seen_notebooks.clear()
    state = {"L_overflow@en": tid_overflow}
    attached = []
    downloaded, left = gmi.harvest(
        state, {}, {}, lambda lid, a: attached.append((lid, a)),
        budget_seconds=0, max_age_days=7,
    )
    assert (downloaded, left) == (1, 0)
    assert len(attached) == 1 and attached[0][0] == "L_overflow"
    assert seen_notebooks == [
        ("artifact", secondary_nb),
        ("download", secondary_nb),
    ]


# ── 2026-10-29: a dead session is not a dead task, and "ran" is not "worked" ──


def test_dead_session_keeps_paid_tasks_counts_no_strike_and_stops(gmi, monkeypatch, capsys):
    state = {"a@en": "task-a", "b@en": "task-b", "c@en": "task-c"}
    errors = {"a@en": 2, "b@en": 2, "c@en": 2}
    meta = {k: {"first_seen": 1000, "last_polled": i} for i, k in enumerate(state)}
    calls = []

    def poll(task_id):
        calls.append(task_id)
        gmi._POLL_REASON[task_id] = "CSRF token not found in HTML"
        return "auth"

    monkeypatch.setattr(gmi, "poll", poll)
    downloaded, left = gmi.harvest(state, errors, meta, lambda *a: None,
                                   budget_seconds=0, max_age_days=0, wall=lambda: 2000)
    assert calls == ["task-a"]            # stopped at the first dead poll
    assert (downloaded, left) == (0, 3)
    on_disk, errs, _m = _disk(gmi)
    assert on_disk == {"a@en": "task-a", "b@en": "task-b", "c@en": "task-c"}
    assert errs == {"a@en": 2, "b@en": 2, "c@en": 2}   # no third strike
    assert gmi.SESSION["dead"] is True
    assert "session is dead (CSRF token not found in HTML)" in capsys.readouterr().out


def test_poll_tells_a_dead_session_from_a_gone_task(gmi, monkeypatch):
    dead = ('{"error": true, "code": "UNEXPECTED_ERROR", "message": '
            '"Unexpected error: CSRF token not found in HTML. Final URL: x"}')
    monkeypatch.setattr(gmi, "_run", lambda args, timeout: (2, dead, ""))
    assert gmi.poll("t1") == "auth"
    assert "CSRF token not found" in gmi._POLL_REASON["t1"]
    monkeypatch.setattr(gmi, "_run", lambda args, timeout: (1, "", "Artifact not found"))
    assert gmi.poll("t2") == "error"
    assert gmi._POLL_REASON["t2"] == "Artifact not found"


def test_harvest_only_exits_3_on_a_dead_session(gmi, monkeypatch):
    gmi.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    gmi.STATE_FILE.write_text(json.dumps({"L1@en": "t-1"}))
    gmi.INDEX_PATH.write_text(json.dumps({"lessons": []}))
    monkeypatch.setattr(gmi, "poll", lambda tid: "auth")
    monkeypatch.setattr(sys, "argv", ["x", "--lang", "en", "--harvest-only"])
    assert gmi.main() == 3
    assert json.loads(gmi.STATE_FILE.read_text()) == {"L1@en": "t-1"}


def _two_lessons(gmi, monkeypatch, trigger):
    gmi.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    gmi.INDEX_PATH.write_text(json.dumps({"lessons": [{"lesson_id": "L1"}, {"lesson_id": "L2"}]}))
    monkeypatch.setattr(gmi, "reverse_source_map", lambda: {"L1": "s1", "L2": "s2"})
    monkeypatch.setattr(gmi, "missing_infographic_lessons",
                        lambda: [{"lesson_id": "L1"}, {"lesson_id": "L2"}])
    monkeypatch.setattr(gmi, "existing_asset", lambda lesson: None)
    monkeypatch.setattr(gmi, "trigger", trigger)
    monkeypatch.setattr(gmi.subprocess, "run", lambda *a, **kw: None)
    monkeypatch.setattr(gmi, "time", types.SimpleNamespace(
        monotonic=lambda: 0.0, time=lambda: 1.0, sleep=lambda s: None))
    monkeypatch.setattr(sys, "argv", ["x", "--lang", "en"])


def test_auth_dead_trigger_stops_the_batch_and_exits_3(gmi, monkeypatch):
    seen = []

    def trigger(lesson, src):
        seen.append(lesson["lesson_id"])
        return "AUTHDEAD"

    _two_lessons(gmi, monkeypatch, trigger)
    assert gmi.main() == 3
    assert seen == ["L1"]                 # did not hammer the second lesson


def test_every_trigger_failing_without_a_refusal_exits_4(gmi, monkeypatch):
    _two_lessons(gmi, monkeypatch, lambda lesson, src: None)
    assert gmi.main() == 4


def test_a_rate_limited_run_that_triggered_nothing_still_exits_0(gmi, monkeypatch):
    _two_lessons(gmi, monkeypatch, lambda lesson, src: "RATELIMIT")
    assert gmi.main() == 0


def test_stale_source_is_skipped_reported_and_exits_4(gmi, monkeypatch, capsys):
    seen = []
    _two_lessons(gmi, monkeypatch, lambda lesson, src: seen.append(src) or "t")
    monkeypatch.setattr(gmi, "live_source_ids", lambda nb: {"someone-else"})
    assert gmi.main() == 4
    assert seen == []                     # never sent a phantom generate call
    assert "STALE SOURCE" in capsys.readouterr().out


def test_only_the_stale_lesson_is_skipped(gmi, monkeypatch):
    seen = []
    _two_lessons(gmi, monkeypatch, lambda lesson, src: seen.append(src) or f"t-{src}")
    monkeypatch.setattr(gmi, "live_source_ids", lambda nb: {"s2"})
    assert gmi.main() == 0
    assert seen == ["s2"]


def _real_module(monkeypatch):
    """A second copy of the script with its real live_source_ids (the fixture
    stubs that one out so no test ever reaches NotebookLM)."""
    monkeypatch.setattr(sys, "argv", ["generate_missing_infographics.py"])
    spec = importlib.util.spec_from_file_location("gmi_real_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_live_source_ids_reads_the_cli_and_flags_a_dead_session(monkeypatch, capsys):
    mod = _real_module(monkeypatch)
    ok = json.dumps({"sources": [{"id": "s1", "title": "x"}, {"id": "s2"}]})
    monkeypatch.setattr(mod, "_run", lambda args, timeout: (0, ok, ""))
    assert mod.live_source_ids("nb") == {"s1", "s2"}
    assert mod.SESSION["dead"] is False

    dead = json.dumps({"error": True, "message": "CSRF token not found in HTML."})
    monkeypatch.setattr(mod, "_run", lambda args, timeout: (2, dead, ""))
    assert mod.live_source_ids("nb") is None
    assert mod.SESSION["dead"] is True


def test_unreadable_source_list_means_do_not_filter(monkeypatch):
    mod = _real_module(monkeypatch)
    monkeypatch.setattr(mod, "_run", lambda args, timeout: (1, "", "502"))
    assert mod.live_source_ids("nb") is None
    monkeypatch.setattr(mod, "_run", lambda args, timeout: (0, "not json", ""))
    assert mod.live_source_ids("nb") is None
    monkeypatch.setattr(mod, "_run", lambda args, timeout: (0, '{"sources": []}', ""))
    assert mod.live_source_ids("nb") is None
    assert mod.SESSION["dead"] is False


def test_paged_source_list_means_do_not_filter(monkeypatch):
    mod = _real_module(monkeypatch)
    paged = json.dumps({"sources": [{"id": "s1"}], "next_page_token": "abc"})
    monkeypatch.setattr(mod, "_run", lambda args, timeout: (0, paged, ""))
    assert mod.live_source_ids("nb") is None


def test_successful_trigger_mentioning_a_marker_is_not_a_dead_session(monkeypatch):
    mod = _real_module(monkeypatch)
    task = "12345678-1234-1234-1234-123456789abc"
    monkeypatch.setattr(mod, "_run", lambda args, timeout: (
        0, f"Started: {task}", "note: login required for private notebooks"))
    lesson = {"lesson_id": "l1"}
    monkeypatch.setattr(mod, "build_description", lambda l: "d")
    monkeypatch.setattr(mod, "notebook_for_lesson", lambda l: "nb")
    assert mod.trigger(lesson, "s1") == task
