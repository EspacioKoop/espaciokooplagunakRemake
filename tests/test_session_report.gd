extends SceneTree
## Synthetic data only. The Python runner isolates all user data directories.
var checks = 0
var failures = 0
const STAMP = "2026-09-10T21:00:00Z"
const SECRET = "REPORT_FORBIDDEN_SENTINEL"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SESSION_REPORT_FAIL " + label)

func same_json_value(expected: Variant, actual: Variant) -> bool:
	# JSON has one number type. Godot's parsed numbers may be floats even when
	# the projected document uses ints. Compare every field, not Dictionary's
	# strict recursive Variant equality; never equate false/null/string with 0.
	if expected is Dictionary:
		if not actual is Dictionary or expected.size() != actual.size(): return false
		for key in expected:
			if not actual.has(key) or not same_json_value(expected[key], actual[key]): return false
		return true
	if expected is Array:
		if not actual is Array or expected.size() != actual.size(): return false
		for i in expected.size():
			if not same_json_value(expected[i], actual[i]): return false
		return true
	if expected is int or expected is float:
		return (actual is int or actual is float) and is_finite(float(actual)) and float(expected) == float(actual)
	return typeof(expected) == typeof(actual) and expected == actual

func settle() -> void:
	for _i in 4:
		await process_frame

func fixture() -> Dictionary:
	return {
		"mission": {"id": "prueba", "title": "Guardia Ártica · 宇宙", "sector": "Argi"},
		"status": "active", "time": 42.25, "objective": 2,
		"campaign": {"credits": 123, "reputation": -2, "survivors": 6, "upgrades": 1,
			"completed": ["anterior"], "decisions": {"prueba": "tregua"}},
		"events": [{"seq": 2, "time": 3.5, "source": "Mando", "text": "Rescate completado."}],
		"ship": {"docked": ""}
	}

func history() -> Dictionary:
	return {"factions": {"haize": {"reputation": 4}},
		"chronicle": [{"time": 1789074000.0, "sector": "Argi", "source": "Dirección", "text": "Encuentro registrado."}]}

func projection_tests() -> void:
	check(same_json_value({"a": [1, 2.5, null, false]}, {"a": [1.0, 2.5, null, false]}), "JSON comparator allows only numeric int/float equivalence")
	for wrong in [{"a": [1.0, 2.5, 0, false]}, {"a": [1.0, 2.5, null, 0]}, {"a": ["1", 2.5, null, false]}, {"a": [2, 2.5, null, false]}, {"a": [1, 2.5, null]}, {"b": [1, 2.5, null, false]}]:
		check(not same_json_value({"a": [1, 2.5, null, false]}, wrong), "JSON comparator detects value, type, shape and key changes")
	var view = fixture()
	var expedition = history()
	var before = view.duplicate(true)
	var history_before = expedition.duplicate(true)
	var report = SessionReport.capture(view, expedition, STAMP)
	check(report.ok, "valid snapshot creates report")
	if not report.ok:
		return
	var doc: Dictionary = report.document
	check(doc.format == "lagunak-session-report" and doc.version == 1, "explicit independent report format")
	check(same_json_value(doc, JSON.parse_string(report.json)), "JSON round trip preserves every value")
	check(SessionReport.capture(view, expedition, STAMP) == report, "deterministic at fixed timestamp")
	check(doc.generated_at_utc == STAMP, "UTC capture timestamp")
	check(doc.mission.title == view.mission.title, "Unicode title retained")
	check(doc.mission.elapsed_seconds == 42.25, "mission clock retained")
	check(doc.events[0].time == 3.5 and doc.chronicle[0].time == 1789074000.0, "distinct event clocks are not mixed")
	check(doc.scope.events_clock == "mission_seconds" and doc.scope.chronicle_clock == "unix_seconds", "clock units documented")
	check(not doc.scope.history_complete, "never claims complete history")
	check(doc.campaign.survivors == 6 and doc.campaign.credits == 123 and doc.campaign.reputation == -2, "campaign counters retained")
	check(doc.campaign.completed == ["anterior"] and doc.campaign.decisions[0].choice == "tregua", "completed milestones and choices retained")
	check(doc.factions == [{"id": "haize", "reputation": 4}], "faction reputation projected")
	check("## Bitácora de la misión actual" in report.markdown and "## Crónica persistente retenida" in report.markdown, "readable report separates histories")
	check(view == before and expedition == history_before, "capture has no input mutation")
	doc.campaign.completed.append("mutated report")
	doc.events[0].text = "mutated report"
	check(view == before and expedition == history_before, "projection does not alias source arrays or dictionaries")
	for state in ["active", "won", "lost"]:
		view.status = state
		check(SessionReport.capture(view, expedition, STAMP).document.mission.status == state, "active and finished missions can be exported: " + state)
	for malformed in [{}, {"mission": []}, {"mission": null}, {"mission": {"id": "", "title": "x"}}, {"mission": {"id": "x", "title": 3}}]:
		check(not SessionReport.capture(malformed, {}, STAMP).ok, "reject absent or invalid mission")
	view = fixture()
	view.campaign = []
	check(not SessionReport.capture(view, {}, STAMP).ok, "reject wrong campaign type")
	view = fixture()
	view.mission.erase("sector")
	check(SessionReport.capture(view, {}, STAMP).document.mission.sector == "prueba", "legacy mission identifier used when sector absent")

