#!/usr/bin/env bash
# Opcional: añade $SSH_PUBKEY a /root/.ssh/authorized_keys (idempotente).
# En Vast las llaves también se gestionan desde el panel (Instances → llave).
# Este paso es un extra por si quieres acceso directo sin pasar por el panel.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

section "SSH (opcional)"

if [[ -z "${SSH_PUBKEY:-}" ]]; then
  info "SSH_PUBKEY vacío → se omite (gestiona las llaves desde el panel de Vast)."
  exit 0
fi

auth="/root/.ssh/authorized_keys"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch "$auth"
chmod 600 "$auth"

if grep -qF "$SSH_PUBKEY" "$auth"; then
  ok "La llave ya estaba en authorized_keys."
else
  echo "$SSH_PUBKEY" >> "$auth"
  ok "Llave SSH añadida a $auth."
fi
