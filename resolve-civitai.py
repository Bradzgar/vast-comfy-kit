#!/usr/bin/env python3
r"""
resolve-civitai.py -- Run this ONCE on your local machine.

It walks a model directory, computes SHA256 for each model file, asks the Civitai
API which model version each hash belongs to, and writes manifests/civitai_lock.json.
The vast.ai instance then downloads straight from that lockfile (no resolution there).

Usage (Windows PowerShell / cmd / bash):
    set CIVITAI_API_KEY=xxxxxxxx        # PowerShell: $env:CIVITAI_API_KEY="xxxx"
    python resolve-civitai.py --scan "Z:\ComfyUI\models" --out manifests\civitai_lock.json

Only stdlib is required (no pip install).
"""

import argparse
import datetime as _dt
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://civitai.com/api/v1/model-versions/by-hash/{hash}"
MODEL_EXTS = {".safetensors", ".ckpt", ".pt", ".pth", ".gguf", ".bin"}
UA = "vast-comfy-kit/resolve-civitai"


def sha256_of(path: str, chunk: int = 8 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    total = os.path.getsize(path)
    done = 0
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(chunk), b""):
            h.update(block)
            done += len(block)
            pct = (done / total * 100) if total else 100
            sys.stdout.write(f"\r  hashing {os.path.basename(path)}  {pct:5.1f}%")
            sys.stdout.flush()
    sys.stdout.write("\r" + " " * 80 + "\r")
    return h.hexdigest()


def civitai_lookup(digest: str, api_key: str, retries: int = 5):
    url = API.format(hash=digest)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    if api_key:
        req.add_header("Authorization", f"Bearer {api_key}")
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None
            if exc.code in (429, 500, 502, 503, 504):
                wait = 2 ** attempt * 2
                print(f"\n  HTTP {exc.code}, backing off {wait}s...")
                time.sleep(wait)
                continue
            print(f"\n  HTTP {exc.code} for {digest}")
            return None
        except Exception as exc:  # noqa: BLE001
            print(f"\n  error {exc!r}, retrying...")
            time.sleep(2 ** attempt)
    return None


def pick_file(version: dict, digest: str):
    for f in version.get("files", []):
        hashes = f.get("hashes") or {}
        if (hashes.get("SHA256") or "").lower() == digest.lower():
            return f
    files = version.get("files") or []
    return files[0] if files else None


def load_env_file() -> None:
    """Populate os.environ from ./env (next to this script) if present."""
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "env")
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = val


def main() -> int:
    load_env_file()
    ap = argparse.ArgumentParser(description="Resolve local model hashes to Civitai download URLs.")
    ap.add_argument("--scan", action="append", required=True,
                    help="Directory to scan (repeatable). Use your models root so dest paths are right.")
    ap.add_argument("--out", default="manifests/civitai_lock.json",
                    help="Output lockfile path.")
    ap.add_argument("--models-root", default=None,
                    help="Base dir that dest paths are relative to (default: first --scan dir).")
    ap.add_argument("--delay", type=float, default=1.2, help="Seconds between API calls.")
    args = ap.parse_args()

    api_key = os.environ.get("CIVITAI_API_KEY", "").strip()
    if not api_key:
        print("WARNING: CIVITAI_API_KEY not set. Some NSFW / restricted models will 404.")
        print("         Set it before running for full results.\n")

    root = os.path.abspath(args.models_root or args.scan[0])
    files = []
    for scan in args.scan:
        scan = os.path.abspath(scan)
        for dirpath, _dirs, names in os.walk(scan):
            for n in names:
                if os.path.splitext(n)[1].lower() in MODEL_EXTS:
                    files.append(os.path.join(dirpath, n))
    files = sorted(set(files))
    if not files:
        print("No model files found.")
        return 1

    print(f"Scanning {len(files)} files under {root}\n")
    resolved, unresolved = [], []
    for path in files:
        digest = sha256_of(path)
        name = os.path.basename(path)
        print(f"  {name}  {digest[:12]}...")
        version = civitai_lookup(digest, api_key)
        time.sleep(args.delay)
        if not version:
            unresolved.append({"filename": name, "sha256": digest})
            print("    -> not found on Civitai")
            continue
        f = pick_file(version, digest) or {}
        model = version.get("model") or {}
        dest = os.path.relpath(path, root).replace("\\", "/")
        entry = {
            "filename": name,
            "dest": dest,
            "sha256": digest,
            "modelId": model.get("id"),
            "modelName": model.get("name"),
            "modelType": model.get("type"),
            "versionId": version.get("id"),
            "versionName": version.get("name"),
            "baseModel": version.get("baseModel"),
            "downloadUrl": f.get("downloadUrl"),
            "sizeKB": f.get("sizeKB"),
        }
        resolved.append(entry)
        print(f"    -> {model.get('name')} / {version.get('name')}  ({version.get('baseModel')})")

    out = {
        "generated": _dt.datetime.now(_dt.timezone.utc).isoformat(),
        "modelsRoot": root,
        "count": len(resolved),
        "models": resolved,
        "unresolved": unresolved,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    print(f"\nWrote {args.out}: {len(resolved)} resolved, {len(unresolved)} unresolved.")
    if unresolved:
        print("Unresolved files (add manually to manifests/models.txt if needed):")
        for u in unresolved:
            print(f"  - {u['filename']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
