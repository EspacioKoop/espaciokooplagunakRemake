extends SceneTree

func _initialize() -> void: call_deferred("run")

static func expect(report: Dictionary, condition: bool, label: String) -> void:
	report.checks += 1
	if not condition:
		report.failures += 1
		push_error("REACTIVE_SCORE_FAIL " + label)

static func verify(tree: SceneTree) -> Dictionary:
	var report = {"checks": 0, "failures": 0}
	var public_view = {"status": "active", "ship": {"hull": 100, "max_hull": 100}, "contacts": []}
	expect(report, ScoreComposer.select_theme({}) == "bridge", "menu has a neutral score")
	for pair in [[9, "shore"], [8, "memories"], [12, "memories"], [7, "social"], [10, "social"], [11, "social"], [0, "bridge"]]:
		expect(report, ScoreComposer.select_theme(public_view, pair[0]) == pair[1], "score follows actual zone " + str(pair[0]))
	public_view.contacts = [{"identified": false, "kind": "unknown", "hostile": true, "hull": 100}]
	expect(report, ScoreComposer.select_theme(public_view) == "bridge", "hidden enemy cannot be heard through score")
	public_view.contacts[0].identified = true
	expect(report, ScoreComposer.select_theme(public_view) == "bridge", "unknown-kind echo stays neutral")
	public_view.contacts[0].kind = "ship"
	expect(report, ScoreComposer.select_theme(public_view, 9) == "tension", "known live threat overrides leisure")
	public_view.contacts[0].hull = 0
	expect(report, ScoreComposer.select_theme(public_view) == "bridge", "destroyed threat stops tension")
	public_view.ship.hull = 20
	expect(report, ScoreComposer.select_theme(public_view) == "tension", "critical known hull triggers warning score")
	public_view.status = "won"
	expect(report, ScoreComposer.select_theme(public_view) == "bridge", "finished mission does not remain in combat")
	for malformed in [{"ship": null}, {"ship": {"hull": NAN, "max_hull": 0}}, {"ship": {}, "contacts": null}, {"status": "active", "ship": {"hull": "private"}, "contacts": [null]}]:
		expect(report, ScoreComposer.select_theme(malformed) == "bridge", "malformed public view has safe fallback")
	for invalid in [null, [], {}, {"version": 2}, {"version": 1, "enabled": "yes", "volume": 50, "mode": "auto"}, {"version": 1, "enabled": true, "volume": NAN, "mode": "auto"}, {"version": 1, "enabled": true, "volume": 50, "mode": "unknown"}]:
		expect(report, ScoreComposer.validate_preferences(invalid) == ScoreComposer.validate_preferences({}), "invalid preferences are sanitized")
	for limit in [-5, 155]:
		var value = ScoreComposer.validate_preferences({"version": 1, "enabled": false, "volume": limit, "mode": "shore", "secret": "unused"})
		expect(report, value.volume == clampf(limit, 0, 100) and not value.has("secret"), "bounded gain and no unrelated preference data")
	for theme in ScoreComposer.THEMES:
		var a = ScoreComposer.new(theme, 710)
		var b = ScoreComposer.new(theme, 710)
		var peak = 0.0
		var energy = 0.0
		var total = Vector2.ZERO
		var stereo = 0.0
		var previous = Vector2.ZERO
		var largest_jump = 0.0
		var deterministic = true
		var finite = true
		for i in ScoreComposer.RATE * 2:
			var frame = a.next_frame()
			deterministic = deterministic and frame == b.next_frame()
			finite = finite and is_finite(frame.x) and is_finite(frame.y)
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			energy += frame.length_squared()
			total += frame
			stereo += absf(frame.x - frame.y)
			largest_jump = maxf(largest_jump, (frame - previous).length())
			previous = frame
		expect(report, finite and deterministic, theme + " reproducible finite synthesis")
		expect(report, peak > 0.01 and peak < 0.6 and energy > 1, theme + " audible PCM with headroom")
		expect(report, total.length() / (ScoreComposer.RATE * 2) < 0.002, theme + " no DC offset")
		expect(report, stereo > 1 and largest_jump < 0.16, theme + " stereo mix without note-boundary clicks")
	var app = load("res://main.tscn").instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	var score: ReactiveScore = app.get_node("ReactiveScore")
	expect(report, score.player != null and score.player.bus == "Master", "main scene loads soundtrack under general volume")
	expect(report, not score.player.playing, "headless/test execution does not generate unnecessary audio")
	var master_db = AudioServer.get_bus_volume_db(0)
	var saved_view: Dictionary = tree.root.get_node("Session").view.duplicate(true)
	score.update_preferences({"version": 1, "enabled": true, "volume": 60, "mode": "memories"}, false)
	expect(report, score.current_theme == "memories", "manual music changes actual composer")
	expect(report, tree.root.get_node("Session").view == saved_view, "music never changes campaign/network view")
	app._go("settings")
	score._attach_settings_button()
	expect(report, is_instance_valid(score.settings_button), "music panel reachable from native Settings")
	score.settings_button.pressed.emit()
	await tree.process_frame
	expect(report, score.panel.visible and score.panel.mode_menu.selected == 4, "panel opens and reflects real soundtrack")
	score.panel.enabled.button_pressed = false
	expect(report, not score.preferences.enabled and score.panel.status.text == "Música desactivada", "UI toggles music independently")
	expect(report, AudioServer.get_bus_volume_db(0) == master_db, "music control preserves master volume")
	score.panel.hide()
	var path = "user://reactive-music-test-%s.json" % OS.get_process_id()
	expect(report, score.save_preferences(path).is_empty(), "preferences persist locally")
	var copy = ReactiveScore.new()
	copy.load_preferences(path)
	expect(report, copy.preferences == score.preferences, "preference JSON roundtrip")
	var broken = FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	copy.load_preferences(path)
	expect(report, copy.preferences == score.preferences, "corrupt preferences preserve working settings without script error")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	copy.free()
	# Exercise the real generator/PCM buffer with the Dummy audio driver too.
	score._audio_enabled = true
	score.update_preferences({"version": 1, "enabled": true, "volume": 60, "mode": "shore"}, false)
	score._process(0.02)
	expect(report, score.player.playing and score._composer.sample_index > 0, "real playback buffer receives generated samples")
	score.set_theme("social")
	expect(report, score._previous != null and score._blend == 0, "live theme transition starts a crossfade")
	score._process(0.02)
	score.update_preferences({"version": 1, "enabled": false, "volume": 60, "mode": "auto"}, false)
	for i in 18:
		await tree.create_timer(0.02).timeout
	expect(report, not score.player.playing and score._previous == null, "mute fades down and stops synthesis including crossfade")
	app._ambient.stop()
	app._effects.stop()
	app.queue_free()
	await tree.process_frame
	print("REACTIVE_SCORE_TESTS ", report.checks, " checks; ", report.failures, " failures")
	return report

func run() -> void:
	var report = await verify(self)
	quit(1 if report.failures else 0)
