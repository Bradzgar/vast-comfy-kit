# vast-comfy-kit

Recreate your local ComfyUI setup (plus Ostris AI Toolkit for Krea 2 LoRA training) on a
fresh vast.ai GPU with **one command**, and access it purely over **SSH** — no vast.ai web
instance tools.

Your local setup this mirrors:
- ComfyUI **v0.39.0**, Python 3.12, torch (cu128 on your RTX 5070 / cu130 on Blackwell)
- 18 custom nodes (KJNodes, Impact-Pack, Easy-Use, LayerStyle, rgthree, RES4LYF, GGUF,
  Lora-Manager, Krea2T-Enhancer, SeedVR2, WAS suite, …)
- Models: Krea 2 Turbo fp8 + Qwen3-VL-4B TE + Qwen VAE; Z-Image Turbo + Qwen3-4B TE + ae VAE;
  SAM; your Civitai LoRAs
- Ostris AI Toolkit configured to train the Krea 2 LoRA on **RAW**

---

## 0. Rotate your tokens first (important)

If your tokens were ever pasted into a chat/commit, invalidate them and make new ones:

- Civitai: <https://civitai.com/user/account> → API Keys → delete → **Add API key**
- Hugging Face: <https://huggingface.co/settings/tokens> → **Invalidate** → **Create new token** (Read)
  - Then accept the licenses at <https://huggingface.co/krea/Krea-2-Raw> and
    <https://huggingface.co/krea/Krea-2-Turbo> **on that same account**.

Never commit the `env` file. It is in `.gitignore`.

---

## 1. Local prep (on your Windows machine, one time)

### 1.1 Create your env file

```powershell
cd C:\Users\bradj\vast-comfy-kit
Copy-Item env.example env
notepad env   # fill in HF_TOKEN and CIVITAI_API_KEY
```

### 1.2 Resolve your Civitai LoRAs to a lockfile

This hashes your local models, asks Civitai to identify them, and records download URLs so the
instance never has to. Run it once (it can take a while for large sets):

```powershell
cd C:\Users\bradj\vast-comfy-kit
$env:CIVITAI_API_KEY="<your_new_civitai_key>"
python resolve-civitai.py --scan "Z:\ComfyUI\models" --out manifests\civitai_lock.json
```

Files it can't find on Civitai are listed as `unresolved` — add those by hand to
`manifests\models.txt` (`url  dest`) if you want them.

### 1.3 Put the kit on GitHub (so instances can self-bootstrap)

Using the GitHub CLI (or the website):

```powershell
cd C:\Users\bradj\vast-comfy-kit
git init
git add .
git commit -m "vast-comfy-kit"
gh repo create vast-comfy-kit --private --source=. --push
```

Copy the repo URL (e.g. `https://github.com/<you>/vast-comfy-kit.git`). If the repo is private,
append a deploy method — simplest is to make it private and use a **classic PAT** in the clone URL
inside the on-start command, or use a deploy key later. (A public repo with no secrets in it also
works: `env` is gitignored, so the only sensitive data are your *model lists*.)

> No-GitHub fallback: create the instance once, `scp` this folder to `/workspace/vast-comfy-kit`
> (see §5), then run `onstart.sh`. Set the volume as described so it persists.

---

## 2. Create the persistent volume (once)

- vast.ai web UI: **Storage** (or during instance creation) → **Create volume**, size **150 GB**
  (models ~55 GB + ComfyUI + venvs + checkpoints), mount path **`/workspace`**.
- CLI:
  ```bash
  vastai create volume --size 150 --disk_name comfyvol
  ```

Attach this volume to every instance (mount at `/workspace`). Everything lives there, so restarts
are fast and cheap — only the GPU is billed while running.

---

## 3. Create the instance

In the vast.ai UI (or CLI). Key fields:

