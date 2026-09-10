"""Publish an explicitly requested 0.9 release only from verified main workflow artifacts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from export_targets import VERSION, checked_zip, package_name


def verified_assets(directory):
    expected = {package_name("linux"), package_name("windows"), "espaciokoop-lagunak-foundry.zip"}
    entries = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        if name not in expected or name in entries:
            raise ValueError("Unexpected or duplicate checksum entry")
        path = directory / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("Missing package or symbolic link")
        with path.open("rb") as source:
            if hashlib.file_digest(source, "sha256").hexdigest() != digest:
                raise ValueError("Package checksum mismatch")
        with checked_zip(path) as archive:
            if "LICENSE" not in archive.namelist():
                raise ValueError("Package license missing")
        entries[name] = path
    if set(entries) != expected:
        raise ValueError("Release requires Linux, Windows and optional Foundry packages")
    return [entries[name] for name in sorted(entries)] + [directory / "SHA256SUMS"]


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def publish(directory, repository, commit, run_id):
    # A future version requires an explicit publication change; never auto-release 1.0.
    if VERSION not in ("0.9.0", "0.9.1"):
        print("No automatic publication requested for", VERSION)
        return
    run = json.loads(gh("api", f"repos/{repository}/actions/runs/{run_id}"))
    if (run["conclusion"] != "success" or run["status"] != "completed"
            or run["head_sha"] != commit or run["head_branch"] != "main"
            or run["event"] != "push" or run["path"] != ".github/workflows/release.yml"
            or run["head_repository"]["full_name"] != repository):
        raise ValueError("Release source must be the successful canonical main workflow")
    tag = "v" + VERSION
    try:
        release = json.loads(gh("api", f"repos/{repository}/releases/tags/{tag}"))
    except subprocess.CalledProcessError as error:
        if "HTTP 404" not in error.stderr:
            raise
    else:
        if release["draft"]:
            raise ValueError("Existing draft requires review; refusing to publish partial assets")
        print("Release already published:", release["html_url"])
        return
    assets = verified_assets(directory)
    # Never reuse an existing tag pointing elsewhere.
    try:
        ref = json.loads(gh("api", f"repos/{repository}/git/ref/tags/{tag}"))
    except subprocess.CalledProcessError as error:
        if "HTTP 404" not in error.stderr:
            raise
    else:
        if ref["object"]["type"] != "commit" or ref["object"]["sha"] != commit:
            raise ValueError("Existing release tag points to a different commit")
    gh("release", "create", tag, *map(str, assets), "--repo", repository,
       "--target", commit, "--title", f"Espaciokoop Lagunak {VERSION}", "--draft",
       "--notes-file", "docs/RELEASE_NOTES.md")
    gh("release", "edit", tag, "--repo", repository, "--draft=false", "--latest")
    print(f"RELEASE_PUBLISHED https://github.com/{repository}/releases/tag/{tag}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    args = parser.parse_args()
    publish(Path("dist"), args.repository, args.commit, args.run_id)
