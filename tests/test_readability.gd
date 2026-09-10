extends SceneTree
const Profile = preload("res://input/readability_profile.gd")
var checks = 0
var failures = 0
var controls: Node
var service: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("READABILITY_FAIL: " + message)

func frames(count: int = 4) -> void:
	for index in count: await process_frame

func write_text(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "fixture is writable")
	if file != null:
		file.store_string(text)
		file.close()

func _run() -> void:
	await frames()
	controls = root.get_node("Controls")
	service = controls.readability
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	if "--verify-persisted" in OS.get_cmdline_user_args():
		check(int(service.profile.text_percent) == 115, "preference survives a new engine process")
		check(service.commit_text_percent(100).is_empty(), "second process restores default")
		_finish()
		return
	if "--require-display" in OS.get_cmdline_user_args():
		check(DisplayServer.get_name() != "headless", "actual graphical display required")
	_test_profile()
	await _test_scaling()
	await _test_dialog()
	check(service.commit_text_percent(115).is_empty(), "persist value for independent restart")
	await frames()
	_finish()

func _test_profile() -> void:
	check(Profile.validate(Profile.defaults()).is_empty(), "default accepted")
	for percent in Profile.PERCENTAGES:
		var candidate = Profile.defaults()
		candidate.text_percent = percent
		check(Profile.validate(candidate).is_empty(), "supported percentage %d" % percent)
		check(Profile.validate(JSON.parse_string(JSON.stringify(candidate))).is_empty(), "JSON numeric round trip")
	for value in [null, [], "text", 100, true, {}, {"format": Profile.FORMAT}]:
		check(not Profile.validate(value).is_empty(), "invalid shape rejected")
	for value in [true, false, "150", 0, -1, 99, 101, 150.5, 1000000, NAN, INF]:
		var candidate = Profile.defaults()
		candidate.text_percent = value
		check(not Profile.validate(candidate).is_empty(), "invalid percentage rejected")
	for value in [true, "1", 0, 2, 1.5, NAN]:
		var candidate = Profile.defaults()
		candidate.version = value
		check(not Profile.validate(candidate).is_empty(), "invalid version rejected")
	var extra = Profile.defaults()
	extra.secret = "not a supported field"
	check(not Profile.validate(extra).is_empty(), "unknown fields rejected")
	extra = Profile.defaults()
	extra.format = "other"
	check(not Profile.validate(extra).is_empty(), "foreign format rejected")
	var path = "user://readability-fixture.json"
	var value = Profile.defaults()
	value.text_percent = 130
	check(Profile.save_file(path, value) == OK, "write local profile")
	check(Profile.load_file(path).profile.text_percent == 130, "read local profile")
	check(not FileAccess.file_exists(path + ".tmp"), "temporary file consumed")
	check(Profile.save_file(path, {}) != OK, "invalid profile not written")
	check(Profile.load_file(path).profile.text_percent == 130, "failed validation preserves file")
	for invalid in ["res://readability.json", "https://example.invalid/readability.json", "user://../escape.json", "user://bad.txt"]:
		check(Profile.save_file(invalid, value) != OK, "non-local path rejected")
		check(not Profile.load_file(invalid).error.is_empty(), "non-local read rejected")
	write_text(path, "{")
	check(not Profile.load_file(path).error.is_empty(), "malformed JSON rejected")
	check(Profile.load_file(path).profile.text_percent == 100, "corrupt profile recovers default")
	write_text(path, "x".repeat(Profile.MAX_BYTES + 1))
	check(not Profile.load_file(path).error.is_empty(), "oversize file rejected before parsing")
	write_text(path, "[]")
	check(not Profile.load_file(path).error.is_empty(), "valid JSON with wrong type rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(Profile.load_file(path).error.is_empty(), "missing file is normal")
	check(Profile.load_file(path).profile.text_percent == 100, "missing file uses default")

func _test_scaling() -> void:
	check(service.commit_text_percent(100).is_empty(), "initial default")
	var fixture = Control.new()
	var shared_theme = Theme.new()
	shared_theme.default_font_size = 18
	fixture.theme = shared_theme
	root.add_child(fixture)
	var inherited = Label.new()
	fixture.add_child(inherited)
	var explicit = Label.new()
	explicit.add_theme_font_size_override("font_size", 20)
	fixture.add_child(explicit)
	var rich = RichTextLabel.new()
	rich.add_theme_font_size_override("normal_font_size", 22)
	fixture.add_child(rich)
	var button = Button.new()
	fixture.add_child(button)
	var edit = LineEdit.new()
	fixture.add_child(edit)
	var sub = SubViewport.new()
	fixture.add_child(sub)
	var world_text = Label.new()
	world_text.add_theme_font_size_override("font_size", 19)
	sub.add_child(world_text)
	var excluded = Control.new()
	excluded.set_meta("readability_exempt", true)
	fixture.add_child(excluded)
	var fixed = Label.new()
	fixed.add_theme_font_size_override("font_size", 17)
	excluded.add_child(fixed)
	await frames()
	check(not inherited.has_theme_font_size_override("font_size"), "100 percent preserves inheritance")
	check(service.commit_text_percent(150).is_empty(), "set 150 percent")
	await frames()
	check(inherited.get_theme_font_size("font_size") == 27, "inherited font enlarged")
	check(explicit.get_theme_font_size("font_size") == 30, "explicit font enlarged")
	check(rich.get_theme_font_size("normal_font_size") == 33, "rich text enlarged")
	check(button.get_theme_font_size("font_size") == 27, "button enlarged")
	check(edit.get_theme_font_size("font_size") == 27, "editable field enlarged")
	check(shared_theme.default_font_size == 18, "shared Theme not mutated")
	check(world_text.get_theme_font_size("font_size") == 19, "SubViewport text excluded")
	check(fixed.get_theme_font_size("font_size") == 17, "explicit exempt subtree excluded")
	check(service.commit_text_percent(150).is_empty(), "repeated percentage accepted")
	await frames()
	check(explicit.get_theme_font_size("font_size") == 30, "no cumulative scaling")
	var late = Label.new()
	late.add_theme_font_size_override("font_size", 24)
	fixture.add_child(late)
	await frames()
	check(late.get_theme_font_size("font_size") == 36, "new screen text scaled")
	explicit.add_theme_font_size_override("font_size", 26)
	shared_theme.default_font_size = 20
	await frames()
	check(explicit.get_theme_font_size("font_size") == 39, "owner override becomes new baseline")
	check(inherited.get_theme_font_size("font_size") == 30, "inherited theme change respected")
	var old_path: String = service.profile_path
	service.profile_path = "user://nonexistent-readability-folder/prefs.json"
	check(not service.commit_text_percent(100).is_empty(), "write failure surfaced")
	check(int(service.profile.text_percent) == 150, "write failure preserves active preference")
	check(explicit.get_theme_font_size("font_size") == 39, "write failure preserves active font")
	service.profile_path = old_path
	check(not service.commit_text_percent(true).is_empty(), "invalid live setting rejected")
	check(service.commit_text_percent(100).is_empty(), "restore original")
	await frames()
	check(not inherited.has_theme_font_size_override("font_size"), "restored inheritance")
	check(explicit.get_theme_font_size("font_size") == 26, "restored latest explicit size")
	check(rich.get_theme_font_size("normal_font_size") == 22, "restored rich text")
	check(service.commit_text_percent(150).is_empty(), "scale before reparent")
	fixture.remove_child(late)
	check(late.get_theme_font_size("font_size") == 24, "leaving tree restores baseline")
	fixture.add_child(late)
	await frames()
	check(late.get_theme_font_size("font_size") == 36, "re-entering tree scales once")
	late.add_theme_font_size_override("font_size", 25)
	late.queue_free()
	await frames()
	check(not is_instance_valid(late), "freed Control not retained by deferred callbacks")
	fixture.queue_free()
	await frames()
	check(service.commit_text_percent(100).is_empty(), "cleanup scaling")

func _test_dialog() -> void:
	var f9 = InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	root.push_input(f9)
	await frames()
	check(controls.is_settings_open(), "F9 opens actual controls panel")
	if not controls.is_settings_open(): return
	var panel: Control = controls.panel
	var launcher = panel.find_child("ReadabilityLauncher", true, false)
	check(launcher != null, "readability entry present")
	if launcher == null: return
	launcher.pressed.emit()
	await frames()
	var window = panel.get_node_or_null("ReadabilitySettings")
	check(window != null and window.visible, "entry opens visible modal")
	if window == null: return
	check(window.exclusive, "modal focus cannot operate background")
	check(controls.gameplay_blocked(), "movement blocked while editing")
	window.scale_buttons[150].pressed.emit()
	await frames()
	check(service.profile.text_percent == 150, "UI applies chosen value")
	check(window.preview.get_theme_font_size("font_size") == 27, "preview enlarged")
	check(Profile.load_file(service.profile_path).profile.text_percent == 150, "UI writes local preference")
	window.size = Vector2i(480, 320)
	await frames()
	window.reset_button.grab_focus()
	await frames()
	check(window.scroll.follow_focus, "scroll follows keyboard focus")
	check(window.scroll.scroll_vertical > 0, "reset reachable in short window")
	check(window.reset_button.has_focus(), "reset can receive keyboard focus")
	var tab = InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	window.push_input(tab)
	await frames()
	check(window.close_button.has_focus(), "Tab advances along explicit focus order")
	window.reset_button.pressed.emit()
	await frames()
	check(service.profile.text_percent == 100, "reset restores default through UI")
	check(window.preview.get_theme_font_size("font_size") == 18, "preview restored")
	window.size = Vector2i(720, 560)
	window.scale_buttons[130].pressed.emit()
	window.scale_buttons[100].grab_focus()
	await frames()
	var capture_path = OS.get_environment("READABILITY_CAPTURE_PATH")
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture_path) == OK, "actual UI screenshot")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	window.push_input(escape)
	await frames()
	check(not is_instance_valid(window), "Escape closes child modal")
	check(controls.is_settings_open(), "Escape does not close parent panel")
	check(launcher.has_focus(), "focus returns to entry")
	controls.close_settings()
	await frames()
	check(not controls.is_settings_open(), "controls close normally")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "pointer remains available")

func _finish() -> void:
	print("READABILITY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0: print("READABILITY_OK")
	quit(1 if failures else 0)
