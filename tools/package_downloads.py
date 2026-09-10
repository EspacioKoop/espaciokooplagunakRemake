#!/usr/bin/env python3
"""Package selected exports, licenses and SHA-256 checksums without changing sources."""
import argparse
from pathlib import Path
import hashlib
import shutil
import sys
import tempfile
import zipfile

from export_targets import (add_target_argument, artifact_name, checked_zip, package_name,
                            selected_targets, validate_artifact)

ROOT = Path(__file__).resolve().parents[1]


def add_licenses(archive, root):
    for name in ("LICENSE", "CREDITS.md"):
        archive.write(root / name, name)
    archive.write(root / "docs/PLAYER_GUIDE.md", "LEEME.md")
    for license_path in sorted((root / "third_party").glob("*.txt")):
        archive.write(license_path, "licenses/" + license_path.name)


def package_exports(root, names, android_debug=False, foundry=True):
    sources = {name: root / "build" / name / artifact_name(name, android_debug) for name in names}
    # Validate every selected input before publishing any output or checksum file.
    for name, source in sources.items():
        validate_artifact(name, source)
    out = root / "dist"
    out.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".packages-", dir=out) as temporary:
        staging = Path(temporary)
        files = []
        for name, source in sources.items():
            path = staging / package_name(name, android_debug)
            with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=7) as archive:
                if name == "macos":
                    with checked_zip(source) as app:
                        for info in app.infolist():
                            # Preserve executable permissions and signed bundle bytes.
                            with app.open(info) as original, archive.open(info, "w") as target:
                                shutil.copyfileobj(original, target)
                else:
                    archive.write(source, source.name)
                add_licenses(archive, root)
                if name in ("macos", "android"):
                    archive.write(root / "docs/PLATFORM_EXPORTS.md", "PLATAFORMAS.md")
            files.append(path)
        if foundry:
            module = root / "integrations/foundry"
            path = staging / "espaciokoop-lagunak-foundry.zip"
            with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
                for name in ("module.json", "main.mjs", "client.mjs", "style.css", "README.md"):
                    archive.write(module / name, name)
                archive.write(root / "LICENSE", "LICENSE")
            files.append(path)
        checksums = []
        for path in files:
            with checked_zip(path) as archive:
                if "LICENSE" not in archive.namelist():
                    raise ValueError(f"Missing license in {path.name}")
            with path.open("rb") as source:
                digest = hashlib.file_digest(source, "sha256").hexdigest()
            checksums.append(f"{digest}  {path.name}\n")
        manifest = staging / "SHA256SUMS"
        manifest.write_text("".join(checksums), encoding="utf-8")
        for path in [*files, manifest]:
            path.replace(out / path.name)
    return checksums


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    add_target_argument(parser)
    parser.add_argument("--android-debug", action="store_true", help="Package the explicitly named debug APK, never a release APK.")
    parser.add_argument("--skip-foundry", action="store_true", help="Package only standalone destinations.")
    args = parser.parse_args(argv)
    if args.android_debug and "android" not in args.targets:
        parser.error("--android-debug requires --targets android")
    try:
        checksums = package_exports(ROOT, selected_targets(args.targets), args.android_debug, not args.skip_foundry)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        print("PACKAGE_FAILED:", error, file=sys.stderr)
        return 1
    print("".join(checksums), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
