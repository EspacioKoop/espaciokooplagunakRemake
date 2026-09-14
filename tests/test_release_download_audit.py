"""Synthetic offline regressions for the read-only published-download audit."""
from copy import deepcopy
import contextlib
import io
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import release_download_audit as audit

REPO = "EspacioKoop/espaciokooplagunakRemake"
SHA = "a" * 40
RUN = 42
TAG = "v" + audit.VERSION


def packages(directory, marker=b"first", module_version=None, magic=b"\x7fELF"):
    for target, filename, header in (("linux", "EspaciokoopLagunak.x86_64", magic),
                                     ("windows", "EspaciokoopLagunak.exe", b"MZ")):
        with zipfile.ZipFile(directory / audit.package_name(target), "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(filename, header + marker + b"x" * 1_000_001)
            for name in ("LICENSE", "CREDITS.md", "LEEME.md"):
                archive.writestr(name, "Synthetic fixture, not a game")
    with zipfile.ZipFile(directory / "espaciokoop-lagunak-foundry.zip", "w") as archive:
        archive.writestr("LICENSE", "Synthetic")
        manifest = audit.FOUNDRY_MANIFEST.read_bytes()
        if module_version is not None:
            module = json.loads(manifest)
            module["version"] = module_version
            manifest = json.dumps(module).encode()
        archive.writestr("module.json", manifest)
    checksums(directory)


def checksums(directory):
    text = "".join(audit.digest_file(directory / name) + "  " + name + "\n"
                   for name in sorted(audit.expected_names() - {"SHA256SUMS"}))
    (directory / "SHA256SUMS").write_text(text)


def metadata(directory):
    release = {"id": 10, "tag_name": TAG, "draft": False, "published_at": "2026-09-11T00:00:00Z", "assets": []}
    for number, name in enumerate(sorted(audit.expected_names()), 1):
        path = directory / name
        release["assets"].append({"id": number, "name": name, "state": "uploaded", "size": path.stat().st_size,
                                  "digest": "sha256:" + audit.digest_file(path)})
    ref = {"object": {"type": "commit", "sha": SHA}}
    run = {"id": RUN, "head_sha": SHA, "head_branch": "main", "event": "push", "status": "completed",
           "conclusion": "success", "path": ".github/workflows/release.yml", "run_attempt": 1,
           "head_repository": {"full_name": REPO}}
    jobs = [{"name": name, "head_sha": SHA, "run_id": RUN, "status": "completed", "conclusion": "success"}
            for name in ("build", "windows-smoke")]
    artifact = {"id": 25, "name": "standalone-downloads", "expired": False, "digest": "sha256:" + "b" * 64,
                "size_in_bytes": 1234, "workflow_run": {"id": RUN, "head_sha": SHA}}
    return release, ref, run, jobs, artifact


class FixtureReader:
    def __init__(self, published, canonical):
        self.published, self.canonical = published, canonical
        self.release, self.ref, self.run, self.jobs, self.artifact = metadata(published)
        self.downloaded = False
        self.change = None
        self.commands = []

    def get(self, endpoint):
        self.commands.append(endpoint)
        if "/releases/tags/" in endpoint:
            result = deepcopy(self.release)
            if self.downloaded and self.change == "release":
                result["assets"][0]["id"] += 1
            return result
        if "/git/ref/tags/" in endpoint:
            result = deepcopy(self.ref)
            if self.downloaded and self.change == "tag":
                result["object"]["sha"] = "c" * 40
            return result
        result = deepcopy(self.run)
        if self.downloaded and self.change == "run":
            result["run_attempt"] += 1
        return result

    def pages(self, endpoint, key):
        if key == "jobs":
            return deepcopy(self.jobs)
        result = deepcopy(self.artifact)
        if self.downloaded and self.change == "artifact":
            result["id"] += 1
        return [result]

    def release_download(self, repository, tag, directory):
        shutil.copytree(self.published, directory, dirs_exist_ok=True)

    def artifact_download(self, repository, run_id, directory):
        shutil.copytree(self.canonical, directory, dirs_exist_ok=True)
        self.downloaded = True


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.published, self.canonical = self.root / "published", self.root / "canonical"
        self.published.mkdir()
        packages(self.published)
        shutil.copytree(self.published, self.canonical)
        self.release, self.ref, self.run, self.jobs, self.artifact = metadata(self.published)

    def validate(self):
        return audit.validate_metadata(self.release, self.ref, self.run, self.jobs, REPO, TAG, SHA, RUN)

    def compare(self):
        return audit.compare_downloads(self.published, self.canonical, self.validate())

    def test_complete_offline_audit(self):
        report = audit.audit(REPO, TAG, SHA, RUN, FixtureReader(self.published, self.canonical))
        self.assertEqual(set(report["files"]), audit.expected_names())
        self.assertEqual(report["canonical_artifact_id"], 25)
        self.assertNotIn(str(self.root), json.dumps(report))
        self.assertEqual(report["commit"], SHA)

    def test_request_rejects_urls_options_and_path_traversal(self):
        for value in ("https://github.com/a/b", "--repo/x", "../x", "a/b/c", "a/--foo", "a/b?x=y"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                audit.validate_request(value, TAG, SHA, RUN)

    def test_request_rejects_wrong_checkout_version(self):
        with self.assertRaises(ValueError):
            audit.validate_request(REPO, "v99.0.0", SHA, RUN)

    def test_request_rejects_incomplete_commit_and_boolean_run(self):
        with self.assertRaises(ValueError):
            audit.validate_request(REPO, TAG, "abc", RUN)
        with self.assertRaises(ValueError):
            audit.validate_request(REPO, TAG, SHA, True)

    def test_draft_is_not_a_release(self):
        self.release["draft"] = True
        with self.assertRaises(ValueError): self.validate()

    def test_tag_must_match_approved_commit(self):
        self.ref["object"]["sha"] = "b" * 40
        with self.assertRaises(ValueError): self.validate()

    def test_wrong_workflow_branch_and_event_are_rejected(self):
        for field, value in (("path", "another.yml"), ("head_branch", "feature"), ("event", "pull_request"),
                             ("head_sha", "c" * 40), ("conclusion", "failure"), ("status", "in_progress")):
            before = deepcopy(self.run)
            self.run[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): self.validate()
            self.run = before

    def test_foreign_run_repository_is_rejected(self):
        self.run["head_repository"]["full_name"] = "other/repo"
        with self.assertRaises(ValueError): self.validate()

    def test_windows_job_cannot_be_skipped_or_missing(self):
        self.jobs[1]["conclusion"] = "skipped"
        with self.assertRaises(ValueError): self.validate()
        self.jobs.pop()
        with self.assertRaises(ValueError): self.validate()

    def test_duplicated_job_is_rejected(self):
        self.jobs.append(deepcopy(self.jobs[0]))
        with self.assertRaises(ValueError): self.validate()

    def test_duplicated_missing_and_unexpected_assets_are_rejected(self):
        before = deepcopy(self.release)
        for replacement in (self.release["assets"][:-1], self.release["assets"] + [self.release["assets"][0]],
                            [self.release["assets"][0]] * 4):
            self.release["assets"] = replacement
            with self.assertRaises(ValueError): self.validate()
        self.release = before
        self.release["assets"][0]["name"] = "../private"
        with self.assertRaises(ValueError): self.validate()

    def test_missing_server_digest_is_rejected(self):
        self.release["assets"][0]["digest"] = None
        with self.assertRaises(ValueError): self.validate()

    def test_oversized_asset_is_rejected(self):
        self.release["assets"][0]["size"] = audit.MAX_ASSET_BYTES + 1
        with self.assertRaises(ValueError): self.validate()

    def test_expired_and_ambiguous_ci_artifacts_are_rejected(self):
        with self.assertRaises(ValueError): audit.validate_artifacts([self.artifact, self.artifact], SHA, RUN)
        self.artifact["expired"] = True
        with self.assertRaises(ValueError): audit.validate_artifacts([self.artifact], SHA, RUN)

    def test_wrong_ci_artifact_commit_is_rejected(self):
        self.artifact["workflow_run"]["head_sha"] = "f" * 40
        with self.assertRaises(ValueError): audit.validate_artifacts([self.artifact], SHA, RUN)

    def test_corrupt_zip_is_rejected(self):
        (self.published / audit.package_name("linux")).write_bytes(b"not a zip")
        with self.assertRaises((ValueError, zipfile.BadZipFile)): self.compare()

    def test_rehashed_replacement_is_not_the_ci_package(self):
        packages(self.published, marker=b"tampered but internally checksummed")
        self.release = metadata(self.published)[0]
        with self.assertRaisesRegex(ValueError, "differ from canonical"): self.compare()

    def test_stale_checksum_is_rejected(self):
        (self.published / "SHA256SUMS").write_text("0" * 64 + "  " + audit.package_name("linux") + "\n")
        with self.assertRaises(ValueError): self.compare()

    def test_server_digest_mismatch_is_rejected(self):
        self.release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "GitHub digest mismatch"): self.compare()

    def test_wrong_embedded_manifest_version_is_rejected(self):
        packages(self.published, module_version="0.0.0")
        shutil.copytree(self.published, self.canonical, dirs_exist_ok=True)
        self.release = metadata(self.published)[0]
        with self.assertRaisesRegex(ValueError, "identity/version"): self.compare()

    def test_invalid_binary_even_with_matching_ci_bytes_is_rejected(self):
        packages(self.published, magic=b"NOPE")
        shutil.copytree(self.published, self.canonical, dirs_exist_ok=True)
        self.release = metadata(self.published)[0]
        with self.assertRaisesRegex(ValueError, "executable header"): self.compare()

    def test_unchanged_optional_adapter_does_not_need_game_version_bump(self):
        self.assertEqual(audit.VERSION, "0.9.3")
        self.assertEqual(json.loads(audit.FOUNDRY_MANIFEST.read_bytes())["version"], "0.9.2")
        self.assertEqual(set(self.compare()), audit.expected_names())

    def test_same_version_with_other_manifest_drift_is_rejected(self):
        module = json.loads(audit.FOUNDRY_MANIFEST.read_bytes())
        module["download"] = "https://example.invalid/unexpected-module.zip"
        with zipfile.ZipFile(self.published / "espaciokoop-lagunak-foundry.zip", "w") as archive:
            archive.writestr("LICENSE", "Synthetic")
            archive.writestr("module.json", json.dumps(module))
        checksums(self.published)
        shutil.copytree(self.published, self.canonical, dirs_exist_ok=True)
        self.release = metadata(self.published)[0]
        with self.assertRaisesRegex(ValueError, "differs from versioned source"): self.compare()

    def test_symlink_download_is_rejected(self):
        path = self.published / "SHA256SUMS"
        path.unlink()
        path.symlink_to(self.canonical / "SHA256SUMS")
        with self.assertRaisesRegex(ValueError, "symbolic link"): self.compare()

    def test_zip_symbolic_link_is_rejected(self):
        with zipfile.ZipFile(self.published / audit.package_name("linux"), "a") as archive:
            link = zipfile.ZipInfo("link")
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, "LICENSE")
        with self.assertRaisesRegex(ValueError, "symbolic links"): self.compare()

    def test_zip_entry_and_expansion_bounds(self):
        with patch.object(audit, "MAX_ZIP_ENTRIES", 1), self.assertRaisesRegex(ValueError, "limits"):
            audit.preflight_directory(self.published)
        with patch.object(audit, "MAX_ZIP_EXPANDED_BYTES", 100), self.assertRaisesRegex(ValueError, "limits"):
            audit.preflight_directory(self.published)

    def test_replacement_during_download_is_rejected(self):
        for change in ("release", "tag", "run", "artifact"):
            reader = FixtureReader(self.published, self.canonical)
            reader.change = change
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, "changed during audit"):
                audit.audit(REPO, TAG, SHA, RUN, reader)

    def test_cli_failure_does_not_write_success_report_or_leak_details(self):
        output = self.root / "report.json"
        error = io.StringIO()
        with patch.object(audit, "audit", side_effect=RuntimeError("private CLI detail")), contextlib.redirect_stderr(error):
            code = audit.main(["--repository", REPO, "--tag", TAG, "--expected-commit", SHA,
                               "--run-id", str(RUN), "--output", str(output)])
        self.assertEqual(code, 1)
        self.assertFalse(output.exists())
        self.assertNotIn("private CLI detail", error.getvalue())

    def test_cli_invocation_has_no_shell_and_sanitizes_failure(self):
        with patch.object(audit.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "gh", stderr="secret")) as mocked:
            with self.assertRaises(RuntimeError) as error:
                audit.GitHubReads().command("api", "repos/a/b")
            self.assertEqual(mocked.call_args.args[0], ["gh", "api", "repos/a/b"])
            self.assertNotIn("shell", mocked.call_args.kwargs)
            self.assertNotIn("secret", str(error.exception))


if __name__ == "__main__":
    unittest.main()
