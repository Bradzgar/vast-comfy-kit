#!/usr/bin/env python3
r"""
extract_frames.py -- turn a video into a LoRA dataset (frames + caption stubs).

Uses ffmpeg to pull stills, then writes a same-named .txt next to each frame with a
caption template you can fill in. Designed to feed the Krea 2 / AI Toolkit workflow.

Frame rate guidance: use 1 fps for most clips (2 fps for short clips or fast motion),
then hand-curate down to 15-40 diverse frames. Prefer --scene to grab only distinct
shots instead of near-duplicate frames.

Examples
--------
# 1 fps, max 1024px, into ./datasets/margot
python extract_frames.py clip.mp4 datasets/margot --fps 1 --max-size 1024

# only distinct shots (scene change > 0.3), capped at 40 frames
python extract_frames.py clip.mp4 datasets/margot --scene 0.3 --max-frames 40

# a whole folder of clips -> one subfolder per clip
python extract_frames.py ./clips datasets/margot --fps 1

# just preview how many frames would be made (no files written)
python extract_frames.py clip.mp4 datasets/margot --fps 1 --dry-run

Requires: ffmpeg + ffprobe on PATH. Pure stdlib otherwise.
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys

VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v", ".mpg", ".mpeg", ".wmv", ".flv"}

CAPTION_TEMPLATE = """\
{trigger}, <single subject>, <framing: close-up / half-body / full-body>, <camera angle>, \
<expression or pose>, <what changes: clothing / accessory / hair style>, <lighting>, <background>, \
<lens & texture>

