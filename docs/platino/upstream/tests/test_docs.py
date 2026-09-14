"""Controles documentales locales; no descargan enlaces externos."""
from pathlib import Path
import re
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def prose(source):
    lines = []
    fence = None
    for line in source.splitlines():
        match = re.match(r"^\s*(`{3,}|~{3,})", line)
        if match:
            token = match.group(1)
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            continue
        if fence is None:
            lines.append(line)
    if fence:
        raise ValueError("Bloque de código sin cerrar.")
    return "\n".join(lines)


class DocsTests(unittest.TestCase):
    def test_local_links_and_fences(self):
        docs = [ROOT / "README.md", ROOT / "AGENTS.md", *sorted((ROOT / "docs").glob("*.md")),
                *sorted((ROOT / "templates").glob("*.md"))]
        for path in docs:
            with self.subTest(path=path.relative_to(ROOT)):
                source = prose(path.read_text(encoding="utf-8"))
                for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", source):
                    url = urlsplit(target)
                    if url.scheme or target.startswith("#"):
                        continue
                    destination = (path.parent / unquote(url.path)).resolve()
                    self.assertTrue(destination.is_relative_to(ROOT), target)
                    self.assertTrue(destination.exists(), f"{path.name}: {target}")

    def test_checker_detects_unclosed_fence(self):
        with self.assertRaises(ValueError): prose("texto\n```python\nsin_cerrar")

    def test_code_examples_are_not_interpreted_as_links(self):
        self.assertNotIn("no-existe", prose("```markdown\n[x](no-existe)\n```"))

    def test_key_sources_are_reachable_from_readme(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for source in ("AGENTS.md", "docs/COOPERACION_AUTONOMA.md", "docs/PLANIFICACION_Y_ENTREGAS.md",
                       "docs/AUTOMATIZACION.md", "templates/ADOPCION.md", "templates/ROADMAP.md",
                       "templates/platino.json", "scripts/platino.py"):
            self.assertIn(f"]({source})", readme)

    def test_workflow_has_no_write_or_privileged_event(self):
        workflow = (ROOT / ".github/workflows/validar.yml").read_text(encoding="utf-8")
        self.assertIn("contents: read", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertNotIn("pull_request_target", workflow)
        self.assertNotRegex(workflow, r"(?m)^\s*\w[\w-]*:\s*write\s*$")
        self.assertNotIn("--apply", workflow)
        self.assertNotIn("schedule:", workflow)
        self.assertRegex(workflow, r"uses: actions/checkout@[0-9a-f]{40}")

    def test_whitespace_and_final_newlines(self):
        paths = [ROOT / "README.md", ROOT / "AGENTS.md", ROOT / ".gitignore",
                 *sorted((ROOT / "docs").glob("*.md")), *sorted((ROOT / "templates").glob("*")),
                 *sorted((ROOT / "scripts").glob("*.py")), *sorted((ROOT / "tests").glob("*.py")),
                 ROOT / ".github/workflows/validar.yml"]
        for path in paths:
            with self.subTest(path=path.relative_to(ROOT)):
                data = path.read_text(encoding="utf-8")
                self.assertTrue(data.endswith("\n"))
                self.assertFalse(any(line.rstrip() != line for line in data.splitlines()))


if __name__ == "__main__":
    unittest.main()
