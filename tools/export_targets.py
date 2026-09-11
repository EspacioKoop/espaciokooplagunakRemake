"""Shared export contract for bootstrap, build and downloadable packages."""
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import configparser
import json
import plistlib
import struct
import zipfile

GODOT_VERSION = "4.7.1"
VERSION = "0.9.2"
BUNDLE_ID = "org.espaciokoop.lagunak"
DEFAULT_TARGETS = ("linux", "windows")


@dataclass(frozen=True)
class Target:
    preset: str
    platform: str
    filename: str
    architecture: str
    templates: tuple[str, ...]


TARGETS = {
    "linux": Target("Linux", "Linux", "EspaciokoopLagunak.x86_64", "x86_64", ("linux_release.x86_64",)),
    "windows": Target("Windows", "Windows Desktop", "EspaciokoopLagunak.exe", "x86_64", ("windows_release_x86_64.exe",)),
    "macos": Target("macOS", "macOS", "EspaciokoopLagunak.zip", "universal", ("macos.zip",)),
    "android": Target("Android", "Android", "EspaciokoopLagunak.apk", "arm64-x86_64", ("android_release.apk", "android_debug.apk")),
}


def add_target_argument(parser):
    parser.add_argument("--targets", nargs="+", choices=TARGETS, default=list(DEFAULT_TARGETS),
                        help="Explicit destinations (default: linux windows).")


def selected_targets(names):
    return list(dict.fromkeys(names))


def artifact_name(name, android_debug=False):
    filename = TARGETS[name].filename
    return filename.replace(".apk", "-debug.apk") if name == "android" and android_debug else filename


def package_name(name, android_debug=False):
    suffix = "-debug" if name == "android" and android_debug else ""
    return f"EspaciokoopLagunak-{VERSION}-{name}-{TARGETS[name].architecture}{suffix}.zip"


def template_directory(root):
    return root / ".toolchain/data/godot/export_templates" / f"{GODOT_VERSION}.stable"


def validate_presets(path, names):
    config = configparser.ConfigParser(interpolation=None)
    config.read_string(path.read_text(encoding="utf-8"))
    presets = {}
    for section in config.sections():
        if section.startswith("preset.") and not section.endswith(".options"):
            name = json.loads(config[section]["name"])
            if name in presets:
                raise ValueError(f"Duplicate export preset: {name}")
            presets[name] = section
    for name in names:
        target = TARGETS[name]
        if target.preset not in presets:
            raise ValueError(f"Missing export preset: {target.preset}")
        section = presets[target.preset]
        base, options = config[section], config[section + ".options"]
        required = {"platform": json.dumps(target.platform), "export_filter": '"all_resources"'}
        for key, value in required.items():
            if base.get(key) != value:
                raise ValueError(f"{target.preset}: expected {key}={value}")
        if "data/*.json" not in base.get("include_filter", ""):
            raise ValueError(f"{target.preset}: campaign JSON must be included")
        if name == "macos":
            required = {"application/bundle_identifier": f'"{BUNDLE_ID}"',
                        "binary_format/architecture": '"universal"',
                        "codesign/codesign": "1", "notarization/notarization": "0"}
        elif name == "android":
            required = {"package/unique_name": f'"{BUNDLE_ID}"', "package/signed": "true",
                        "gradle_build/use_gradle_build": "false", "gradle_build/target_sdk": '"35"',
                        "architectures/arm64-v8a": "true", "architectures/x86_64": "true",
                        "permissions/internet": "true"}
            for key, value in options.items():
                if key.startswith("keystore/") and value != '""':
                    raise ValueError("Android: keystore configuration belongs in environment variables, not tracked presets")
        else:
            required = {"binary_format/architecture": '"x86_64"', "binary_format/embed_pck": "true"}
        for key, value in required.items():
            if options.get(key) != value:
                raise ValueError(f"{target.preset}: expected {key}={value}")


def checked_zip(path):
    archive = zipfile.ZipFile(path)
    try:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Archive contains duplicate entries")
        for name in names:
            member = PurePosixPath(name)
            if not member.parts or member.is_absolute() or ".." in member.parts or "\\" in name or ":" in member.parts[0]:
                raise ValueError(f"Unsafe archive member: {name}")
        if archive.testzip() is not None:
            raise ValueError("Archive CRC validation failed")
    except Exception:
        archive.close()
        raise
    return archive


def validate_artifact(name, path):
    if not path.is_file() or path.stat().st_size <= 1_000_000:
        raise ValueError(f"Missing or incomplete {name} export: {path}")
    if name in ("linux", "windows"):
        with path.open("rb") as source:
            if not source.read(4).startswith(b"\x7fELF" if name == "linux" else b"MZ"):
                raise ValueError(f"Invalid {name} executable header")
        return
    with checked_zip(path) as archive:
        names = archive.namelist()
        if name == "macos":
            plists = [n for n in names if n.endswith(".app/Contents/Info.plist")]
            if len(plists) != 1:
                raise ValueError("macOS export must contain one app bundle")
            plist = plistlib.loads(archive.read(plists[0]))
            if plist.get("CFBundleIdentifier") != BUNDLE_ID:
                raise ValueError("Unexpected macOS bundle identifier")
            contents = plists[0].removesuffix("Info.plist")
            executable = contents + "MacOS/" + plist["CFBundleExecutable"]
            info = archive.getinfo(executable)
            if not ((info.external_attr >> 16) & 0o111):
                raise ValueError("macOS executable permission is missing")
            with archive.open(executable) as source:
                header = source.read(48)
            if header[:4] != bytes.fromhex("cafebabe") or struct.unpack(">I", header[4:8])[0] != 2:
                raise ValueError("macOS executable must be Universal 2")
            if {struct.unpack_from(">I", header, offset)[0] for offset in (8, 28)} != {0x01000007, 0x0100000C}:
                raise ValueError("macOS executable lacks x86_64 or arm64")
            if not any(n.startswith(contents + "Resources/") and n.endswith(".pck") for n in names):
                raise ValueError("macOS bundle lacks game data")
            if contents + "_CodeSignature/CodeResources" not in names:
                raise ValueError("macOS bundle lacks its ad-hoc signature")
        elif name == "android":
            for required in ("AndroidManifest.xml", "classes.dex", "assets/project.binary",
                             "lib/arm64-v8a/libgodot_android.so", "lib/x86_64/libgodot_android.so"):
                if required not in names or archive.getinfo(required).file_size == 0:
                    raise ValueError(f"Android APK missing {required}")
