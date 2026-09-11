#!/usr/bin/env python3
"""Check localization CSV catalog completeness for Spanish (es) and English (en).

Exit 0: localization catalog valid and complete.
Exit 1: invalid file or format.
Exit 2: --require-complete set but untranslated or missing keys found.
"""
import argparse
import csv
import sys
from pathlib import Path

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--csv", default="game/localization/controls.csv")
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()

    csv_path = args.root / args.csv
    if not csv_path.is_file():
        print(f"ERROR: No existe el archivo de localización: {csv_path}", file=sys.stderr)
        return 1

    try:
        with csv_path.open("r", encoding="utf-8") as f:
            reader = csv.reader(f)
            rows = list(reader)
    except Exception as exc:
        print(f"ERROR al leer CSV: {exc}", file=sys.stderr)
        return 1

    if not rows:
        print("ERROR: Archivo CSV vacío", file=sys.stderr)
        return 1

    header = rows[0]
    if len(header) < 3 or header[0].strip() != "keys" or "es" not in header or "en" not in header:
        print("ERROR: El encabezado del CSV debe contener 'keys', 'es' y 'en'", file=sys.stderr)
        return 1

    es_idx = header.index("es")
    en_idx = header.index("en")

    total_keys = 0
    missing_es = []
    missing_en = []
    seen_keys = set()

    for line_num, row in enumerate(rows[1:], start=2):
        if not row or not any(row):
            continue
        if len(row) <= max(es_idx, en_idx):
            print(f"ERROR línea {line_num}: Fila con columnas insuficientes", file=sys.stderr)
            return 1
        key = row[0].strip()
        if not key:
            continue
        if key in seen_keys:
            print(f"ERROR línea {line_num}: Clave duplicada '{key}'", file=sys.stderr)
            return 1
        seen_keys.add(key)
        total_keys += 1

        es_val = row[es_idx].strip()
        en_val = row[en_idx].strip()

        if not es_val:
            missing_es.append(key)
        if not en_val:
            missing_en.append(key)

    print(f"Catálogo de localización: {total_keys} claves registradas.")
    print(f"Cobertura es-ES: {total_keys - len(missing_es)} / {total_keys} ({100.0 if total_keys==0 else (total_keys - len(missing_es))/total_keys*100:.1f}%)")
    print(f"Cobertura en-US: {total_keys - len(missing_en)} / {total_keys} ({100.0 if total_keys==0 else (total_keys - len(missing_en))/total_keys*100:.1f}%)")

    if missing_es or missing_en:
        if missing_es:
            print(f"Faltan traducciones en español ({len(missing_es)}): {', '.join(missing_es[:5])}", file=sys.stderr)
        if missing_en:
            print(f"Faltan traducciones en inglés ({len(missing_en)}): {', '.join(missing_en[:5])}", file=sys.stderr)
        if args.require_complete:
            return 2

    return 0

if __name__ == "__main__":
    sys.exit(main())
