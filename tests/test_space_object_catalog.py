import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"


class SpaceObjectCatalogContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((GAME / "data/space_object_templates.json").read_text())
        cls.assets = json.loads((GAME / "data/runtime_asset_library.json").read_text())
        cls.campaign = json.loads((GAME / "data/campaign.json").read_text())
        cls.asset_by_id = {item["id"]: item for item in cls.assets["assets"]}
        cls.template_by_id = {item["id"]: item for item in cls.catalog["templates"]}

    def test_catalog_is_versioned_and_closed(self):
        self.assertEqual(self.catalog["format"], "lagunak-space-object-templates")
        self.assertEqual(self.catalog["version"], 1)
        self.assertEqual(
            set(self.template_by_id),
            {"small_station", "medium_station", "large_station", "huge_station"},
        )
        self.assertEqual(len(self.catalog["templates"]), 4)

    def test_original_reference_and_non_product_decision_are_explicit(self):
        reference = self.catalog["reference"]
        self.assertEqual(reference["commit"], "fecd0740545f485d2402c6dfe4b47d5a859cb96c")
        self.assertEqual(reference["file"], "scripts/shiptemplates/stations.lua")
        decisions = {item["id"]: item for item in self.catalog["decisions"]}
        self.assertEqual(decisions["defense_platform"]["decision"], "exclude")
        self.assertIn("six shield", decisions["defense_platform"]["reason"])

    def test_visuals_are_allowlisted_and_present(self):
        for template in self.catalog["templates"]:
            visual = self.asset_by_id[template["visual_model"]]
            self.assertIn("station", visual["contact_kinds"])
            self.assertTrue((ROOT / "game" / visual["resource"][len("res://") :]).is_file())
            self.assertEqual(template["decision"], "include")

    def test_campaign_uses_every_template_without_adding_new_contact_kind(self):
        station_contacts = []
        for mission in self.campaign["missions"]:
            for contact in mission["contacts"]:
                if contact["kind"] == "station":
                    station_contacts.append(contact)
                    template = self.template_by_id[contact["space_object_template"]]
                    self.assertEqual(template["kind"], contact["kind"])
                    self.assertEqual(template["visual_model"], contact["visual_model"])
        self.assertEqual(len(station_contacts), 6)
        self.assertEqual(
            {contact["space_object_template"] for contact in station_contacts},
            set(self.template_by_id),
        )

    def test_ship_catalog_remains_owned_by_pr25(self):
        ship_catalog = json.loads((GAME / "data/ship_templates.json").read_text())
        self.assertEqual(len(ship_catalog["templates"]), 38)
        self.assertNotIn("small_station", {item["id"] for item in ship_catalog["templates"]})


if __name__ == "__main__":
    unittest.main()
