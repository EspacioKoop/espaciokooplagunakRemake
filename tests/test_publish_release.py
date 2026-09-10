"""Publication boundary tests; ZIP fixtures are deliberately synthetic."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import publish_release as release


class PublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.names = [release.package_name("linux"), release.package_name("windows"), "espaciokoop-lagunak-foundry.zip"]
        for name in self.names:
            with zipfile.ZipFile(self.root / name, "w") as archive:
                archive.writestr("LICENSE", "synthetic test fixture")
        self.manifest()
        self.run = dict(conclusion="success", status="completed", head_sha="a" * 40,
                        head_branch="main", event="push", path=".github/workflows/release.yml",
                        head_repository={"full_name": "owner/repo"})

    def manifest(self):
        (self.root / "SHA256SUMS").write_text("".join(
            f"{hashlib.sha256((self.root / name).read_bytes()).hexdigest()}  {name}\n" for name in self.names))

    def test_complete_checksums(self):
        self.assertEqual(len(release.verified_assets(self.root)), 4)

    def test_corrupt_missing_duplicate_and_unsafe_entries(self):
        original = (self.root / "SHA256SUMS").read_text()
        for bad in (original.replace(original[:64], "0" * 64, 1), original + original.splitlines()[0] + "\n",
                    original.replace(self.names[0], "../escape"), "\n".join(original.splitlines()[1:])):
            with self.subTest(bad=bad):
                (self.root / "SHA256SUMS").write_text(bad)
                with self.assertRaises(ValueError):
                    release.verified_assets(self.root)

    def test_release_metadata_matches_exports(self):
        root = Path(__file__).resolve().parents[1]
        self.assertIn(f'config/version="{release.VERSION}"', (root / "game/project.godot").read_text())
        self.assertIn(f'application/product_version="{release.VERSION}.0"', (root / "game/export_presets.cfg").read_text())

    def test_reject_failed_foreign_or_different_source_before_writes(self):
        for key, value in (("conclusion", "failure"), ("status", "in_progress"), ("head_sha", "b" * 40),
                           ("head_branch", "branch"), ("event", "pull_request"), ("path", "other.yml"),
                           ("head_repository", {"full_name": "foreign/repo"})):
            with self.subTest(key=key), patch.object(release, "gh", return_value=json.dumps(self.run | {key: value})) as cli:
                with self.assertRaises(ValueError):
                    release.publish(self.root, "owner/repo", "a" * 40, 1)
                self.assertEqual(cli.call_count, 1)

    def test_upload_failure_never_publishes_draft(self):
        missing = subprocess.CalledProcessError(1, "gh", stderr="HTTP 404")
        failed = subprocess.CalledProcessError(1, "gh", stderr="upload failed")
        with patch.object(release, "gh", side_effect=[json.dumps(self.run), missing, missing, failed]) as cli:
            with self.assertRaises(subprocess.CalledProcessError):
                release.publish(self.root, "owner/repo", "a" * 40, 1)
            self.assertFalse(any(call.args[:2] == ("release", "edit") for call in cli.call_args_list))

    def test_publish_only_after_successful_upload(self):
        missing = subprocess.CalledProcessError(1, "gh", stderr="HTTP 404")
        with patch.object(release, "gh", side_effect=[json.dumps(self.run), missing, missing, "created", "published"]) as cli:
            release.publish(self.root, "owner/repo", "a" * 40, 1)
            self.assertEqual(cli.call_args_list[-2].args[:2], ("release", "create"))
            self.assertIn("--draft", cli.call_args_list[-2].args)
            self.assertEqual(cli.call_args_list[-1].args[:2], ("release", "edit"))

    def test_existing_published_release_is_immutable(self):
        with patch.object(release, "gh", side_effect=[json.dumps(self.run), json.dumps({"draft": False, "html_url": "fixture"})]) as cli:
            release.publish(self.root, "owner/repo", "a" * 40, 1)
            self.assertEqual(cli.call_count, 2)


if __name__ == "__main__":
    unittest.main()