| Field | Value |
|---|---|
| Image | A CUDA **12.8+ / 13.x** PyTorch image. For 24 GB+ cards an `nvidia/cuda:12.8.1-devel-ubuntu22.04`-style base works; PyTorch is installed by the kit. |
| GPU | Pick by VRAM: **24 GB** = comfortable Krea 2 inference; **48–80 GB** for fast LoRA training. Blackwell (5090/B200) needs cu130. |
| Disk | ~60 GB (models go on the volume, not the instance disk) |
| Volume | Attach `comfyvol` at `/workspace` |
| SSH key | Select your existing `vastai.pub` key (already in `~`), or add it under Account → SSH Keys |
| On-start script | See below |

**On-start script:**

```bash
bash -c "git clone https://<you>:<PAT>@github.com/<you>/vast-comfy-kit.git /workspace/vast-comfy-kit 2>/dev/null || true; bash /workspace/vast-comfy-kit/onstart.sh; exec sleep infinity"
```

- For a **public** repo drop the `<you>:<PAT>@` part.
- `exec sleep infinity` keeps the container alive after setup finishes.
- On a **fresh** volume this installs everything and downloads models (20–60 min).
  On a **warm** volume it just verifies and starts ComfyUI (seconds).

CLI example (edit to taste):

```bash
vastai create instance <OFFER_ID> --image <IMAGE> --disk 60 \
  --onstart-cmd 'bash -c "git clone <REPO> /workspace/vast-comfy-kit; bash /workspace/vast-comfy-kit/onstart.sh; exec sleep infinity"' \
  --env '-p 8188:8188' --ssh --direct
```

---

## 4. Connect (the part that used to be painful)

Find `HOST` and `PORT` on the instance card (**Connect** → SSH). Then, from your Windows machine:

```powershell
ssh -i C:\Users\bradj\vastai -p <PORT> root@<HOST>
```

Watch setup progress:

```bash
tail -f /workspace/onstart.log
tmux attach -t comfy      # ComfyUI logs (detach: Ctrl-b then d)
```

### 4.1 VS Code Remote-SSH (recommended)

Add to `C:\Users\bradj\.ssh\config`:

```
Host vast-comfy
    HostName <HOST>
    User root
    Port <PORT>
    IdentityFile C:/Users/bradj/vastai
    IdentitiesOnly yes
    LocalForward 8188 localhost:8188
```

Then in VS Code: **Remote-SSH → Connect to Host → vast-comfy**. You get a real terminal, file
editing, and the ComfyUI port tunneled automatically.

### 4.2 Open ComfyUI locally

With the tunnel (`LocalForward 8188` above) or a manual one:

```powershell
ssh -i C:\Users\bradj\vastai -p <PORT> root@<HOST> -L 8188:localhost:8188 -N
```

Then open <http://localhost:8188> in your local browser. Nothing needs to be exposed publicly.

---

## 5. Manual / no-GitHub fallback

If you don't want a repo, copy the kit to the volume once:

```powershell
scp -i C:\Users\bradj\vastai -P <PORT> -r C:\Users\bradj\vast-comfy-kit root@<HOST>:/workspace/vast-comfy-kit
ssh  -i C:\Users\bradj\vastai -p <PORT> root@<HOST> "bash /workspace/vast-comfy-kit/onstart.sh"
```

Because `/workspace` is the persistent volume, the kit stays across restarts.

---

## 6. Run the scripts by hand (optional)

```bash
cd /workspace/vast-comfy-kit
bash setup-comfy.sh        # ComfyUI + torch + venv + extra_model_paths.yaml
bash setup-nodes.sh        # custom nodes (+ writes manifests/custom_nodes.lock)
bash setup-toolkit.sh      # Ostris AI Toolkit
bash download-models.sh    # fetch missing models (idempotent)
```

Restart ComfyUI:

