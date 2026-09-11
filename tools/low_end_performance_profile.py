#!/usr/bin/env python3
"""Run a real low-end runtime profile without publishing machine details."""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT_VERSION = "4.7.1"
PROFILE = {
    "name": "low-end",
    "resolution": [960, 540],
    "renderer": "gl_compatibility",
    "audio_driver": "Dummy",
    "vsync": "disabled",
    "default_rounds": 1,
    "default_sample_frames": 60,
}
ROUTES = ("ship_itsaso", "beach", "tables_3d")
DIAGNOSTIC = re.compile(r"^(?:SCRIPT ERROR|ERROR):", re.MULTILINE)
MARKER = re.compile(r"^PERF_REPORT_JSON (\{.*\})$", re.MULTILINE)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--profile", choices=[PROFILE["name"]], default=PROFILE["name"])
    value.add_argument("--godot", help="Godot 4.7.1 editor; defaults to GODOT or .toolchain/godot")
    value.add_argument("--mode", choices=("graphical", "headless"), default="graphical")
    value.add_argument("--rounds", type=int, default=PROFILE["default_rounds"])
    value.add_argument("--samples", type=int, default=PROFILE["default_sample_frames"])
    value.add_argument("--build", action="store_true", help="Measure a real Linux export before the runtime probe")
    value.add_argument("--output", type=Path, help="Write the sanitized JSON report")
    value.add_argument("--markdown", type=Path, help="Write the sanitized Markdown report")
    return value


def source_sha() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def clean_version(text: str) -> str:
    return next((line.strip() for line in text.splitlines() if line.strip()), "unknown")[:120]


def safe_error(error: BaseException) -> str:
    """Keep diagnostics useful without copying local filesystem identity."""
    value = str(error).replace(str(ROOT), "<repo>")
    value = re.sub(r"/home/[^\s]+", "<private-path>", value)
    value = re.sub(r"/tmp/[^\s]+", "<temporary-path>", value)
    return value[:240]


