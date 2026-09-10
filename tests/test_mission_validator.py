"""Transport/orchestration regressions. Real Godot tests run separately in CI."""
from __future__ import annotations

from contextlib import redirect_stdout, redirect_stderr
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import validate_mission as validator


class MissionValidatorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "game").mkdir()
        (self.root / "game/project.godot").write_text("config_version=5\n", encoding="utf-8")
        self.path = self.root / "mission.json"
        self.example = json.loads((ROOT / "examples/missions/first-contact.json").read_text(encoding="utf-8"))
        self.path.write_text(json.dumps(self.example, ensure_ascii=False), encoding="utf-8")

    def raw(self, text):
        self.path.write_bytes(text if isinstance(text, bytes) else text.encode("utf-8"))
        return validator.read_document(self.path)

    def invoke(self, payload=None, code=0, stdout="", stderr="", missing=False):
        if payload is None:
            payload = {"format": validator.FORMAT, "version": 1, "valid": True, "error": ""}
        def run(command, **kwargs):
            self.assertNotIn("shell", kwargs)
            self.assertEqual(command[-3], "--test")
            self.assertEqual(json.loads(Path(command[-2]).read_text(encoding="utf-8")), self.example)
            self.assertNotEqual(kwargs["env"]["HOME"], os.environ.get("HOME"))
            self.assertEqual(kwargs["timeout"], 30)
            if not missing:
                Path(command[-1]).write_text(json.dumps(payload), encoding="utf-8")
            self.staged = Path(command[-2])
            return subprocess.CompletedProcess(command, code, stdout, stderr)
        with patch.object(validator.shutil, "which", return_value=sys.executable), patch.object(validator.subprocess, "run", side_effect=run):
            return validator.validate_one(self.path, "godot", root=self.root)

    def test_utf8_round_trip_does_not_change_source(self):
        before = self.path.read_bytes()
        self.assertEqual(validator.read_document(self.path), self.example)
        self.assertEqual(self.path.read_bytes(), before)

    def test_duplicate_top_level_key(self):
        with self.assertRaises(validator.InvalidDocument): self.raw('{"id":"a","id":"b"}')

    def test_duplicate_nested_key(self):
        with self.assertRaises(validator.InvalidDocument): self.raw('{"contact":{"kind":1,"kind":2}}')

    def test_nonfinite_numbers(self):
        for token in ("NaN", "Infinity", "-Infinity", "1e999", "-1e999"):
            with self.subTest(token=token), self.assertRaises(validator.InvalidDocument): self.raw('{"n":' + token + '}')

    def test_inexact_integer_rejected(self):
        with self.assertRaises(validator.InvalidDocument): self.raw('{"n":9007199254740992}')

    def test_exact_integer_boundary(self):
        self.assertEqual(self.raw('{"n":9007199254740991}')["n"], 2**53 - 1)

    def test_invalid_utf8(self):
        with self.assertRaises(validator.InvalidDocument): self.raw(b'{"text":"\xff"}')

    def test_bom_is_rejected(self):
        with self.assertRaises(validator.InvalidDocument): self.raw(b'\xef\xbb\xbf{}')

    def test_incomplete_unicode_in_keys_and_values(self):
        for document in ('{"text":"\\ud800"}', '{"\\udfff":"x"}'):
            with self.subTest(document=document), self.assertRaises(validator.InvalidDocument): self.raw(document)

    def test_nonstandard_json(self):
        for document in ('{"n":1,}', '// comment\n{}', '{} {}', '', '{"n":01}'):
            with self.subTest(document=document), self.assertRaises(validator.InvalidDocument): self.raw(document)

    def test_size_limit(self):
        with self.assertRaises(validator.InvalidDocument): self.raw(b' ' * (validator.MAX_BYTES + 1))

    def test_depth_limit(self):
        with self.assertRaises(validator.InvalidDocument): self.raw('[' * 34 + '0' + ']' * 34)

    def test_recursive_json_is_controlled(self):
        with self.assertRaises(validator.InvalidDocument): self.raw('[' * 2000 + '0' + ']' * 2000)

    def test_root_type_is_left_to_catalog(self):
        self.assertEqual(self.raw('[true, null, 1]'), [True, None, 1])

    def test_external_ref_remains_plain_data(self):
        self.assertEqual(self.raw('{"$ref":"https://invalid.example/never-fetch"}')["$ref"], "https://invalid.example/never-fetch")

    def test_missing_file_is_environment_error(self):
        self.assertEqual(validator.validate_one(self.root / "absent.json", "missing").status, "error")

    def test_directory_is_environment_error(self):
        self.assertEqual(validator.validate_one(self.root, "missing").status, "error")

    @unittest.skipUnless(hasattr(os, "mkfifo"), "POSIX FIFO")
    def test_fifo_is_rejected_without_blocking(self):
        fifo = self.root / "pipe"
        os.mkfifo(fifo)
        self.assertEqual(validator.validate_one(fifo, "missing").status, "error")

    def test_bad_json_never_launches_engine(self):
        self.path.write_text('{"private":"SENTINEL",}', encoding="utf-8")
        with patch.object(validator.subprocess, "run") as run:
            result = validator.validate_one(self.path, "missing")
            self.assertEqual(result.status, "invalid")
            self.assertNotIn("SENTINEL", result.message)
            run.assert_not_called()

    def test_missing_engine_is_not_success(self):
        with patch.object(validator.shutil, "which", return_value=None):
            self.assertEqual(validator.validate_one(self.path, "missing", root=self.root).status, "error")

    def test_success_and_private_temporary_cleanup(self):
        before = self.path.read_bytes()
        self.assertEqual(self.invoke().status, "valid")
        self.assertFalse(self.staged.exists())
        self.assertEqual(self.path.read_bytes(), before)

    def test_catalog_rejection(self):
        result = self.invoke({"format": validator.FORMAT, "version": 1, "valid": False, "error": "Objetivo incompatible."}, code=1)
        self.assertEqual(result.status, "invalid")

    def test_return_code_mismatch(self):
        self.assertEqual(self.invoke(code=1).status, "error")

    def test_engine_error_overrides_success(self):
        for text in ("SCRIPT ERROR: test", "ERROR: test", "  FATAL ERROR: test"):
            with self.subTest(text=text): self.assertEqual(self.invoke(stdout=text).status, "error")
        self.assertEqual(self.invoke(stderr="SCRIPT ERROR: test").status, "error")

    def test_missing_report_is_not_success(self):
        self.assertEqual(self.invoke(missing=True).status, "error")

    def test_report_contract(self):
        good = {"format": validator.FORMAT, "version": 1, "valid": True, "error": ""}
        for key, value in (("format", "other"), ("version", True), ("version", 2), ("valid", 1), ("error", []), ("error", "inconsistent")):
            with self.subTest(key=key, value=value):
                bad = dict(good, **{key: value})
                self.assertEqual(self.invoke(bad).status, "error")
        self.assertEqual(self.invoke([]).status, "error")

    def test_report_size_limit(self):
        self.assertEqual(self.invoke({"padding": "x" * 9000}).status, "error")

    def test_timeout_is_not_success(self):
        with patch.object(validator.shutil, "which", return_value=sys.executable), patch.object(validator.subprocess, "run", side_effect=subprocess.TimeoutExpired("godot", 30)):
            self.assertEqual(validator.validate_one(self.path, "godot", root=self.root).status, "error")

    def test_cli_exit_codes_and_json(self):
        for status, expected in (("valid", 0), ("invalid", 1), ("error", 2)):
            with self.subTest(status=status), patch.object(validator, "validate_one", return_value=validator.Result("file", status, "")):
                output = io.StringIO()
                with redirect_stdout(output): self.assertEqual(validator.main(["file", "--json"]), expected)
                self.assertEqual(json.loads(output.getvalue())["results"][0]["status"], status)

    def test_cli_error_takes_precedence(self):
        results = [validator.Result("a", "invalid", "x"), validator.Result("b", "error", "y")]
        with patch.object(validator, "validate_one", side_effect=results), redirect_stdout(io.StringIO()):
            self.assertEqual(validator.main(["a", "b"]), 2)

    def test_cli_escapes_terminal_controls(self):
        result = validator.Result("evil\n\x1b[31m", "invalid", "text\n\x1b")
        with patch.object(validator, "validate_one", return_value=result):
            output = io.StringIO()
            with redirect_stdout(output): validator.main(["file"])
            self.assertEqual(len(output.getvalue().splitlines()), 1)
            self.assertNotIn("\x1b", output.getvalue())

    def test_cli_limits(self):
        for args in (["file", "--timeout", "nan"], ["file", "--timeout", "0"], ["file", "--timeout", "301"], ["file", "--timeout", "text"], ["file"] * 33):
            with self.subTest(args=args), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                validator.main(args)
            self.assertEqual(error.exception.code, 2)


class MissionSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads((ROOT / "schemas/mission-v1.schema.json").read_text(encoding="utf-8"))
        cls.example = json.loads((ROOT / "examples/missions/first-contact.json").read_text(encoding="utf-8"))
        cls.validator = Draft202012Validator(cls.schema)

    def test_meta_schema(self):
        Draft202012Validator.check_schema(self.schema)

    def test_example_and_local_schema_link(self):
        self.validator.validate(self.example)
        link = ROOT / "examples/missions" / self.example["$schema"]
        self.assertEqual(link.resolve(), (ROOT / "schemas/mission-v1.schema.json").resolve())

    def test_required_fields(self):
        for key in self.schema["required"]:
            value = copy.deepcopy(self.example)
            del value[key]
            with self.subTest(key=key): self.assertFalse(self.validator.is_valid(value))

    def test_shape_and_bounds(self):
        mutations = [lambda m: m.update(reward=-1), lambda m: m.update(id="space id"),
                     lambda m: m.update(objectives=[]), lambda m: m["contacts"][0].update(position=[12001, 0]),
                     lambda m: m["contacts"][0].update(known="true"),
                     lambda m: m["objectives"][0].update(type="execute_script")]
        for change in mutations:
            value = copy.deepcopy(self.example)
            change(value)
            self.assertFalse(self.validator.is_valid(value))

    def test_schema_does_not_claim_semantic_authority(self):
        value = copy.deepcopy(self.example)
        value["objectives"][0]["target"] = "missing"
        self.assertTrue(self.validator.is_valid(value))  # Catalog must reject it in Godot.

    def test_extensions_do_not_become_executable(self):
        value = dict(self.example, notes={"author": "Example"})
        self.validator.validate(value)


if __name__ == "__main__":
    unittest.main()
