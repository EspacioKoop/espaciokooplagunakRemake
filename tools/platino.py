#!/usr/bin/env python3
"""Ejecuta la copia revisada y versionada de Normas Platino, sin descargar código."""
from pathlib import Path
import runpy

if __name__ == "__main__":
    source = Path(__file__).resolve().parents[1] / "docs/platino/upstream/scripts/platino.py"
    runpy.run_path(str(source), run_name="__main__")
