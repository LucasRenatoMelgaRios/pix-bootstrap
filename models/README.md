# models/

Manifiesto declarativo de pesos. **Los archivos de modelo (`.safetensors`, etc.) NO se
versionan** (están en `.gitignore`) — se descargan en la instancia GPU al correr el bootstrap.

- **`models.yaml`** — la única fuente de verdad de qué pesos instalar. Edítalo para añadir o
  quitar checkpoints, LoRAs, VAE, ControlNet, upscalers o embeddings.
- El descargador es `scripts/40_models.py` (lo invoca `bootstrap.sh`).

Cómo agregar un modelo: ver [`docs/models.md`](../docs/models.md).
