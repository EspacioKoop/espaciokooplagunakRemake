"""Package the actual module without Godot exports; never substitute runtime files."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from package_downloads import package_exports


class FoundryWorkspacePackageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        module = self.root / "integrations/foundry"
        module.mkdir(parents=True)
        self.module = module
        # Use real source bytes. Extra local files must not be swept into the ZIP.
        for path in (ROOT / "integrations/foundry").iterdir():
            if path.is_file():
                shutil.copyfile(path, module / path.name)
        shutil.copyfile(ROOT / "LICENSE", self.root / "LICENSE")
        (module / "local-token.txt").write_text("SYNTHETIC_NOT_FOR_DISTRIBUTION", encoding="utf-8")

    def test_package_contains_runtime_imports_exactly_and_valid_checksum(self):
        before = {p.name: p.read_bytes() for p in self.module.iterdir()}
        lines = package_exports(self.root, [])
        self.assertEqual(len(lines), 1)
        digest, name = lines[0].strip().split("  ")
        archive_path = self.root / "dist" / name
        self.assertEqual(hashlib.sha256(archive_path.read_bytes()).hexdigest(), digest)
        self.assertEqual((self.root / "dist/SHA256SUMS").read_text(), "".join(lines))
        with zipfile.ZipFile(archive_path) as archive:
            members = set(archive.namelist())
            self.assertEqual(members, {"module.json", "main.mjs", "client.mjs", "workspace.mjs", "style.css", "README.md", "LICENSE"})
            manifest = json.loads(archive.read("module.json"))
            for entry in manifest["esmodules"] + manifest["styles"]:
                self.assertIn(entry, members)
            for script in ("main.mjs", "client.mjs", "workspace.mjs"):
                self.assertEqual(archive.read(script), (self.module / script).read_bytes())
                for dependency in re.findall(r'from\s+["\'](\./[^"\']+)["\']', archive.read(script).decode("utf-8")):
                    self.assertIn(str(PurePosixPath(script).parent / dependency), members)
            self.assertEqual(archive.read("LICENSE"), (ROOT / "LICENSE").read_bytes())
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.module.iterdir()})

    def test_missing_workspace_fails_without_replacing_previous_outputs(self):
        package_exports(self.root, [])
        before = {p.name: p.read_bytes() for p in (self.root / "dist").iterdir()}
        (self.module / "workspace.mjs").unlink()
        with self.assertRaises(FileNotFoundError):
            package_exports(self.root, [])
        self.assertEqual(before, {p.name: p.read_bytes() for p in (self.root / "dist").iterdir()})


if __name__ == "__main__":
    unittest.main(verbosity=2)
