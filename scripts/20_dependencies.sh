#!/usr/bin/env bash
# Verifica dependencias base. Instala SOLO lo que falte. NUNCA `apt upgrade`.
# El template de Vast ya trae casi todo; esto rellena huecos (git, python, pyyaml).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

section "Dependencias base"

apt_updated=0
apt_install() {
  # apt_install <paquete> <comando-que-provee>
  local pkg="$1" cmd="$2"
  if have_cmd "$cmd"; then ok "$cmd ya presente"; return 0; fi
  if ! have_cmd apt-get; then warn "apt-get no disponible; instala $pkg manualmente."; return 0; fi
  if [[ "$apt_updated" -eq 0 ]]; then
    info "apt-get update (solo índices, NO upgrade)…"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || warn "apt-get update falló (sigo)."
    apt_updated=1
  fi
  info "Instalando $pkg…"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" >/dev/null 2>&1 \
    && ok "$pkg instalado" || warn "No se pudo instalar $pkg."
}

apt_install git git
apt_install curl curl
apt_install ca-certificates update-ca-certificates || true

# Python 3 (el template lo trae; solo verificamos)
if have_cmd python3; then ok "python3: $(python3 --version 2>&1)"; else die "python3 no disponible."; fi

# PyYAML para el descargador declarativo (instala solo si falta)
if python3 -c 'import yaml' >/dev/null 2>&1; then
  ok "PyYAML ya presente"
else
  info "Instalando PyYAML (pip)…"
  python3 -m pip install --quiet --disable-pip-version-check pyyaml >/dev/null 2>&1 \
    || python3 -m pip install --quiet --disable-pip-version-check --break-system-packages pyyaml >/dev/null 2>&1 \
    || warn "No se pudo instalar PyYAML; 40_models.py intentará un fallback."
  python3 -c 'import yaml' >/dev/null 2>&1 && ok "PyYAML listo"
fi

ok "Dependencias verificadas."
