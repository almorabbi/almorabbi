"""Unit tests for ops/tools/brand_lesson_media.py safety guards.

Ensures the media branding tool never overwrites unbranded source files in-place
without first archiving and SHA-256-verifying the untouched original strictly
outside the serving directory, and supports writing branded outputs to a
separate ``--output-dir`` without touching originals at all.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "brand_lesson_media", ROOT / "ops" / "tools" / "brand_lesson_media.py"
)
assert SPEC and SPEC.loader
blm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(blm)


def test_refuses_inplace_without_originals_dir(tmp_path: Path) -> None:
    serving = tmp_path / "docs"
    (serving / "podcasts").mkdir(parents=True)
    src = serving / "podcasts" / "sample_ar.mp3"
    src.write_bytes(b"clean-original-audio")

    with pytest.raises(ValueError, match="Refusing in-place overwrite"):
        blm.brand_podcast(src, serving_root=serving)
    with pytest.raises(ValueError, match="Refusing in-place overwrite"):
        blm.brand_video(src, serving_root=serving)

    assert src.read_bytes() == b"clean-original-audio"


def test_refuses_originals_dir_inside_serving_dir(tmp_path: Path) -> None:
    serving = tmp_path / "docs"
    (serving / "videos").mkdir(parents=True)
    src = serving / "videos" / "sample_ar.mp4"
    src.write_bytes(b"clean-original-video")

    # Subdirectory inside serving root must be rejected
    with pytest.raises(ValueError, match="strictly outside"):
        blm._resolve_safe_destination(
            src, originals_dir=serving / "originals", serving_root=serving
        )
    # Same directory as serving root must be rejected
    with pytest.raises(ValueError, match="strictly outside"):
        blm._resolve_safe_destination(
            src, originals_dir=serving, serving_root=serving
        )
    # Parent directory containing serving root must also be rejected
    with pytest.raises(ValueError, match="strictly outside"):
        blm._resolve_safe_destination(
            src, originals_dir=tmp_path, serving_root=serving
        )


def test_archives_and_verifies_original_outside_serving_dir(tmp_path: Path) -> None:
    serving = tmp_path / "docs"
    originals = tmp_path / "originals_vault"
    (serving / "podcasts").mkdir(parents=True)
    src = serving / "podcasts" / "lesson_01.mp3"
    original_bytes = b"untouched-notebooklm-audio-payload"
    src.write_bytes(original_bytes)

    dest, backup = blm._resolve_safe_destination(
        src, originals_dir=originals, serving_root=serving
    )
    assert dest == src
    assert backup == originals / "podcasts" / "lesson_01.mp3"

    blm._archive_original(src, backup)
    assert backup.is_file()
    assert backup.read_bytes() == original_bytes

    # Mutate serving file and re-run archive: must NOT clobber archived original!
    src.write_bytes(b"branded-version-bytes")
    blm._archive_original(src, backup)
    assert backup.read_bytes() == original_bytes


def test_output_dir_leaves_original_untouched_and_refuses_same_path(tmp_path: Path) -> None:
    serving = tmp_path / "docs"
    out_dir = tmp_path / "docs_branded"
    (serving / "videos").mkdir(parents=True)
    src = serving / "videos" / "path_01.mp4"
    src.write_bytes(b"clean-video")

    dest, backup = blm._resolve_safe_destination(
        src, output_dir=out_dir, serving_root=serving
    )
    assert dest == out_dir / "videos" / "path_01.mp4"
    assert backup is None

    # Passing serving root itself as --output-dir must be rejected
    with pytest.raises(ValueError, match="destination resolves to source file"):
        blm._resolve_safe_destination(src, output_dir=serving, serving_root=serving)
