extends SceneTree
## Run through run_mission_briefing.py: disposable user data, never player saves.
var checks = 0
var failures = 0
var scratch = ""

func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MISSION_BRIEFING_FAIL " + label)

func settle() -> void:
	for _i in range(5): await process_frame

func sample() -> Dictionary:
	return {"mission": {"title": "Guardia en Itsaso", "sector": "Argi", "briefing": "Coordinad el rescate.", "objectives": [{"text": "Identificad la señal", "target": "private_target"}, {"text": "Completad el rescate"}]}, "objective": 0, "status": "active"}

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = find_button(child, text)
		if found != null: return found
	return null

func campaign_tests() -> void:
	var missions = Catalog.missions()
	check(not missions.is_empty(), "real built-in campaign is present")
	check(MissionBriefing.CHECKLISTS.size() == Catalog.ROLES.size(), "guide for every native role")
	for mission in missions:
		var sim = Simulation.new()
		sim.start(mission)
		var before = var_to_bytes(sim.state)
		for role in Catalog.ROLES:
			var view = sim.snapshot(role, "synthetic-recipient")
			var copy = var_to_bytes(view)
			var created = MissionBriefing.create(view, role)
			check(created.ok, "build real mission " + mission.id + " / " + role)
			if not created.ok: continue
			check(created.document.station.id == role and created.document.station.name == Catalog.role_name(role), "correct station")
			check(created.document.station.checklist.size() == 3, "three actionable coordination checks")
			check(created.document.objectives.size() == mission.objectives.size(), "all shared mission objectives")
			for extension in MissionBriefing.EXTENSIONS:
				var output = MissionBriefing.render(view, role, extension)
				check(output.ok and not output.text.is_empty(), "render " + extension)
				if not output.ok: continue
				check(output.text.to_utf8_buffer().size() <= MissionBriefing.MAX_OUTPUT_BYTES, "bounded document")
				if extension == "json":
					check(JSON.parse_string(output.text) == created.document, "JSON round-trip of real campaign briefing")
			check(var_to_bytes(view) == copy, "recipient view unchanged")
		check(var_to_bytes(sim.state) == before, "authoritative simulation unchanged")

func privacy_and_format_tests() -> void:
	var view = sample()
	var marker = "DO_NOT_EXPORT_PRIVATE_CANARY"
	for key in ["access_key", "token", "tickets", "profiles", "events", "contacts", "campaign_document", "lounge", "operations", "ship", "poses", "roster"]:
		view[key] = {"secret": marker}
	for key in ["contacts", "gm_notes", "reward", "future", "secrets"]: view.mission[key] = {"nested": [marker]}
	view.mission.objectives[0].target = marker
	view.mission.objectives[0].secret = marker
	view.mission.id = marker
	for extension in MissionBriefing.EXTENSIONS:
		var output = MissionBriefing.render(view, "mando", extension)
		check(output.ok and marker not in output.text, "no nested private fields in " + extension)
	var document = MissionBriefing.create(view, "mando").document
	check(document.keys().size() == 6, "only version format mission station objectives notice")
	check(document.mission.keys().size() == 4, "only mission title sector briefing status")
	check(document.objectives[0].keys().size() == 3, "only numbered objective text and progress")
	document.objectives[0].text = "Changed"
	document.station.checklist[0] = "Changed"
	check(view.mission.objectives[0].text == "Identificad la señal", "output does not alias input")
	check(MissionBriefing.CHECKLISTS.mando[0] != "Changed", "output does not alias role constants")
	var injection = "Áne 宇宙 <script>alert('x')</script> ![foto](https://example.invalid/a.png) <img src=\"https://example.invalid/b\" onerror=\"x()\"> & \"texto\"\n# falso"
	var authored = sample()
	authored.mission.title = injection
	authored.mission.sector = injection
	authored.mission.briefing = injection
	authored.mission.objectives[0].text = injection
	var html = MissionBriefing.render(authored, "sensores", "html")
	check(html.ok and "<script>" not in html.text and "<img " not in html.text, "HTML authored markup cannot become executable tags")
	check("&lt;script&gt;" in html.text and "&quot;" in html.text, "HTML encodes text and quotes")
	check("default-src 'none'" in html.text and "form-action 'none'" in html.text, "HTML denies network resources and forms")
	check("@page{size:A4" in html.text and "@media print" in html.text, "HTML contains printable layout")
	var markdown = MissionBriefing.render(authored, "sensores", "md")
	check(markdown.ok and "![foto](" not in markdown.text and "<img " not in markdown.text, "Markdown images and raw HTML escaped")
	check("\n# falso" not in markdown.text, "authored newline cannot inject document heading")
	var parsed = JSON.parse_string(MissionBriefing.render(authored, "sensores", "json").text)
	check(parsed.mission.briefing == injection and parsed.mission.title == injection, "Unicode and markup preserved as JSON data")
	var progress = sample()
	progress.objective = 1.0
	var current = MissionBriefing.create(progress, "enlace").document
	check(current.objectives[0].status == "completed" and current.objectives[1].status == "current", "integer JSON progress recognized")
	progress.status = "lost"
	check(MissionBriefing.create(progress, "enlace").document.objectives[1].status == "pending", "lost mission has no falsely active objective")
	progress.status = "won"
	progress.objective = 2
	check(MissionBriefing.create(progress, "enlace").document.objectives[1].status == "completed", "completed mission progress")

