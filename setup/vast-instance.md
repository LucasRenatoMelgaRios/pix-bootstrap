# Crear una instancia Vast desde cero

Guía paso a paso para levantar un servidor GPU nuevo. Objetivo: **operativo en <15 min**.

## 1. Crear la instancia
- **Template:** el oficial **Vast base-image ComfyUI** (PyTorch). Trae ComfyUI + supervisor +
  Caddy + el API Wrapper ya montados. **No uses otro template** — el bootstrap asume este.
- **GPU:** RTX 4090 (24 GB). ~US$0.35/h.
- **Disco:** ≥ 40 GB (el checkpoint WAI pesa ~7 GB; deja margen para más modelos).

## 2. Variables de entorno (en la pantalla de creación)
Defínelas como env vars de la instancia para no depender de un `.env`:

| Variable | Obligatoria | Qué es |
|---|---|---|
| `CIVITAI_TOKEN` | sí | Token de Civitai (Account → API Keys) para descargar el modelo |
| `CF_TUNNEL_TOKEN` | sí | Token del túnel `comfy` de Cloudflare (identidad estable) |
| `HF_TOKEN` | no | Solo si añades modelos privados de HuggingFace |
| `SSH_PUBKEY` | no | Tu clave pública si quieres SSH directo además del panel |

> Los valores reales de `CF_TUNNEL_TOKEN` y `CIVITAI_TOKEN` NO están en este repo (secretos).
> Guárdalos en tu gestor de contraseñas. Ver `docs/troubleshooting.md`.

## 3. Clave SSH
Añade tu llave pública en el panel de Vast (**Instances → icono de llave → Manage SSH Keys**).
Vast gestiona esto por-instancia; una llave metida a mano dentro del contenedor **no** sobrevive
a un stop/start. (El bootstrap también puede añadir `SSH_PUBKEY`, pero el panel es lo canónico.)

## 4. Provisionar
Dos formas:

**A) Zero-touch (recomendado):** pega el contenido de [`on-start.sh`](on-start.sh) en el campo
**On-start script** de la instancia (ajustando la URL del repo). Al arrancar, clona y corre el
bootstrap solo.

**B) Manual:** entra por SSH y corre:
```bash
cd /workspace
git clone https://github.com/CHANGE_ME/pix-bootstrap.git
cd pix-bootstrap
cp .env.example .env && nano .env      # pega los tokens
./bootstrap.sh
```

## 5. Verificar
El bootstrap termina con un health check. Además, desde tu máquina:
```bash
curl -sI https://comfy.vericerbiz.com/     # 200/404/405 = túnel arriba (NO 530/1033)
```
Y una generación real por el backend (que no cambia nunca):
```bash
curl -s -X POST https://pix-api.vericerbiz.com/api/generations \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -H 'Authorization: Bearer <TU_TOKEN>' \
  -d '{"prompt":"1girl, masterpiece","count":1}'
```

## 6. Al terminar
- **Detener** la instancia corta el cobro de GPU (el storage sigue facturando).
- ⚠️ Al detener, la GPU física puede quedar alquilada por otro y la instancia puede quedar
  "Scheduled". Por eso el modelo es **desechable**: si eso pasa, `destroy` y crea una nueva
  siguiendo esta guía. Perder la instancia ya no es un problema — reconstruir es rutina.
