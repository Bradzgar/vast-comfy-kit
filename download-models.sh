#!/usr/bin/env bash
# Download any missing models into the persistent model store.
# Sources: manifests/models.txt (HF/direct) + manifests/civitai_lock.json (Civitai).
# Idempotent: existing non-empty files are skipped.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[[ "${FETCH_MODELS:-1}" == "1" ]] || { log "FETCH_MODELS=0, skipping"; exit 0; }
mkdir -p "$MODELS_DIR"

fetch_one() {
  # $1 = url, $2 = absolute dest path
  local url="$1" dest="$2" tmp
  tmp="$dest.part"
  if [[ -s "$dest" ]]; then
    log "skip (exists): ${dest#$MODELS_DIR/}"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  local -a hdr=()
  if [[ "$url" == *huggingface.co* && -n "${HF_TOKEN:-}" ]]; then
    hdr+=( -H "Authorization: Bearer $HF_TOKEN" )
  fi
  log "downloading ${dest#$MODELS_DIR/}"
  if curl -fL --retry 5 --retry-delay 5 --retry-connrefused -C - \
        ${hdr[@]+"${hdr[@]}"} -o "$tmp" "$url"; then
    mv -f "$tmp" "$dest"
    log "  ok: ${dest#$MODELS_DIR/} ($(du -h "$dest" | cut -f1))"
  else
    warn "FAILED: $url (partial kept at $tmp)"
    return 1
  fi
}

log "=== download-models : Hugging Face / direct ==="
if [[ -f "$KIT_DIR/manifests/models.txt" ]]; then
  while read -r url dest || [[ -n "$url" ]]; do
    url="${url#"${url%%[![:space:]]*}"}"
    [[ -z "$url" || "$url" == \#* ]] && continue
    [[ -z "${dest:-}" ]] && dest="$(basename "$url")"
    fetch_one "$url" "$MODELS_DIR/$dest" || true
  done < "$KIT_DIR/manifests/models.txt"
else
  warn "no manifests/models.txt found"
fi

log "=== download-models : Civitai (lockfile) ==="
LOCK="$KIT_DIR/manifests/civitai_lock.json"
if [[ -f "$LOCK" ]] && have python3; then
  # Emit "url<TAB>dest" lines from the lockfile, appending the API token if needed.
  while IFS=$'\t' read -r url dest; do
    [[ -z "$url" ]] && continue
    fetch_one "$url" "$MODELS_DIR/$dest" || true
  done < <(python3 - "$LOCK" "${CIVITAI_API_KEY:-}" <<'PY'
import json, sys, urllib.parse
lock, token = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
with open(lock, encoding="utf-8") as fh:
    data = json.load(fh)
for entry in data.get("models", data if isinstance(data, list) else []):
    url = entry.get("downloadUrl") or ""
    dest = entry.get("dest") or entry.get("filename") or ""
    if not url or not dest:
        continue
    if token and "token=" not in url:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}token={urllib.parse.quote(token)}"
    print(f"{url}\t{dest}")
PY
)
else
  [[ -f "$LOCK" ]] || warn "no civitai_lock.json yet (run resolve-civitai.py locally)"
fi

log "=== download-models done ==="