func invalid_tests() -> void:
	check(not MissionBriefing.create({}, "mando").ok, "no absent mission")
	for value in [null, [], "secret", 7, true]:
		var wrong = sample()
		wrong.mission = value
		check(not MissionBriefing.create(wrong, "mando").ok, "reject non-object mission")
	for key in ["title", "sector", "briefing"]:
		for value in [null, [], {}, 12, true, "", " \n\t", "x".repeat(4001), "a" + String.chr(1), "a" + String.chr(127)]:
			var wrong = sample()
			wrong.mission[key] = value
			check(not MissionBriefing.create(wrong, "mando").ok, "reject invalid mission text " + key)
		var missing = sample()
		missing.mission.erase(key)
		check(not MissionBriefing.create(missing, "mando").ok, "reject missing " + key)
	for value in [null, false, {}, "objectives", [], [null], [{"text": 5}], [{"text": ""}], [{"text": "x".repeat(501)}]]:
		var wrong = sample()
		wrong.mission.objectives = value
		check(not MissionBriefing.create(wrong, "mando").ok, "reject invalid objectives")
	var too_many = sample()
	for _i in range(23): too_many.mission.objectives.append({"text": "extra"})
	check(not MissionBriefing.create(too_many, "mando").ok, "reject more than 24 objectives")
	for value in [-1, 3, 0.5, NAN, INF, true, "1", null, [], {}]:
		var wrong = sample()
		wrong.objective = value
		check(not MissionBriefing.create(wrong, "mando").ok, "reject invalid progress")
	for value in [null, false, 1, [], {}, "unknown"]:
		var wrong = sample()
		wrong.status = value
		check(not MissionBriefing.create(wrong, "mando").ok, "reject invalid mission status")
	for role in ["", "observador", "admin", "../mando"]:
		check(not MissionBriefing.create(sample(), role).ok, "reject unsupported role")
	for extension in ["", "pdf", "exe", "../json"]:
		check(not MissionBriefing.render(sample(), "mando", extension).ok, "reject unsupported export format")
	var maximum = sample()
	for key in ["title", "sector", "briefing"]: maximum.mission[key] = "<".repeat(4000)
	maximum.mission.objectives = []
	for _i in range(24): maximum.mission.objectives.append({"text": "<".repeat(500)})
	for extension in MissionBriefing.EXTENSIONS:
		check(MissionBriefing.render(maximum, "ingenieria", extension).ok, "valid upper bound including escaped expansion")

func file_tests() -> void:
	for extension in MissionBriefing.EXTENSIONS:
		var output = MissionBriefing.render(sample(), "armas", extension)
		var path = scratch.path_join("briefing." + extension)
		check(MissionBriefing.write_new(path, output).ok, "explicit local write " + extension)
		check(FileAccess.get_file_as_string(path) == output.text, "written UTF-8 equals preview " + extension)
		var changed = output.duplicate(true)
		changed.text = "must not replace existing file"
		check(not MissionBriefing.write_new(path, changed).ok, "refuse overwrite " + extension)
		check(FileAccess.get_file_as_string(path) == output.text, "existing file not changed " + extension)
		DirAccess.remove_absolute(path)
	var output = MissionBriefing.render(sample(), "armas", "md")
	for path in ["", "relative.md", "res://forbidden.md", "https://example.invalid/briefing.md", "ftp://example.invalid/briefing.md", scratch.path_join("wrong.json"), scratch.path_join("missing/briefing.md")]:
		check(not MissionBriefing.write_new(path, output).ok, "reject invalid location or extension")
	for prepared in [{}, {"ok": false}, {"ok": true, "text": []}, {"ok": true, "text": "", "extension": "md"}, {"ok": true, "text": "x", "extension": "exe"}, {"ok": true, "text": "x".repeat(MissionBriefing.MAX_OUTPUT_BYTES + 1), "extension": "md"}]:
		var path = scratch.path_join("invalid.md")
		check(not MissionBriefing.write_new(path, prepared).ok, "reject invalid prepared file")
		check(not FileAccess.file_exists(path), "invalid content creates no file")

