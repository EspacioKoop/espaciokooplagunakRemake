extends SceneTree
## Internal adapter: public entry point is tools/validate_mission.py.
## Never starts a mission or a server; Catalog remains the sole rules authority.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or args[0] != "--test":
		quit(2)
		return
	var source := FileAccess.open(args[1], FileAccess.READ)
	if source == null or source.get_length() > 256 * 1024:
		quit(2)
		return
	var parser := JSON.new()
	var parse_error := parser.parse(source.get_as_text())
	source.close()
	if parse_error != OK:
		quit(2)
		return
	var error := Catalog.validate_mission(parser.data)
	var report := FileAccess.open(args[2], FileAccess.WRITE)
	if report == null:
		quit(2)
		return
	report.store_string(JSON.stringify({
		"format": "lagunak-mission-validation", "version": 1,
		"valid": error.is_empty(), "error": error
	}))
	report.flush()
	var write_error := report.get_error()
	report.close()
	if write_error != OK:
		quit(2)
		return
	quit(0 if error.is_empty() else 1)
