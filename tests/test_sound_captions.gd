extends SceneTree

var checks = 0
var failures = 0
var app: Control
var captions: SoundCaptions

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("SOUND_CAPTIONS_FAIL: " + message)

func frames(count: int = 4) -> void:
	for index in count: await process_frame

func write_text(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "synthetic fixture writable")
	if file != null:
		file.store_string(text)
		file.close()

func _run() -> void:
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var args = OS.get_cmdline_user_args()
	if "--verify-persisted" in args:
		var stored = SoundCaptionProfile.read_profile()
		check(stored.enabled == false and stored.duration == 9.0, "settings survive independent engine restart")
		_finish()
		return
	if "--require-display" in args:
		check(DisplayServer.get_name() != "headless", "real graphical display")
	_test_queue()
	_test_profile()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames()
	captions = app._sound_captions
	check(captions != null, "real main scene owns captions")
	check(not captions.panel.visible, "empty overlay starts hidden")
	if "--verify-audio" in args:
		captions.profile.enabled = true
		for cue in SoundCaptionQueue.CUES:
			app._play_effect(cue)
			check(app._effects.playing, "real audio playback started: " + cue)
			check(captions.queue.entries().back().cue == cue, "playback and caption share cue: " + cue)
		await _cleanup()
		return
	await _test_ui()
	await _cleanup()

func _test_queue() -> void:
	var queue = SoundCaptionQueue.new()
	check(queue.lines().is_empty(), "initial empty queue")
	for cue in SoundCaptionQueue.CUES:
		queue.clear()
		check(queue.push(cue, 1.0, 5.0), "known cue accepted: " + cue)
		check(queue.lines("es_ES")[0].begins_with("[Sonido]"), "Spanish description")
		check(queue.lines("en_US")[0].begins_with("[Sound]"), "English description")
		check(queue.lines("eu_ES") == queue.lines("es"), "unknown locale safely falls back to Spanish")
		check(not queue.expire(5.9), "remains for full configured duration")
		check(queue.expire(6.0), "expires at exact deadline")
		check(queue.lines().is_empty(), "expired text removed")
	for cue in ["", "secret-target", "[url]private[/url]", "../confirm", "x".repeat(4096)]:
		check(not queue.push(cue, 0.0, 5.0), "unknown text never displayed")
	for now in [-1.0, NAN, INF]: check(not queue.push("confirm", now, 5.0), "invalid clock rejected")
	for duration in [-1.0, 0.0, 1.9, 12.1, NAN, INF]: check(not queue.push("confirm", 0.0, duration), "invalid duration rejected")
	queue.push("confirm", 1.0, 5.0)
	for index in 110: queue.push("confirm", 2.0, 5.0)
	check(queue.entries().size() == 1 and queue.entries()[0].repeats == 99, "repeat flood bounded and grouped")
	check(queue.lines()[0].ends_with("× 99"), "repeat count visible without colour or audio")
	check(not queue.expire(NAN), "invalid expiry leaves queue unchanged")
	for cue in ["scan", "pulse", "torpedo", "arrival"]: queue.push(cue, 3.0, 5.0)
	check(queue.entries().size() == 3, "at most three visible cues")
	check(queue.entries()[0].cue == "pulse" and queue.entries().back().cue == "arrival", "latest three retained in order")
	var detached = queue.entries()
	detached[0].cue = "secret"
	check(queue.entries()[0].cue == "pulse", "returned data cannot corrupt queue")
	queue.push("pulse", 4.0, 5.0)
	check(queue.entries().back().cue == "pulse", "repeated cue becomes most recent")
	queue.clear()
	check(queue.entries().is_empty(), "clear discards all history")

func _test_profile() -> void:
	var defaults = SoundCaptionProfile.DEFAULTS
	for value in [null, [], true, 12, "profile", {}, {"version": 2}, {"version": true}, {"version": NAN}]:
		check(SoundCaptionProfile.normalize(value) == defaults, "malformed or unsupported profile recovers defaults")
	for duration in [true, "5", [], null, -1, 1, 13, NAN, INF]:
		check(SoundCaptionProfile.normalize({"version": 1, "enabled": false, "duration": duration}).duration == 5.0, "invalid duration recovers default")
	for duration in [2, 5, 12, 7.5]:
		check(SoundCaptionProfile.normalize({"version": 1, "enabled": false, "duration": duration}).duration == duration, "valid duration retained")
	check(SoundCaptionProfile.normalize({"version": 1, "enabled": "false", "duration": 5}).enabled, "string false not coerced")
	var extra = defaults.duplicate()
	extra.secret = "private-canary"
	check(not SoundCaptionProfile.normalize(extra).has("secret"), "unknown fields not retained")
	var path = "user://sound-captions-fixture.json"
	check(SoundCaptionProfile.read_profile(path) == defaults, "missing profile uses defaults")
	var value = {"version": 1, "enabled": false, "duration": 9.0}
	check(SoundCaptionProfile.write_profile(value, path) == OK, "write local configuration")
	check(SoundCaptionProfile.read_profile(path) == value, "JSON numeric round trip")
	check(not FileAccess.file_exists(path + ".tmp"), "atomic temporary consumed")
	for invalid in [{}, {"version": true, "enabled": false, "duration": 9.0}, {"version": 1, "enabled": true, "duration": 100}, extra]:
		check(SoundCaptionProfile.write_profile(invalid, path) != OK, "invalid write refused")
		check(SoundCaptionProfile.read_profile(path) == value, "invalid write preserves configuration")
	for invalid_path in ["res://bad.json", "/tmp/bad.json", "user://../bad.json", "https://example.invalid/bad.json", "user://bad.txt"]:
		check(SoundCaptionProfile.write_profile(value, invalid_path) != OK, "nonlocal or traversal path refused")
		check(SoundCaptionProfile.read_profile(invalid_path) == defaults, "nonlocal read refused")
	for text in ["{", "[]", "null", "x".repeat(SoundCaptionProfile.MAX_BYTES + 1)]:
		write_text(path, text)
		check(SoundCaptionProfile.read_profile(path) == defaults, "corrupt or oversize profile falls back")
	check(SoundCaptionProfile.write_profile(value, "user://missing-caption-folder/prefs.json") != OK, "write failure returned")
	DirAccess.remove_absolute(path)