func privacy_tests() -> void:
	var view = fixture()
	var expedition = history()
	for key in ["access_key", "token", "campaign_document", "profiles", "inventory", "lounge", "cards", "dice", "contacts", "operations", "roster", "peer_id", "facts"]:
		view[key] = {"nested": SECRET}
		expedition[key] = {"nested": SECRET}
	view.mission.contacts = [{"name": SECRET}]
	view.mission.objectives = [{"text": SECRET}]
	view.mission.briefing = SECRET
	view.campaign.private = SECRET
	view.events[0].credentials = SECRET
	expedition.chronicle[0].actor = SECRET
	expedition.factions.haize.hidden = SECRET
	expedition.factions[SECRET] = {"reputation": 8}
	var report = SessionReport.capture(view, expedition, STAMP)
	check(report.ok and SECRET not in report.json and SECRET not in report.markdown, "no unrelated or nested private field exported")
	check(report.document.keys().size() == 9, "only nine explicitly projected root fields")
	view.events[0].text = {"unexpected": SECRET}
	view.campaign.decisions.other = {"nested": SECRET}
	view.campaign.completed.append({"nested": SECRET})
	report = SessionReport.capture(view, expedition, STAMP)
	check(SECRET not in report.json, "non-string nested values never coerced into leaked text")
	check(report.document.scope.omitted_records.events == 1 and report.document.scope.omitted_records.decisions == 1 and report.document.scope.omitted_records.completed == 1, "invalid records counted")
	view = fixture()
	view.events[0].text = "<script>alert(1)</script> ![image](https://invalid.example/image)\n# heading\t" + String.chr(1) + String.chr(8238)
	report = SessionReport.capture(view, {}, STAMP)
	check("<script>" not in report.markdown and "&lt;script&gt;" in report.markdown, "HTML is inert in Markdown")
	check("![image]" not in report.markdown and "\\!\\[image\\]" in report.markdown, "Markdown image/link syntax escaped")
	check("\n" not in report.document.events[0].text and "\t" not in report.document.events[0].text and String.chr(1) not in report.json and String.chr(8238) not in report.json, "controls and bidi formatting removed")

