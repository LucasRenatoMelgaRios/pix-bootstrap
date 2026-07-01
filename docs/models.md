# Añadir / quitar modelos

Todo se controla desde **`models/models.yaml`**. Edita ese archivo y vuelve a correr:
```bash
./bootstrap.sh --only models
```
Es idempotente: solo descarga lo que falte.

## Formato

Cada entrada va bajo su tipo (`checkpoints`, `loras`, `vae`, `controlnet`, `upscale_models`,
`embeddings`) y define `dest` (nombre del archivo) + una `source`:

### Civitai
```yaml
loras:
  - dest: miLora.safetensors
    source: civitai
    id: 123456          # el versionId (NO el modelId). En la página del modelo,
                        # elige la versión → el número tras /models/ en el botón Download.
```
Requiere `CIVITAI_TOKEN` en el entorno.

### HuggingFace
```yaml
vae:
  - dest: sdxl_vae.safetensors
    source: huggingface
    repo: stabilityai/sdxl-vae
    path: sdxl_vae.safetensors
    rev: main           # opcional (rama/tag/commit)
```
`HF_TOKEN` solo si el repo es privado.

### URL directa
```yaml
controlnet:
  - dest: control_sdxl_canny.safetensors
    source: url
    url: https://ejemplo.com/control_sdxl_canny.safetensors
```

## Dónde caen los archivos
| Tipo | Subdir en la instancia |
|---|---|
| `checkpoints` | `${COMFYUI}/models/checkpoints` |
| `loras` | `${COMFYUI}/models/loras` |
| `vae` | `${COMFYUI}/models/vae` |
| `controlnet` | `${COMFYUI}/models/controlnet` |
| `upscale_models` | `${COMFYUI}/models/upscale_models` |
| `embeddings` | `${COMFYUI}/models/embeddings` |

## Notas
- Tras añadir un checkpoint, reinicia ComfyUI para que lo liste:
  `./bootstrap.sh --only services` (o `supervisorctl restart comfyui`).
- El descargador valida que la respuesta no sea HTML (Civitai devuelve HTML si el token es
  inválido) y descarga atómicamente (`.part` → renombrar), así un corte no deja archivos a medias.
- Si un LoRA solo existe en SeaArt (sin descarga directa), busca al mismo creador en Civitai
  antes de descartarlo — es común que republiquen el mismo archivo ahí (mismo nombre de
  archivo = misma pieza). Verifica con el nombre exacto del `.safetensors` que aparece en el
  tag `<lora:...>` de SeaArt.

## LoRAs instalados — trigger words

| LoRA | Base | Trigger |
|---|---|---|
| Yuki Suou (Illustrious) | illustrious | `yuki suou, long hair, bangs, brown hair, black hair, hair between eyes, purple eyes, half updo, mature female, small breasts, anime screencap` |
| Yuki Suou (Pony) | pony | `long hair, brown hair, purple eyes, blazer, pleated skirt, long sleeves` |
| Anna Yanami (Illustrious) | illustrious | `anna yanami (makeine), blue hair, medium hair, ahoge, blue eyes` |
| Anna Yanami (Pony) | pony | `anna yanami, blue hair, medium hair, ahoge, blue eyes` |

Outfits de Anna Yanami (agregar al trigger, no lo reemplazan):
- Uniforme: `school uniform, white collared shirt, short sleeves, blue bowtie, yellow bowtie, grey pleated skirt, blue kneehighs, brown footwear`
- Uniforme de invierno: `winter school uniform, white blazer, open blazer, white collared shirt, long sleeves, sleeves past wrist, blue bowtie, yellow bowtie, yellow vest, grey pleated skirt, blue kneehighs, brown footwear`
- Traje de baño: `swimsuit, collarbone, cleavage, blue bikini, print bikini, navel, side-tie bikini bottom, sandals`
- Disfraz de fantasma: `ghost costume, hitodama hair ornament, hitaikakushi, white robe, nagajuban, long sleeves, wide sleeves, sleeves past wrists, white bow, blood stain`
- Salida: `white coat, long sleeves, purple dress, black footwear`
