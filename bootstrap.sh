#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  pix-bootstrap · reconstruye el servidor GPU (ComfyUI) desde cero en <15 min.
#
#  Uso en una instancia Vast NUEVA (template base-image ComfyUI):
#     git clone <repo> && cd pix-bootstrap
#     cp .env.example .env && nano .env      # pega CIVITAI_TOKEN y CF_TUNNEL_TOKEN
#     ./bootstrap.sh
#
#  (Zero-touch: si defines CIVITAI_TOKEN/CF_TUNNEL_TOKEN como env vars de la
#   instancia, NO hace falta el archivo .env — ver setup/on-start.sh.)
#
#  Flags:
#    --dry-run       solo inspecciona (00) y sale; no instala nada
#    --skip-models   omite la descarga de modelos
#    --skip-tunnel   omite el túnel Cloudflare
#    --only <paso>   corre solo un paso: inspect|ssh|deps|nodes|models|tunnel|services|health
#    --gen           al final, hace una generación de prueba real
#    --yes           no pregunta (no interactivo)
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$ROOT/scripts"
# shellcheck source=scripts/lib.sh
source "$SCRIPTS/lib.sh"

DRY_RUN=0; SKIP_MODELS=0; SKIP_TUNNEL=0; ONLY=""; DO_GEN=0; ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-models) SKIP_MODELS=1 ;;
    --skip-tunnel) SKIP_TUNNEL=1 ;;
    --only) ONLY="${2:-}"; shift ;;
    --gen) DO_GEN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) die "Flag desconocido: $1 (usa --help)" ;;
  esac
  shift
done

printf "${C_BLUE}"
cat <<'BANNER'
  ┌──────────────────────────────────────────────┐
  │  pix-bootstrap · servidor GPU ComfyUI         │
  └──────────────────────────────────────────────┘
BANNER
printf "${C_RESET}"

# ── Carga de secretos: .env si existe; si no, se usan las env vars ya exportadas ─
if [[ -f "$ROOT/.env" ]]; then
  set -a; # exporta todo lo que se sourcee
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
  ok "Cargado .env"
else
  warn "No hay .env — usando variables de entorno existentes (modo zero-touch)."
fi

t_start=$(date +%s)
declare -a RESULTS=()
step() { # step <clave> <descripción> <comando...>
  local key="$1" desc="$2"; shift 2
  if [[ -n "$ONLY" && "$ONLY" != "$key" ]]; then return 0; fi
  if "$@"; then RESULTS+=("✓ $desc"); else RESULTS+=("✗ $desc"); FAILED=1; fi
}
FAILED=0

# ── 00 · Inspección (siempre) ────────────────────────────────────────────────
step inspect "Inspección" bash "$SCRIPTS/00_inspect.sh"

if [[ "$DRY_RUN" -eq 1 ]]; then
  section "Dry-run: solo inspección. Fin."
  exit 0
fi

# ── Pasos de instalación ─────────────────────────────────────────────────────
step ssh      "SSH (opcional)"        bash "$SCRIPTS/10_ssh.sh"
step deps     "Dependencias"          bash "$SCRIPTS/20_dependencies.sh"
step nodes    "Custom nodes"          bash "$SCRIPTS/30_custom_nodes.sh"

if [[ "$SKIP_MODELS" -eq 0 ]]; then
  step models "Modelos" bash -c "source '$SCRIPTS/lib.sh'; section 'Modelos'; detect_paths; \
      python3 '$SCRIPTS/40_models.py' --comfyui \"\$COMFYUI\""
else
  warn "Modelos omitidos (--skip-models)."
fi

if [[ "$SKIP_TUNNEL" -eq 0 ]]; then
  step tunnel "Túnel Cloudflare" bash "$SCRIPTS/50_tunnel.sh"
else
  warn "Túnel omitido (--skip-tunnel)."
fi

step services "Servicios" bash "$SCRIPTS/60_services.sh"

# ── Health check final ───────────────────────────────────────────────────────
if [[ "$DO_GEN" -eq 1 ]]; then
  step health "Health check (+gen)" bash "$SCRIPTS/90_healthcheck.sh" --gen
else
  step health "Health check" bash "$SCRIPTS/90_healthcheck.sh"
fi

# ── Resumen ──────────────────────────────────────────────────────────────────
t_end=$(date +%s); mins=$(( (t_end - t_start) / 60 )); secs=$(( (t_end - t_start) % 60 ))
section "Resumen"
for r in "${RESULTS[@]}"; do
  if [[ "$r" == ✓* ]]; then printf "    ${C_GREEN}%s${C_RESET}\n" "$r"; else printf "    ${C_RED}%s${C_RESET}\n" "$r"; fi
done
printf "\n    Tiempo total: ${C_DIM}%dm %ds${C_RESET}\n" "$mins" "$secs"
if [[ "$FAILED" -eq 0 ]]; then
  printf "    ${C_GREEN}Servidor listo → https://comfy.vericerbiz.com${C_RESET}\n"
  exit 0
else
  printf "    ${C_RED}Hubo pasos fallidos (ver arriba). Revisa docs/troubleshooting.md${C_RESET}\n"
  exit 1
fi
