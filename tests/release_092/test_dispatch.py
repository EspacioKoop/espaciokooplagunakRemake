"""Exercise the embedded dispatch guard with a real engine and synthetic profiles."""
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest
import run as runner


class DispatchTests(unittest.TestCase):
    def launch(self, arguments):
        with tempfile.TemporaryDirectory(prefix="lagunak-dispatch-") as temp:
            root = Path(temp)
            command = [str(runner.ROOT / ".toolchain/godot"), "--headless", "--path", str(runner.ROOT / "game"), "--quit-after", "6", "--", *arguments]
            result = subprocess.run(command, env=runner.isolated_environment(root), cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=25)
            return result.returncode, result.stdout

    def test_inactive_without_explicit_phase(self):
        code, text = self.launch(["--test"])
        self.assertEqual(code, 0, text)
        self.assertNotIn("EMBEDDED_ACCEPTANCE", text)
        self.assertNotIn("EXPORT_CONTRACT_RESULT", text)
        self.assertIsNone(runner.ERROR.search(text), text)

    def test_unknown_duplicate_or_non_test_requests_rejected(self):
        cases = [["--test", "--release-acceptance=../foreign"], ["--release-acceptance=contract"],
                 ["--test", "--release-acceptance=contract", "--release-acceptance=leisure"]]
        for args in cases:
            with self.subTest(args=args):
                code, text = self.launch(args)
                self.assertEqual(code, 2, text)
                self.assertIn("RELEASE_ACCEPTANCE_INVALID", text)
                self.assertNotIn("EMBEDDED_ACCEPTANCE phase=", text)

    def test_same_scene_tree_runs_closed_fixture_and_rejects_wrong_runtime(self):
        checksum = runner.digest(runner.ROOT / runner.prepare.MANIFEST)
        code, text = self.launch(["--test", "--release-acceptance=contract", "--expected-version=" + runner.VERSION, "--expected-fixtures=" + checksum])
        # Deliberate negative control: editor+headless is NOT the release acceptance.
        self.assertEqual(code, 1, text)
        self.assertIn("EMBEDDED_ACCEPTANCE phase=contract", text)
        self.assertIn("EXPORT_CONTRACT_RESULT checks=16 failures=2", text)
        self.assertIn("actual exported application, not editor", text)
        self.assertIn("real display available", text)
        self.assertNotIn("embedded fixtures match", text)


if __name__ == "__main__": unittest.main(verbosity=2)
