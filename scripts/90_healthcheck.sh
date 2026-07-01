#!/usr/bin/env bash
# Comprobaciones finales: ComfyUI, API Wrapper, túnel, y (opcional) una generación real.
# Con --gen hace una generación de prueba vía el wrapper local.
set -uo pipefail   # sin -e: queremos reportar todos los checks aunque uno falle
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

section "Health check"
detect_paths
wp="$(wrapper_port)"; cp="$(comfy_port)"
fail=0

check_http() { # check_http <nombre> <url> <codigos-ok-regex>
  local name="$1" url="$2" okre="$3" code
  code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "$url" 2>/dev/null || echo 000)"
  if [[ "$code" =~ $okre ]]; then ok "$name → HTTP $code"; else err "$name → HTTP $code"; fail=1; fi
}

# 1) ComfyUI nativo
check_http "ComfyUI  127.0.0.1:$cp" "http://127.0.0.1:$cp/system_stats" '^(200)$'
# 2) API Wrapper (405/404/200 = vivo; sirve para la ruta de Laravel)
check_http "Wrapper  127.0.0.1:$wp" "http://127.0.0.1:$wp/" '^(200|404|405)$'

# 3) Túnel local (supervisor) + accesibilidad pública
if have_cmd supervisorctl; then
  st="$(supervisorctl status cf-comfy-tunnel 2>/dev/null | awk '{print $2}')"
  [[ "$st" == "RUNNING" ]] && ok "Túnel supervisor: RUNNING" || { err "Túnel supervisor: ${st:-ausente}"; fail=1; }
fi
# Público (puede tardar unos segundos en propagar tras el primer arranque)
pub="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://comfy.vericerbiz.com/ 2>/dev/null || echo 000)"
if [[ "$pub" =~ ^(200|404|405)$ ]]; then
  ok "comfy.vericerbiz.com → HTTP $pub (túnel público arriba)"
elif [[ "$pub" == "530" ]]; then
  warn "comfy.vericerbiz.com → 530/1033 (túnel aún no conectado; espera unos segundos y reintenta)"
else
  warn "comfy.vericerbiz.com → HTTP $pub (revisa el túnel)"
fi

# 4) Generación de prueba opcional
if [[ "${1:-}" == "--gen" ]]; then
  section "Generación de prueba (wrapper local)"
  wf="$ROOT/comfy/workflows/wai_txt2img.api.json"
  if [[ -f "$wf" ]]; then
    payload="$(python3 - "$wf" <<'PY'
import json,sys,random
wf=json.load(open(sys.argv[1]))
wf.pop("_comment",None)
wf["3"]["inputs"]["seed"]=random.randint(0,2**31-1)
print(json.dumps({"input":{"workflow_json":wf,"return_outputs_as_base64":True}}))
PY
)"
    code="$(curl -s -o /tmp/pix_gen.json -w "%{http_code}" --max-time 120 \
      -X POST "http://127.0.0.1:$wp/generate/sync" \
      -H 'Content-Type: application/json' -d "$payload" 2>/dev/null || echo 000)"
    if [[ "$code" == "200" ]] && grep -q '"data"' /tmp/pix_gen.json 2>/dev/null; then
      ok "Generación de prueba OK (el wrapper devolvió una imagen)."
    else
      err "Generación de prueba falló (HTTP $code). Revisa que el checkpoint esté descargado."
      fail=1
    fi
  else
    warn "No se encontró el workflow de prueba ($wf)."
  fi
fi

echo
if [[ "$fail" -eq 0 ]]; then
  ok "TODO VERDE. Servidor listo para producir imágenes vía https://comfy.vericerbiz.com"
else
  err "Hay checks en rojo (ver arriba)."
fi
exit "$fail"
