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
import sys
import urllib.request
import urllib.error
from urllib.parse import urlsplit

# Salida robusta en cualquier consola (la instancia es Linux/UTF-8; esto además
# evita fallos en terminales Windows cp1252 al validar el script localmente).
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, ValueError):
    pass


class _StripAuthRedirect(urllib.request.HTTPRedirectHandler):
    """Quita el header Authorization al redirigir a OTRO host.

    Civitai responde 307 → URL firmada de R2/Cloudflare (con auth en el query
    string). Si urllib arrastra el `Authorization: Bearer` al host del CDN, este
    la rechaza (HTTP 400/403). Al cambiar de host, la eliminamos.
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        newreq = super().redirect_request(req, fp, code, msg, headers, newurl)
        if newreq is not None and urlsplit(req.full_url).netloc != urlsplit(newurl).netloc:
            newreq.headers = {k: v for k, v in newreq.headers.items()
                              if k.lower() != "authorization"}
        return newreq


_OPENER = urllib.request.build_opener(_StripAuthRedirect)

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
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers=headers)
    # timeout amplio: es el tiempo máx por operación de socket, no del total.
    with _OPENER.open(req, timeout=120) as resp:
        ctype = resp.headers.get("Content-Type", "")
        # Civitai devuelve HTML cuando el token es inválido / se requiere login.
        if "text/html" in ctype:
            raise RuntimeError(
                f"la respuesta es HTML ({ctype}) — token inválido o descarga que requiere login"
            )
        if dry_run:
            log(f"[dry-run] descargaría desde {url}")
            return
        total = int(resp.headers.get("Content-Length", 0))
        done = 0
        last_pct = -1
        with open(tmp, "wb") as out:
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
                done += len(chunk)
                if total:
                    pct = done * 100 // total
                    if pct != last_pct:  # solo al cambiar de % (log limpio)
                        last_pct = pct
                        print(f"\r      {pct:3d}%  ({done // (1<<20)}/{total // (1<<20)} MB)",
                              end="", flush=True)
                    # Ya recibimos todo Content-Length: cortamos sin un read() extra
                    # que se bloquearía esperando EOF (causaba "read operation timed out").
                    if done >= total:
                        break
        if total:
            print()
    if os.path.getsize(tmp) < MIN_BYTES:
        os.remove(tmp)
        raise RuntimeError("archivo descargado demasiado pequeño (probable error)")
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
            except (urllib.error.URLError, urllib.error.HTTPError, RuntimeError, OSError) as e:
                log(f"✗ {mtype}/{dest_name}: {e}")
                failed += 1

    print()
    log(f"Resumen modelos: {planned} declarados · {downloaded} descargados · "
        f"{skipped} ya presentes · {failed} fallidos")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
