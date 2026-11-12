"""Why did a notebooklm CLI call fail? — shared by the three EN-media generators.

Until 2026-10-29 `poll()` and `trigger()` in the audio, video and infographic
generators turned EVERY failure into the bare word "error" / "no task id" and
threw the CLI's stderr away. A dead session ("CSRF token not found in HTML",
"Authentication expired") therefore looked exactly like a task that was gone:

  · the infographic harvest counted three of them as strikes and DROPPED paid
    tasks that were only unreachable (the log showed 12 dropped on one run);
  · every run exited 0 with "0 downloaded" and no reason, for weeks.

This module keeps the two kinds of failure apart and gives the reason a place
in the log. It imports nothing from the project, so a generator can use it
without pulling in the backend.
"""
from __future__ import annotations

import json

# Exit codes shared by the generators and read by scripts/cron_gen_en_media.sh.
EXIT_SESSION_DEAD = 3   # the CLI could not authenticate: nothing was tried
EXIT_NO_OUTPUT = 4      # ran, had work to do, produced nothing, and says why

# Lower-cased fragments that mean "the session is dead", not "the task is gone".
_AUTH_MARKERS = (
    "csrf token not found",
    "authentication expired",
    "re-authenticate",
    "reauthenticate",
    "not authenticated",
    "login required",
    "please login",
    "run 'notebooklm login'",
    "run `notebooklm login`",
)


def _message(rc: int, out: str, err: str) -> str:
    """The most informative single line the CLI gave us."""
    text = ""
    try:
        data = json.loads(out)
        if isinstance(data, dict) and data.get("message"):
            text = str(data["message"])
    except (ValueError, TypeError):
        pass
    if not text:
        text = err or out or ""
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line
    return f"exit {rc}, no output"


def is_auth_failure(rc: int, out: str, err: str) -> bool:
    blob = f"{out}\n{err}".lower()
    return any(marker in blob for marker in _AUTH_MARKERS)


def short_reason(rc: int, out: str, err: str, limit: int = 160) -> str:
    msg = _message(rc, out, err)
    return msg if len(msg) <= limit else msg[: limit - 1] + "…"
