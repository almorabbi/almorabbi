"""Every avatar the app's picker offers must be one the server accepts.

On 2026-11-06 a parent could not add a third child: they picked ⭐, which
the picker offers but the server's emoji pattern refused, so POST
/api/children answered 422 four times. The family of five (nine codepoints)
was refused too, by the length cap. This reads the picker list straight from
the Dart source so a new avatar cannot ship without the server agreeing.
"""
import re
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.routers.children import ChildCreateRequest, ChildUpdateRequest

ROOT = Path(__file__).resolve().parents[2]
PICKER = ROOT / "mobile/lib/features/onboarding/screens/avatar_picker_sheet.dart"


def _picker_emojis() -> list[str]:
    src = PICKER.read_text(encoding="utf-8")
    body = re.search(r"const List<String> kAvatarEmojis = \[(.*?)\];", src, re.S)
    assert body, "kAvatarEmojis not found — update this test's parser"
    items = re.findall(r"'([^']+)'", re.sub(r"//[^\n]*", "", body.group(1)))
    assert len(items) >= 40, items  # the parser found the real list
    return items


@pytest.mark.parametrize("emoji", _picker_emojis())
def test_server_accepts_every_picker_avatar(emoji):
    assert ChildCreateRequest(name="x", age_group="4-6", avatar_emoji=emoji).avatar_emoji == emoji
    assert ChildUpdateRequest(avatar_emoji=emoji).avatar_emoji == emoji


@pytest.mark.parametrize("bad", ["hello", "⭐ x", "⭐\n", "\x07", "سارة", "1"])
def test_server_still_refuses_text_and_control_characters(bad):
    with pytest.raises(ValidationError):
        ChildCreateRequest(name="x", age_group="4-6", avatar_emoji=bad)