func bounds_tests() -> void:
	for invalid in [null, "12", true, -1, 1.5, INF, NAN, [], {}, 1000000000001]:
		var view = fixture()
		view.campaign.credits = invalid
		var report = SessionReport.capture(view, {}, STAMP)
		check(report.ok and report.document.campaign.credits == null, "invalid discrete count stays unavailable, not invented zero")
	var view = fixture()
	view.time = NAN
	view.events.append({"seq": 3, "time": INF, "text": "invalid"})
	view.events.append({"seq": 0, "time": 3, "text": "invalid sequence"})
	view.events.append(null)
	var report = SessionReport.capture(view, {}, STAMP)
	check(report.document.mission.elapsed_seconds == null and report.document.events.size() == 1 and report.document.scope.omitted_records.events == 3, "nonfinite clock and invalid event rows handled")
	view.events = []
	var expedition = history()
	expedition.chronicle = []
	for i in 250:
		view.events.append({"seq": i + 1, "time": i * 0.5, "source": "S", "text": "E"})
	for i in 350:
		expedition.chronicle.append({"time": i + 1000.0, "sector": "Argi", "source": "S", "text": "C"})
	report = SessionReport.capture(view, expedition, STAMP)
	check(report.document.events.size() == 200 and report.document.events[0].seq == 51 and report.document.events[-1].seq == 250, "latest 200 events retained in source order")
	check(report.document.chronicle.size() == 300 and report.document.chronicle[0].time == 1050.0, "latest 300 chronicle entries retained")
	check(report.document.scope.omitted_records.events == 50 and report.document.scope.omitted_records.chronicle == 50, "truncation explicitly counted")
	view.campaign.completed = []
	view.campaign.decisions = {}
	for i in 280:
		view.campaign.completed.append("m" + str(i))
		view.campaign.decisions["m" + str(i)] = "choice"
	report = SessionReport.capture(view, {}, STAMP)
	check(report.document.campaign.completed.size() == 256 and report.document.campaign.decisions.size() == 256, "campaign collection limits")
	check(report.document.scope.omitted_records.completed == 24 and report.document.scope.omitted_records.decisions == 24, "campaign omissions counted")
	view = fixture()
	view.mission.title = "Á".repeat(1000)
	view.events[0].text = "x".repeat(9000)
	report = SessionReport.capture(view, {}, STAMP)
	check(report.document.mission.title.length() == 160 and report.document.events[0].text.length() == 2048, "string lengths bounded without splitting Unicode characters")
	for key in ["events", "completed", "decisions"]:
		view = fixture()
		if key == "events": view[key] = "invalid"
		else: view.campaign[key] = "invalid"
		report = SessionReport.capture(view, {}, STAMP)
		check(report.ok and report.document.scope.omitted_records[key] == 1, "wrong collection type handled: " + key)

func file_tests() -> void:
	var directory = "user://report-tests"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "isolated output directory created")
	var report = SessionReport.capture(fixture(), history(), STAMP)
	for kind in ["md", "json"]:
		var text = str(report.markdown if kind == "md" else report.json)
		var path = directory + "/report." + kind
		check(SessionReport.write_new(path, text, kind).ok, "local write: " + kind)
		check(FileAccess.get_file_as_string(path) == text, "file contains exact captured UTF-8: " + kind)
		check(not SessionReport.write_new(path, "replacement", kind).ok, "existing file refused: " + kind)
		check(FileAccess.get_file_as_string(path) == text, "existing file unchanged: " + kind)
	for path in ["res://forbidden.md", "relative.md", "user://../forbidden.md", "https://invalid.example/report.md", "user://report-tests/missing/report.md"]:
		check(not SessionReport.write_new(path, "test", "md").ok, "reject invalid or unavailable destination")
	check(not SessionReport.write_new(directory + "/wrong.json", "test", "md").ok, "extension must match format")
	check(not SessionReport.write_new(directory + "/empty.md", "", "md").ok, "empty file refused")
	check(not SessionReport.write_new(directory + "/large.md", "x".repeat(SessionReport.MAX_BYTES + 1), "md").ok, "oversized file refused")
	var target_directory = ProjectSettings.globalize_path(directory + "/folder.md")
	DirAccess.make_dir_absolute(target_directory)
	check(not SessionReport.write_new(target_directory, "test", "md").ok, "directory is never overwritten")
	var absolute = ProjectSettings.globalize_path(directory + "/absolute.md")
	check(SessionReport.write_new(absolute, report.markdown, "md").ok, "absolute local path supported")
	var files = DirAccess.get_files_at(directory)
	check(files.size() == 3, "no temporary files left after success or rejected writes")