func ui_tests() -> void:
	var session = root.get_node("Session")
	session.suppress_saves = true
	session.new_campaign()
	session.paused = true
	await settle()
	var original_role: String = session.role
	var console = CrewConsole.new()
	console.crew = root.get_node("Crew")
	root.add_child(console)
	console.popup_centered(Vector2i(1040, 740))
	await settle()
	var button = find_button(console, "Briefing de misión")
	check(button != null, "public F4 console exposes briefing button")
	if button == null:
		console.queue_free()
		return
	button.pressed.emit()
	await settle()
	var windows = get_nodes_in_group(MissionBriefingWindow.WINDOW_GROUP)
	check(windows.size() == 1, "button opens one briefing window")
	if windows.size() != 1:
		console.queue_free()
		return
	var window: MissionBriefingWindow = windows[0]
	check(window.get_parent() == root and window.visible, "window is visible and root-owned")
	check(not window.save_button.disabled and not window.preview.editable, "valid read-only preview enables saving")
	check(window.station_menu.item_count == 8 and window.format_menu.item_count == 3, "all eight roles and three formats selectable")
	check(MissionBriefingWindow.open_for(self) == window, "reopening reuses same window")
	console._rebuild()
	await settle()
	check(is_instance_valid(window), "crew console rebuild cannot free briefing")
	for i in range(Catalog.ROLES.size()):
		window.station_menu.select(i)
		window.station_menu.item_selected.emit(i)
		check(window.prepared.ok and Catalog.role_name(Catalog.ROLES[i]) in window.preview.text, "select role through UI")
	check(session.role == original_role, "guide selector never changes authority or station")
	window.format_menu.select(1)
	window.format_menu.item_selected.emit(1)
	check(window.prepared.extension == "html", "HTML selected through format UI")
	var expected: String = window.prepared.text
	window.save_button.pressed.emit()
	check(not window._pending.is_empty() and window.file_dialog.visible, "explicit save opens file dialog")
	var old_view: Dictionary = session.view.duplicate(true)
	session.view = sample()
	window.refresh_preview()
	var path = scratch.path_join("ui.html")
	window.file_dialog.hide()
	window.file_dialog.file_selected.emit(path)
	check(FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == expected, "file selection writes the frozen preview not newer session state")
	DirAccess.remove_absolute(path)
	check(window._pending.is_empty(), "pending save cleared after selection")
	window.save_button.pressed.emit()
	window.file_dialog.hide()
	window.file_dialog.canceled.emit()
	check(window._pending.is_empty(), "cancel clears pending content")
	check(not window.save_selected(path).ok and not FileAccess.file_exists(path), "cancelled or unsolicited file event cannot write")
	session.view = {}
	window.refresh_preview()
	check(window.save_button.disabled and window.preview.text.is_empty(), "missing session disables export and clears preview")
	session.view = old_view
	window.refresh_preview()
	console.queue_free()
	await settle()
	check(is_instance_valid(window) and window.prepared.ok, "closing F4 preserves independent briefing")
	window.close_requested.emit()
	await settle()
	check(get_nodes_in_group(MissionBriefingWindow.WINDOW_GROUP).is_empty(), "close frees singleton")
	var reopened = MissionBriefingWindow.open_for(self)
	check(is_instance_valid(reopened) and reopened.prepared.ok, "can reopen after closing")
	reopened.queue_free()
	await settle()

func run() -> void:
	if "--test" not in OS.get_cmdline_user_args():
		push_error("Run only using the isolated briefing test runner.")
		quit(2)
		return
	scratch = "user://briefing-tests-%d" % Time.get_ticks_msec()
	check(DirAccess.make_dir_recursive_absolute(scratch) == OK, "disposable local export directory")
	campaign_tests()
	privacy_and_format_tests()
	invalid_tests()
	file_tests()
	await ui_tests()
	check(DirAccess.remove_absolute(scratch) == OK, "all test exports cleaned up")
	print("MISSION_BRIEFING_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
