#!/bin/bash
set -e

echo "=========================================================="
echo "      Pix LoRA Training Automation (Kohya_ss)             "
echo "=========================================================="

if [ -z "$1" ]; then
    echo "Error: Faltó indicar la palabra clave (Trigger word)."
    echo "Uso: ./train_lora.sh <palabra_clave> [ruta_al_zip]"
    echo "Ejemplo: ./train_lora.sh chicarosita ../images/lena.zip"
    exit 1
fi

TRIGGER="$1"
ZIP_PATH="${2:-../images/lena.zip}"
TRAIN_DIR="/workspace/lora_train"
KOHYA_DIR="/workspace/kohya_ss"
MODEL_REPO="gsdf/PonyDiffusionV6XL"

if [ ! -f "$ZIP_PATH" ]; then
    echo "Error: No se encontró el archivo ZIP en $ZIP_PATH"
    echo "Asegúrate de que la ruta sea correcta."
    exit 1
fi

echo "Palabra clave (Trigger): $TRIGGER"
echo "Archivo Dataset: $ZIP_PATH"

# 1. Preparar carpetas
echo ""
echo "[1/4] Preparando carpetas en $TRAIN_DIR..."
rm -rf "$TRAIN_DIR"
mkdir -p "$TRAIN_DIR/img/40_${TRIGGER}"
mkdir -p "$TRAIN_DIR/model"
mkdir -p "$TRAIN_DIR/log"

# 2. Extraer imágenes
echo ""
echo "[2/4] Extrayendo dataset..."
unzip -q -j "$ZIP_PATH" -d "$TRAIN_DIR/img/40_${TRIGGER}"
echo "Dataset extraído. Archivos encontrados:"
ls -1 "$TRAIN_DIR/img/40_${TRIGGER}" | wc -l

# 3. Buscar carpeta de Kohya y Auto-Tagger (WD14)
echo ""
echo "[3/4] Auto-Etiquetado con WD14 Tagger..."

# Buscamos dónde instaló Vast.ai el Kohya_ss
if [ -d "/workspace/kohya_ss" ]; then
    KOHYA_DIR="/workspace/kohya_ss"
elif [ -d "/kohya_ss" ]; then
    KOHYA_DIR="/kohya_ss"
elif [ -f "./sdxl_train_network.py" ]; then
    KOHYA_DIR="."
else
    # Buscar en todo el sistema (puede tardar un poco)
    KOHYA_DIR=$(dirname $(find / -name "sdxl_train_network.py" -type f -print -quit 2>/dev/null))
fi

echo "Carpeta de Kohya encontrada en: $KOHYA_DIR"

if [ -f "$KOHYA_DIR/venv/bin/activate" ]; then
    source "$KOHYA_DIR/venv/bin/activate"
fi
cd "$KOHYA_DIR"

python finetune/tag_images_by_wd14_tagger.py \
    "$TRAIN_DIR/img/40_${TRIGGER}" \
    --batch_size 4 \
    --general_threshold 0.35 \
    --character_threshold 0.35 \
    --caption_extension .txt \
    --max_data_loader_n_workers 2 \
    --undesired_tags "" \
    --frequency_tags \
    --caption_separator ", " \
    --repo_id SmilingWolf/wd-v1-4-convnextv2-tagger-v2 \
    --caption_prefix "${TRIGGER}, "

# 4. Entrenamiento SDXL (Pony V6)
echo ""
echo "[4/4] Iniciando entrenamiento LoRA (SDXL - Pony V6)..."
# Usamos el config.toml provisto en pix-bootstrap
CONFIG_FILE="/workspace/pix-bootstrap/train/config.toml"

accelerate launch \
    --num_cpu_threads_per_process=2 \
    "./sdxl_train_network.py" \
    --pretrained_model_name_or_path="$MODEL_REPO" \
    --train_data_dir="$TRAIN_DIR/img" \
    --output_dir="$TRAIN_DIR/model" \
    --logging_dir="$TRAIN_DIR/log" \
    --output_name="${TRIGGER}_lora" \
    --config_file="$CONFIG_FILE"

echo ""
echo "=========================================================="
echo "               ENTRENAMIENTO COMPLETADO                   "
echo "=========================================================="
echo "Tu archivo safetensors se encuentra en:"
ls -lh "$TRAIN_DIR/model"
echo "¡Ya puedes descargarlo y destruir esta máquina!"
