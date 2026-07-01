#!/usr/bin/env bash
# Helpers compartidos por los scripts de pix-bootstrap. Se hace `source`, no se ejecuta.

# Colores (se desactivan si no hay TTY)
if [[ -t 1 ]]; then
  C_RESET='\033[0m'; C_BLUE='\033[1;34m'; C_GREEN='\033[1;32m'
  C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_DIM='\033[2m'
else
  C_RESET=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''
fi

section() { printf "\n${C_BLUE}==> %s${C_RESET}\n" "$*"; }
info()    { printf "    %s\n" "$*"; }
ok()      { printf "    ${C_GREEN}✓${C_RESET} %s\n" "$*"; }
warn()    { printf "    ${C_YELLOW}!${C_RESET} %s\n" "$*"; }
err()     { printf "    ${C_RED}✗ %s${C_RESET}\n" "$*" >&2; }
die()     { err "$*"; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_env() {
  # require_env VAR "mensaje de ayuda"
  local name="$1" help="${2:-}"
  if [[ -z "${!name:-}" ]]; then
    err "Falta la variable de entorno requerida: ${name}"
    [[ -n "$help" ]] && info "$help"
    return 1
  fi
}

# Detecta la raíz del workspace y de ComfyUI. Exporta WORKSPACE y COMFYUI.
detect_paths() {
  WORKSPACE="${WORKSPACE:-${WORKSPACE_DIR:-/workspace}}"
  if [[ ! -d "$WORKSPACE" ]]; then
    # fallbacks comunes
    for c in /workspace /root/workspace "$HOME/workspace"; do
      [[ -d "$c" ]] && { WORKSPACE="$c"; break; }
    done
  fi
  COMFYUI="${COMFYUI:-$WORKSPACE/ComfyUI}"
  export WORKSPACE COMFYUI
}

# Puerto interno del API Wrapper (default 18288, override con WRAPPER_PORT)
wrapper_port() { echo "${WRAPPER_PORT:-18288}"; }
# Puerto interno de ComfyUI nativo (default 18188)
comfy_port()   { echo "${COMFY_PORT:-18188}"; }
