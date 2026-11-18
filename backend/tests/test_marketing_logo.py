"""Marketing tools stamp the current mark, never the old logo.

The old logo — a child's profile inside a crescent, on a teal square — went on
being stamped on tip cards, watermarked infographics and reels for months after
the launcher icon, the store and the app had moved to the paper-cut mark. It
also broke the rule that nothing leaving the app shows a person. Nothing
failed: the old PNGs decoded and the outputs looked finished.

Pinned here:
- the three tools read one file, remotion-reels/public/noor/app_logo_round.png
  (the store icon cut to a circle by remotion-reels/scripts/make_round_logo.py),
  and so does the Remotion Reel composition;
- that file is round: opaque in the middle, clear in the corners — the tools
  paste it as-is, so a square image there would come out as a square tile;
- no tracked file carries the bytes of any old logo copy again.
"""
import ast
import hashlib
import json
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
CURRENT = ROOT / "remotion-reels" / "public" / "noor" / "app_logo_round.png"
TOOLS = {
    "ops/tools/generate_tip_cards.py": "LOGO_PATH",
    "ops/tools/watermark_infographics.py": "LOGO_PATH",
    "scripts/reel_from_video.py": "LOGO",
}
# (size, sha256) of the old-logo copies this change deleted. The size is checked
# first so the ~260 MB of tracked images are not all hashed.
OLD_LOGOS = {
    (202804, "b18c9294b8f225e0d7b811489add80c24f1ac6922cdd35a19305b3de344b3513"):
        "docs/marketing/launch_graphics/facebook_profile_logo.png",
    (257068, "71aa87801585d79f5eb05f3caf70ae6451e8a14ac390bf552b107c48b6a7e39d"):
        "remotion-reels/public/logo.png (= the deleted mobile/assets/images/logo.png)",
    (307608, "b01b6b40bff699686864b397ce1031701705a0efc3cad694de60ab493cd95fa2"):
        "frontend/assets/logo.png",
}

# Outside backend/: skip where the image does not ship it (pattern of 18da165c).
pytestmark = pytest.mark.skipif(
    not all((ROOT / rel).exists() for rel in TOOLS) or not CURRENT.parent.exists(),
    reason="ops/tools, scripts or remotion-reels not present (backend-only image)",
)


def _path_constant(rel: str, name: str) -> Path:
    """Evaluate `NAME = ROOT / "a" / "b"` from the tool's source without importing
    it (the tools pull in ffmpeg paths, fonts and optional libraries)."""
    tree = ast.parse((ROOT / rel).read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == name for t in node.targets):
            parts, expr = [], node.value
            while isinstance(expr, ast.BinOp) and isinstance(expr.op, ast.Div):
                assert isinstance(expr.right, ast.Constant), ast.unparse(node)
                parts.append(expr.right.value)
                expr = expr.left
            assert isinstance(expr, ast.Name) and expr.id == "ROOT", ast.unparse(node)
            return ROOT.joinpath(*reversed(parts))
    raise AssertionError(f"{rel}: no top-level {name} = ROOT / ...")


@pytest.mark.parametrize("rel,name", sorted(TOOLS.items()))
def test_tool_reads_the_current_mark(rel, name):
    assert _path_constant(rel, name) == CURRENT, f"{rel}: {name} is not {CURRENT.relative_to(ROOT)}"


def test_remotion_reel_uses_the_current_mark():
    rel = CURRENT.relative_to(ROOT / "remotion-reels" / "public").as_posix()
    assert json.loads((ROOT / "remotion-reels/data/reel.json").read_text())["logoPath"] == rel
    src = (ROOT / "remotion-reels/scripts/make_reel_data.py").read_text(encoding="utf-8")
    assert f'"logoPath": "{rel}"' in src


def test_current_mark_is_round():
    Image = pytest.importorskip("PIL.Image")
    im = Image.open(CURRENT)
    assert im.mode == "RGBA" and im.width == im.height and im.width >= 512, (im.mode, im.size)
    w = im.width
    assert im.getpixel((w // 2, w // 2))[3] == 255
    for corner in ((1, 1), (w - 2, 1), (1, w - 2), (w - 2, w - 2)):
        assert im.getpixel(corner)[3] == 0, corner


def test_no_tracked_file_is_an_old_logo():
    if not (ROOT / ".git").exists():
        pytest.skip("not a git checkout")
    files = subprocess.run(["git", "ls-files", "-z", "*.png", "*.jpg", "*.jpeg", "*.webp"],
                           cwd=ROOT, capture_output=True, check=True).stdout.split(b"\0")
    sizes = {size for size, _ in OLD_LOGOS}
    found = []
    for raw in filter(None, files):
        path = ROOT / raw.decode()
        if not path.is_file() or (size := path.stat().st_size) not in sizes:
            continue
        if (size, hashlib.sha256(path.read_bytes()).hexdigest()) in OLD_LOGOS:
            found.append(raw.decode())
    assert not found, f"old logo is back: {found}"
