#!/usr/bin/env bash
# Instala el túnel Cloudflare como servicio de supervisor.
# ESTA es la pieza que da identidad estable: el MISMO CF_TUNNEL_TOKEN en cualquier
# instancia hace que comfy.vericerbiz.com apunte aquí → el backend Laravel no cambia.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

section "Túnel Cloudflare (identidad estable)"

require_env CF_TUNNEL_TOKEN "Pon CF_TUNNEL_TOKEN en .env o como env var de la instancia (ver .env.example)." \
  || die "Sin CF_TUNNEL_TOKEN no se puede levantar el túnel."

# Localiza cloudflared
CLOUDFLARED=""
for c in /opt/instance-tools/bin/cloudflared "$(command -v cloudflared 2>/dev/null || true)"; do
  [[ -n "$c" && -x "$c" ]] && { CLOUDFLARED="$c"; break; }
done
if [[ -z "$CLOUDFLARED" ]]; then
  info "cloudflared no encontrado; instalando binario oficial…"
  arch="$(uname -m)"; case "$arch" in x86_64) a=amd64;; aarch64|arm64) a=arm64;; *) a=amd64;; esac
  mkdir -p /opt/instance-tools/bin
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${a}" \
    -o /opt/instance-tools/bin/cloudflared && chmod +x /opt/instance-tools/bin/cloudflared \
    && CLOUDFLARED=/opt/instance-tools/bin/cloudflared || die "No se pudo instalar cloudflared."
fi
ok "cloudflared: $CLOUDFLARED"

if ! have_cmd supervisorctl; then
  die "supervisorctl no disponible; no puedo registrar el servicio del túnel."
fi

conf="/etc/supervisor/conf.d/cf-comfy-tunnel.conf"
# OJO: el orden importa → `--token` DESPUÉS de `run`, o cloudflared aborta con
# "flag provided but not defined: -token".
cat > "$conf" <<EOF
[program:cf-comfy-tunnel]
environment=PROC_NAME="%(program_name)s"
command=$CLOUDFLARED tunnel --no-autoupdate run --token $CF_TUNNEL_TOKEN
autostart=true
autorestart=unexpected
startsecs=5
stopasgroup=true
killasgroup=true
stopsignal=TERM
stopwaitsecs=10
stdout_logfile=/dev/stdout
redirect_stderr=true
stdout_events_enabled=true
stdout_logfile_maxbytes=0
stdout_logfile_backups=0
EOF
chmod 600 "$conf"   # contiene el token → solo root
ok "Escrito $conf"

supervisorctl reread >/dev/null 2>&1 || true
supervisorctl update >/dev/null 2>&1 || true
# Reinicia por si ya existía con otro token
supervisorctl restart cf-comfy-tunnel >/dev/null 2>&1 || supervisorctl start cf-comfy-tunnel >/dev/null 2>&1 || true

sleep 4
status="$(supervisorctl status cf-comfy-tunnel 2>/dev/null | awk '{print $2}')"
if [[ "$status" == "RUNNING" ]]; then
  ok "Túnel corriendo (supervisor: RUNNING)."
else
  warn "Estado del túnel: ${status:-desconocido}. Revisa 'supervisorctl tail -f cf-comfy-tunnel'."
fi
