"""Regresiones con datos ficticios; ninguna prueba necesita gh, red o credenciales."""
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

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import platino as p


def config():
    return {"schema_version": 1, "repository": "equipo/demo", "milestones": [
        {"title": "v1.0.0", "description": "Entrega comprobable.", "issues": [10]}]}


def milestone(managed=True, **changes):
    result = {"number": 1, "title": "v1.0.0", "state": "open", "due_on": None,
              "description": "Entrega comprobable." + ("\n\n" + p.MARKER if managed else "")}
    return {**result, **changes}


class Fake(p.GitHub):
    def __init__(self, milestones=(), assigned=None):
        super().__init__("equipo/demo")
        self.milestones = copy.deepcopy(list(milestones))
        self.issues = {10: {"number": 10, "state": "open", "milestone": assigned}}
        self.calls = []
        self.repository = {"full_name": "equipo/demo", "archived": False}
        self.fail_write = False
        self.ignore_write = False

    def request(self, method, suffix="", payload=None):
        self.calls.append((method, suffix, copy.deepcopy(payload)))
        if method == "GET":
            if not suffix:
                return copy.deepcopy(self.repository)
            if suffix.startswith("/milestones?"):
                page = int(suffix.rsplit("=", 1)[1])
                return copy.deepcopy(self.milestones[(page - 1) * 100:page * 100])
            return copy.deepcopy(self.issues[int(suffix.rsplit("/", 1)[1])])
        p.require(self.writable, "El fake también bloquea escrituras no autorizadas.")
        if self.fail_write:
            raise p.Error("Fallo simulado.")
        if self.ignore_write:
            return {}
        if method == "POST":
            item = {"number": max((x["number"] for x in self.milestones), default=0) + 1,
                    "due_on": None, **payload}
            self.milestones.append(item)
            return copy.deepcopy(item)
        number = int(suffix.rsplit("/", 1)[1])
        if suffix.startswith("/issues/"):
            self.issues[number]["milestone"] = {"number": payload["milestone"]}
        else:
            next(x for x in self.milestones if x["number"] == number).update(payload)
        return {}

    def writes(self):
        return [x for x in self.calls if x[0] != "GET"]


class ValidationTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(p.validate(config()), config())

    def test_empty_milestones_allowed(self):
        value = config(); value["milestones"] = []
        self.assertEqual(p.validate(value), value)

    def test_bad_root_fields_and_types(self):
        for value in ([], {}, {**config(), "secret": "no-publicar"},
                      {**config(), "schema_version": True}, {**config(), "schema_version": 2},
                      {**config(), "milestones": {}}, {**config(), "milestones": [None]}):
            with self.subTest(value=value), self.assertRaises(p.Error):
                p.validate(value)

    def test_invalid_repository(self):
        for repo in ("../repo", "https://github.com/equipo/demo", "a/b/c", "a/x?evil=1", None, "a/.git"):
            with self.subTest(repo=repo), self.assertRaises(p.Error):
                p.validate({**config(), "repository": repo})

    def test_bad_milestone_fields(self):
        for changes in ({"title": " "}, {"title": "x\nwrite"}, {"title": "x\x1b"},
                        {"description": p.MARKER}, {"description": "\ttexto"},
                        {"issues": [True]}, {"issues": [0]}, {"issues": ["10"]},
                        {"issues": [10, 10]}, {"issues": {}}, {"extra": 1}):
            value = config(); value["milestones"][0].update(changes)
            with self.subTest(changes=changes), self.assertRaises(p.Error):
                p.validate(value)

    def test_duplicate_titles(self):
        value = config(); value["milestones"] += [{"title": "V1.0.0", "description": "Otra.", "issues": []}]
        with self.assertRaises(p.Error): p.validate(value)

    def test_issue_in_two_versions(self):
        value = config(); value["milestones"] += [{"title": "v2", "description": "Otra.", "issues": [10]}]
        with self.assertRaises(p.Error): p.validate(value)

    def test_dates(self):
        value = config(); item = value["milestones"][0]
        item["due_on"] = "2028-02-29T12:30:00Z"
        p.validate(value)
        for date in (None, "2027-02-29T12:30:00Z", "2028-01-01", "2028-01-01T00:00:00+02:00"):
            item["due_on"] = date
            with self.subTest(date=date), self.assertRaises(p.Error): p.validate(value)

    def test_duplicate_json_keys(self):
        for value in ('{"x":1,"x":2}', '{"nested":{"x":1,"x":2}}'):
            with self.assertRaises(p.Error): json.loads(value, object_pairs_hook=p.unique_object)

    def test_bad_file_and_bad_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            with self.assertRaises(p.Error): p.load(path)
            path.write_text("{bad", encoding="utf-8")
            with self.assertRaises(p.Error): p.load(path)
            path.write_text("x" * (p.MAX_CONFIG + 1), encoding="utf-8")
            with self.assertRaises(p.Error): p.load(path)

    def test_cli_check_is_offline(self):
        path = Path(__file__).resolve().parents[1] / "templates/platino.json"
        with patch.object(p.subprocess, "run", side_effect=AssertionError("No se permite red")), \
                patch("sys.stdout", new_callable=io.StringIO) as output:
            self.assertEqual(p.main(["check", str(path)]), 0)
            self.assertFalse(json.loads(output.getvalue())["network"])


