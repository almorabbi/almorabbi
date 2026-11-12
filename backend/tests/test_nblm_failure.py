"""scripts/nblm_failure.py — tell a dead NotebookLM session from a gone task."""
import importlib.util
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
MOD = REPO / "scripts" / "nblm_failure.py"

pytestmark = pytest.mark.skipif(
    not MOD.exists(), reason="scripts/ not present (backend-only image)")


@pytest.fixture(scope="module")
def nf():
    spec = importlib.util.spec_from_file_location("nblm_failure_under_test", MOD)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CSRF_JSON = ('{"error": true, "code": "UNEXPECTED_ERROR", "message": "Unexpected '
             'error: CSRF token not found in HTML. Final URL: https://notebook.google.com/\\n'
             'This may indicate the page structure has changed."}')


def test_csrf_and_expired_auth_are_auth_failures(nf):
    assert nf.is_auth_failure(2, CSRF_JSON, "")
    assert nf.is_auth_failure(1, "", "Authentication expired. Run login")
    assert nf.is_auth_failure(1, "", "please re-authenticate")


def test_task_level_failures_are_not_auth_failures(nf):
    assert not nf.is_auth_failure(1, "", "Artifact not found")
    assert not nf.is_auth_failure(1, "", "Audio generation is unavailable")
    assert not nf.is_auth_failure(0, '{"status": "completed"}', "")


def test_short_reason_prefers_the_json_message_first_line(nf):
    assert nf.short_reason(2, CSRF_JSON, "") == (
        "Unexpected error: CSRF token not found in HTML. Final URL: https://notebook.google.com/")


def test_short_reason_falls_back_to_stderr_then_a_placeholder(nf):
    assert nf.short_reason(1, "", "boom\nmore") == "boom"
    assert nf.short_reason(7, "", "") == "exit 7, no output"


def test_short_reason_truncates(nf):
    assert len(nf.short_reason(1, "", "x" * 500, limit=40)) == 40


def test_exit_codes_are_distinct_and_nonzero(nf):
    assert {nf.EXIT_SESSION_DEAD, nf.EXIT_NO_OUTPUT}.isdisjoint({0, 1, 2})
    assert nf.EXIT_SESSION_DEAD != nf.EXIT_NO_OUTPUT
