from pathlib import Path


def test_named_save_integration_contract():
    root = Path(__file__).parents[1]
    session = (root / "game/net/session.gd").read_text()
    expedition = (root / "game/core/expedition_systems.gd").read_text()
    app = (root / "game/ui/app.gd").read_text()
    assert "restore_named_save" in session
    assert "NamedSaveStore.capture" in session
    assert "checkpoint_cursor" in expedition
    assert "Guardados de campaña" in app


def test_named_save_never_loads_on_client_or_host():
    text = (Path(__file__).parents[1] / "game/net/session.gd").read_text()
    assert 'if mode == "client"' in text
    assert 'if mode == "host"' in text