def environment(folder: Path) -> dict[str, str]:
    env = dict(os.environ)
    for name in ("HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
        path = folder / name.lower()
        path.mkdir(parents=True, exist_ok=True)
        env[name] = str(path)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    # This makes the profile repeatable in CI, but is not a hardware claim.
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    return env


def base_report(args: argparse.Namespace, status: str, blocker: str | None = None) -> dict:
    report = {
        "schema": 1,
        "tool": "low-end-performance-profile",
        "status": status,
        "profile": args.profile,
        "profile_settings": PROFILE,
        "mode": args.mode,
        "source_sha": source_sha(),
        "godot_version": None,
        "build": {"status": "not_requested", "elapsed_ms": None, "linux_artifact_bytes": None},
        "routes": [],
        "limits": {
            "hardware_certified": False,
            "fps_certified": False,
            "release_gate": False,
            "software_renderer": True,
            "note": "Measured values require a real execution; this report never certifies a target device.",
        },
        "blockers": [blocker] if blocker else [],
    }
    return report


def atomic_write(path: Path | None, text: str) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def render_markdown(report: dict) -> str:
    lines = [
        "# Low-end runtime profile",
        "",
        f"- Status: **{report['status']}**",
        f"- Profile: `{report['profile']}`",
        f"- Source SHA: `{report['source_sha']}`",
        f"- Godot: `{report.get('godot_version') or 'not executed'}`",
        f"- Mode: `{report['mode']}`",
        "- Signature: **OTACON Astra**",
        "",
        "This is a sanitized report. It contains no hardware identity, private path, save, session, or credential.",
        "The software renderer and fixed viewport make the procedure repeatable; they do not certify a player's GPU or FPS target.",
        "",
        "## Build",
        "",
    ]
    build = report["build"]
    if build["status"] == "measured":
        lines.append(f"- Real Linux export: `{build['elapsed_ms']:.3f} ms`; artifact size `{build['linux_artifact_bytes']} bytes`.")
    elif build["status"] == "not_requested":
        lines.append("- Not requested; run with `--build` to measure the real Linux export.")
    else:
        lines.append(f"- Build status: **{build['status']}**.")
    lines += ["", "## Runtime routes", ""]
    if report["status"] == "measured":
        lines += ["| Route | Frames | Elapsed (ms) | Average FPS* | p95 frame (ms) |", "|---|---:|---:|---:|---:|"]
        for route in report["routes"]:
            metrics = route["metrics"]
            p95 = metrics.get("p95_frame_ms_worst_segment", metrics.get("p95_frame_ms"))
            lines.append(
                f"| `{route['id']}` | {metrics['frames']} | {metrics['elapsed_ms']:.3f} | "
                f"{metrics['avg_fps']:.3f} | {p95:.3f} |"
            )
            for segment in route.get("segments", []):
                segment_metrics = segment["metrics"]
                lines.append(
                    f"| ↳ `{segment['id']}` | {segment_metrics['frames']} | {segment_metrics['elapsed_ms']:.3f} | "
                    f"{segment_metrics['avg_fps']:.3f} | {segment_metrics['p95_frame_ms']:.3f} |"
                )
        lines += ["", "\\* FPS is derived from frames and elapsed time observed in this run; it is not a hardware certification."]
    else:
        lines.append("No runtime metrics were recorded because the runner failed closed before a valid measurement.")
    if report.get("blockers"):
        lines += ["", "## Blockers", ""]
        lines.extend(f"- {blocker}" for blocker in report["blockers"])
    lines += [
        "",
        "## Limits",
        "",
        "- Pending: execute this profile on the intended low-end physical machine; no hardware result is included here.",
        "- Pending: compare a candidate build against an agreed budget; this workflow does not create a release gate.",
        "- The routes are the existing production `main.tscn` deck, beach zone, and 3D poker table projection; no mock scene is used.",
        "",
    ]
    return "\n".join(lines)


def validate_report(report: dict, expected_mode: str | None = None) -> None:
    required = {"schema", "tool", "status", "profile", "build", "routes", "limits", "blockers"}
    missing = required - report.keys()
    if missing:
        raise ValueError("report missing keys: " + ",".join(sorted(missing)))
    if report["schema"] != 1 or report["tool"] != "low-end-performance-profile":
        raise ValueError("unexpected report identity")
    if report["profile"] != PROFILE["name"]:
        raise ValueError("unexpected profile")
    if expected_mode and report.get("mode") != expected_mode:
        raise ValueError("unexpected mode")
    if report["status"] == "measured":
        if set(route["id"] for route in report["routes"]) != set(ROUTES):
            raise ValueError("measured report must contain exactly the three production routes")
        for route in report["routes"]:
            metrics = route.get("metrics", {})
            for key in ("frames", "elapsed_ms", "avg_fps"):
                if key not in metrics or not math.isfinite(float(metrics[key])):
                    raise ValueError(f"invalid metric {route['id']}.{key}")
            if int(metrics["frames"]) <= 0 or float(metrics["elapsed_ms"]) <= 0 or float(metrics["avg_fps"]) <= 0:
                raise ValueError(f"non-positive metric {route['id']}")
    elif report["routes"]:
        raise ValueError("blocked/failed report cannot contain measurements")
    if report["limits"].get("hardware_certified") or report["limits"].get("fps_certified"):
        raise ValueError("the runner cannot certify hardware or FPS")
    if any(key in report for key in ("cpu_model", "gpu_model", "hostname", "private_path")):
        raise ValueError("report contains forbidden machine identity")


def resolve_godot(args: argparse.Namespace) -> Path | None:
    value = args.godot or os.environ.get("GODOT") or str(ROOT / ".toolchain/godot")
    path = Path(value).expanduser()
    return path if path.is_file() and os.access(path, os.X_OK) else None


def godot_version(godot: Path, env: dict[str, str]) -> str:
    result = subprocess.run(
        [str(godot), "--version"], cwd=ROOT, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30, check=False,
    )
    version = clean_version(result.stdout)
    if result.returncode or not version.startswith(GODOT_VERSION + ".stable."):
        raise RuntimeError(f"expected Godot {GODOT_VERSION}.stable; observed {version}")
    return version


def build_export(env: dict[str, str]) -> dict:
    started = time.perf_counter()
    result = subprocess.run(
        [sys.executable, str(ROOT / "tools/build.py"), "--targets", "linux"],
        cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=600, check=False,
    )
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    if result.returncode or DIAGNOSTIC.search(result.stdout):
        raise RuntimeError("real Linux export failed")
    artifact = ROOT / "build" / "linux" / "EspaciokoopLagunak.x86_64"
    if not artifact.is_file() or artifact.stat().st_size <= 1_000_000:
        raise RuntimeError("real Linux export did not produce a complete executable")
    return {"status": "measured", "elapsed_ms": elapsed_ms, "linux_artifact_bytes": artifact.stat().st_size}


def runtime_command(godot: Path, args: argparse.Namespace) -> list[str]:
    command = [
        str(godot),
        "--path", str(ROOT / "game"),
        "--audio-driver", PROFILE["audio_driver"],
        "--rendering-method", PROFILE["renderer"],
        "--disable-vsync",
        "--resolution", f"{PROFILE['resolution'][0]}x{PROFILE['resolution'][1]}",
    ]
    if args.mode == "headless":
        command.insert(1, "--headless")
    command += [
        "--script", "../tools/low_end_performance_profile.gd", "--",
        "--performance-rounds=" + str(args.rounds),
        "--performance-samples=" + str(args.samples),
        "--performance-mode=" + args.mode,
    ]
    return command


def run_runtime(godot: Path, args: argparse.Namespace, env: dict[str, str], version: str) -> dict:
    if args.mode == "graphical" and not env.get("DISPLAY"):
        raise RuntimeError("graphical mode requires DISPLAY; use Xvfb or --mode headless")
    result = subprocess.run(
        runtime_command(godot, args), cwd=ROOT, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300, check=False,
    )
    if result.returncode or DIAGNOSTIC.search(result.stdout):
        raise RuntimeError(f"runtime probe failed (exit={result.returncode})")
    match = MARKER.findall(result.stdout)
    if len(match) != 1:
        raise RuntimeError("runtime probe emitted no unique sanitized report")
    report = json.loads(match[0])
    report["source_sha"] = source_sha()
    report["godot_version"] = version
    report["profile_settings"] = PROFILE
    report["limits"] = {
        "hardware_certified": False,
        "fps_certified": False,
        "release_gate": False,
        "software_renderer": True,
        "note": "Measured values require a real execution; this report never certifies a target device.",
    }
    report["mode"] = args.mode
    validate_report(report, args.mode)
    return report


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    if not 1 <= args.rounds <= 3:
        parser().error("--rounds must be between 1 and 3")
    if not 10 <= args.samples <= 600:
        parser().error("--samples must be between 10 and 600")
    report = base_report(args, "blocked")
    try:
        godot = resolve_godot(args)
        if godot is None:
            raise RuntimeError("Godot 4.7.1 executable is unavailable; run tools/bootstrap.py or pass --godot")
        with tempfile.TemporaryDirectory(prefix="lagunak-performance-") as temporary:
            env = environment(Path(temporary))
            version = godot_version(godot, env)
            report["godot_version"] = version
            build = build_export(env) if args.build else report["build"]
            report = run_runtime(godot, args, env, version)
            report["build"] = build
            report["status"] = "measured"
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError, subprocess.TimeoutExpired) as error:
        report["status"] = "blocked" if report["godot_version"] is None else "failed"
        report["blockers"] = [safe_error(error)]
    validate_report(report, args.mode)
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    atomic_write(args.output, payload)
    atomic_write(args.markdown, render_markdown(report))
    if report["status"] == "measured":
        print("PERFORMANCE_PROFILE_OK routes=3", flush=True)
        return 0
    marker = "PERFORMANCE_PROFILE_BLOCKED" if report["status"] == "blocked" else "PERFORMANCE_PROFILE_FAILED"
    print(marker + " " + report["blockers"][0], flush=True)
    return 2 if report["status"] == "blocked" else 1


if __name__ == "__main__":
    raise SystemExit(main())
