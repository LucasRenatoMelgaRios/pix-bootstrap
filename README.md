# pix-bootstrap

Reconstrucción **automatizada y reproducible** del servidor GPU (ComfyUI sobre Vast.ai) del
proyecto `pix`. Las instancias de Vast son **desechables**: si una muere o queda "Scheduled", se
crea otra y queda operativa en **menos de 15 minutos** con unos pocos comandos.

```bash
git clone <este-repo> pix-bootstrap && cd pix-bootstrap
cp .env.example .env && nano .env        # pega CIVITAI_TOKEN y CF_TUNNEL_TOKEN
./bootstrap.sh
```

## Por qué funciona: identidad estable

El **túnel nombrado de Cloudflare** (`comfy.vericerbiz.com`) vive en Cloudflare, no en la GPU.
Cualquier instancia nueva que corra `cloudflared` con el **mismo `CF_TUNNEL_TOKEN`** se vuelve el
origen del túnel → la URL pública nunca cambia → **el backend Laravel no se toca jamás**.
Perder una instancia deja de ser un problema. Detalle en [`docs/architecture.md`](docs/architecture.md).

## Qué hace `bootstrap.sh`
Corre, en orden, pasos idempotentes (re-ejecutable sin romper):

| Paso | Script | Qué hace |
|---|---|---|
| inspect | `scripts/00_inspect.sh` | Detecta el entorno; falla temprano si no es el template esperado |
| ssh | `scripts/10_ssh.sh` | (opcional) añade `SSH_PUBKEY` a authorized_keys |
| deps | `scripts/20_dependencies.sh` | Verifica/instala solo lo que falte (nunca `apt upgrade`) |
| nodes | `scripts/30_custom_nodes.sh` | Instala custom_nodes de `config/custom_nodes.yaml` |
| models | `scripts/40_models.py` | Descarga los pesos de `models/models.yaml` (idempotente) |
| tunnel | `scripts/50_tunnel.sh` | Levanta el túnel Cloudflare como servicio de supervisor |
| services | `scripts/60_services.sh` | Reinicia ComfyUI/wrapper para tomar modelos nuevos |
| health | `scripts/90_healthcheck.sh` | Verifica todo (+ `--gen` para una generación real) |

## Qué NO hace (por diseño)
- **No instala ComfyUI desde cero** — el template oficial de Vast ya lo trae. Solo rellena huecos.
- **No hace `apt upgrade`** ni toca el core de ComfyUI.
- **No guarda secretos** en el repo (tokens vía `.env`, gitignored, o env vars de la instancia).
- **No usa Docker Compose** — no aplica en el contenedor no privilegiado de Vast (ver architecture).

## Estructura
```
bootstrap.sh          orquestador
.env.example          plantilla de secretos (copiar a .env)
config/               custom_nodes.yaml, overrides opcionales de ComfyUI
models/               models.yaml (manifiesto declarativo; los pesos NO se versionan)
comfy/                workflow de referencia + extra_model_paths de ejemplo
scripts/              pasos numerados 00→90 + lib.sh
setup/                cómo crear la instancia + snippet on-start (zero-touch)
docs/                 architecture · runbook · models · troubleshooting
```

## Documentación
- **Crear una instancia:** [`setup/vast-instance.md`](setup/vast-instance.md)
- **Perdí la instancia:** [`docs/runbook.md`](docs/runbook.md)
- **Añadir modelos:** [`docs/models.md`](docs/models.md)
- **Problemas comunes:** [`docs/troubleshooting.md`](docs/troubleshooting.md)

## Regla de oro
Cada cambio permanente en el servidor GPU se refleja **aquí**, no en la memoria de una
conversación. Si tuviste que correr un comando a mano en la caja, ese comando pertenece a un
script de este repo.
