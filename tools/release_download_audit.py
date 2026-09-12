#!/usr/bin/env python3
"""Read-only comparison of published downloads with canonical workflow artifacts.

Run from a checkout of the version being audited. Requires gh with read access to
Actions artifacts. It never executes a downloaded game or writes to GitHub.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

from export_targets import VERSION, checked_zip, package_name
from publish_release import verified_assets

MAX_ASSET_BYTES = 1024 * 1024 * 1024
MAX_ZIP_EXPANDED_BYTES = 2 * MAX_ASSET_BYTES
MAX_ZIP_ENTRIES = 4096
FOUNDRY_MANIFEST = Path(__file__).resolve().parents[1] / "integrations/foundry/module.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def expected_names() -> set[str]:
    return {package_name("linux"), package_name("windows"),
            "espaciokoop-lagunak-foundry.zip", "SHA256SUMS"}


def validate_request(repository: str, tag: str, commit: str, run_id: int) -> None:
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repository) is not None,
            "Expected a GitHub owner/repository, not a URL or option")
    require(tag == "v" + VERSION, "Checkout version does not match the requested tag")
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "Expected a complete lowercase commit SHA")
    require(type(run_id) is int and run_id > 0, "Expected a positive canonical run ID")


def validate_metadata(release: dict, tag_ref: dict, run: dict, jobs: list,
                      repository: str, tag: str, commit: str, run_id: int) -> dict:
    validate_request(repository, tag, commit, run_id)
    require(release.get("tag_name") == tag and release.get("draft") is False
            and bool(release.get("published_at")), "Release is absent, a draft or has the wrong tag")
    require(type(release.get("id")) is int, "Missing release identity")
    require(tag_ref.get("object", {}).get("type") == "commit"
            and tag_ref["object"].get("sha") == commit, "Release tag does not point to the approved commit")
    expected_run = {"id": run_id, "status": "completed", "conclusion": "success",
                    "head_sha": commit, "head_branch": "main", "event": "push",
                    "path": ".github/workflows/release.yml"}
    require(all(run.get(key) == value for key, value in expected_run.items())
            and run.get("head_repository", {}).get("full_name") == repository,
            "Run is not the successful canonical push of the approved main commit")
    for name in ("build", "windows-smoke"):
        matching = [job for job in jobs if job.get("name") == name]
        require(len(matching) == 1, "Missing or duplicated canonical job: " + name)
        job = matching[0]
        require(job.get("status") == "completed" and job.get("conclusion") == "success"
                and job.get("head_sha") == commit and job.get("run_id") == run_id,
                "Canonical job is not successful for this commit: " + name)
    assets = release.get("assets", [])
    require(isinstance(assets, list) and len(assets) == len(expected_names()), "Unexpected release asset count")
    by_name = {}
    for asset in assets:
        name = asset.get("name")
        require(name in expected_names() and name not in by_name, "Unexpected or duplicate release asset")
        size = asset.get("size")
        require(asset.get("state") == "uploaded" and type(asset.get("id")) is int
                and type(size) is int and 0 < size <= MAX_ASSET_BYTES, "Incomplete or oversized release asset")
        digest = asset.get("digest")
        require(isinstance(digest, str) and re.fullmatch(r"sha256:[0-9a-f]{64}", digest) is not None,
                "Release asset has no usable GitHub SHA-256 digest")
        by_name[name] = asset
    require(set(by_name) == expected_names(), "Missing release assets")
    return by_name


def validate_artifacts(artifacts: list, commit: str, run_id: int) -> dict:
    matching = [item for item in artifacts if item.get("name") == "standalone-downloads"]
    require(len(matching) == 1, "Missing or ambiguous standalone-downloads artifact")
    artifact = matching[0]
    origin = artifact.get("workflow_run", {})
    require(artifact.get("expired") is False and type(artifact.get("id")) is int
            and origin.get("id") == run_id and origin.get("head_sha") == commit,
            "Canonical artifact is expired or belongs to another run/commit")
    return artifact


def digest_file(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def preflight_directory(directory: Path) -> None:
    # Bound decompression before calling the shared ZIP/checksum validator.
    for name in expected_names():
        path = directory / name
        require(path.is_file() and not path.is_symlink(), "Missing download or symbolic link: " + name)
        require(0 < path.stat().st_size <= MAX_ASSET_BYTES, "Invalid download size: " + name)
        if name == "SHA256SUMS":
            require(path.stat().st_size <= 4096, "Oversized checksum manifest")
            continue
        with zipfile.ZipFile(path) as archive:
            entries = archive.infolist()
            require(len(entries) <= MAX_ZIP_ENTRIES
                    and sum(info.file_size for info in entries) <= MAX_ZIP_EXPANDED_BYTES,
                    "ZIP exceeds audit limits")
            require(not any(stat.S_ISLNK(info.external_attr >> 16) for info in entries), "ZIP contains symbolic links")


def compare_downloads(published: Path, canonical: Path, assets: dict) -> dict:
    for directory in (published, canonical):
        preflight_directory(directory)
        verified_assets(directory)  # Reuse the publisher's checksum/license/path contract.
    result = {}
    for name in sorted(expected_names()):
        path = published / name
        digest = digest_file(path)
        require(path.stat().st_size == assets[name]["size"], "Published size mismatch: " + name)
        require("sha256:" + digest == assets[name]["digest"], "GitHub digest mismatch: " + name)
        require(digest == digest_file(canonical / name), "Published bytes differ from canonical CI: " + name)
        result[name] = {"size": path.stat().st_size, "sha256": digest}
    for platform, filename, magic in (("linux", "EspaciokoopLagunak.x86_64", b"\x7fELF"),
                                     ("windows", "EspaciokoopLagunak.exe", b"MZ")):
        with checked_zip(published / package_name(platform)) as archive:
            require({filename, "LICENSE", "CREDITS.md", "LEEME.md"} <= set(archive.namelist()),
                    "Missing game or instructions: " + platform)
            require(archive.getinfo(filename).file_size > 1_000_000, "Truncated executable: " + platform)
            with archive.open(filename) as binary:
                require(binary.read(len(magic)) == magic, "Invalid executable header: " + platform)
    with checked_zip(published / "espaciokoop-lagunak-foundry.zip") as archive:
        require(archive.getinfo("module.json").file_size <= 131072, "Oversized Foundry manifest")
        manifest_bytes = archive.read("module.json")
        module = json.loads(manifest_bytes)
        # The optional adapter can remain unchanged across game releases.
        # Require the COMPLETE versioned source, not an arbitrary older version.
        require(isinstance(module, dict) and module.get("id") == "espaciokoop-lagunak"
                and manifest_bytes == FOUNDRY_MANIFEST.read_bytes(),
                "Foundry manifest has the wrong identity/version or differs from versioned source")
    return result


class GitHubReads:
    """Only read commands. Never print stderr, which can include local CLI details."""

    def command(self, *args: str, timeout: int = 180) -> str:
        try:
            completed = subprocess.run(["gh", *args], capture_output=True, text=True,
                                       check=True, timeout=timeout)
        except (subprocess.SubprocessError, OSError) as error:
            raise RuntimeError("GitHub read/download failed; check access, rate limits and artifact retention") from error
        return completed.stdout

    def get(self, endpoint: str) -> dict:
        return json.loads(self.command("api", endpoint, timeout=45))

    def pages(self, endpoint: str, key: str) -> list:
        pages = json.loads(self.command("api", "--paginate", "--slurp", endpoint, timeout=90))
        return [item for page in pages for item in page[key]]

    def release_download(self, repository: str, tag: str, directory: Path) -> None:
        patterns = [part for name in sorted(expected_names()) for part in ("--pattern", name)]
        self.command("release", "download", tag, "--repo", repository, "--dir", str(directory), *patterns)

    def artifact_download(self, repository: str, run_id: int, directory: Path) -> None:
        self.command("run", "download", str(run_id), "--repo", repository,
                     "--name", "standalone-downloads", "--dir", str(directory))


def audit(repository: str, tag: str, commit: str, run_id: int, reader=None) -> dict:
    validate_request(repository, tag, commit, run_id)
    reader = reader or GitHubReads()
    prefix = "repos/" + repository
    release_endpoint = prefix + "/releases/tags/" + tag
    ref_endpoint = prefix + "/git/ref/tags/" + tag
    run_endpoint = prefix + "/actions/runs/" + str(run_id)
    release = reader.get(release_endpoint)
    ref = reader.get(ref_endpoint)
    run = reader.get(run_endpoint)
    jobs = reader.pages(run_endpoint + "/jobs?filter=latest&per_page=100", "jobs")
    assets = validate_metadata(release, ref, run, jobs, repository, tag, commit, run_id)
    artifact = validate_artifacts(reader.pages(run_endpoint + "/artifacts?per_page=100", "artifacts"), commit, run_id)
    with tempfile.TemporaryDirectory(prefix="lagunak-public-download-audit-") as temporary:
        published, canonical = Path(temporary) / "published", Path(temporary) / "canonical"
        published.mkdir()
        canonical.mkdir()
        reader.release_download(repository, tag, published)
        reader.artifact_download(repository, run_id, canonical)
        files = compare_downloads(published, canonical, assets)
    # Detect replacement during the read; no claim of permanent immutability.
    final = reader.get(release_endpoint)
    require(final.get("id") == release["id"] and final.get("draft") is False
            and final.get("tag_name") == tag, "Release identity/status changed during audit")
    identity = lambda items: sorted((item.get("id"), item.get("name"), item.get("size"), item.get("digest")) for item in items)
    require(identity(final.get("assets", [])) == identity(release["assets"]), "Release assets changed during audit")
    require(reader.get(ref_endpoint).get("object") == ref.get("object"), "Release tag changed during audit")
    final_run = reader.get(run_endpoint)
    require(final_run.get("run_attempt") == run.get("run_attempt")
            and final_run.get("status") == "completed" and final_run.get("conclusion") == "success",
            "Canonical run changed during audit")
    final_artifact = validate_artifacts(reader.pages(run_endpoint + "/artifacts?per_page=100", "artifacts"), commit, run_id)
    require(all(final_artifact.get(key) == artifact.get(key) for key in ("id", "digest", "size_in_bytes")),
            "Canonical artifact changed during audit")
    return {"schema": "lagunak-release-download-audit-v1", "repository": repository,
            "tag": tag, "commit": commit, "canonical_run_id": run_id,
            "canonical_artifact_id": artifact["id"], "release_id": release["id"], "files": files,
            "scope": "Published bytes match canonical CI; no game execution or human playtest performed by this audit"}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        report = audit(args.repository, args.tag, args.expected_commit, args.run_id)
        if args.output:
            # Only a public metadata report, never downloaded binaries or CLI logs.
            args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except (ValueError, KeyError, TypeError, OSError, RuntimeError, zipfile.BadZipFile):
        print("RELEASE_DOWNLOAD_AUDIT_FAILED: metadata, downloads or provenance did not validate", file=sys.stderr)
        return 1
    print("RELEASE_DOWNLOAD_AUDIT_OK", report["tag"], report["commit"], "4/4 identical published files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