# --- how to caption (Krea 2 / AI Toolkit rules) -----------------------------
# * First token is the trigger word. Replace "{trigger}" with your real one everywhere.
#   (AI Toolkit auto-substitutes the literal [trigger] token if trigger_word is set.)
# * Write NATURAL LANGUAGE, not a tag list.
# * Describe only what CHANGES per image. Do NOT describe fixed identity traits
#   (face shape, hair colour, skin, body) or the model learns identity as a variable.
# * 12-40 curated, diverse frames beat hundreds of near-duplicates.
# * Keep the trigger word in EVERY caption, or the association is inconsistent.
#
# Examples (delete these lines in the files you keep):
# {trigger}, a woman, close-up head and shoulders, front view, soft smile, white knit sweater, warm window light, plain gray background
# {trigger}, a woman, three-quarter body, side angle, neutral expression, black dress, outdoor daylight, city street, shallow depth of field
# {trigger}, a woman, full body standing, front view, hands on hips, denim jacket, studio lighting, dark backdrop, shoes visible
# {trigger}, a woman, close-up, high angle, laughing, red hoodie, golden-hour light, garden with bokeh, crisp focus
"""


def tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        sys.exit(f"error: '{name}' not found on PATH. Install ffmpeg first.")
    return path


def vfr_args(ffmpeg: str) -> list[str]:
    """ffmpeg 8+ removed -vsync in favour of -fps_mode; older builds only know -vsync."""
    try:
        out = subprocess.run([ffmpeg, "-version"], capture_output=True, text=True).stdout
    except Exception:
        out = ""
    m = re.search(r"ffmpeg version n?(\d+)", out)
    major = int(m.group(1)) if m else None
    if major is not None and major >= 8:
        return ["-fps_mode", "vfr"]
    return ["-vsync", "vfr"]


def probe_duration(ffprobe: str, video: str) -> float:
    try:
        out = subprocess.run(
            [ffprobe, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", video],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return float(out)
    except Exception:
        return 0.0


def build_filters(args) -> str:
    parts = []
    conds = []
    if args.start_frame:
        conds.append(f"gte(n\\,{args.start_frame})")
    if args.scene is not None:
        conds.append(f"gt(scene,{args.scene})")
        parts.append("select='" + "*".join(conds) + "'")
    elif args.every:
        conds.append(f"not(mod(n\\,{args.every}))")
        parts.append("select='" + "*".join(conds) + "'")
    else:
        if args.start_frame:
            print("  note: --start-frame needs --every or --scene; for fps use --start (timestamp)")
        parts.append(f"fps={args.fps}")
    if args.max_size > 0:
        m = args.max_size
        parts.append(
            f"scale=w='if(gt(iw,ih),min(iw,{m}),-2)':h='if(gt(iw,ih),-2,min(ih,{m}))'"
        )
    return ",".join(parts)


def extract_one(ffmpeg: str, ffprobe: str, video: str, out_dir: str, args) -> list[str]:
    os.makedirs(out_dir, exist_ok=True)
    ext = args.format
    pattern = os.path.join(out_dir, f"{args.prefix}_%06d.{ext}")

    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y"]
    if args.start:
        cmd += ["-ss", args.start]
    if args.end:
        cmd += ["-to", args.end]
    cmd += ["-i", video, "-vf", build_filters(args)] + vfr_args(ffmpeg)
    if args.max_frames > 0:
        cmd += ["-frames:v", str(args.max_frames)]
    if ext == "jpg":
        cmd += ["-q:v", str(args.quality)]
    cmd += ["-start_number", "1", pattern]

    if args.dry_run:
        dur = probe_duration(ffprobe, video)
        if args.scene is not None:
            rate, est = "scene-based", "-"
        elif args.every:
            rate, est = f"1 of every {args.every} frames", "-"
        else:
            rate = f"{args.fps} fps"
            est = f"~{int(dur * args.fps)}" if dur else "?"
        print(f"[dry-run] {video}: {rate}, est. {est} frames -> {out_dir}/{args.prefix}_%06d.{ext}")
        return []

    print(f"  ffmpeg: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

    frames = sorted(glob.glob(os.path.join(out_dir, f"{args.prefix}_*.{ext}")))
    made = []
    for frame in frames:
        txt = os.path.splitext(frame)[0] + ".txt"
        if os.path.exists(txt) and not args.overwrite:
            continue
        with open(txt, "w", encoding="utf-8") as fh:
            fh.write(CAPTION_TEMPLATE.format(trigger=args.trigger))
        made.append(os.path.basename(frame))
    return frames


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract video frames into a LoRA dataset with caption stubs.")
    ap.add_argument("input", help="video file OR a folder of videos")
    ap.add_argument("out", help="output dataset folder")
    ap.add_argument("--fps", type=float, default=1.0, help="frames per second (default 1)")
    ap.add_argument("--every", type=int, default=None,
                     help="keep 1 out of every N source frames (overrides --fps; ignores frame rate)")
    ap.add_argument("--start-frame", type=int, default=None,
                     help="skip source frames before this index (use with --every or --scene)")
    ap.add_argument("--scene", type=float, default=None,
                    help="use scene-change detection instead of fps (e.g. 0.3; lower = more frames)")
    ap.add_argument("--max-frames", type=int, default=0, help="cap total frames per video (0 = no cap)")
    ap.add_argument("--max-size", type=int, default=0,
                    help="downscale so the longest side is <= N px (0 = keep original; never upscales)")
    ap.add_argument("--start", default=None, help="start timestamp, e.g. 00:00:05")
    ap.add_argument("--end", default=None, help="end timestamp, e.g. 00:00:30")
    ap.add_argument("--format", choices=["png", "jpg"], default="png", help="frame format (default png)")
    ap.add_argument("--quality", type=int, default=2, help="jpg quality 2(best)-31(worst)")
    ap.add_argument("--prefix", default="frame", help="frame filename prefix (default frame)")
    ap.add_argument("--trigger", default="[trigger]", help="trigger word placed in the caption template")
    ap.add_argument("--overwrite", action="store_true", help="overwrite existing .txt files")
    ap.add_argument("--dry-run", action="store_true", help="show what would be created, write nothing")
    args = ap.parse_args()

    ffmpeg = "ffmpeg" if args.dry_run else tool("ffmpeg")
    ffprobe = "ffprobe" if args.dry_run else tool("ffprobe")

    if not os.path.exists(args.input):
        sys.exit(f"error: input not found: {args.input}")

    videos: list[str] = []
    if os.path.isdir(args.input):
        for name in sorted(os.listdir(args.input)):
            p = os.path.join(args.input, name)
            if os.path.isfile(p) and os.path.splitext(name)[1].lower() in VIDEO_EXTS:
                videos.append(p)
        if not videos:
            sys.exit(f"error: no video files in {args.input}")
    else:
        videos = [args.input]

    os.makedirs(args.out, exist_ok=True)
    multi = len(videos) > 1
    if args.scene is not None:
        rate = f"scene>{args.scene}"
    elif args.every:
        rate = f"1 of every {args.every} frames"
    else:
        rate = f"{args.fps} fps"
    print(f"Extracting at {rate} -> {args.out}  ({'dry-run' if args.dry_run else 'writing'})")

    total = 0
    for v in videos:
        sub = os.path.splitext(os.path.basename(v))[0] if multi else ""
        out_dir = os.path.join(args.out, sub) if sub else args.out
        print(f"- {v}")
        frames = extract_one(ffmpeg, ffprobe, v, out_dir, args)
        total += len(frames)

    if args.dry_run:
        print("\nDry run complete. Re-run without --dry-run to write files.")
    else:
        print(f"\nDone: {total} frame(s) + caption .txt files in {args.out}")
        print("Next: open each .txt, put your trigger word first, describe only what changes,")
        print("then cull down to 15-40 diverse frames before training.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
