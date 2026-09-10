#!/usr/bin/env python3
"""Contract and negative tests; synthetic fixtures are not executable smoke tests."""
import argparse
import contextlib
import hashlib
import io
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build
import bootstrap
import export_targets as exports
import package_downloads as packages


def macos_fixture(path, executable=True, both_cpus=True, pck=True, signature=True):
    path.parent.mkdir(parents=True, exist_ok=True)
    contents = "EspaciokoopLagunak.app/Contents/"
    plist = {"CFBundleIdentifier": exports.BUNDLE_ID, "CFBundleExecutable": "EspaciokoopLagunak"}
    header = struct.pack(">II", 0xCAFEBABE, 2)
    header += struct.pack(">IIIII", 0x01000007, 3, 4096, 400000, 12)
    header += struct.pack(">IIIII", 0x0100000C if both_cpus else 7, 0, 500000, 500000, 12)
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(contents + "Info.plist", plistlib.dumps(plist))
        info = zipfile.ZipInfo(contents + "MacOS/EspaciokoopLagunak")
        info.create_system = 3
        info.external_attr = (0o100755 if executable else 0o100644) << 16
        archive.writestr(info, header + bytes(1_000_001))
        if pck:
            archive.writestr(contents + "Resources/EspaciokoopLagunak.pck", b"GDPCgame")
        if signature:
            archive.writestr(contents + "_CodeSignature/CodeResources", b"signature-fixture")


