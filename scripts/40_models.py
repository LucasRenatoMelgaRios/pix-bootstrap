#!/usr/bin/env python3
"""Descargador declarativo de modelos para ComfyUI.

Lee models/models.yaml y descarga lo que falte a los subdirectorios correctos de
ComfyUI. Idempotente: salta archivos que ya existen (y pesan > umbral). Fuentes:
civitai, huggingface, url directa. No guarda secretos: usa CIVITAI_TOKEN/HF_TOKEN
del entorno.

Uso:  python3 40_models.py [--manifest RUTA] [--comfyui RUTA] [--dry-run]
"""
import argparse
import os
import subprocess
import sys

# Salida robusta en cualquier consola (la instancia es Linux/UTF-8; esto además
# evita fallos en terminales Windows cp1252 al validar el script localmente).
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, ValueError):
    pass

# Tipo declarado -> subdirectorio bajo ComfyUI/models
TYPE_DIRS = {
    "checkpoints": "checkpoints",
    "loras": "loras",
    "vae": "vae",
    "controlnet": "controlnet",
    "upscale_models": "upscale_models",
    "embeddings": "embeddings",
}
MIN_BYTES = 1024 * 1024  # 1 MB: por debajo, casi seguro es un error/HTML, no un peso


def log(msg):
    print(f"    {msg}", flush=True)


def load_manifest(path):
    try:
        import yaml
    except ImportError:
        sys.exit("PyYAML no está instalado. Corre scripts/20_dependencies.sh primero.")
    with open(path) as fh:
        return yaml.safe_load(fh) or {}


def build_url_and_headers(entry):
    """Devuelve (url, headers, needs_token_name) según la fuente."""
    src = (entry.get("source") or "").lower()
    headers = {"User-Agent": "pix-bootstrap/1.0"}
    if src == "civitai":
        mid = entry.get("id")
        if not mid:
            raise ValueError("entrada civitai sin 'id' (versionId)")
        token = os.environ.get("CIVITAI_TOKEN", "")
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return f"https://civitai.com/api/download/models/{mid}", headers, "CIVITAI_TOKEN"
    if src == "huggingface":
        repo = entry.get("repo")
        path = entry.get("path")
        rev = entry.get("rev", "main")
        if not repo or not path:
            raise ValueError("entrada huggingface requiere 'repo' y 'path'")
        token = os.environ.get("HF_TOKEN", "")
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return f"https://huggingface.co/{repo}/resolve/{rev}/{path}", headers, "HF_TOKEN"
    if src == "url":
        url = entry.get("url")
        if not url:
            raise ValueError("entrada url sin 'url'")
        return url, headers, None
    raise ValueError(f"source desconocido: {src!r}")


def download(url, headers, dest, dry_run):
    """Descarga con curl: robusto para archivos grandes (reintentos + resume) y,
    clave, curl QUITA el header Authorization al redirigir a otro host (civitai→R2),
    que es justo lo que necesitamos. urllib fallaba en la cola de descargas de ~7GB.
    """
    if dry_run:
        log(f"[dry-run] descargaría desde {url}")
        return
    tmp = dest + ".part"
    cmd = [
        "curl", "-fL", "--silent", "--show-error",
        "--retry", "5", "--retry-delay", "3", "--retry-connrefused",
        "--connect-timeout", "30",
        "-C", "-",            # resume si quedó un .part parcial
        "-o", tmp, url,
    ]
    for k, v in headers.items():
        if k.lower() == "user-agent":
            cmd += ["-A", v]
        else:
            cmd += ["-H", f"{k}: {v}"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"curl falló ({res.returncode}): {res.stderr.strip() or 'sin detalle'}")
    if not os.path.exists(tmp) or os.path.getsize(tmp) < MIN_BYTES:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise RuntimeError("archivo descargado demasiado pequeño (probable error/HTML)")
    os.replace(tmp, dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=None)
    ap.add_argument("--comfyui", default=os.environ.get("COMFYUI", "/workspace/ComfyUI"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    manifest = args.manifest or os.path.join(here, "..", "models", "models.yaml")
    data = load_manifest(manifest)

    planned = skipped = downloaded = failed = 0
    for mtype, subdir in TYPE_DIRS.items():
        for entry in (data.get(mtype) or []):
            planned += 1
            dest_name = entry.get("dest")
            if not dest_name:
                log(f"✗ entrada en '{mtype}' sin 'dest' — se omite")
                failed += 1
                continue
            dest_dir = os.path.join(args.comfyui, "models", subdir)
            os.makedirs(dest_dir, exist_ok=True)
            dest = os.path.join(dest_dir, dest_name)

            if os.path.exists(dest) and os.path.getsize(dest) >= MIN_BYTES:
                log(f"• {mtype}/{dest_name} ya existe → salto")
                skipped += 1
                continue
            try:
                url, headers, tok = build_url_and_headers(entry)
            except ValueError as e:
                log(f"✗ {mtype}/{dest_name}: {e}")
                failed += 1
                continue
            if tok and not os.environ.get(tok):
                log(f"! {mtype}/{dest_name}: {tok} no está definido (puede fallar si el modelo lo requiere)")
            log(f"↓ {mtype}/{dest_name}  ← {url}")
            try:
                download(url, headers, dest, args.dry_run)
                if not args.dry_run:
                    log(f"✓ {mtype}/{dest_name}")
                downloaded += 1
            except (RuntimeError, OSError, subprocess.SubprocessError) as e:
                log(f"✗ {mtype}/{dest_name}: {e}")
                failed += 1

    print()
    log(f"Resumen modelos: {planned} declarados · {downloaded} descargados · "
        f"{skipped} ya presentes · {failed} fallidos")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
