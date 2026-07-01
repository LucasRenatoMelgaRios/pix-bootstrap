#!/usr/bin/env bash
# ── Snippet para el "On-start script" de Vast (provisioning zero-touch) ────────
# Pégalo en el campo On-start al crear la instancia. Requiere que definas como
# env vars de la instancia (en la misma pantalla de creación):
#     CIVITAI_TOKEN=...
#     CF_TUNNEL_TOKEN=eyJ...
#     (opcional) HF_TOKEN, SSH_PUBKEY
# y que ajustes REPO abajo a la URL pública de tu pix-bootstrap.
# ──────────────────────────────────────────────────────────────────────────────
set -e
REPO="https://github.com/CHANGE_ME/pix-bootstrap.git"   # ← tu repo público
DIR="/workspace/pix-bootstrap"

if [ ! -d "$DIR/.git" ]; then
  git clone "$REPO" "$DIR"
else
  git -C "$DIR" pull --ff-only || true
fi

cd "$DIR"
# No hace falta .env: bootstrap toma los tokens de las env vars de la instancia.
bash ./bootstrap.sh --yes
