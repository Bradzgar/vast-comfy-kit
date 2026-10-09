#!/usr/bin/env bash
# Idempotent Ostris AI Toolkit install (for training the Krea 2 LoRA on RAW).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "=== setup-toolkit ==="
if [[ "${INSTALL_TOOLKIT:-1}" != "1" ]]; then
  log "INSTALL_TOOLKIT=0, skipping"
  exit 0
fi

apt_install git python3-venv curl

# --- source ------------------------------------------------------------------
if [[ ! -d "$TOOLKIT_DIR/.git" ]]; then
  log "cloning Ostris AI Toolkit -> $TOOLKIT_DIR"
  git clone https://github.com/ostris/ai-toolkit.git "$TOOLKIT_DIR"
else
  log "updating ai-toolkit"
  git -C "$TOOLKIT_DIR" pull --ff-only || warn "ai-toolkit pull skipped"
fi

# --- venv + deps -------------------------------------------------------------
if [[ ! -x "$VENV_TOOLKIT/bin/python" ]]; then
  log "creating toolkit venv -> $VENV_TOOLKIT"
  python3 -m venv "$VENV_TOOLKIT"
fi
install_torch_into "$VENV_TOOLKIT"
log "installing ai-toolkit requirements"
"$VENV_TOOLKIT/bin/python" -m pip install --no-cache-dir -r "$TOOLKIT_DIR/requirements.txt"
"$VENV_TOOLKIT/bin/python" -m pip install --no-cache-dir "huggingface_hub[cli]" || true

# --- copy the Krea2 training config, pointing at instance paths --------------
mkdir -p "$TOOLKIT_DIR/config"
if [[ -f "$KIT_DIR/configs/krea2_lora.yml" ]]; then
  sed "s#@MODELS@#$MODELS_DIR#g" "$KIT_DIR/configs/krea2_lora.yml" > "$TOOLKIT_DIR/config/krea2_lora.yml"
  log "wrote $TOOLKIT_DIR/config/krea2_lora.yml"
fi

# --- optional: gated Krea-2-Raw training base (~25 GB) ------------------------
if [[ "${FETCH_TRAIN_BASE:-0}" == "1" ]]; then
  if [[ -z "${HF_TOKEN:-}" ]]; then
    warn "FETCH_TRAIN_BASE=1 but HF_TOKEN is empty; skipping (accept the license on the repo first)"
  else
    DEST="$MODELS_DIR/krea2-raw"
    mkdir -p "$DEST"
    log "downloading krea/Krea-2-Raw -> $DEST (gated; license must be accepted)"
    HF_TOKEN="$HF_TOKEN" "$VENV_TOOLKIT/bin/hf" download krea/Krea-2-Raw \
      --local-dir "$DEST" || warn "Krea-2-Raw download failed (check gate/token)"
  fi
else
  log "FETCH_TRAIN_BASE=0 (set to 1 in env to pull the gated Krea-2-Raw base, ~25 GB)"
fi

log "=== setup-toolkit done ==="
