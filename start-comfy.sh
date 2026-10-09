#!/usr/bin/env bash
# Start (or restart) ComfyUI in a tmux session so it survives SSH disconnects.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PY="$VENV_COMFY/bin/python"
[[ -x "$PY" ]] || { die "ComfyUI venv missing at $VENV_COMFY (run setup-comfy.sh first)"; }

if tmux has-session -t comfy 2>/dev/null; then
  log "ComfyUI already running in tmux 'comfy'"
else
  log "starting ComfyUI in tmux 'comfy' (port $COMFY_PORT)"
  tmux new-session -d -s comfy \
    "cd '$COMFY_DIR' && '$PY' main.py --listen 0.0.0.0 --port $COMFY_PORT 2>&1 | tee -a '$WORKSPACE/comfy.log'"
  sleep 3
fi
log "ComfyUI -> http://localhost:$COMFY_PORT  (via SSH tunnel)"
