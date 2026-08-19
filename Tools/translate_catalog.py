#!/usr/bin/env python3
"""
translate_catalog.py
====================

Toma catalog.json del proyecto EVA Bridge, traduce los top N comandos
a inglés y ruso usando la API gratuita MyMemory (https://mymemory.translated.net/),
y genera un catalog-expanded.json con los campos extra.

Por qué MyMemory:
- 100% gratis sin API key
- 10,000 palabras/día (más que suficiente para 100 comandos × 2 idiomas)
- Buena calidad para frases cortas de comandos de auto

Uso:
    python translate_catalog.py
        --input  ../../D:/EVA/Source/iOS/EVA-Bridge/catalog.json
        --output ../../D:/EVA/Source/iOS/EVA-Bridge/catalog-expanded.json
        --top    100
        --delay  0.2    # segundos entre requests (rate limit)
"""

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path

API_URL = "https://api.mymemory.translated.net/get"
USER_AGENT = "EVA-Copilot-Translator/1.0 (contact: johegocr@gmail.com)"


def translate(text: str, target: str, retries: int = 3) -> str:
    """Traduce `text` del español a `target` (en/ru) usando MyMemory API."""
    if not text or not text.strip():
        return text

    params = urllib.parse.urlencode({"q": text, "langpair": f"es|{target}"})
    url = f"{API_URL}?{params}"

    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("responseStatus") == 200:
                    translated = data["responseData"]["translatedText"]
                    # MyMemory a veces devuelve warnings en lugar de texto;
                    # los filtramos por longitud absurda o palabras de error.
                    if "MYMEMORY WARNING" in translated.upper() or len(translated) > len(text) * 4:
                        if attempt < retries - 1:
                            time.sleep(1)
                            continue
                        return text  # fallback: deja el español
                    return translated
                else:
                    detail = data.get("responseDetails", "unknown error")
                    if attempt < retries - 1:
                        time.sleep(1)
                        continue
                    print(f"  [WARN] No se pudo traducir '{text[:40]}...': {detail}", file=sys.stderr)
                    return text
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
            if attempt < retries - 1:
                time.sleep(1)
                continue
            print(f"  [ERROR] '{text[:40]}...': {e}", file=sys.stderr)
            return text
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="Path al catalog.json original")
    ap.add_argument("--output", required=True, help="Path al catalog.json expandido de salida")
    ap.add_argument("--top", type=int, default=100, help="Cantidad de comandos a traducir (top N)")
    ap.add_argument("--delay", type=float, default=0.25, help="Segundos entre requests")
    args = ap.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.exists():
        sys.exit(f"[ERROR] No existe {input_path}")

    print(f"[INFO] Leyendo {input_path}")
    with input_path.open(encoding="utf-8") as f:
        commands = json.load(f)

    print(f"[INFO] {len(commands)} comandos en el catálogo. Traduciendo top {args.top}...")

    translated_count_en = 0
    translated_count_ru = 0
    failed_count = 0

    for i, cmd in enumerate(commands[: args.top]):
        cmd_id = cmd.get("id", f"#{i}")
        es_text = cmd.get("es", "")
        if not es_text:
            continue

        print(f"  [{i+1:3d}/{args.top}] {cmd_id}: {es_text[:50]}")

        # Traducir a inglés
        en_text = translate(es_text, "en")
        if en_text != es_text:
            cmd["en"] = en_text
            translated_count_en += 1
        else:
            failed_count += 1
        time.sleep(args.delay)

        # Traducir a ruso
        ru_text = translate(es_text, "ru")
        if ru_text != es_text:
            cmd["ru"] = ru_text
            translated_count_ru += 1
        else:
            failed_count += 1
        time.sleep(args.delay)

        # Progreso cada 10
        if (i + 1) % 10 == 0:
            print(f"  [PROGRESS] {i+1}/{args.top} done, EN: {translated_count_en}, RU: {translated_count_ru}, fallbacks: {failed_count}")

    # Escribir el catálogo expandido
    print(f"[INFO] Escribiendo {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        json.dump(commands, f, ensure_ascii=False, indent=2)

    print()
    print("=" * 60)
    print(f"✅ Traducción completada")
    print(f"   EN traducidos: {translated_count_en}/{args.top}")
    print(f"   RU traducidos: {translated_count_ru}/{args.top}")
    print(f"   Fallbacks (quedó en ES): {failed_count}")
    print(f"   Output: {output_path}")
    print("=" * 60)


if __name__ == "__main__":
    main()
