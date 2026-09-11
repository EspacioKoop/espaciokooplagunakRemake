"""Offline adversarial tests; fixture data is deliberately synthetic."""
from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
import random
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("parity_evidence", Path(__file__).resolve().parents[1] / "tools/check_parity_evidence.py")
assert SPEC and SPEC.loader
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
SOURCE = "a" * 40
CANDIDATE = "b" * 40
RUN = "https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/runs/123"
REVIEW = "https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32#issuecomment-123"


class RegisterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in ("game/core/example.gd", "tests/test_example.gd", "docs/SHIP_TEMPLATES.md", "tests/test_ship_templates.gd"):
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("# Synthetic fixture only.\n", encoding="utf-8")
        self.data = {"version": 1, "source_repository": P.ORIGINAL, "source_revision": SOURCE,
                     "remake_revision": CANDIDATE, "coverage": {"complete": False, "note": "Fixture parcial."},
                     "catalogs": [], "overrides": {}, "items": [self.row(gate.lower(), gate) for gate in P.GATES]}

    def row(self, key, gate="G1"):
        return {"id": key, "gate": gate, "priority": "P0", "scope": "parity",
                "original": "Capacidad de prueba", "source": "README.md", "equivalent": "Ejemplo nativo",
                "status": "partial", "decision": "reimplement", "owner_issue": 2,
                "acceptance": "Ejecutar prueba reproducible.", "note": "No certificada.",
                "evidence": [{"kind": "implementation", "path": "game/core/example.gd"},
                             {"kind": "test", "path": "tests/test_example.gd"}]}

    def verified(self, row):
        row["status"] = "verified"
        row["evidence"].append({"kind": "run", "url": RUN, "revision": CANDIDATE,
                                "result": "passed", "checks": "Fixture de ejecución, no real."})

    def write(self, path, data):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        return target

    def catalog(self):
        raw = {"format": 1, "reference": SOURCE, "templates": [{"id": "example", "name": "Ejemplo",
               "source": "corvette.lua", "line": 1, "unsupported": ["setTubes"]}],
               "excluded": [{"name": "Otra nave", "file": "OLD.lua", "line": 10, "reasons": ["límite del modelo"]}]}
        self.data["catalogs"] = [{"type": "ship_templates", "path": "game/data/ship_templates.json", "owner_issue": 2}]
        self.write("game/data/ship_templates.json", raw)
        return raw

    def invalid(self, data=None):
        with self.assertRaises(P.Invalid):
            P.collect(self.data if data is None else data, self.root)

    def test_valid_partial_is_not_complete(self):
        rows = P.collect(self.data, self.root)
        self.assertEqual(len(rows), 4)
        self.assertTrue(P.blockers(self.data, rows, CANDIDATE))

    def test_missing_owner_is_invalid(self):
        del self.data["items"][0]["owner_issue"]
        self.invalid()

    def test_boolean_is_not_issue_number(self):
        self.data["items"][0]["owner_issue"] = True
        self.invalid()

    def test_boolean_is_not_version(self):
        self.data["version"] = True
        self.invalid()

    def test_unknown_version(self):
        self.data["version"] = 2
        self.invalid()

    def test_empty_items_and_missing_gate(self):
        self.data["items"] = []
        self.invalid()

    def test_proposal_does_not_supply_missing_gate(self):
        self.data["items"][0]["scope"] = "proposal"
        self.invalid()

    def test_duplicate_ids(self):
        self.data["items"].append(copy.deepcopy(self.data["items"][0]))
        self.invalid()

    def test_no_button_only_completion(self):
        self.data["items"][0]["status"] = "verified"
        self.invalid()

    def test_failed_pending_wrong_commit_runs(self):
        for result, rev in (("failed", CANDIDATE), ("pending", CANDIDATE), ("passed", SOURCE)):
            data = copy.deepcopy(self.data)
            self.verified(data["items"][0])
            data["items"][0]["evidence"][-1].update(result=result, revision=rev)
            self.invalid(data)

    def test_mixed_commit_runs_rejected(self):
        self.verified(self.data["items"][0])
        run = copy.deepcopy(self.data["items"][0]["evidence"][-1])
        run["revision"] = SOURCE
        self.data["items"][0]["evidence"].append(run)
        self.invalid()

    def test_docs_only_not_verification(self):
        self.verified(self.data["items"][0])
        self.data["items"][0]["evidence"][0]["kind"] = "document"
        self.invalid()

    def test_missing_evidence_file(self):
        (self.root / "tests/test_example.gd").unlink()
        self.invalid()

    def test_unsafe_paths(self):
        for path in ("../private", "/etc/passwd", "C:\\private", "docs//x", "docs/./x", "docs/x](https://evil)"):
            data = copy.deepcopy(self.data)
            data["items"][0]["evidence"][0]["path"] = path
            self.invalid(data)

    def test_source_path_escape(self):
        self.data["items"][0]["source"] = "../secret"
        self.invalid()

    def test_source_line_is_positive_integer(self):
        self.data["items"][0]["source_line"] = "1](https://evil)"
        self.invalid()

    def test_symlink_cannot_escape_repository(self):
        with tempfile.TemporaryDirectory() as outside:
            secret = Path(outside) / "secret.gd"
            secret.write_text("private", encoding="utf-8")
            link = self.root / "leak.gd"
            link.symlink_to(secret)
            self.data["items"][0]["evidence"][0]["path"] = "leak.gd"
            self.invalid()

    def test_unapproved_exclusion_is_not_waiver(self):
        self.data["items"][0].update(status="waived", decision="waive")
        self.invalid()

    def test_waiver_requires_consistent_fields(self):
        self.data["items"][0].update(status="partial", decision="waive", approval=REVIEW)
        self.invalid()

    def test_approved_waiver_is_recorded(self):
        self.data["items"][0].update(status="waived", decision="waive", approval=REVIEW)
        self.assertEqual(P.collect(self.data, self.root)[0]["status"], "waived")

    def test_coverage_needs_review(self):
        self.data["coverage"]["complete"] = True
        self.invalid()

    def test_empty_register_cannot_pass_all(self):
        self.data["items"] = []
        self.data["coverage"].update(complete=True, review=REVIEW)
        self.invalid()

    def test_valid_complete_attestations_need_exact_candidate(self):
        for row in self.data["items"]:
            self.verified(row)
        self.data["coverage"].update(complete=True, review=REVIEW)
        rows = P.collect(self.data, self.root)
        self.assertFalse(P.blockers(self.data, rows, CANDIDATE))
        self.assertTrue(P.blockers(self.data, rows, SOURCE))
        self.assertTrue(P.blockers(self.data, rows, None))

    def test_proposals_do_not_block_recorded_parity(self):
        for row in self.data["items"]:
            self.verified(row)
        proposal = self.row("optional")
        proposal["scope"] = "proposal"
        self.data["items"].append(proposal)
        self.data["coverage"].update(complete=True, review=REVIEW)
        self.assertFalse(P.blockers(self.data, P.collect(self.data, self.root), CANDIDATE))

    def test_unsafe_run_urls(self):
        for url in (RUN.replace("https:", "http:"), RUN.replace("github.com", "github.com.evil"), RUN + "]()", RUN + "#x](https://evil)", RUN.replace("EspacioKoop/", "someone/"), RUN + "?token=secret"):
            data = copy.deepcopy(self.data)
            self.verified(data["items"][0])
            data["items"][0]["evidence"][-1]["url"] = url
            self.invalid(data)

    def test_duplicate_json_keys(self):
        path = self.root / "duplicate.json"
        path.write_text('{"version":1,"version":2}', encoding="utf-8")
        with self.assertRaises(P.Invalid):
            P.load_json(path)

    def test_nonfinite_and_invalid_utf8_json(self):
        path = self.root / "invalid.json"
        for payload in (b'{"n":NaN}', b'{"n":Infinity}', b'\xff', b'{broken'):
            path.write_bytes(payload)
            with self.assertRaises(P.Invalid):
                P.load_json(path)

    def test_oversized_json(self):
        path = self.root / "large.json"
        path.write_bytes(b" " * (P.MAX_BYTES + 1))
        with self.assertRaises(P.Invalid):
            P.load_json(path)

    def test_catalog_expands_supported_and_excluded(self):
        self.catalog()
        rows = P.collect(self.data, self.root)
        self.assertEqual(len(rows), 6)
        by_id = {r["id"]: r for r in rows}
        self.assertEqual(by_id["ship:example"]["status"], "partial")
        self.assertEqual(by_id["ship-excluded:old.lua:10"]["status"], "pending")
        self.assertIn("setTubes", by_id["ship:example"]["note"])

    def test_empty_unsupported_still_not_full_parity(self):
        raw = self.catalog()
        raw["templates"][0]["unsupported"] = []
        self.write("game/data/ship_templates.json", raw)
        row = next(r for r in P.collect(self.data, self.root) if r["id"] == "ship:example")
        self.assertEqual(row["status"], "partial")
        self.assertIn("prestaciones comunes", row["note"])

    def test_catalog_mismatched_source_revision(self):
        raw = self.catalog()
        raw["reference"] = CANDIDATE
        self.write("game/data/ship_templates.json", raw)
        self.invalid()

    def test_excluded_needs_reasons(self):
        raw = self.catalog()
        raw["excluded"][0]["reasons"] = []
        self.write("game/data/ship_templates.json", raw)
        self.invalid()

    def test_duplicate_catalog_declarations(self):
        raw = self.catalog()
        raw["excluded"][0].update(file="corvette.lua", line=1)
        self.write("game/data/ship_templates.json", raw)
        self.invalid()

    def test_duplicate_catalog_ids(self):
        raw = self.catalog()
        other = copy.deepcopy(raw["templates"][0])
        other["line"] = 2
        raw["templates"].append(other)
        self.write("game/data/ship_templates.json", raw)
        self.invalid()

    def test_duplicate_catalog_spec(self):
        self.catalog()
        self.data["catalogs"] *= 2
        self.invalid()

    def test_unknown_override(self):
        self.catalog()
        self.data["overrides"] = {"ship:absent": {"status": "verified"}}
        self.invalid()

    def test_override_does_not_change_scope_or_bypass_evidence(self):
        self.catalog()
        for patch in ({"scope": "proposal"}, {"status": "verified"}):
            self.data["overrides"] = {"ship:example": patch}
            self.invalid()

    def test_deterministic_and_escaped_markdown(self):
        self.data["items"][0]["original"] = '<img src=x> | [bad](https://evil) `'
        rows = P.collect(self.data, self.root)
        report = P.markdown(self.data, rows, CANDIDATE)
        self.assertEqual(report, P.markdown(self.data, list(rows), CANDIDATE))
        self.assertNotIn("<img", report)
        self.assertNotIn("[bad]", report)
        self.assertIn("BLOQUEADO", report)

    def test_fuzz_invalid_required_fields(self):
        rng = random.Random(32)
        bad = [None, True, [], {}, 0, -1, "", "\n"]
        fields = ["id", "gate", "priority", "scope", "status", "decision", "owner_issue", "acceptance"]
        for _ in range(300):
            data = copy.deepcopy(self.data)
            data["items"][0][rng.choice(fields)] = rng.choice(bad)
            self.invalid(data)

    def test_cli_exit_codes_and_local_output(self):
        self.write("docs/parity/issue32_inventory.json", self.data)
        output = self.root / "report.md"
        base = ["--root", str(self.root), "--markdown", str(output)]
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(P.main(base), 0)
            self.assertEqual(P.main(base + ["--require-complete", "--candidate", CANDIDATE]), 2)
            self.assertEqual(P.main(base + ["--candidate", "main"]), 1)
            self.assertEqual(P.main(["--root", str(self.root), "--inventory", "../secret"]), 1)
        self.assertIn("Original → remake", output.read_text(encoding="utf-8"))


    def test_real_inventory_reconciles_merged_npc_workbench(self):
        inventory_path = Path(__file__).resolve().parents[1] / "docs/parity/issue32_inventory.json"
        data = P.load_json(inventory_path)
        by_id = {row["id"]: row for row in data["items"]}
        self.assertEqual(data["remake_revision"], "f2015279bb7a8c307352a9526d1942a9df047ac4")
        self.assertEqual(by_id["npc-generator"]["status"], "partial")
        self.assertEqual(by_id["npc-generator"]["decision"], "replace")
        self.assertTrue(any("pull/50" in evidence.get("url", "")
                            for evidence in by_id["npc-generator"]["evidence"]))
        self.assertEqual(by_id["npc-scene-placement"]["status"], "pending")
        self.assertEqual(by_id["npc-dialogue-agenda"]["status"], "pending")
        self.assertEqual(by_id["npc-memory-combat"]["status"], "pending")
        self.assertFalse(data["coverage"]["complete"])


if __name__ == "__main__":
    unittest.main()
