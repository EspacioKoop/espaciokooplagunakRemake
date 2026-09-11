"""Static equivalence gate for the real Foundry callers and authority contract.

This checks source/document alignment only. It is not a Foundry installation or
runtime test.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

EXPECTED = {
    "alert": "mando",
    "helm": "navegacion",
    "autopilot": "navegacion",
    "dock": "navegacion",
    "undock": "navegacion",
    "power": "ingenieria",
    "coolant": "ingenieria",
    "shields": "ingenieria",
    "fire": "armas",
    "scan": "sensores",
    "hail": "comunicaciones",
    "probe": "enlace",
    "repair": "reparaciones",
}


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def match_body(pattern: str, text: str, path: str) -> str:
    match = re.search(pattern, text, re.DOTALL)
    if not match:
        raise AssertionError(f"no se pudo extraer el contrato de {path}")
    return match.group("body")


def javascript_commands() -> list[str]:
    body = match_body(
        r'export const COMMANDS = Object\.freeze\(\{(?P<body>.*?)\n\}\);',
        source("integrations/foundry/client.mjs"),
        "client.mjs COMMANDS",
    )
    return re.findall(r"^\s{2}([a-z]+):\s*\{label:", body, re.MULTILINE)


def authority_schemas() -> list[str]:
    body = match_body(
        r"const SCHEMAS = \{(?P<body>.*?)\n\}",
        source("game/net/foundry_authority.gd"),
        "foundry_authority.gd SCHEMAS",
    )
    return re.findall(r'"([a-z]+)"\s*:\s*\{', body)


def catalog_permissions() -> dict[str, set[str]]:
    body = match_body(
        r"const PERMISSIONS := \{(?P<body>.*?)\n\}",
        source("game/core/catalog.gd"),
        "catalog.gd PERMISSIONS",
    )
    rows = re.findall(r'"([a-z]+)"\s*:\s*\[([^\]]*)\]', body)
    return {role: set(re.findall(r'"([a-z_]+)"', operations)) for role, operations in rows}


def documented_equivalences() -> dict[str, str]:
    text = source("docs/FOUNDRY_WORKSPACE.md")
    labels = {
        "Mando": "mando",
        "Navegación": "navegacion",
        "Ingeniería": "ingenieria",
        "Armas": "armas",
        "Sensores": "sensores",
        "Comunicaciones": "comunicaciones",
        "Enlace": "enlace",
        "Control de daños": "reparaciones",
    }
    rows = re.findall(r"^\|\s*`([a-z]+)`\s*\|\s*([^|]+?)\s*\|", text, re.MULTILINE)
    return {operation: labels[role.strip()] for operation, role in rows}


class FoundryEquivalenceTests(unittest.TestCase):
    def test_client_and_host_share_exactly_thirteen_closed_operations(self):
        self.assertEqual(javascript_commands(), list(EXPECTED))
        self.assertEqual(authority_schemas(), list(EXPECTED))

    def test_each_operation_is_filtered_by_the_native_role(self):
        permissions = catalog_permissions()
        self.assertEqual(set(permissions), {
            "mando", "navegacion", "ingenieria", "armas",
            "sensores", "comunicaciones", "enlace", "reparaciones",
        })
        for role in permissions:
            exposed = {operation for operation, owner in EXPECTED.items() if owner == role}
            self.assertEqual(
                {operation for operation in EXPECTED if operation in permissions[role]},
                exposed,
                role,
            )

    def test_workspace_table_covers_the_same_equivalences(self):
        self.assertEqual(documented_equivalences(), EXPECTED)

    def test_real_callers_preserve_public_read_only_and_personal_control_paths(self):
        main = source("integrations/foundry/main.mjs")
        client = source("integrations/foundry/client.mjs")
        authority = source("game/net/foundry_authority.gd")
        self.assertIn('mode.value === "personal" ? new FoundryClient', main)
        self.assertIn(': new LagunakClient', main)
        self.assertIn('client instanceof FoundryClient ? await client.view() : await client.state()', main)
        self.assertIn('client instanceof FoundryClient ? state.log : await client.events(0)', main)
        self.assertIn('await client.command(operation, args)', main)
        self.assertIn('request("/v1/state")', client)
        self.assertIn('request("/v1/events?after=" + after)', client)
        self.assertIn('request("/v2/view")', client)
        self.assertIn('request("/v2/command"', client)
        self.assertIn('"X-Lagunak-User"', client)
        self.assertIn('if grant.get("control", false):', authority)
        self.assertIn('if not envelope.operation is String or envelope.operation not in commands(grant)', authority)
        self.assertIn('session.sim.command(grant.context.role, operation', authority)
        self.assertIn('FoundryProjection.state(session.sim.snapshot())', authority)

    def test_document_keeps_the_foundry_13_human_boundary_explicit(self):
        text = source("docs/FOUNDRY_WORKSPACE.md")
        normalized = " ".join(text.split())
        self.assertIn("No se han ejecutado localmente Godot, una instalación licenciada de Foundry", normalized)
        self.assertIn("no se afirma paridad de experiencia en Foundry real", normalized)


if __name__ == "__main__":
    unittest.main(verbosity=2)
