"""Regression tests for the bounded scenario corpus verifier."""
from __future__ import annotations

import copy
import importlib.util
import io
import json
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("scenario_corpus_checker", ROOT / "tools/check_scenario_corpus.py")
assert SPEC and SPEC.loader
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class ScenarioCorpusTests(unittest.TestCase):
    def test_real_corpus_matches_local_campaign(self) -> None:
        self.assertEqual(CHECKER.validate(ROOT), (38, 6))
        corpus = CHECKER.load_json(ROOT / CHECKER.CORPUS)
        self.assertFalse(corpus["coverage"]["complete"])
        statuses = [record["remake"]["status"] for record in corpus["records"]]
        self.assertEqual(statuses.count("candidate_only"), 1)
        self.assertEqual(statuses.count("unmapped_in_current_catalog"), 37)

    def make_fixture(self) -> Path:
        temp = Path(tempfile.mkdtemp(prefix="scenario-corpus-test-"))
        self.addCleanup(shutil.rmtree, temp)
        for relative in (CHECKER.CORPUS, CHECKER.CAMPAIGN):
            target = temp / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        return temp

    def read_corpus(self, root: Path) -> dict:
        return json.loads((root / CHECKER.CORPUS).read_text(encoding="utf-8"))

    def write_corpus(self, root: Path, corpus: dict) -> None:
        (root / CHECKER.CORPUS).write_text(json.dumps(corpus, ensure_ascii=False), encoding="utf-8")

    def test_duplicate_record_is_rejected(self) -> None:
        root = self.make_fixture()
        corpus = self.read_corpus(root)
        corpus["records"].append(copy.deepcopy(corpus["records"][0]))
        self.write_corpus(root, corpus)
        with self.assertRaises(CHECKER.Invalid):
            CHECKER.validate(root)

    def test_complete_flag_cannot_be_promoted(self) -> None:
        root = self.make_fixture()
        corpus = self.read_corpus(root)
        corpus["coverage"]["complete"] = True
        self.write_corpus(root, corpus)
        with self.assertRaises(CHECKER.Invalid):
            CHECKER.validate(root)

    def test_catalog_drift_is_rejected(self) -> None:
        root = self.make_fixture()
        campaign = CHECKER.load_json(root / CHECKER.CAMPAIGN)
        campaign["missions"][0]["id"] = "invented"
        (root / CHECKER.CAMPAIGN).write_text(json.dumps(campaign), encoding="utf-8")
        with self.assertRaises(CHECKER.Invalid):
            CHECKER.validate(root)

    def test_cli_keeps_bounded_corpus_non_exhaustive(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            self.assertEqual(CHECKER.main(["--root", str(ROOT)]), 0)
            self.assertEqual(CHECKER.main(["--root", str(ROOT), "--require-complete"]), 2)
        self.assertIn("38 escenarios", stdout.getvalue())
        self.assertIn("coverage.complete=false", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
