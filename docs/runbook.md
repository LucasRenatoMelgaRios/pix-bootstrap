# Runbook — "perdí la instancia"

Procedimiento rutinario cuando una instancia de Vast muere, queda "Scheduled", o simplemente
quieres una nueva. Objetivo: **verde en <15 min**.

## Pasos

1. **Destruye** la instancia vieja si sigue colgada (Vast → Instances → 🗑). No pierdes nada
   importante: todo lo reproducible está aquí.

2. **Crea una instancia nueva** siguiendo [`setup/vast-instance.md`](../setup/vast-instance.md):
   template *base-image ComfyUI*, RTX 4090, y las env vars `CIVITAI_TOKEN` + `CF_TUNNEL_TOKEN`.

3. **Provisiona:**
   ```bash
   cd /workspace
   git clone <repo> pix-bootstrap && cd pix-bootstrap
   cp .env.example .env && nano .env     # si no pusiste las env vars en la instancia
   ./bootstrap.sh
   ```
   (o deja que el On-start lo haga solo — ver `setup/on-start.sh`.)

4. **Prueba de aceptación** (esto es lo que define "listo"):
   ```bash
   ./bootstrap.sh --only health --gen        # health check + generación real local
   ```
   y desde tu máquina:
   ```bash
   curl -sI https://comfy.vericerbiz.com/     # 200/404/405 = túnel arriba (no 530/1033)
   ```
   Finalmente, una generación real por el backend (que NO tocaste):
   `POST https://pix-api.vericerbiz.com/api/generations` → debe devolver una imagen.

## Cronómetro esperado
- Arranque del template + drivers: ~2–4 min (fuera de nuestro control).
- `bootstrap.sh`: dependencias ~1 min, **descarga del checkpoint WAI (~7 GB) ~3–6 min**, túnel
  ~15 s, health ~30 s. Total típico **< 15 min**, dominado por la descarga del modelo.

## Re-ejecutar es seguro
`bootstrap.sh` es idempotente: si algo falló a mitad, vuelve a correrlo. Salta modelos ya
descargados, no re-clona nodos, y reescribe el túnel sin duplicar.

## Comandos útiles dentro de la caja
```bash
supervisorctl status                       # estado de todos los servicios
supervisorctl tail -f cf-comfy-tunnel      # logs del túnel
./bootstrap.sh --only tunnel               # re-levantar solo el túnel
./bootstrap.sh --only models               # re-intentar solo modelos
./bootstrap.sh --dry-run                   # solo inspección, no instala
```
