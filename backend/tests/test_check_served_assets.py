"""Tests for ops/tools/check_served_assets.py quarantine manifest handling."""
import importlib.util
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = REPO_ROOT / "ops" / "tools" / "check_served_assets.py"


def _load_tool():
    spec = importlib.util.spec_from_file_location("check_served_assets", TOOL_PATH)
    mod = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod


def _make_site(tmp_path: Path):
    """Create a minimal repo root with one present podcast and one missing podcast."""
    docs = tmp_path / "docs"
    docs.mkdir(parents=True, exist_ok=True)
    present_file = docs / "lesson_0-3_present_podcast.mp3"
    present_file.write_bytes(b"present-audio-bytes")

    index = {
        "lessons": [
            {
                "lesson_id": "lesson_0-3_present",
                "assets": {
                    "podcasts": [
                        {"file": "docs/lesson_0-3_present_podcast.mp3", "language": "ar"},
                    ],
                    "videos": [],
                },
            },
            {
                "lesson_id": "lesson_0-3_missing",
                "assets": {
                    "podcasts": [
                        {"file": "docs/lesson_0-3_missing_podcast.mp3", "language": "ar"},
                    ],
                    "videos": [],
                },
            },
        ]
    }
    (docs / "lesson_index.json").write_text(json.dumps(index), encoding="utf-8")
    return tmp_path


def test_missing_file_in_manifest_with_physical_copy_passes(tmp_path, capsys):
    """Case 1: Missing from docs/, listed in MANIFEST.json, AND physical copy exists -> PASS."""
    mod = _load_tool()
    site = _make_site(tmp_path / "site")
    qdir = tmp_path / "quarantined_media_20261127"
    qdir.mkdir()
    qcopy = qdir / "lesson_0-3_missing_podcast.mp3"
    qcopy.write_bytes(b"quarantined-audio-bytes")
    manifest = {
        "moved_at_utc": "2026-11-27T12:00:00Z",
        "files": [
            {
                "rel": "lesson_0-3_missing_podcast.mp3",
                "from": "/root/tutor-guardian/docs/lesson_0-3_missing_podcast.mp3",
                "to": str(qcopy),
            }
        ],
    }
    (qdir / "MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")

    rc = mod.main([
        "--root", str(site),
        "--quarantine-glob", str(tmp_path / "quarantined_media_*" / "MANIFEST.json"),
    ])
    out = capsys.readouterr().out
    assert rc == 0
    assert "QUARANTINED" in out
    assert "1 file(s)" in out
    assert "docs/lesson_0-3_missing_podcast.mp3" in out


def test_missing_file_not_in_manifest_fails(tmp_path, capsys):
    """Case 2: Missing from docs/ and NOT listed in any MANIFEST.json -> FAIL."""
    mod = _load_tool()
    site = _make_site(tmp_path / "site")
    qdir = tmp_path / "quarantined_media_20261127"
    qdir.mkdir()
    (qdir / "MANIFEST.json").write_text(json.dumps({"files": []}), encoding="utf-8")

    rc = mod.main([
        "--root", str(site),
        "--quarantine-glob", str(tmp_path / "quarantined_media_*" / "MANIFEST.json"),
    ])
    out = capsys.readouterr().out
    assert rc == 1
    assert "REFERENCED BUT MISSING — 1 file(s)" in out
    assert "docs/lesson_0-3_missing_podcast.mp3" in out


def test_missing_file_in_manifest_without_physical_copy_fails(tmp_path, capsys):
    """Case 3: Listed in MANIFEST.json, but physical copy is missing from quarantine dir -> FAIL."""
    mod = _load_tool()
    site = _make_site(tmp_path / "site")
    qdir = tmp_path / "quarantined_media_20261127"
    qdir.mkdir()
    manifest = {
        "moved_at_utc": "2026-11-27T12:00:00Z",
        "files": [
            {
                "rel": "lesson_0-3_missing_podcast.mp3",
                "from": "/root/tutor-guardian/docs/lesson_0-3_missing_podcast.mp3",
                "to": str(qdir / "lesson_0-3_missing_podcast.mp3"),
            }
        ],
    }
    (qdir / "MANIFEST.json").write_text(json.dumps(manifest), encoding="utf-8")

    rc = mod.main([
        "--root", str(site),
        "--quarantine-glob", str(tmp_path / "quarantined_media_*" / "MANIFEST.json"),
    ])
    out = capsys.readouterr().out
    assert rc == 1
    assert "REFERENCED BUT MISSING — 1 file(s)" in out
    assert "docs/lesson_0-3_missing_podcast.mp3" in out


def test_language_mismatch_still_blocks_even_when_quarantined(tmp_path, capsys):
    """Language-mismatch check remains untouched and blocking."""
    mod = _load_tool()
    site = _make_site(tmp_path / "site")
    idx_path = site / "docs" / "lesson_index.json"
    idx = json.loads(idx_path.read_text(encoding="utf-8"))
    # Corrupt declared language of the present Arabic file to 'en'
    idx["lessons"][0]["assets"]["podcasts"][0]["language"] = "en"
    idx_path.write_text(json.dumps(idx), encoding="utf-8")

    qdir = tmp_path / "quarantined_media_20261127"
    qdir.mkdir()
    qcopy = qdir / "lesson_0-3_missing_podcast.mp3"
    qcopy.write_bytes(b"quarantined-audio-bytes")
    (qdir / "MANIFEST.json").write_text(
        json.dumps({"files": ["docs/lesson_0-3_missing_podcast.mp3"]}),
        encoding="utf-8",
    )

    rc = mod.main([
        "--root", str(site),
        "--quarantine-glob", str(tmp_path / "quarantined_media_*" / "MANIFEST.json"),
    ])
    out = capsys.readouterr().out
    assert rc == 1
    assert "DECLARED LANGUAGE ≠ FILENAME" in out