def android_fixture(path, omit=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as archive:
        for name in ("AndroidManifest.xml", "classes.dex", "assets/project.binary",
                     "lib/arm64-v8a/libgodot_android.so", "lib/x86_64/libgodot_android.so"):
            if name != omit:
                archive.writestr(name, b"fixture")
        archive.writestr("assets/padding", bytes(1_000_001))


class PlatformExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def sdk_environment(self):
        sdk, java = self.root / "sdk", self.root / "jdk"
        for path in (sdk / "platform-tools/adb", sdk / "build-tools/35.0.1/apksigner",
                     sdk / "build-tools/35.0.1/zipalign", sdk / "platforms/android-35/android.jar",
                     java / "bin/java", java / "bin/keytool"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        return {"ANDROID_HOME": str(sdk), "JAVA_HOME": str(java)}

    def preset_variant(self, before, after):
        path = self.root / "export_presets.cfg"
        path.write_text((ROOT / "game/export_presets.cfg").read_text().replace(before, after))
        return path

    def package_sources(self):
        for name in ("LICENSE", "CREDITS.md", "docs/PLAYER_GUIDE.md", "docs/PLATFORM_EXPORTS.md", "third_party/godot.txt"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
        for name in ("module.json", "main.mjs", "client.mjs", "style.css", "README.md"):
            path = self.root / "integrations/foundry" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
        for name, magic in (("linux", b"\x7fELF"), ("windows", b"MZ")):
            path = self.root / "build" / name / exports.artifact_name(name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(magic + bytes(1_000_001))
            if name == "linux":
                path.chmod(0o755)

    def test_defaults_keep_linux_windows(self):
        parser = argparse.ArgumentParser()
        exports.add_target_argument(parser)
        self.assertEqual(parser.parse_args([]).targets, ["linux", "windows"])
        self.assertEqual(exports.selected_targets(["macos", "android", "macos"]), ["macos", "android"])

    def test_unknown_target_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            build.main(["--targets", "ios"])

    def test_debug_must_select_android(self):
        for main in (build.main, packages.main):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                main(["--android-debug"])

    def test_all_presets_are_complete(self):
        exports.validate_presets(ROOT / "game/export_presets.cfg", exports.TARGETS)

    def test_missing_preset_fails(self):
        path = self.preset_variant('name="Android"', 'name="Other"')
        with self.assertRaisesRegex(ValueError, "Missing export preset"):
            exports.validate_presets(path, ["android"])

    def test_duplicate_preset_fails(self):
        path = self.preset_variant('name="Android"', 'name="Linux"')
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            exports.validate_presets(path, ["linux"])

    def test_android_cannot_be_unsigned(self):
        path = self.preset_variant("package/signed=true", "package/signed=false")
        with self.assertRaisesRegex(ValueError, "package/signed"):
            exports.validate_presets(path, ["android"])

    def test_android_requires_network_permission(self):
        path = self.preset_variant("permissions/internet=true", "permissions/internet=false")
        with self.assertRaisesRegex(ValueError, "permissions/internet"):
            exports.validate_presets(path, ["android"])

    def test_tracked_keystore_rejected(self):
        path = self.preset_variant("package/signed=true", 'package/signed=true\nkeystore/release_password="private"')
        with self.assertRaisesRegex(ValueError, "environment variables"):
            exports.validate_presets(path, ["android"])

    def test_campaign_data_must_be_exported(self):
        path = self.preset_variant("data/*.json", "data/*.txt")
        with self.assertRaisesRegex(ValueError, "campaign JSON"):
            exports.validate_presets(path, ["macos"])

    def test_missing_sdk_stops_before_download_or_export(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(build, "run_checked") as runner:
            with contextlib.redirect_stderr(io.StringIO()) as output:
                self.assertEqual(build.main(["--targets", "android"]), 1)
            self.assertIn("Android SDK missing", output.getvalue())
            runner.assert_not_called()

    def test_missing_java(self):
        with self.assertRaisesRegex(ValueError, "JAVA_HOME"):
            build.android_preflight({"ANDROID_HOME": str(self.root)})

    def test_incomplete_sdk(self):
        env = self.sdk_environment()
        (Path(env["ANDROID_HOME"]) / "build-tools/35.0.1/apksigner").unlink()
        with self.assertRaisesRegex(ValueError, "Incomplete Android SDK/JDK"):
            build.android_preflight(env, debug=True)

    def test_old_java_rejected(self):
        with patch.object(build, "run_checked", return_value='openjdk version "11.0.0"'):
            with self.assertRaisesRegex(ValueError, "OpenJDK 17"):
                build.android_preflight(self.sdk_environment(), debug=True)

    def test_release_cannot_silently_use_debug_key(self):
        with patch.object(build, "run_checked", return_value='openjdk version "17.0.1"'):
            with self.assertRaisesRegex(ValueError, "release signing requires"):
                build.android_preflight(self.sdk_environment())

    def test_debug_does_not_require_release_credentials(self):
        env = self.sdk_environment()
        env["ANDROID_SDK_ROOT"] = env.pop("ANDROID_HOME")
        with patch.object(build, "run_checked", return_value='openjdk version "17.0.1"'):
            self.assertEqual(build.android_preflight(env, True).name, "apksigner")
        self.assertEqual(env["ANDROID_HOME"], env["ANDROID_SDK_ROOT"])

    def test_release_missing_key_file(self):
        env = self.sdk_environment()
        env.update({"GODOT_ANDROID_KEYSTORE_RELEASE_" + key: value for key, value in
                    {"PATH": str(self.root / "missing.jks"), "USER": "release", "PASSWORD": "secret"}.items()})
        with patch.object(build, "run_checked", return_value='openjdk version "17.0.1"'):
            with self.assertRaisesRegex(ValueError, "keystore file does not exist"):
                build.android_preflight(env)

    def test_release_secret_is_never_a_process_argument(self):
        env = self.sdk_environment()
        key = self.root / "signing.jks"
        key.write_text("fixture")
        env.update({"GODOT_ANDROID_KEYSTORE_RELEASE_" + field: value for field, value in
                    {"PATH": str(key), "USER": "release", "PASSWORD": "private-secret"}.items()})
        with patch.object(build, "run_checked", return_value='openjdk version "17.0.1"') as runner:
            build.android_preflight(env)
        command = runner.call_args.args[0]
        self.assertIn("-storepass:env", command)
        self.assertNotIn("private-secret", command)

    def test_godot_errors_fail_even_with_zero_exit_and_secrets_are_redacted(self):
        result = subprocess.CompletedProcess([], 0, "\x1b[31mERROR: private-secret\x1b[0m\n")
        with patch.object(subprocess, "run", return_value=result), contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaisesRegex(ValueError, "Command failed"):
                build.run_checked(["godot"], {"GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": "private-secret"})
        self.assertNotIn("private-secret", output.getvalue())
        self.assertIn("<REDACTED>", output.getvalue())

    def test_check_does_not_bootstrap_missing_templates(self):
        with patch.object(build, "ROOT", self.root), patch.object(build, "validate_presets"), patch.object(build, "run_checked") as runner:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(build.main(["--check", "--targets", "macos"]), 1)
        runner.assert_not_called()

    def test_bootstrap_rejects_checksum_mismatch(self):
        sums = ("0" * 128 + "  templates.tpz\n").encode()
        with patch.object(bootstrap, "CACHE", self.root), patch.object(bootstrap.urllib.request, "urlopen", side_effect=[io.BytesIO(sums), io.BytesIO(b"tampered")]):
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
                bootstrap.download("templates.tpz")
        self.assertFalse((self.root / "templates.tpz").exists())
        self.assertFalse((self.root / "templates.partial").exists())

    def test_bootstrap_reuses_only_checksum_verified_archive(self):
        archive = self.root / "templates.tpz"
        archive.write_bytes(b"verified archive fixture")
        sums = (hashlib.sha512(archive.read_bytes()).hexdigest() + "  templates.tpz\n").encode()
        with patch.object(bootstrap, "CACHE", self.root), patch.object(bootstrap.urllib.request, "urlopen", return_value=io.BytesIO(sums)) as fetch:
            self.assertEqual(bootstrap.download("templates.tpz"), archive)
        self.assertEqual(fetch.call_count, 1)

    def test_invalid_binary_rejected(self):
        path = self.root / "invalid.exe"
        path.write_bytes(b"not an exe" + bytes(1_000_001))
        with self.assertRaisesRegex(ValueError, "header"):
            exports.validate_artifact("windows", path)

    def test_missing_or_tiny_export_rejected(self):
        path = self.root / "missing"
        with self.assertRaisesRegex(ValueError, "Missing or incomplete"):
            exports.validate_artifact("linux", path)
        path.write_bytes(b"\x7fELF")
        with self.assertRaisesRegex(ValueError, "Missing or incomplete"):
            exports.validate_artifact("linux", path)

    def test_macos_contract(self):
        path = self.root / "macos.zip"
        macos_fixture(path)
        exports.validate_artifact("macos", path)

    def test_macos_executable_permission_required(self):
        path = self.root / "macos.zip"
        macos_fixture(path, executable=False)
        with self.assertRaisesRegex(ValueError, "permission"):
            exports.validate_artifact("macos", path)

    def test_macos_requires_both_cpus_game_data_and_signature(self):
        for kwargs, error in (({"both_cpus": False}, "lacks x86_64"), ({"pck": False}, "game data"), ({"signature": False}, "signature")):
            with self.subTest(kwargs=kwargs):
                path = self.root / "macos.zip"
                macos_fixture(path, **kwargs)
                with self.assertRaisesRegex(ValueError, error):
                    exports.validate_artifact("macos", path)

    def test_android_requires_game_and_both_architectures(self):
        path = self.root / "android.apk"
        android_fixture(path)
        exports.validate_artifact("android", path)
        for missing in ("assets/project.binary", "lib/arm64-v8a/libgodot_android.so", "lib/x86_64/libgodot_android.so"):
            with self.subTest(missing=missing):
                android_fixture(path, omit=missing)
                with self.assertRaisesRegex(ValueError, "missing"):
                    exports.validate_artifact("android", path)

    def test_archive_paths_and_duplicates_rejected(self):
        for names in ((".",), ("../escape",), ("/absolute",), ("C:/escape",), ("a\\b",), ("duplicate", "duplicate")):
            with self.subTest(names=names):
                path = self.root / "invalid.zip"
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    with zipfile.ZipFile(path, "w") as archive:
                        for name in names:
                            archive.writestr(name, "fixture")
                with self.assertRaises(ValueError):
                    exports.checked_zip(path)

    def test_legacy_packages_checksums_and_foundry_read_only(self):
        self.package_sources()
        foundry = self.root / "integrations/foundry"
        before = {p.name: p.read_bytes() for p in foundry.iterdir()}
        checksums = packages.package_exports(self.root, ["linux", "windows"])
        self.assertEqual(len(checksums), 3)
        self.assertEqual(before, {p.name: p.read_bytes() for p in foundry.iterdir()})
        self.assertFalse((foundry / "LICENSE").exists())
        for line in checksums:
            digest, filename = line.strip().split("  ")
            path = self.root / "dist" / filename
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest)
            with zipfile.ZipFile(path) as archive:
                self.assertIn("LICENSE", archive.namelist())
        with zipfile.ZipFile(self.root / "dist" / exports.package_name("linux")) as archive:
            self.assertTrue((archive.getinfo(exports.artifact_name("linux")).external_attr >> 16) & 0o111)

    def test_failed_input_keeps_previous_packages_and_manifest(self):
        self.package_sources()
        packages.package_exports(self.root, ["linux"])
        before = {p.name: p.read_bytes() for p in (self.root / "dist").iterdir()}
        with self.assertRaisesRegex(ValueError, "Missing or incomplete"):
            packages.package_exports(self.root, ["linux", "macos"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in (self.root / "dist").iterdir()})

    def test_macos_packaging_keeps_bundle_bytes_and_permissions(self):
        self.package_sources()
        source = self.root / "build/macos" / exports.artifact_name("macos")
        macos_fixture(source)
        packages.package_exports(self.root, ["macos"], foundry=False)
        with zipfile.ZipFile(source) as original, zipfile.ZipFile(self.root / "dist" / exports.package_name("macos")) as packaged:
            self.assertNotIn(source.name, packaged.namelist())
            for info in original.infolist():
                self.assertEqual(original.read(info), packaged.read(info.filename))
                self.assertEqual(info.external_attr, packaged.getinfo(info.filename).external_attr)

    def test_debug_and_release_packages_are_distinct(self):
        self.package_sources()
        path = self.root / "build/android" / exports.artifact_name("android", True)
        android_fixture(path)
        packages.package_exports(self.root, ["android"], android_debug=True, foundry=False)
        self.assertTrue((self.root / "dist" / exports.package_name("android", True)).is_file())
        with self.assertRaises(ValueError):
            packages.package_exports(self.root, ["android"], foundry=False)
        self.assertFalse((self.root / "dist" / exports.package_name("android")).exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
