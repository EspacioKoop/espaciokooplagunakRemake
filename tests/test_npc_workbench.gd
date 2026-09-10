extends SceneTree

var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	var editor = MissionEditor.new()
	editor.size = Vector2(1280, 800)
	root.add_child(editor)
	await process_frame
	var baseline = editor.mission.duplicate(true)
	var access = editor.find_child("NpcWorkbenchButton", true, false)
	check(access is Button, "workbench accessible in mission editor")
	if access == null:
		editor.queue_free()
		await process_frame
		_finish()
		return
	access.pressed.emit()
	await process_frame
	var window: NpcWorkbench
	for child in editor.get_children():
		if child is NpcWorkbench: window = child
	check(window != null and window.visible, "native window opens")
	if window == null:
		editor.queue_free()
		await process_frame
		_finish()
		return
	check(NpcGenerator.validate_document(window.document).ok, "initial generated sheet")
	check(window.preview.editable == false and window.preview.text.contains("AFINIDADES"), "read-only complete preview")
	window.seed_field.text = "2147483647"
	window.challenge_field.select(window.challenge_field.item_count - 1)
	check(window.generate_preview(), "max seed and challenge usable")
	var generated = window.document.duplicate(true)
	window.seed_field.text = "-1"
	check(not window.generate_preview() and window.export_button.disabled, "bad seed disables export")
	check(window.document == generated, "bad input preserves previous sheet")
	window.seed_field.text = "2.5"
	check(not window.generate_preview(), "fractional seed rejected")
	window.seed_field.text = "42"
	check(window.generate_preview(), "recover after error")
	var before_export = window.document.duplicate(true)
	var json_path = "user://npc-test.json"
	var text_path = "user://npc-test.txt"
	var bad_path = "user://npc-invalid.json"
	check(window.export_file(json_path), "export local JSON")
	check(window.export_file(text_path, true), "export local readable text")
	check(FileAccess.get_file_as_string(text_path).contains("RECETA"), "text includes reproducible recipe")
	window.seed_field.text = "10"
	check(window.generate_preview(), "change local draft")
	check(window.import_file(json_path), "import local generated file")
	check(window.document == before_export, "round trip exact")
	var bad = FileAccess.open(bad_path, FileAccess.WRITE)
	var altered = before_export.duplicate(true)
	altered.sheet.armor_class = 999
	bad.store_string(JSON.stringify(altered))
	bad.close()
	check(not window.import_file(bad_path) and window.document == before_export, "tamper rejected without losing draft")
	bad = FileAccess.open(bad_path, FileAccess.WRITE)
	bad.store_string(" ".repeat(NpcGenerator.MAX_BYTES + 1))
	bad.close()
	check(not window.import_file(bad_path), "oversized file rejected before parsing")
	check(not window.import_file("user://no-such-npc.json"), "missing file handled")
	check(not window.export_file("user://missing-folder/npc.json"), "write error handled")
	check(editor.mission == baseline, "no changes to mission authoring data")
	window.close_requested.emit()
	await process_frame
	check(not is_instance_valid(window), "close frees local window")
	access.pressed.emit()
	await process_frame
	var reopened = false
	for child in editor.get_children():
		if child is NpcWorkbench: reopened = child.visible
	check(reopened, "can reopen after close")
	for path in [json_path, text_path, bad_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	editor.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("NPC_WORKBENCH_PASS checks=%d" % checks)
		quit(0)
	else:
		for failure in failures: printerr("NPC_WORKBENCH_FAIL: " + failure)
		quit(1)