func ui_tests() -> void:
	var session = root.get_node("Session")
	var expedition = root.get_node("Expedition")
	check(session.start_mission(0).ok, "native standalone mission starts")
	session.paused = true
	expedition._consume_session(session)
	var simulation_before = session.sim.state.duplicate(true)
	var input = InputEventKey.new()
	input.keycode = KEY_F2
	input.pressed = true
	# Exercise the actual F2 handler and its normal console, not a duplicate UI.
	expedition._unhandled_key_input(input)
	await settle()
	var console = expedition._window
	check(console is ExpeditionConsole, "F2 opens existing expedition console")
	if not console is ExpeditionConsole:
		return
	console.tabs.current_tab = 3
	await settle()
	var button = console.find_child("ExportSessionReport", true, false)
	check(button is Button and not button.disabled and button.is_visible_in_tree(), "export entry available in the chronicle tab")
	if not button is Button:
		console.queue_free()
		return
	button.pressed.emit()
	await settle()
	var dialog = console.get_node_or_null("SessionReportDialog")
	check(dialog is SessionReportDialog and dialog.visible, "export button opens report preview")
	if not dialog is SessionReportDialog:
		console.queue_free()
		return
	check(not dialog.preview.editable and dialog.preview.text.begins_with("# Crónica"), "plain read-only Markdown preview")
	check(dialog.report.document.mission.id == session.view.mission.id, "report comes from the running mission's visible state")
	check(session.sim.state == simulation_before, "opening export never mutates simulation")
	var frozen: String = dialog.report.json
	session.view.campaign.credits += 987
	expedition.data.chronicle.append({"time": 2.0, "sector": "test", "source": "test", "text": "Later event"})
	check(dialog.report.json == frozen, "preview snapshot remains frozen while source changes")
	dialog.format_choice.select(1)
	dialog.format_choice.item_selected.emit(1)
	check(dialog.preview.text == frozen, "format switch renders the same frozen report")
	dialog.save_button.pressed.emit()
	await settle()
	check(dialog.file_dialog.visible and dialog.file_dialog.access == FileDialog.ACCESS_FILESYSTEM, "explicit save opens local chooser")
	check(dialog.file_dialog.current_file.ends_with(".json"), "chooser extension matches selected format")
	var path = ProjectSettings.globalize_path("user://report-tests/ui.json")
	dialog.file_dialog.hide()
	dialog.file_dialog.file_selected.emit(path)
	check(FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == frozen, "file selection writes the exact displayed report")
	check(not dialog.save_to(path, "json").ok, "UI reports overwrite refusal")
	check("Ya existe" in dialog.status.text, "write error is visible to the user")
	dialog.close_requested.emit()
	await settle()
	check(not is_instance_valid(dialog), "close frees export window")
	button.pressed.emit()
	await settle()
	check(console.get_node_or_null("SessionReportDialog") is SessionReportDialog, "export can reopen after closing")
	console.close_requested.emit()
	await settle()
	check(not is_instance_valid(console), "closing F2 also frees nested export dialog")
	session.view = {}
	expedition._unhandled_key_input(input)
	await settle()
	console = expedition._window
	button = console.find_child("ExportSessionReport", true, false)
	check(button.disabled, "no-mission export entry disabled")
	console.close_requested.emit()
	await settle()
	var empty = SessionReportDialog.new()
	root.add_child(empty)
	check(empty.save_button.disabled and not empty.save_to("user://report-tests/no-report.md", "md").ok, "empty dialog cannot export")
	empty.queue_free()
	await settle()

func run() -> void:
	if "--test" not in OS.get_cmdline_user_args():
		push_error("Use the isolated session report runner with --test.")
		quit(2)
		return
	root.gui_embed_subwindows = true
	for child in root.get_children():
		child.set_process(false)
		child.set_physics_process(false)
	projection_tests()
	privacy_tests()
	bounds_tests()
	file_tests()
	await ui_tests()
	await settle()
	print("SESSION_REPORT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