class SyncTests(unittest.TestCase):
    def preview(self, fake, value=None):
        return p.sync(value or config(), "equipo/demo", api=fake)

    def apply(self, fake, value=None):
        value = value or config()
        approval = self.preview(fake, value)["approval"]
        return p.sync(value, "equipo/demo", True, approval, fake)

    def test_preview_does_not_write(self):
        fake = Fake(); plan = self.preview(fake)
        self.assertEqual([x["kind"] for x in plan["actions"]], ["create", "assign"])
        self.assertEqual(fake.writes(), [])

    def test_apply_and_idempotence(self):
        fake = Fake()
        self.assertEqual(self.apply(fake)["applied"], 2)
        self.assertEqual(self.preview(fake)["actions"], [])
        self.assertEqual(self.apply(fake)["applied"], 0)
        self.assertEqual(len(fake.writes()), 2)
        self.assertFalse(fake.writable)

    def test_wrong_repository_no_requests(self):
        fake = Fake()
        with self.assertRaises(p.Error): p.sync(config(), "otro/demo", api=fake)
        self.assertEqual(fake.calls, [])

    def test_missing_or_extra_approval_no_requests(self):
        for apply, approval in ((True, None), (True, "bad"), (False, "a" * 64)):
            fake = Fake()
            with self.assertRaises(p.Error): p.sync(config(), "equipo/demo", apply, approval, fake)
            self.assertEqual(fake.calls, [])

    def test_wrong_hash_no_writes(self):
        fake = Fake()
        with self.assertRaises(p.Error): p.sync(config(), "equipo/demo", True, "0" * 64, fake)
        self.assertEqual(fake.writes(), [])

    def test_changed_remote_invalidates_approval(self):
        fake = Fake(); approval = self.preview(fake)["approval"]
        fake.milestones.append(milestone())
        with self.assertRaises(p.Error): p.sync(config(), "equipo/demo", True, approval, fake)
        self.assertEqual(fake.writes(), [])

    def test_change_during_preflight_no_writes(self):
        fake = Fake(); approval = self.preview(fake)["approval"]
        original = fake.request
        count = 0
        def changed(method, suffix="", payload=None):
            nonlocal count
            if not suffix:
                count += 1
                if count == 2: fake.milestones.append(milestone())
            return original(method, suffix, payload)
        fake.request = changed
        with self.assertRaises(p.Error): p.sync(config(), "equipo/demo", True, approval, fake)
        self.assertEqual(fake.writes(), [])

    def test_manual_milestone_preserved(self):
        fake = Fake([milestone(False)])
        self.assertEqual(self.apply(fake)["applied"], 1)
        self.assertEqual(fake.milestones[0]["description"], "Entrega comprobable.")

    def test_manual_conflict_fails(self):
        fake = Fake([milestone(False, description="Decisión manual.")])
        with self.assertRaises(p.Error): self.preview(fake)
        self.assertEqual(fake.writes(), [])

    def test_managed_update_preserves_unspecified_due_date(self):
        fake = Fake([milestone(description="Anterior.\n\n" + p.MARKER, due_on="2027-01-01T00:00:00Z")])
        self.apply(fake)
        self.assertEqual(fake.milestones[0]["due_on"], "2027-01-01T00:00:00Z")
        self.assertEqual(fake.milestones[0]["description"], milestone()["description"])

    def test_explicit_due_date(self):
        value = config(); value["milestones"][0]["due_on"] = "2027-01-02T00:00:00Z"
        fake = Fake([milestone()]); self.apply(fake, value)
        self.assertEqual(fake.milestones[0]["due_on"], value["milestones"][0]["due_on"])

    def test_no_reassignment(self):
        fake = Fake([milestone()], assigned={"number": 2})
        with self.assertRaises(p.Error): self.preview(fake)
        self.assertEqual(fake.writes(), [])

    def test_closed_issue_not_assigned(self):
        fake = Fake(); fake.issues[10]["state"] = "closed"
        with self.assertRaises(p.Error): self.preview(fake)

    def test_closed_milestone_not_modified_or_populated(self):
        for description in (milestone()["description"], "Antigua.\n\n" + p.MARKER):
            fake = Fake([milestone(state="closed", description=description)])
            with self.assertRaises(p.Error): self.preview(fake)
            self.assertEqual(fake.writes(), [])

    def test_existing_closed_assignment_is_noop(self):
        fake = Fake([milestone(state="closed")], assigned={"number": 1})
        fake.issues[10]["state"] = "closed"
        self.assertEqual(self.preview(fake)["actions"], [])

    def test_pr_is_not_issue(self):
        fake = Fake(); fake.issues[10]["pull_request"] = {}
        with self.assertRaises(p.Error): self.preview(fake)

    def test_duplicate_or_case_ambiguous_remote(self):
        for items in ([milestone(), milestone(number=2)], [milestone(title="V1.0.0")]):
            with self.assertRaises(p.Error): self.preview(Fake(items))

    def test_pagination_finds_existing_item_on_second_page(self):
        items = [milestone(number=n + 2, title=f"otro-{n}") for n in range(100)]
        fake = Fake(items + [milestone()])
        self.assertEqual([x["kind"] for x in self.preview(fake)["actions"]], ["assign"])
        self.assertTrue(any("page=2" in x[1] for x in fake.calls))

    def test_incomplete_listing_fails_closed(self):
        for items in ([{}], [milestone(number=True)], [milestone(), milestone()]):
            fake = Fake(items)
            with self.assertRaises(p.Error): self.preview(fake)
            self.assertEqual(fake.writes(), [])

    def test_partial_failure_is_recoverable(self):
        fake = Fake()
        original = fake.request
        def fail_assignment(method, suffix="", payload=None):
            if method == "PATCH": raise p.Error("Fallo simulado de asignación.")
            return original(method, suffix, payload)
        fake.request = fail_assignment
        with self.assertRaisesRegex(p.Error, "cambios parciales"): self.apply(fake)
        self.assertEqual(len(fake.milestones), 1)
        fake.request = original
        self.assertEqual(self.apply(fake)["applied"], 1)
        self.assertEqual(len(fake.milestones), 1)

    def test_incomplete_issue_fails_closed(self):
        fake = Fake(); del fake.issues[10]["milestone"]
        with self.assertRaises(p.Error): self.preview(fake)

    def test_archived_or_transferred_repository(self):
        for changes in ({"archived": True}, {"full_name": "otro/demo"}):
            fake = Fake(); fake.repository.update(changes)
            with self.assertRaises(p.Error): self.preview(fake)
            self.assertEqual(fake.writes(), [])

    def test_write_error_reports_partial_and_disables_write(self):
        fake = Fake(); fake.fail_write = True
        with self.assertRaisesRegex(p.Error, "cambios parciales"): self.apply(fake)
        self.assertFalse(fake.writable)

    def test_verification_detects_ignored_write(self):
        fake = Fake([milestone()]); fake.ignore_write = True
        with self.assertRaisesRegex(p.Error, "verificación remota"): self.apply(fake)
        self.assertFalse(fake.writable)

    def test_unlisted_milestone_is_not_deleted(self):
        fake = Fake([milestone(title="otro", number=4)])
        self.apply(fake)
        self.assertEqual(fake.milestones[0]["title"], "otro")
        self.assertNotIn("DELETE", [x[0] for x in fake.calls])


