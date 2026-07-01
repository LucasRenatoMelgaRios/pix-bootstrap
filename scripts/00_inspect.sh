#!/usr/bin/env bash
# Inspecciona el entorno de la instancia ANTES de instalar nada.
# Reporta el estado y falla temprano si no es el template esperado.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

section "Inspección del entorno"
detect_paths

# ── GPU ───────────────────────────────────────────────────────────────────────
if have_cmd nvidia-smi; then
  gpu="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
  ok "GPU: ${gpu:-desconocida}"
else
  warn "nvidia-smi no encontrado (¿instancia sin GPU o driver no listo?)"
fi

# ── Sistema ───────────────────────────────────────────────────────────────────
info "OS: $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-desconocido}")"
info "Disco (workspace): $(df -h "$WORKSPACE" 2>/dev/null | awk 'NR==2{print $4" libres de "$2}')"

# ── Workspace / ComfyUI ───────────────────────────────────────────────────────
[[ -d "$WORKSPACE" ]] && ok "WORKSPACE = $WORKSPACE" || die "No existe WORKSPACE ($WORKSPACE)."
if [[ -d "$COMFYUI" ]]; then
  ok "ComfyUI = $COMFYUI"
  ver="$(cat "$COMFYUI/comfyui_version.py" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [[ -n "$ver" ]] && info "ComfyUI versión: $ver"
else
  err "No se encontró ComfyUI en $COMFYUI."
  die "Este bootstrap asume el template oficial Vast base-image ComfyUI (que ya trae ComfyUI). Crea la instancia con ese template."
fi

# ── supervisor ────────────────────────────────────────────────────────────────
if have_cmd supervisorctl; then
  ok "supervisor presente"
  if supervisorctl status >/dev/null 2>&1; then
    info "Servicios:"
    supervisorctl status 2>/dev/null | awk '{printf "      %-22s %s\n", $1, $2}' || true
  fi
else
  die "supervisorctl no encontrado — no es el template esperado."
fi

# ── cloudflared ───────────────────────────────────────────────────────────────
CLOUDFLARED=""
for c in /opt/instance-tools/bin/cloudflared "$(command -v cloudflared 2>/dev/null || true)"; do
  [[ -n "$c" && -x "$c" ]] && { CLOUDFLARED="$c"; break; }
done
if [[ -n "$CLOUDFLARED" ]]; then
  ok "cloudflared: $CLOUDFLARED ($("$CLOUDFLARED" --version 2>/dev/null | head -1))"
else
  warn "cloudflared no encontrado — 50_tunnel.sh intentará instalarlo si hace falta."
fi

# ── Puertos internos (comfy nativo / API wrapper) ────────────────────────────
wp="$(wrapper_port)"; cp="$(comfy_port)"
probe() { curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:$1/" 2>/dev/null || echo "000"; }
info "API Wrapper 127.0.0.1:$wp → HTTP $(probe "$wp")   (405/404/200 = arriba)"
info "ComfyUI     127.0.0.1:$cp → HTTP $(probe "$cp")"

# ── Modelos / custom_nodes existentes ────────────────────────────────────────
if [[ -d "$COMFYUI/models/checkpoints" ]]; then
  n="$(find "$COMFYUI/models/checkpoints" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  info "Checkpoints existentes: $n"
fi
if [[ -d "$COMFYUI/custom_nodes" ]]; then
  n="$(find "$COMFYUI/custom_nodes" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  info "Custom nodes existentes: $n"
fi

ok "Inspección completa."
