#!/usr/bin/env python3
"""Negative result-parser controls, independent from the actual ENet suite."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest

from run_authenticated_aux_rpc import isolated_environment, validate_result


class ResultTests(unittest.TestCase):
    def report(self, name="member"):
        return {"case": name, "checks": {"host": 11, "member": 5, "guest": 7}[name],
                "failures": 0, "axis_updates": 0 if name == "guest" else 8,
                "fleet_updates": 0 if name == "guest" else 9}

    def log(self, value):
        return "Godot test\nAUX_RPC_RESULT " + json.dumps(value) + "\n"

    def test_three_valid_identities(self):
        for name in ("host", "member", "guest"):
            report = self.report(name)
            self.assertEqual(validate_result(name, 0, self.log(report), report), report)

    def test_nonzero_exit(self):
        value = self.report()
        with self.assertRaises(ValueError):
            validate_result("member", 1, self.log(value), value)

    def test_engine_error_first_line_indented_and_ansi(self):
        value = self.report()
        for diagnostic in ("ERROR: broken", "  ERROR: broken", "SCRIPT ERROR: broken",
                           "\x1b[31mERROR:\x1b[0m broken", "Unicode parsing error", "AUX_RPC_FAIL broken"):
            with self.subTest(diagnostic=diagnostic), self.assertRaises(ValueError):
                validate_result("member", 0, diagnostic + "\n" + self.log(value), value)

    def test_missing_malformed_and_ambiguous_stdout(self):
        value = self.report()
        for output in ("Godot started", "AUX_RPC_RESULT {", self.log(value) * 2,
                       self.log(value) + "AUX_RPC_RESULT malformed\n"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                validate_result("member", 0, output, value)

    def test_json_scalar_is_not_a_report(self):
        for value in (None, [], True, 1, "result"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_result("member", 0, self.log(value), value)

    def test_unknown_missing_and_wrong_identity(self):
        for change in ("extra", "missing", "identity"):
            value = self.report()
            if change == "extra": value["unexpected"] = "field"
            elif change == "missing": del value["checks"]
            else: value["case"] = "host"
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_result("member", 0, self.log(value), value)

    def test_boolean_float_string_negative_and_oversize_numbers(self):
        for field in ("checks", "failures", "axis_updates", "fleet_updates"):
            for invalid in (True, False, 1.0, "5", None, -1, 100001):
                value = self.report()
                value[field] = invalid
                with self.subTest(field=field, invalid=invalid), self.assertRaises(ValueError):
                    validate_result("member", 0, self.log(value), value)

    def test_zero_or_incomplete_assertions(self):
        for name in ("host", "member", "guest"):
            for count in (0, self.report(name)["checks"] - 1):
                value = self.report(name)
                value["checks"] = count
                with self.subTest(name=name, count=count), self.assertRaises(ValueError):
                    validate_result(name, 0, self.log(value), value)

    def test_report_failure(self):
        value = self.report()
        value["failures"] = 1
        with self.assertRaises(ValueError):
            validate_result("member", 0, self.log(value), value)

    def test_stdout_and_file_must_match_without_type_coercion(self):
        disk = self.report()
        for new in (True, 10):
            printed = copy.deepcopy(disk)
            printed["axis_updates"] = new
            with self.subTest(new=new), self.assertRaises(ValueError):
                validate_result("member", 0, self.log(printed), disk)

    def test_unauthenticated_leak_rejected_even_when_tests_claim_success(self):
        for field in ("axis_updates", "fleet_updates"):
            value = self.report("guest")
            value[field] = 1
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_result("guest", 0, self.log(value), value)

    def test_missing_authenticated_delivery_rejected(self):
        for field in ("axis_updates", "fleet_updates"):
            value = self.report()
            value[field] = 2
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_result("member", 0, self.log(value), value)

    def test_isolation_creates_all_user_roots_without_mutating_parent_environment(self):
        before = dict(os.environ)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            env = isolated_environment(directory)
            for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
                self.assertTrue(Path(env[key]).is_dir())
                self.assertTrue(Path(env[key]).is_relative_to(directory))
        self.assertEqual(dict(os.environ), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
