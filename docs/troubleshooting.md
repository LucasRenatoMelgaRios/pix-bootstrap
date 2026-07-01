# Troubleshooting

Problemas reales que ya nos pegaron y cómo resolverlos.

## `comfy.vericerbiz.com` devuelve 530 / error 1033
El túnel no está conectado. Casi siempre porque la GPU está apagada o `cloudflared` no arrancó.
- Dentro de la caja: `supervisorctl status cf-comfy-tunnel` → debe estar `RUNNING`.
- Ver logs: `supervisorctl tail -f cf-comfy-tunnel`.
- Re-levantar: `./bootstrap.sh --only tunnel`.

## `cloudflared: flag provided but not defined: -token`
El **orden de los flags** importa: `--token` va **después** de `run`:
`cloudflared tunnel --no-autoupdate run --token <TOKEN>` ✅
`cloudflared tunnel --no-autoupdate --token <TOKEN> run` ❌
(`scripts/50_tunnel.sh` ya lo escribe bien.)

## La descarga de Civitai "funciona" pero baja un HTML de 2 KB
El `CIVITAI_TOKEN` es inválido o el modelo requiere login. El descargador
(`scripts/40_models.py`) detecta el `Content-Type: text/html` y aborta esa entrada en vez de
guardar basura. Revisa el token (Civitai → Account → API Keys).
Nota: NO usamos `conditional_downloads`/validación previa del token porque el validador de Civitai
devuelve 403 de forma poco fiable y saltaría descargas válidas.

## "Could not resolve host: comfy.vericerbiz.com" desde el VPS
El resolver del VPS (Hostinger, `153.92.2.6`) cacheó negativamente el nombre antes de que existiera
el CNAME. Es temporal (~30 min). Mitigación puntual en el VPS:
`resolvectl dns eth0 1.1.1.1` (no persistente; revierte al reiniciar, y para entonces la caché ya
expiró). No afecta a la instancia GPU.

## SSH deja de funcionar tras stop/start
Vast gestiona `authorized_keys` **por-instancia desde el panel**. Una llave metida a mano dentro
del contenedor no sobrevive. Re-añádela en **Instances → icono de llave → Manage SSH Keys**, o
define `SSH_PUBKEY` para que el bootstrap la reponga.

## Nada persiste tras destroy/recycle
`workspace_is_volume = false` — es esperado. Reconstruye con el runbook. Solo `stop/start`
preserva el contenedor.

## No hay `apt`/no puedo instalar algo del sistema
El contenedor es no privilegiado. El bootstrap **nunca** hace `apt upgrade` y solo instala
paquetes puntuales que falten. Si algo del sistema no está y no se puede instalar, documenta el
hueco aquí en vez de forzarlo.

## Secretos (dónde NO buscarlos)
Los tokens reales (`CF_TUNNEL_TOKEN`, `CIVITAI_TOKEN`) **no** están en este repo por diseño.
Viven en tu gestor de contraseñas / env vars de la instancia. Recursos fijos de Cloudflare para
referencia: túnel `comfy` id `76f940be-3f10-4cdc-9b29-9e2586d6edb9`, ingress → `localhost:18288`,
CNAME `comfy.vericerbiz.com`.
