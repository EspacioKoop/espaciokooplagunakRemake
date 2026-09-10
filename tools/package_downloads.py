#!/usr/bin/env python3
"""Build downloadable ZIPs with licenses and SHA-256 checksums."""
from pathlib import Path
import hashlib
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist"
OUT.mkdir(exist_ok=True)
VERSION = "1.0.0"
files = []
for platform, binary in [("linux", "EspaciokoopLagunak.x86_64"), ("windows", "EspaciokoopLagunak.exe")]:
    path = OUT / f"EspaciokoopLagunak-{VERSION}-{platform}-x86_64.zip"
    source = ROOT / "build" / platform / binary
    assert source.is_file(), str(source)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=7) as archive:
        archive.write(source, binary)
        for name in ["LICENSE", "CREDITS.md"]: archive.write(ROOT / name, name)
        archive.write(ROOT / "docs/PLAYER_GUIDE.md", "LEEME.md")
        for license in sorted((ROOT / "third_party").glob("*.txt")): archive.write(license, "licenses/" + license.name)
    files.append(path)
module = ROOT / "integrations/foundry"
shutil.copyfile(ROOT / "LICENSE", module / "LICENSE")
path = OUT / "espaciokoop-lagunak-foundry.zip"
with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
    for name in ["module.json", "main.mjs", "client.mjs", "style.css", "README.md", "LICENSE"]: archive.write(module / name, name)
files.append(path)
(OUT / "SHA256SUMS").write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in files))
print((OUT / "SHA256SUMS").read_text())
