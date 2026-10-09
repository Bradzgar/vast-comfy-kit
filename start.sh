#!/usr/bin/env bash
# Bring everything up after a `vastai start instance`.
# vast.ai's on-start script only runs at creation, so run this on every restart.
#
#   bash /workspace/vast-comfy-kit/start.sh             # ComfyUI only
#   bash /workspace/vast-comfy-kit/start.sh --desktop   # ComfyUI + remote desktop
#   DESKTOP=1 bash /workspace/vast-comfy-kit/start.sh   # same via env
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WANT_DESKTOP="${DESKTOP:-0}"
for a in "$@"; do [[ "$a" == "--desktop" ]] && WANT_DESKTOP=1; done

bash "$KIT_DIR/start-comfy.sh"

if [[ "$WANT_DESKTOP" == "1" ]]; then
  bash "$KIT_DIR/setup-desktop.sh"
  bash "$KIT_DIR/start-desktop.sh"
fi

log "start.sh complete"
