#!/usr/bin/env bash
# Asegura que los servicios que consume el backend estén arriba tras instalar
# modelos/nodos. NO reinicia ComfyUI si ya está corriendo bien; solo lo levanta
# si nuevos modelos/nodos requieren recargarlo.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

section "Servicios (supervisor)"

have_cmd supervisorctl || die "supervisorctl no disponible."

# ComfyUI carga los checkpoints al arrancar; si acabamos de bajar modelos nuevos,
# conviene reiniciarlo para que los detecte. Reinicio dirigido, no de todo.
for svc in comfyui api-wrapper; do
  if supervisorctl status "$svc" >/dev/null 2>&1; then
    info "Reiniciando $svc para tomar modelos/nodos nuevos…"
    supervisorctl restart "$svc" >/dev/null 2>&1 || warn "No se pudo reiniciar $svc."
  else
    warn "Servicio '$svc' no listado en supervisor (¿nombre distinto en este template?)."
  fi
done

sleep 3
info "Estado actual:"
supervisorctl status 2>/dev/null | awk '{printf "      %-22s %s\n", $1, $2}' || true
ok "Servicios revisados."