```bash
tmux kill-session -t comfy 2>/dev/null
tmux new-session -d -s comfy "cd /workspace/ComfyUI && /workspace/venvs/comfy/bin/python main.py --listen 0.0.0.0 --port 8188 2>&1 | tee -a /workspace/comfy.log"
```

---

## 7. Train the Krea 2 LoRA on the instance

1. Set `FETCH_TRAIN_BASE=1` in `env` and re-run `setup-toolkit.sh` (pulls the gated
   `krea/Krea-2-Raw`, ~25 GB). Requires `HF_TOKEN` with the license accepted.
2. Put a dataset at `/workspace/datasets/my-dataset` (`NNN.png` + `NNN.txt` pairs).
3. Edit `/workspace/ai-toolkit/config/krea2_lora.yml` — set `trigger_word` and `folder_path`.
4. Run in tmux so it survives disconnects:

```bash
tmux new-session -d -s train \
  "cd /workspace/ai-toolkit && source /workspace/venvs/toolkit/bin/activate && \
   python run.py config/krea2_lora.yml 2>&1 | tee -a /workspace/train.log"
tmux attach -t train
```

5. **Validate the result on Turbo** (8 steps, CFG 0.0, mu 1.15) in ComfyUI — never judge on RAW
   previews alone. Checkpoints land in `/workspace/ai-toolkit/output/...`.

---

## 8. Cost / friction tips

- **Persistent volume is the whole game:** models download once, restarts are seconds, you stop
  paying for setup mistakes.
- **Stop, don't destroy**, when pausing: the volume survives; the instance disk does not.
- Set `FETCH_MODELS=0` in `env` for fast restarts (skips the model pass).
- Prefer interruptible/spot offers for training; keep a snapshot of container state before long
  runs if the offer can be preempted.
- cu130 vs cu128 is auto-detected; if you ever hit “optimized CUDA operations” warnings on a
  50-series card, force `TORCH_INDEX=https://download.pytorch.org/whl/cu130` in `env`.

---

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| `HF` download 401/403 | Token missing or license not accepted on that account. Fix in `env`, re-run `download-models.sh`. |
| Civitai downloads fail | `CIVITAI_API_KEY` missing/invalid, or the model needs the key. Re-run `resolve-civitai.py` after rotating. |
| ComfyUI won't start | `tmux attach -t comfy` and read the error; usually a node's `requirements.txt` failed — re-run `setup-nodes.sh`. |
| Custom node import error | Node needs its own deps or a specific ComfyUI version; pin its `ref` in `manifests/custom_nodes.txt`. |
| Missing a model in ComfyUI | It must be under `/workspace/models/<subdir>`; `extra_model_paths.yaml` maps the subdirs. |
| TensorRT/attention warnings on 50-series | Set `TORCH_INDEX` to cu130. |
| Fresh instance is slow | First boot downloads models; check `tail -f /workspace/onstart.log`. Subsequent boots are fast. |

---

## File map

```
vast-comfy-kit/
├── onstart.sh              # vast.ai on-start entrypoint (idempotent)
├── lib.sh                  # shared vars + helpers (torch index detection, etc.)
├── setup-comfy.sh          # ComfyUI + torch + venv + extra_model_paths.yaml
├── setup-nodes.sh          # custom nodes from manifests/custom_nodes.txt
├── setup-toolkit.sh        # Ostris AI Toolkit + Krea2 training config
├── download-models.sh      # fetch models (HF + Civitai lockfile), resume-friendly
├── resolve-civitai.py      # run LOCALLY: hash -> Civitai API -> lockfile
├── env.example             # copy to env; holds tokens + options
├── manifests/
│   ├── custom_nodes.txt    # node repos (+ optional ref/dirname)
│   ├── models.txt          # HF/direct model URLs -> dest
│   └── civitai_lock.json   # generated by resolve-civitai.py
└── configs/
    ├── extra_model_paths.yaml   # reference copy
    └── krea2_lora.yml           # AI Toolkit training config (@MODELS@ substituted)
```