func _test_ui() -> void:
	var session = root.get_node("Session")
	app._new_game()
	await frames()
	session.paused = true
	var previous_volume = AudioServer.get_bus_volume_db(0)
	AudioServer.set_bus_volume_db(0, -80.0)
	AudioServer.set_bus_mute(0, true)
	app._send("helm", {"heading": 45.0, "throttle": 0.0})
	check(captions.panel.visible and captions.queue.entries().back().cue == "confirm", "accepted real command captioned while muted")
	captions.clear()
	app._send("helm", {"heading": 45.0, "throttle": 1000.0})
	check(captions.queue.entries().is_empty(), "rejected real command produces no success cue")
	app._choose_role("sensores")
	app._send("scan", {"target": "argi"})
	check(not captions.queue.entries().is_empty() and captions.queue.entries().back().cue == "scan", "real sensor command routes to scan cue")
	check(captions.caption_label.mouse_filter == Control.MOUSE_FILTER_IGNORE and captions.panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay does not capture clicks")
	check(captions.caption_label.focus_mode == Control.FOCUS_NONE, "overlay never takes keyboard focus")
	captions.clear()
	app._play_effect("../private-canary")
	check(captions.queue.entries()[0].cue == "confirm", "unknown audio ID uses same safe fallback for audio and caption")
	check(not captions.caption_label.text.contains("private-canary"), "unknown ID is not exposed")
	var before = session.sim.state.duplicate(true)
	captions.present("torpedo")
	check(session.sim.state == before, "caption itself never changes simulation")
	var readability = root.get_node("Controls").readability
	check(readability.commit_text_percent(150).is_empty(), "existing 150 percent setting accepted")
	await frames(8)
	check(captions.caption_label.get_theme_font_size("font_size") == 30, "caption respects existing text scaling")
	check(captions.panel.get_global_rect().end.y <= root.size.y, "scaled captions fit window")
	check(readability.commit_text_percent(100).is_empty(), "existing text scale restored")
	captions.clear()
	app._play_effect("scan")
	app._play_effect("confirm")
	app._play_effect("confirm")
	await frames()
	await _capture("sound-captions.png")
	app._go("settings")
	await frames()
	var launcher: Button
	for button in app.find_children("*", "Button", true, false):
		if button.text == "Subtítulos de avisos sonoros…": launcher = button
	check(launcher != null and launcher.is_visible_in_tree(), "settings launcher accessible from real shell")
	if launcher == null: return
	launcher.pressed.emit()
	await frames()
	check(captions.settings.visible, "settings launcher opens modal")
	check(captions.enabled_control.has_focus(), "initial focus on checkbox")
	var key = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	captions.settings.push_input(key)
	key = key.duplicate()
	key.pressed = false
	captions.settings.push_input(key)
	await frames()
	check(not captions.profile.enabled, "real keyboard input toggles focused checkbox")
	check(not captions.panel.visible, "disabling clears overlay immediately")
	app._play_effect("pulse")
	check(captions.queue.entries().is_empty(), "disabled captions retain no cue history")
	captions.enabled_control.button_pressed = true
	check(captions.queue.entries().is_empty(), "re-enabling does not replay old cues")
	captions.duration_control.value = 9
	check(captions.profile.duration == 9, "duration control applies value")
	var saved_path = captions.profile_path
	captions.profile_path = "user://missing-caption-folder/prefs.json"
	captions.duration_control.value = 8
	check(captions.status_label.text.contains("No se pudo guardar"), "write failure visible to user")
	captions.profile_path = saved_path
	captions.duration_control.value = 9
	check(captions.status_label.text.contains("este equipo"), "local persistence acknowledged in UI")
	await frames()
	await _capture("sound-caption-settings.png")
	var original_dialog = captions.settings.get_instance_id()
	captions.settings.hide()
	launcher.pressed.emit()
	check(captions.settings.get_instance_id() == original_dialog and captions.settings.visible, "reopening reuses a single modal")
	captions.settings.hide()
	captions.clear()
	captions.present("pulse")
	captions.queue.expire(Time.get_ticks_msec() / 1000.0 + 20.0)
	captions._refresh()
	check(not captions.panel.visible, "expired caption removes background as well")
	captions.open_settings()
	captions.enabled_control.button_pressed = false
	captions.duration_control.value = 9
	captions.settings.hide()
	AudioServer.set_bus_mute(0, false)
	AudioServer.set_bus_volume_db(0, previous_volume)

func _capture(name: String) -> void:
	var directory = OS.get_environment("SOUND_CAPTION_CAPTURE_DIR")
	if directory.is_empty(): return
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "actual rendered capture")
	if image != null and not image.is_empty(): check(image.save_png(directory.path_join(name)) == OK, "PNG saved from viewport")

func _cleanup() -> void:
	app.queue_free()
	await frames()
	# Audio mixing is on its own clock; headless frames can finish before it drains.
	await create_timer(0.2).timeout
	_finish()

func _finish() -> void:
	print("SOUND_CAPTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0: print("SOUND_CAPTIONS_OK")
	quit(0 if failures == 0 else 1)
