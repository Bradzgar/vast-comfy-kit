#!/usr/bin/env bash
# Shared helpers and configuration for the vast-comfy-kit scripts.
# Source this from other scripts:  source "$(dirname "$0")/lib.sh"

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load local env file if present (never committed). See env.example.
if [[ -f "$KIT_DIR/env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$KIT_DIR/env"
  set +a
fi

WORKSPACE="${WORKSPACE:-/workspace}"
MODELS_DIR="${MODELS_DIR:-$WORKSPACE/models}"
COMFY_DIR="${COMFY_DIR:-$WORKSPACE/ComfyUI}"
TOOLKIT_DIR="${TOOLKIT_DIR:-$WORKSPACE/ai-toolkit}"
VENVS_DIR="${VENVS_DIR:-$WORKSPACE/venvs}"
VENV_COMFY="${VENV_COMFY:-$VENVS_DIR/comfy}"
VENV_TOOLKIT="${VENV_TOOLKIT:-$VENVS_DIR/toolkit}"
HF_CACHE="${HF_CACHE:-$WORKSPACE/cache/huggingface}"
COMFY_PORT="${COMFY_PORT:-8188}"

export HF_HOME="$HF_CACHE"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-0}"

log()  { printf '\033[1;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Pick a PyTorch wheel index based on GPU compute capability.
# Blackwell (50-series / B-series, compute_cap >= 12) needs cu130; otherwise cu128.
detect_torch_index() {
  if [[ -n "${TORCH_INDEX:-}" ]]; then
    echo "$TORCH_INDEX"
    return 0
  fi
  local cc=""
  if have nvidia-smi; then
    cc="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ')"
  fi
  case "$cc" in
    12.*|13.*|14.*) echo "https://download.pytorch.org/whl/cu130" ;;
    *)              echo "https://download.pytorch.org/whl/cu128" ;;
  esac
}

# Ensure system packages are installed (apt only, best effort). No sudo needed as root.
SUDO=""
if [[ "$(id -u 2>/dev/null || echo 0)" != "0" ]] && have sudo; then SUDO="sudo"; fi
apt_install() {
  if have apt-get; then
    $SUDO apt-get update -qq || true
    $SUDO apt-get install -y -qq "$@" || warn "apt install failed for: $*"
  fi
}

install_torch_into() {
  # $1 = venv dir
  local venv="$1" idx
  idx="$(detect_torch_index)"
  log "installing PyTorch (index: $idx) into $venv"
  "$venv/bin/python" -m pip install -U pip wheel setuptools
  "$venv/bin/python" -m pip install --no-cache-dir \
    torch torchvision torchaudio --index-url "$idx"
}
