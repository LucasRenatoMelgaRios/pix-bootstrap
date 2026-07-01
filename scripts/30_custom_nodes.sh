#!/usr/bin/env bash
# Instala/actualiza custom_nodes declarados en config/custom_nodes.yaml (idempotente).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

section "Custom nodes"
detect_paths

CFG="$ROOT/config/custom_nodes.yaml"
[[ -f "$CFG" ]] || { warn "No hay $CFG; se omite."; exit 0; }

dest_dir="$COMFYUI/custom_nodes"
mkdir -p "$dest_dir"

# Extrae las entradas como líneas "url|ref|pip" usando python (PyYAML).
mapfile -t entries < <(python3 - "$CFG" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1])) or {}
for n in (data.get("nodes") or []):
    url = (n.get("url") or "").strip()
    if not url:
        continue
    ref = (n.get("ref") or "").strip()
    pip = "false" if n.get("pip") is False else "true"
    print(f"{url}|{ref}|{pip}")
PY
)

if [[ "${#entries[@]}" -eq 0 ]]; then
  ok "Sin custom nodes declarados (nada que instalar)."
  exit 0
fi

for e in "${entries[@]}"; do
  IFS='|' read -r url ref pip <<<"$e"
  name="$(basename "${url%.git}")"
  target="$dest_dir/$name"
  if [[ -d "$target/.git" ]]; then
    info "Actualizando $name…"
    git -C "$target" pull --ff-only --quiet || warn "git pull falló en $name (sigo)."
  else
    info "Clonando $name…"
    git clone --quiet "$url" "$target" || { warn "clone falló: $url"; continue; }
  fi
  [[ -n "$ref" ]] && git -C "$target" checkout --quiet "$ref" || true
  if [[ "$pip" == "true" && -f "$target/requirements.txt" ]]; then
    info "pip install requirements de $name…"
    python3 -m pip install --quiet --disable-pip-version-check -r "$target/requirements.txt" >/dev/null 2>&1 \
      || python3 -m pip install --quiet --disable-pip-version-check --break-system-packages -r "$target/requirements.txt" >/dev/null 2>&1 \
      || warn "pip requirements de $name falló."
  fi
  ok "$name"
done
