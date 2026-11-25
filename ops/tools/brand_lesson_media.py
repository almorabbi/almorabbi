#!/usr/bin/env python3
"""Brand lesson podcasts (MP3) and videos (MP4) with Al-Murabbi's voice & visual signature.

Idempotent: stamps ``comment=almorabbi_branded_v1`` into container metadata and skips
any file that already carries that marker unless ``--force`` is passed.

Podcasts (real MPEG Layer-3 MP3, 44.1 kHz mono 96 kbps, ID3v2.3 + Noor cover art):
  - Warm voice-only intro (~5.5s, no music)
  - Optional gentle mid-roll (~6s) inserted ONLY at a natural silence pause near the
    40%–60% midpoint (via ffmpeg ``silencedetect``); never cuts mid-word
  - Warm voice-only outro (~7.5s) inviting download on Google Play

Videos (H.264 yuv420p +faststart, AAC 96k):
  - Subtle Paper-Cut Noor corner watermark across the main video
  - Clean 8-second Paper-Cut Noor QR outro card (VD15 for AR, VD16 for EN) paired
    with the spoken voice-only outro

Usage:
  python3 ops/tools/brand_lesson_media.py --file <path> [--lang ar|en] [--force]
  python3 ops/tools/brand_lesson_media.py --batch-from-index docs/lesson_index.json \
      --media-root /home/khalednew/projects/tutor-guardian/docs \
      [--kind podcasts|videos|all] [--workers 8]
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlparse

BRAND_MARKER = "almorabbi_branded_v1"
DEFAULT_ASSETS_DIR = Path("/home/khalednew/projects/tutor-guardian/scratch/brand_assets_v1")

_SILENCE_END_RE = re.compile(
    r"silence_end:\s*([0-9.]+)\s*\|\s*silence_duration:\s*([0-9.]+)"
)


def _ffprobe_json(path: Path) -> dict:
    out = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration,format_name:format_tags=comment:stream=codec_type,codec_name,width,height,r_frame_rate",
            "-of",
            "json",
            str(path),
        ],
        text=True,
    )
    return json.loads(out)


def is_branded(path: Path) -> bool:
    try:
        info = _ffprobe_json(path)
    except Exception:
        return False
    tags = (info.get("format") or {}).get("tags") or {}
    for k, v in tags.items():
        if k.lower() == "comment" and BRAND_MARKER in str(v):
            return True
    return False


def detect_lang(path: Path, explicit: str | None = None) -> str:
    if explicit in ("ar", "en"):
        return explicit
    name = path.name.lower()
    if any(tok in name for tok in ("_en.", "_en_", "en_us", "_en-us")):
        return "en"
    return "ar"


def find_midpoint_silence(path: Path, duration: float) -> float | None:
    """Return timestamp (seconds) at the center of the best natural silence near 50%."""
    if duration < 90.0:
        return None
    proc = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "info",
            "-i",
            str(path),
            "-af",
            "silencedetect=noise=-32dB:d=0.45",
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    lo, hi, target = duration * 0.38, duration * 0.62, duration * 0.50
    best: tuple[float, float] | None = None  # (score, midpoint)
    for m in _SILENCE_END_RE.finditer(proc.stderr):
        end_t = float(m.group(1))
        dur_s = float(m.group(2))
        mid = end_t - dur_s / 2.0
        if lo <= mid <= hi:
            # Prefer longer pauses closest to exact 50%
            score = abs(mid - target) - min(dur_s, 1.5) * 20.0
            if best is None or score < best[0]:
                best = (score, mid)
    return best[1] if best is not None else None


def brand_podcast(
    path: Path,
    *,
    assets_dir: Path = DEFAULT_ASSETS_DIR,
    lang: str | None = None,
    force: bool = False,
) -> str:
    if not path.is_file():
        return f"MISSING:{path}"
    if not force and is_branded(path):
        return f"SKIP:{path.name}"

    lg = detect_lang(path, lang)
    intro = assets_dir / f"intro_{lg}.wav"
    mid = assets_dir / f"mid_{lg}.wav"
    outro = assets_dir / f"outro_{lg}.wav"
    cover = assets_dir / "podcast_cover.png"
    for req in (intro, mid, outro, cover):
        if not req.is_file():
            raise FileNotFoundError(f"Missing brand asset: {req}")

    info = _ffprobe_json(path)
    duration = float((info.get("format") or {}).get("duration") or 0.0)
    if duration <= 5.0:
        raise ValueError(f"Podcast too short ({duration:.1f}s): {path}")

    split_at = find_midpoint_silence(path, duration)
    artist = "تطبيق المربّي | Al-Murabbi"
    album = "منهج المربّي التربوي" if lg == "ar" else "Al-Murabbi Parenting Curriculum"
    comment = (
        f"{BRAND_MARKER} | مجاني بالكامل لوجه الله — https://tg-api.alsaba.cloud/go"
        if lg == "ar"
        else f"{BRAND_MARKER} | 100% Free & Ad-Free — https://tg-api.alsaba.cloud/go?lang=en"
    )

    with tempfile.TemporaryDirectory(prefix="tg-brand-mp3-") as tmp:
        out_tmp = Path(tmp) / "out.mp3"
        if split_at is not None:
            fc = (
                "anullsrc=r=44100:cl=mono:d=0.35[s1];"
                "anullsrc=r=44100:cl=mono:d=0.35[s2];"
                "anullsrc=r=44100:cl=mono:d=0.35[s3];"
                "anullsrc=r=44100:cl=mono:d=0.45[s4];"
                "[0:a]aresample=44100,aformat=channel_layouts=mono[a0];"
                f"[1:a]aresample=44100,aformat=channel_layouts=mono,atrim=0:{split_at:.3f},asetpts=PTS-STARTPTS,afade=t=out:st={max(split_at - 0.12, 0):.3f}:d=0.12[p1];"
                f"[1:a]aresample=44100,aformat=channel_layouts=mono,atrim={split_at:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.12[p2];"
                "[2:a]aresample=44100,aformat=channel_layouts=mono[am];"
                "[3:a]aresample=44100,aformat=channel_layouts=mono[ao];"
                "[a0][s1][p1][s2][am][s3][p2][s4][ao]concat=n=9:v=0:a=1[aout]"
            )
            cmd = [
                "ffmpeg",
                "-y",
                "-v",
                "error",
                "-threads",
                "2",
                "-i",
                str(intro),
                "-i",
                str(path),
                "-i",
                str(mid),
                "-i",
                str(outro),
                "-i",
                str(cover),
                "-filter_complex",
                fc,
                "-map",
                "[aout]",
                "-map",
                "4:v",
                "-c:a",
                "libmp3lame",
                "-b:a",
                "96k",
                "-ar",
                "44100",
                "-ac",
                "1",
                "-c:v",
                "mjpeg",
                "-id3v2_version",
                "3",
                "-metadata:s:v",
                "title=Al-Murabbi Cover",
                "-metadata:s:v",
                "comment=Cover (front)",
                "-metadata",
                f"artist={artist}",
                "-metadata",
                f"album={album}",
                "-metadata",
                f"comment={comment}",
                str(out_tmp),
            ]
        else:
            fc = (
                "anullsrc=r=44100:cl=mono:d=0.35[s1];"
                "anullsrc=r=44100:cl=mono:d=0.45[s2];"
                "[0:a]aresample=44100,aformat=channel_layouts=mono[a0];"
                "[1:a]aresample=44100,aformat=channel_layouts=mono[a1];"
                "[2:a]aresample=44100,aformat=channel_layouts=mono[ao];"
                "[a0][s1][a1][s2][ao]concat=n=5:v=0:a=1[aout]"
            )
            cmd = [
                "ffmpeg",
                "-y",
                "-v",
                "error",
                "-threads",
                "2",
                "-i",
                str(intro),
                "-i",
                str(path),
                "-i",
                str(outro),
                "-i",
                str(cover),
                "-filter_complex",
                fc,
                "-map",
                "[aout]",
                "-map",
                "3:v",
                "-c:a",
                "libmp3lame",
                "-b:a",
                "96k",
                "-ar",
                "44100",
                "-ac",
                "1",
                "-c:v",
                "mjpeg",
                "-id3v2_version",
                "3",
                "-metadata:s:v",
                "title=Al-Murabbi Cover",
                "-metadata:s:v",
                "comment=Cover (front)",
                "-metadata",
                f"artist={artist}",
                "-metadata",
                f"album={album}",
                "-metadata",
                f"comment={comment}",
                str(out_tmp),
            ]
        subprocess.run(cmd, check=True)
        if not is_branded(out_tmp):
            raise RuntimeError(f"Branded verification failed for {path}")
        dest_tmp = path.with_suffix(".brand_tmp.mp3")
        dest_tmp.write_bytes(out_tmp.read_bytes())
        os.chmod(dest_tmp, 0o644)
        os.replace(dest_tmp, path)
    tag = f"mid@{split_at:.1f}s" if split_at is not None else "no-mid"
    return f"OK:MP3:{lg}:{tag}:{path.name}"


def brand_video(
    path: Path,
    *,
    assets_dir: Path = DEFAULT_ASSETS_DIR,
    lang: str | None = None,
    force: bool = False,
) -> str:
    if not path.is_file():
        return f"MISSING:{path}"
    if not force and is_branded(path):
        return f"SKIP:{path.name}"

    lg = detect_lang(path, lang)
    wm = assets_dir / f"watermark_{lg}.png"
    outro_img = assets_dir / f"outro_card_{lg}.png"
    outro_wav = assets_dir / f"outro_{lg}.wav"
    for req in (wm, outro_img, outro_wav):
        if not req.is_file():
            raise FileNotFoundError(f"Missing brand asset: {req}")

    info = _ffprobe_json(path)
    vstream = next(
        (s for s in info.get("streams", []) if s.get("codec_type") == "video"),
        None,
    )
    if not vstream:
        raise ValueError(f"No video stream in {path}")
    w = int(vstream.get("width") or 1280)
    h = int(vstream.get("height") or 720)
    outro_dur = float((_ffprobe_json(outro_wav).get("format") or {}).get("duration") or 7.5) + 0.8

    artist = "تطبيق المربّي | Al-Murabbi"
    comment = (
        f"{BRAND_MARKER} | مجاني بالكامل لوجه الله — https://tg-api.alsaba.cloud/go?ref=VD15"
        if lg == "ar"
        else f"{BRAND_MARKER} | 100% Free & Ad-Free — https://tg-api.alsaba.cloud/go?ref=VD16&lang=en"
    )

    with tempfile.TemporaryDirectory(prefix="tg-brand-mp4-") as tmp:
        tmp_dir = Path(tmp)
        main_mp4 = tmp_dir / "main.mp4"
        outro_mp4 = tmp_dir / "outro.mp4"
        concat_txt = tmp_dir / "concat.txt"
        out_tmp = tmp_dir / "out.mp4"

        # Two-step encode + demuxer stream-copy concat keeps peak RAM under
        # ~200 MB per worker (avoids filtergraph concat buffering gigabytes of
        # decoded 720p frames).
        wm_fc = (
            f"[0:v]scale={w}:{h}:force_original_aspect_ratio=decrease,"
            f"pad={w}:{h}:(ow-iw)/2:(oh-ih)/2,fps=24,format=yuv420p,setsar=1[vmain];"
            f"[1:v]scale={w}:{h},format=rgba[wm];"
            "[vmain][wm]overlay=0:0:shortest=1[vout]"
        )
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-v",
                "error",
                "-threads",
                "2",
                "-i",
                str(path),
                "-i",
                str(wm),
                "-filter_complex",
                wm_fc,
                "-map",
                "[vout]",
                "-map",
                "0:a",
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-crf",
                "23",
                "-pix_fmt",
                "yuv420p",
                "-r",
                "24",
                "-video_track_timescale",
                "24000",
                "-c:a",
                "aac",
                "-b:a",
                "96k",
                "-ar",
                "44100",
                "-ac",
                "1",
                str(main_mp4),
            ],
            check=True,
        )

        outro_fc = (
            f"[0:v]scale={w}:{h},fps=24,format=yuv420p,setsar=1,"
            f"fade=t=in:st=0:d=0.35,fade=t=out:st={outro_dur - 0.35:.2f}:d=0.35[v1];"
            "anullsrc=r=44100:cl=mono:d=0.35[lead];"
            "anullsrc=r=44100:cl=mono:d=0.45[tail];"
            "[1:a]aresample=44100,aformat=channel_layouts=mono[av];"
            "[lead][av][tail]concat=n=3:v=0:a=1[a1]"
        )
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-v",
                "error",
                "-threads",
                "2",
                "-loop",
                "1",
                "-t",
                f"{outro_dur:.2f}",
                "-i",
                str(outro_img),
                "-i",
                str(outro_wav),
                "-filter_complex",
                outro_fc,
                "-map",
                "[v1]",
                "-map",
                "[a1]",
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-crf",
                "23",
                "-pix_fmt",
                "yuv420p",
                "-r",
                "24",
                "-video_track_timescale",
                "24000",
                "-c:a",
                "aac",
                "-b:a",
                "96k",
                "-ar",
                "44100",
                "-ac",
                "1",
                str(outro_mp4),
            ],
            check=True,
        )

        concat_txt.write_text(
            f"file '{main_mp4}'\nfile '{outro_mp4}'\n",
            encoding="utf-8",
        )
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-v",
                "error",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                str(concat_txt),
                "-c",
                "copy",
                "-movflags",
                "+faststart",
                "-metadata",
                f"artist={artist}",
                "-metadata",
                f"comment={comment}",
                str(out_tmp),
            ],
            check=True,
        )
        if not is_branded(out_tmp):
            raise RuntimeError(f"Branded verification failed for {path}")
        dest_tmp = path.with_suffix(".brand_tmp.mp4")
        dest_tmp.write_bytes(out_tmp.read_bytes())
        os.chmod(dest_tmp, 0o644)
        os.replace(dest_tmp, path)
    return f"OK:MP4:{lg}:{w}x{h}:{path.name}"


def collect_from_index(index_path: Path, media_root: Path, kind: str) -> list[tuple[Path, str, str]]:
    """Return deduplicated list of (abs_path, media_type, lang) from lesson_index.json."""
    data = json.loads(index_path.read_text(encoding="utf-8"))
    seen: dict[Path, tuple[str, str]] = {}

    def _norm_rel(raw: str) -> str:
        if raw.startswith(("http://", "https://")):
            raw = urlparse(raw).path
        rel = raw.lstrip("/")
        return rel[5:] if rel.startswith("docs/") else rel

    for lesson in data.get("lessons", []):
        assets = lesson.get("assets") or {}
        if kind in ("podcasts", "all"):
            for entry in assets.get("podcasts") or []:
                f = entry.get("file") or ""
                if not f:
                    continue
                p = media_root / _norm_rel(f)
                lg = "en" if str(entry.get("language") or "").lower().startswith("en") else "ar"
                seen.setdefault(p, ("podcast", lg))
        if kind in ("videos", "all"):
            for entry in assets.get("videos") or []:
                f = entry.get("file") or ""
                if not f:
                    continue
                p = media_root / _norm_rel(f)
                lg = "en" if str(entry.get("language") or "").lower().startswith("en") else "ar"
                seen.setdefault(p, ("video", lg))

    return [(p, mtype, lg) for p, (mtype, lg) in sorted(seen.items())]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--file", type=Path, help="Single .mp3 or .mp4 file to brand in-place")
    ap.add_argument("--lang", choices=["ar", "en"], help="Explicit language override")
    ap.add_argument("--batch-from-index", type=Path, help="lesson_index.json path for batch branding")
    ap.add_argument("--media-root", type=Path, default=Path("/home/khalednew/projects/tutor-guardian/docs"))
    ap.add_argument("--assets-dir", type=Path, default=DEFAULT_ASSETS_DIR)
    ap.add_argument("--kind", choices=["podcasts", "videos", "all"], default="all")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if args.file:
        ext = args.file.suffix.lower()
        if ext == ".mp3":
            print(brand_podcast(args.file, assets_dir=args.assets_dir, lang=args.lang, force=args.force))
        elif ext == ".mp4":
            print(brand_video(args.file, assets_dir=args.assets_dir, lang=args.lang, force=args.force))
        else:
            print(f"Unsupported extension: {args.file}", file=sys.stderr)
            return 2
        return 0

    if not args.batch_from_index:
        ap.error("Specify --file or --batch-from-index")

    jobs = collect_from_index(args.batch_from_index, args.media_root, args.kind)
    print(f"Batch branding {len(jobs)} files (kind={args.kind}, workers={args.workers})...")
    ok = skip = err = 0

    def _run(job: tuple[Path, str, str]) -> str:
        p, mtype, lg = job
        if mtype == "podcast":
            return brand_podcast(p, assets_dir=args.assets_dir, lang=lg, force=args.force)
        return brand_video(p, assets_dir=args.assets_dir, lang=lg, force=args.force)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futs = {pool.submit(_run, j): j for j in jobs}
        for i, fut in enumerate(as_completed(futs), 1):
            j = futs[fut]
            try:
                res = fut.result()
                if res.startswith("SKIP:"):
                    skip += 1
                elif res.startswith("OK:"):
                    ok += 1
                else:
                    err += 1
                if i % 25 == 0 or res.startswith(("MISSING:", "ERR")) or i == len(jobs):
                    print(f"[{i}/{len(jobs)}] {res} (ok={ok}, skip={skip}, err={err})", flush=True)
            except Exception as exc:
                err += 1
                print(f"[{i}/{len(jobs)}] ERROR {j[0].name}: {exc}", file=sys.stderr, flush=True)

    print(f"DONE: total={len(jobs)} ok={ok} skip={skip} err={err}")
    return 1 if err else 0


if __name__ == "__main__":
    raise SystemExit(main())
