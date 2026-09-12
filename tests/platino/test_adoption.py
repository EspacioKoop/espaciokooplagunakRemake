"""Checks for the local, pinned adoption; no network or metadata writes."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import unittest
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = ROOT / 'docs/platino/upstream'
SOURCE_SHA = 'b5e01a2b2060a31268507797708a92a7d14ffc52'
REPOSITORY = 'EspacioKoop/espaciokooplagunakRemake'


class AdoptionTests(unittest.TestCase):
    def test_upstream_has_exactly_the_locked_original_files(self):
        lock = json.loads((ROOT / 'docs/platino/upstream-lock.json').read_text())
        self.assertEqual(lock['commit'], SOURCE_SHA)
        self.assertEqual(lock['repository'], 'EspacioKoop/normas_platino')
        self.assertEqual(len(lock['files']), 13)
        expected = {x['path'] for x in lock['files']}
        actual = {str(x.relative_to(UPSTREAM)) for x in UPSTREAM.rglob('*')
                  if x.is_file() and '__pycache__' not in x.parts}
        self.assertEqual(actual, expected)
        for entry in lock['files']:
            with self.subTest(path=entry['path']):
                path = UPSTREAM / entry['path']
                self.assertFalse(path.is_symlink())
                self.assertTrue(path.resolve().is_relative_to(UPSTREAM.resolve()))
                raw = path.read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), entry['sha256'])
                self.assertEqual(hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest(), entry['git_blob_sha'])

        # Keep the previously integrated entry point byte-identical, not a second implementation.
        self.assertEqual((ROOT / 'scripts/platino.py').read_bytes(),
                         (UPSTREAM / 'scripts/platino.py').read_bytes())

    def test_manifest_is_an_explicit_project_decision(self):
        config = json.loads((ROOT / '.platino.json').read_text())
        self.assertEqual(config['repository'], REPOSITORY)
        expected = {'1.0 — Paridad funcional': [29, 32], 'Cosmografía y navegación': [56, 59],
                    'Contenido y catálogo': [2, 3, 6, 52], 'Plataforma y publicación': [4, 5, 30],
                    'Adopción Normas Platino': [72], 'Diseño futuro — decisiones sin release': [33, 71]}
        self.assertEqual({x['title']: x['issues'] for x in config['milestones']}, expected)
        for item in config['milestones']:
            self.assertNotIn('due_on', item)
            self.assertFalse({1, 7, 69, 70}.intersection(item['issues']))
            self.assertIn(item['title'], (ROOT / 'docs/ROADMAP.md').read_text())

    def test_launch_check_does_not_need_gh_or_change_files(self):
        env = {**os.environ, 'GH_PROMPT_DISABLED': '1', 'PYTHONDONTWRITEBYTECODE': '1'}
        before = (ROOT / '.platino.json').read_bytes()
        result = subprocess.run(['python3', 'tools/platino.py', 'check', '.platino.json'], cwd=ROOT,
                                env=env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {'valid': True, 'repository': REPOSITORY, 'network': False})
        self.assertEqual(before, (ROOT / '.platino.json').read_bytes())

    def test_local_document_links_and_closed_fences(self):
        files = ('AGENTS.md', 'CONTRIBUTING.md', 'docs/PLATINO_ADOPTION.md', 'docs/ROADMAP.md',
                 'docs/REPOSITORY_REVIEW.md', 'docs/platino/README.md', 'docs/NORMAS_PLATINO.md')
        for name in files:
            path = ROOT / name
            fence = False
            for line in path.read_text().splitlines():
                if line.startswith('```'):
                    fence = not fence
                    continue
                if fence:
                    continue
                for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', line):
                    url = urlsplit(target)
                    if url.scheme or target.startswith('#'):
                        continue
                    resolved = (path.parent / unquote(url.path)).resolve()
                    self.assertTrue(resolved.is_relative_to(ROOT.resolve()), (name, target))
                    self.assertTrue(resolved.exists(), (name, target))
            self.assertFalse(fence, name)

    def test_sources_and_coordination_are_not_duplicated(self):
        agents = (ROOT / 'AGENTS.md').read_text()
        self.assertIn('docs/PLATINO_ADOPTION.md', agents)
        self.assertIn('docs/ROADMAP.md', agents)
        self.assertIn('no libera la reserva', agents)
        self.assertIn('No empujes directamente a `main`', agents)
        self.assertIn('no caduca por silencio', agents)
        self.assertIn(SOURCE_SHA, (ROOT / 'docs/PLATINO_ADOPTION.md').read_text())
        for link in ('docs/NORMAS_PLATINO.md', 'docs/ROADMAP.md'):
            self.assertIn(link, (ROOT / 'README.md').read_text())

    def test_known_trap_regression_paths_exist(self):
        paths = ('tests/test_storage_properties.gd', 'tests/test_storage_runtime.gd',
                 'tests/test_authenticated_aux_rpc.gd', 'tests/test_network_boundary.gd',
                 'tests/release_092/test_export_contract.gd', 'tests/test_parity_evidence.py')
        for path in paths:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_ci_read_only_and_pinned(self):
        workflow = (ROOT / '.github/workflows/platino.yml').read_text()
        self.assertIn('contents: read', workflow)
        self.assertNotRegex(workflow, r'(?m)^\s*[\w-]+:\s*write\s*$')
        for prohibited in ('pull_request_target', 'schedule:', '--apply', 'GH_TOKEN:'):
            self.assertNotIn(prohibited, workflow)
        self.assertIn('persist-credentials: false', workflow)
        self.assertIn('docs/platino/upstream/tests', workflow)
        self.assertIn('tests/platino', workflow)
        self.assertIn('tools/platino.py check .platino.json', workflow)
        for action in re.findall(r'uses:\s*(\S+)', workflow):
            self.assertRegex(action, r'^[\w/-]+@[0-9a-f]{40}$')

    def test_write_workflow_is_manual_main_only_and_has_separate_approval(self):
        workflow = (ROOT / '.github/workflows/platino-sync.yml').read_text()
        self.assertIn('workflow_dispatch:', workflow)
        self.assertNotRegex(workflow, r'(?m)^\s+(?:push|pull_request|pull_request_target|schedule):')
        self.assertEqual(workflow.count("github.ref == 'refs/heads/main'"), 2)
        self.assertEqual(workflow.count('persist-credentials: false'), 2)
        self.assertIn('expected_sha:', workflow)
        self.assertIn('approval:', workflow)
        self.assertIn('--apply --approve "$APPROVAL"', workflow)
        self.assertNotIn('contents: write', workflow)
        self.assertIn('cancel-in-progress: false', workflow)
        preview, apply = workflow.split('\n  apply:', 1)
        self.assertNotIn('issues: write', preview)
        self.assertIn('issues: write', apply)
        self.assertNotIn('${{ inputs.', '\n'.join(x for x in workflow.splitlines() if '--approve' in x or 'python3 tools/' in x))

    def test_no_placeholders_in_adoption_sheet(self):
        source = (ROOT / 'docs/PLATINO_ADOPTION.md').read_text()
        self.assertNotIn('<organización/repositorio>', source)
        self.assertNotIn('<URL', source)
        self.assertIn('No adoptado', source)
        self.assertIn('no significa que esté integrada', source)


if __name__ == '__main__':
    unittest.main()
