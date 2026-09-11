extends SceneTree
## Read the embedded release metadata and resources, never a loose project.
var checks = 0
var failures = 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("EXPORT_CONTRACT_FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var expected = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-version="):
			expected = argument.trim_prefix("--expected-version=")
	check(not expected.is_empty(), "explicit version required")
	check(ProjectSettings.get_setting("application/config/version", "") == expected, "embedded application version matches package")
	check(OS.has_feature("template") and not OS.has_feature("editor"), "actual exported application, not editor")
	check(DisplayServer.get_name() != "headless", "real display available")
	for path in ["res://main.tscn", "res://ui/tactical_board_3d.gd", "res://ui/sound_captions.gd", "res://world/ship_deck_layout.gd", "res://data/runtime_asset_library.json", "res://assets/models/itsasargi_pack/manifest.json", "res://assets/models/bizi_planets/manifest.json", "res://assets/models/portu_environments/manifest.json", "res://assets/models/orbita_pack/player_batch/manifest.json"]:
		check(ResourceLoader.exists(path) if not path.ends_with(".json") else FileAccess.file_exists(path), "embedded resource exists: " + path)
	print("EXPORT_CONTRACT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
