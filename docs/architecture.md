# Arquitectura

## Instancias desechables + identidad estable

```
   Frontend (pix.vericerbiz.tech, hosting estático)
        │  HTTPS + Bearer token
        ▼
   Backend Laravel (pix-api.vericerbiz.com, VPS Hostinger — PERMANENTE)
        │  POST https://comfy.vericerbiz.com/generate/sync
        ▼
   Túnel Cloudflare  «comfy»  (en Cloudflare, PERMANENTE)  ◄── identidad estable
        │  ingress → http://localhost:18288
        ▼
   Instancia Vast.ai (GPU, ComfyUI)  ◄── DESECHABLE
        └─ cloudflared (mismo CF_TUNNEL_TOKEN) se conecta al túnel «comfy»
```

**La clave:** el túnel nombrado y el DNS `comfy.vericerbiz.com` viven en Cloudflare, no en la
GPU. Cualquier instancia nueva que corra `cloudflared` con el **mismo `CF_TUNNEL_TOKEN`** se
vuelve el nuevo origen del túnel. Resultado: la URL pública nunca cambia y **el backend Laravel
no se toca jamás** al reconstruir la GPU. Eso es lo que convierte "perder una instancia" en un
trámite rutinario.

## Puertos internos de la instancia (template oficial Vast ComfyUI)

| Servicio | Interno | Externo (Caddy) | Uso |
|---|---|---|---|
| ComfyUI (API nativa, cola) | `127.0.0.1:18188` | `8188` | `POST /prompt`, `GET /history`, `GET /view` |
| **API Wrapper** (one-shot) | `127.0.0.1:18288` | `8288` | `POST /generate/sync` → **ruta de Laravel** |

El túnel apunta **directo al wrapper (18288)**, evitando el edge Caddy (así no hay token de Caddy
que cambie por sesión). Envelope del wrapper:
`{"input": {"workflow_json": <grafo API-format>, "return_outputs_as_base64": true}}`.

## Persistencia

`workspace_is_volume = false`: un `destroy`/`recycle` borra todo. Por eso **este repo es la
fuente de verdad**. Un `stop/start` sí preserva el contenedor, pero no dependemos de ello.

## Dónde vive cada cosa

| Componente | Ubicación | Repo |
|---|---|---|
| Frontend React | hosting estático `pix.vericerbiz.tech` | `pix/frontend` |
| Backend Laravel | VPS `pix-api.vericerbiz.com` | `pix/backend` |
| Imágenes generadas | S3 `pix-vericerbiz-media` (URL pública directa) | — |
| Infra GPU (esto) | instancia Vast desechable | **`pix-bootstrap`** |

## ¿Y Docker Compose?

**No aplica en la caja Vast.** Corres dentro de un contenedor Docker **no privilegiado**: no hay
acceso al daemon de Docker, así que no puedes levantar Compose ahí. La herramienta correcta en ese
entorno es **bash + supervisor** (que es justo lo que usa el template). Compose solo tendría
sentido si algún día migras a un **VPS con GPU propia**; en ese caso este repo se podría envolver
en un `docker-compose.yml`, pero hoy sería complejidad sin beneficio.
