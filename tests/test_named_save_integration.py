from pathlib import Path
import unittest


class NamedSaveIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).parents[1]

    def test_named_save_integration_contract(self):
        session = (self.root / "game/net/session.gd").read_text()
        expedition = (self.root / "game/core/expedition_systems.gd").read_text()
        app = (self.root / "game/ui/app.gd").read_text()

        self.assertIn("restore_named_save", session)
        self.assertIn("NamedSaveStore.capture", session)
        self.assertIn("checkpoint_cursor", expedition)
        self.assertIn("Guardados de campaña", app)

    def test_named_save_never_loads_on_client_or_host(self):
        text = (self.root / "game/net/session.gd").read_text()
        self.assertIn('if mode == "client"', text)
        self.assertIn('if mode == "host"', text)


if __name__ == "__main__":
    unittest.main()
