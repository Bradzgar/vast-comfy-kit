#!/usr/bin/env bash
# Install / update the ComfyUI custom nodes listed in manifests/custom_nodes.txt.
# Line format: <git-url> [ref] [dirname]   (ref and dirname optional)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

NODES_FILE="$KIT_DIR/manifests/custom_nodes.txt"
NODES_DIR="$COMFY_DIR/custom_nodes"
PY="$VENV_COMFY/bin/python"

[[ -x "$PY" ]] || die "ComfyUI venv missing. Run setup-comfy.sh first."
[[ -f "$NODES_FILE" ]] || die "missing $NODES_FILE"
mkdir -p "$NODES_DIR"

log "=== setup-nodes ==="
while read -r url ref name || [[ -n "$url" ]]; do
  # strip leading whitespace and skip blanks / comments
  url="${url#"${url%%[![:space:]]*}"}"
  [[ -z "$url" || "$url" == \#* ]] && continue
  ref="${ref:-}"; name="${name:-}"
  [[ "$ref" == "-" ]] && ref=""
  [[ "$name" == "-" ]] && name=""
  name="${name:-$(basename "${url%.git}")}"
  dest="$NODES_DIR/$name"

  if [[ ! -d "$dest/.git" ]]; then
    log "cloning $name  <-  $url"
    if ! git clone --recursive "$url" "$dest"; then
      warn "failed to clone $name (skipping)"
      continue
    fi
  else
    log "updating $name"
    git -C "$dest" pull --ff-only || warn "$name pull skipped (local changes?)"
  fi

  if [[ -n "$ref" ]]; then
    log "  $name -> $ref"
    git -C "$dest" fetch --all --tags --prune || true
    git -C "$dest" checkout "$ref" || warn "could not checkout $ref for $name"
    git -C "$dest" submodule update --init --recursive || true
  fi

  if [[ -f "$dest/requirements.txt" ]]; then
    log "  installing requirements for $name"
    "$PY" -m pip install --no-cache-dir -r "$dest/requirements.txt" || warn "requirements failed for $name"
  fi
  if [[ -f "$dest/install.py" ]]; then
    log "  running install.py for $name"
    "$PY" "$dest/install.py" || warn "install.py failed for $name"
  fi
done < "$NODES_FILE"

# Record a lockfile of installed node commits for reproducibility.
LOCK="$KIT_DIR/manifests/custom_nodes.lock"
: > "$LOCK"
while read -r url ref name || [[ -n "$url" ]]; do
  url="${url#"${url%%[![:space:]]*}"}"
  [[ -z "$url" || "$url" == \#* ]] && continue
  ref="${ref:-}"; name="${name:-}"
  [[ "$ref" == "-" ]] && ref=""
  [[ "$name" == "-" ]] && name=""
  name="${name:-$(basename "${url%.git}")}"
  dest="$NODES_DIR/$name"
  [[ -d "$dest/.git" ]] || continue
  printf '%s\t%s\t%s\n' "$url" "$(git -C "$dest" rev-parse HEAD)" "$name" >> "$LOCK"
done < "$NODES_FILE"

log "=== setup-nodes done (lock: $LOCK) ==="