class TransportTests(unittest.TestCase):
    def test_write_and_endpoint_guards(self):
        api = p.GitHub("equipo/demo")
        with patch.object(p.subprocess, "run") as run:
            for method, suffix in (("POST", "/milestones"), ("DELETE", "/milestones/1"),
                                   ("GET", "/../../orgs/equipo"), ("GET", "https://other.invalid")):
                with self.assertRaises(p.Error): api.request(method, suffix)
            run.assert_not_called()

    def test_stdin_not_shell_and_debug_disabled(self):
        api = p.GitHub("equipo/demo"); api.writable = True
        payload = {"description": "$(no-ejecutar)"}
        with patch.dict(os.environ, {"GH_DEBUG": "api"}), patch.object(
                p.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, '{"number":1}', "")) as run:
            api.request("POST", "/milestones", payload)
            args, kwargs = run.call_args
            self.assertEqual(json.loads(kwargs["input"]), payload)
            self.assertFalse(kwargs.get("shell", False))
            self.assertNotIn("GH_DEBUG", kwargs["env"])
            self.assertIn("github.com", args[0])
            self.assertNotIn("$(no-ejecutar)", args[0])

    def test_api_error_does_not_echo_private_response(self):
        with patch.object(p.subprocess, "run", return_value=subprocess.CompletedProcess(
                [], 1, "dato-privado-simulado", "credencial-simulada")):
            with self.assertRaises(p.Error) as error: p.GitHub("equipo/demo").request("GET")
            self.assertNotIn("privado", str(error.exception))
            self.assertNotIn("credencial-simulada", str(error.exception))

    def test_missing_gh_and_timeout(self):
        for error in (FileNotFoundError(), subprocess.TimeoutExpired("gh", 60)):
            with patch.object(p.subprocess, "run", side_effect=error), self.assertRaises(p.Error):
                p.GitHub("equipo/demo").request("GET")

    def test_malformed_response(self):
        with patch.object(p.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "not-json", "")):
            with self.assertRaises(p.Error): p.GitHub("equipo/demo").request("GET")


if __name__ == "__main__":
    unittest.main()
