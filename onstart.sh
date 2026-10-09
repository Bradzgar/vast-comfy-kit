#!/usr/bin/env bash
# vast.ai on-start entrypoint.
# Point your instance's "On-start script" at this file, e.g.:
#
#   git clone <YOUR_REPO_URL> /workspace/vast-comfy-kit && \
#     nohup bash /workspace/vast-comfy-kit/onstart.sh >/workspace/onstart.console.log 2>&1 &
#
# It is idempotent: on a fresh volume it installs everything; on a warm volume it
# just verifies and (re)starts ComfyUI.

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$KIT_DIR/lib.sh"

LOG="$WORKSPACE/onstart.log"
mkdir -p "$WORKSPACE" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

log "=================================================================="
log "vast-comfy-kit onstart  $(date)"
log "kit: $KIT_DIR"
have nvidia-smi && nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv,noheader || true

# 1) Wait for the persistent volume to be mounted at WORKSPACE.
for _ in $(seq 1 60); do
  if mountpoint -q "$WORKSPACE" 2>/dev/null || [[ -w "$WORKSPACE" ]]; then
    break
  fi
  sleep 2
done
log "workspace ready: $WORKSPACE"

# 2) Install / verify everything.
bash "$KIT_DIR/setup-comfy.sh"
bash "$KIT_DIR/setup-nodes.sh"   || warn "setup-nodes had errors"
bash "$KIT_DIR/setup-toolkit.sh" || warn "setup-toolkit had errors"
bash "$KIT_DIR/download-models.sh" || warn "download-models had errors (re-run later)"

# 3) Start services (ComfyUI, and optionally the remote desktop).
bash "$KIT_DIR/start-comfy.sh" || warn "start-comfy failed"
if [[ "${DESKTOP:-0}" == "1" ]]; then
  bash "$KIT_DIR/setup-desktop.sh" || warn "setup-desktop failed"
  bash "$KIT_DIR/start-desktop.sh" || warn "start-desktop failed"
fi

log "ComfyUI: http://localhost:$COMFY_PORT  (tunnel: ssh -L $COMFY_PORT:localhost:$COMFY_PORT ...)"
log "Attach logs:  tmux attach -t comfy"
log "vast-comfy-kit onstart COMPLETE"
log "=================================================================="
