#!/usr/bin/env python3
"""Cross-export standalone applications from Linux with the pinned Godot editor."""
import argparse
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

from export_targets import (GODOT_VERSION, TARGETS, add_target_argument, artifact_name,
                            selected_targets, template_directory, validate_artifact, validate_presets)

ROOT = Path(__file__).resolve().parents[1]


def run_checked(command, env):
    result = subprocess.run([str(c) for c in command], env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    output = result.stdout
    for key, value in env.items():
        if key.startswith("GODOT_") and "PASSWORD" in key and value:
            output = output.replace(value, "<REDACTED>")
    print(output, end="", flush=True)
    if result.returncode or re.search(r"^(?:SCRIPT ERROR|ERROR):", output, re.MULTILINE):
        raise ValueError(f"Command failed: {Path(command[0]).name} (exit {result.returncode}); see output above")
    return output


def android_preflight(env, debug=False):
    sdk_value = env.get("ANDROID_HOME") or env.get("ANDROID_SDK_ROOT")
    if not sdk_value:
        raise ValueError("Android SDK missing: set ANDROID_HOME (or ANDROID_SDK_ROOT); install platform-tools, build-tools;35.0.1 and platforms;android-35. See docs/PLATFORM_EXPORTS.md.")
    sdk = Path(sdk_value).expanduser().resolve()
    java_value = env.get("JAVA_HOME")
    if not java_value:
        raise ValueError("Android requires JAVA_HOME pointing to OpenJDK 17 (not its bin directory).")
    java = Path(java_value).expanduser().resolve()
    for path in (sdk / "platform-tools/adb", sdk / "build-tools/35.0.1/apksigner",
                 sdk / "build-tools/35.0.1/zipalign", sdk / "platforms/android-35/android.jar",
                 java / "bin/java", java / "bin/keytool"):
        if not path.is_file():
            raise ValueError(f"Incomplete Android SDK/JDK: missing {path}")
    env["JAVA_HOME"] = str(java)
    env["ANDROID_HOME"] = str(sdk)
    env["PATH"] = str(java / "bin") + os.pathsep + env.get("PATH", "")
    version = run_checked([java / "bin/java", "-version"], env)
    match = re.search(r'version "(\d+)', version)
    if not match or int(match.group(1)) < 17:
        raise ValueError("Android requires OpenJDK 17 or later.")
    if not debug:
        prefix = "GODOT_ANDROID_KEYSTORE_RELEASE_"
        missing = [prefix + key for key in ("PATH", "USER", "PASSWORD") if not env.get(prefix + key)]
        if missing:
            raise ValueError("Android release signing requires " + ", ".join(missing) + ". Use --android-debug only for a test APK; no release key is generated automatically.")
        keystore = Path(env[prefix + "PATH"]).expanduser().resolve()
        if not keystore.is_file():
            raise ValueError("Android release keystore file does not exist.")
        env[prefix + "PATH"] = str(keystore)
        # keytool reads the secret from its environment, never from process arguments.
        run_checked([java / "bin/keytool", "-list", "-keystore", keystore,
                     "-alias", env[prefix + "USER"], "-storepass:env", prefix + "PASSWORD"], env)
    return sdk / "build-tools/35.0.1/apksigner"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    add_target_argument(parser)
    parser.add_argument("--android-debug", action="store_true", help="Export a signed test APK with Godot's debug key; desktop builds remain release builds.")
    parser.add_argument("--check", action="store_true", help="Validate presets, toolchain, SDK and signing without downloading or exporting.")
    args = parser.parse_args(argv)
    names = selected_targets(args.targets)
    if args.android_debug and "android" not in names:
        parser.error("--android-debug requires --targets android")
    try:
        validate_presets(ROOT / "game/export_presets.cfg", names)
        if sys.platform != "linux":
            raise ValueError("This reproducible cross-export command requires a Linux build host; the exported applications run on their target platforms.")
        env = os.environ.copy()
        env["XDG_DATA_HOME"] = str(ROOT / ".toolchain/data")
        signer = android_preflight(env, args.android_debug) if "android" in names else None
        godot = Path(env.get("GODOT", ROOT / ".toolchain/godot")).expanduser().resolve()
        needed = [template_directory(ROOT) / f for n in names for f in TARGETS[n].templates
                  if f != ("android_release.apk" if args.android_debug else "android_debug.apk")]
        missing = [str(path) for path in needed if not path.is_file()]
        if not godot.is_file() or missing:
            if args.check:
                raise ValueError("Missing Godot editor/export templates; run python3 tools/bootstrap.py --templates --targets " + " ".join(names))
            command = [sys.executable, ROOT / "tools/bootstrap.py", "--templates", "--targets", *names]
            if godot.is_file():
                command.append("--templates-only")
            elif "GODOT" in env:
                raise ValueError("GODOT points to a missing editor; correct it or unset GODOT to use bootstrap.")
            run_checked(command, env)
        version = run_checked([godot, "--version"], env).strip()
        if not version.startswith(GODOT_VERSION + ".stable."):
            raise ValueError(f"Expected Godot {GODOT_VERSION}.stable, received {version}")
        if args.check:
            print("EXPORT_CHECK_OK", ", ".join(names))
            return 0
        # Fresh editor settings pick up JAVA_HOME/ANDROID_HOME without replacing user settings.
        with tempfile.TemporaryDirectory(prefix="lagunak-export-config-") as config:
            env["XDG_CONFIG_HOME"] = config
            for name in names:
                target = ROOT / "build" / name / artifact_name(name, args.android_debug)
                target.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.TemporaryDirectory(prefix=".export-", dir=target.parent) as staging:
                    staged = Path(staging) / target.name
                    flag = "--export-debug" if name == "android" and args.android_debug else "--export-release"
                    run_checked([godot, "--headless", "--path", ROOT / "game", flag, TARGETS[name].preset, staged], env)
                    validate_artifact(name, staged)
                    if name == "android":
                        run_checked([signer, "verify", "--verbose", staged], env)
                    if name == "linux":
                        staged.chmod(0o755)
                    staged.replace(target)
                print("EXPORTED", target.name, target.stat().st_size, flush=True)
        return 0
    except (ValueError, OSError, KeyError) as error:
        print("EXPORT_FAILED:", error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
