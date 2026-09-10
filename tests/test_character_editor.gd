extends SceneTree
## Run only with isolated XDG directories (see tests/run_character_editor.py).
var checks = 0
var failures = 0
var session: Node
var expedition: Node
var crew: Node

# A deliberately non-authoritative transport fixture: never masquerades as an
# ENet test. It can acknowledge a send without producing an applied snapshot.
class DelayedExpedition:
	extends Node
	signal updated
	signal notice(text: String, ok: bool)
	var data: Dictionary = {}
	var received: Dictionary = {}
	var calls = 0
	func actor_id() -> String: return "self"
	func command(operation: String, args: Dictionary) -> Dictionary:
		calls += 1
		received = {"operation": operation, "args": args.duplicate(true)}
		return {"ok": true, "message": "Orden enviada al anfitrión."}

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CHARACTER_EDITOR_FAIL " + label)

func settle() -> void:
	for _i in 5: await process_frame

func sample() -> Dictionary:
	return {"name": "Ane Itsaso", "approach": "tecnica", "skills": {"pilotaje": 2, "ciencia": 3, "ingenieria": 3, "negociacion": 2, "combate": 2}}

func _write(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _schema_tests() -> void:
	var doc = CharacterDocument.document(sample())
	var valid = CharacterDocument.validate(doc)
	check(valid.ok and valid.document == doc, "native template v1 validates without mutation")
	check(CharacterDocument.parse_text(JSON.stringify(doc)).document == doc, "JSON floats normalize into equivalent integer skills")
	check(typeof(CharacterDocument.parse_text(JSON.stringify(doc)).document.character.skills.ciencia) == TYPE_INT, "discrete values are normalized to int")
	check(CharacterDocument.command_args(sample()).size() == 7, "command contains exactly seven editable keys")
	var rich = sample()
	for key in ["xp", "level", "focus", "traits", "condition", "milestones", "actor", "inventory", "secrets"]: rich[key] = "private fixture"
	var projected = CharacterDocument.editable_from_profile(rich)
	check(projected == sample(), "projection contains no progression, identity or unrelated data")
	projected.skills.ciencia = 0
	check(rich.skills.ciencia == 3, "projected skills are deep copied")
	for malformed in [null, [], "{}", 7, true]:
		check(not CharacterDocument.validate(malformed).ok, "reject non-object root " + str(malformed))
	for key in ["format", "version", "character"]:
		var missing = doc.duplicate(true)
		missing.erase(key)
		check(not CharacterDocument.validate(missing).ok, "reject missing root field " + key)
	for version in [0, 2, 1.5, "1", true, null, INF, NAN]:
		var wrong = doc.duplicate(true)
		wrong.version = version
		check(not CharacterDocument.validate(wrong).ok, "reject incompatible or mistyped version " + str(version))
	var wrong_format = doc.duplicate(true)
	wrong_format.format = "lagunak-expedition"
	check(not CharacterDocument.validate(wrong_format).ok, "reject expedition save as template")
	for field in ["name", "approach", "skills"]:
		var missing = doc.duplicate(true)
		missing.character.erase(field)
		check(not CharacterDocument.validate(missing).ok, "reject missing editable field " + field)
	for key in ["xp", "level", "focus", "condition", "traits", "milestones", "actor", "actor_id", "profiles", "inventory", "crew_position_id", "ship_id", "campaign_id", "legacy_role", "tags", "$ref"]:
		for target in ["root", "character", "skills"]:
			var extra = doc.duplicate(true)
			var container: Dictionary = extra if target == "root" else (extra.character if target == "character" else extra.character.skills)
			container[key] = "forbidden"
			check(not CharacterDocument.validate(extra).ok, "reject extra/runtime/reference " + target + "." + key)
	for name in ["", " ", " Ane", "Ane ", "A".repeat(33), "A\nB", "A\tB", "A" + String.chr(127), 5, null, []]:
		var wrong = doc.duplicate(true)
		wrong.character.name = name
		check(not CharacterDocument.validate(wrong).ok, "reject invalid name " + str(name))
	var unicode_doc = doc.duplicate(true)
	unicode_doc.character.name = "Áne 宇宙 \\\"Itsaso\\\""
	check(CharacterDocument.parse_text(JSON.stringify(unicode_doc)).ok, "Unicode and escaped quotes/backslashes remain valid")
	for approach in ExpeditionSystems.APPROACHES:
		var candidate = doc.duplicate(true)
		candidate.character.approach = approach
		check(CharacterDocument.validate(candidate).ok, "native approach reference " + approach)
	for approach in ["unknown", "Técnica", "res://profile.tres", "Actor.other", 0, null]:
		var wrong = doc.duplicate(true)
		wrong.character.approach = approach
		check(not CharacterDocument.validate(wrong).ok, "reject invalid approach reference " + str(approach))
	for skill in ExpeditionSystems.SKILLS:
		var missing = doc.duplicate(true)
		missing.character.skills.erase(skill)
		check(not CharacterDocument.validate(missing).ok, "reject missing skill " + skill)
		for value in [-1, 5, 1.25, "2", true, null, INF, NAN, {}, []]:
			var wrong = doc.duplicate(true)
			wrong.character.skills[skill] = value
			check(not CharacterDocument.validate(wrong).ok, "reject invalid skill " + skill + ":" + str(value))
	var over = doc.duplicate(true)
	over.character.skills.combate = 3
	check(not CharacterDocument.validate(over).ok, "reject thirteen points")
	var zero = doc.duplicate(true)
	for skill in ExpeditionSystems.SKILLS: zero.character.skills[skill] = 0
	check(CharacterDocument.validate(zero).ok, "zero points allowed; budget need not be fully used")
	for text in ["", "{", "{} garbage", '{"format":"x",}', '{"a":1,"a":2}', '{"a":1,"\\u0061":2}', '{"a":{"b":0,"b":1}}', '{"a":[0,]}', '{"a":01}', '{"a":+1}', '{"a":NaN}', '{"a":1.}', '/*comment*/{}', '{"a":"line\nfeed"}', "[".repeat(20) + "0" + "]".repeat(20)]:
		check(not CharacterDocument.parse_text(text).ok, "strict JSON rejects malformed/duplicate/overdeep input " + text.left(50))
	var duplicate_valid = JSON.stringify(doc).replace('"version":1', '"version":1,"version":1')
	check(not CharacterDocument.parse_text(duplicate_valid).ok, "duplicate version in otherwise valid template rejected")
	var escaped_duplicate = JSON.stringify(doc).replace('"name":', '"n\\u0061me":"Other","name":')
	check(not CharacterDocument.parse_text(escaped_duplicate).ok, "duplicate decoded character key rejected")
	for escape in ["\\ud800", "\\udfff", "\\ud800\\u0041"]:
		var unpaired = JSON.stringify(doc).replace("Ane Itsaso", escape)
		check(not CharacterDocument.parse_text(unpaired).ok, "unpaired Unicode surrogate rejected without decoder errors")
	check(CharacterDocument.parse_text(JSON.stringify(doc).replace("Ane Itsaso", "Ane \\ud83d\\ude80")).ok, "paired Unicode escape accepted")
	var padded = JSON.stringify(doc)
	padded += " ".repeat(CharacterDocument.MAX_BYTES - padded.to_utf8_buffer().size())
	check(CharacterDocument.parse_text(padded).ok, "exactly 32 KiB valid JSON accepted")
	check(not CharacterDocument.parse_text(padded + " ").ok, "32 KiB plus one byte rejected before parse")
	check(not CharacterDocument.parse_text("á".repeat(CharacterDocument.MAX_BYTES / 2 + 1)).ok, "limit measures UTF-8 bytes, not character count")

func _file_tests() -> void:
	var path = "user://character-roundtrip.json"
	var fields = sample()
	check(CharacterDocument.save_file(path, fields).ok, "export creates and rereads template")
	var read = CharacterDocument.load_file(path)
	check(read.ok and read.document.character == fields, "file import/export round trip")
	var original = FileAccess.get_file_as_bytes(path)
	var invalid = fields.duplicate(true)
	invalid.skills.pilotaje = 4
	check(not CharacterDocument.save_file(path, invalid).ok, "invalid export rejected")
	check(FileAccess.get_file_as_bytes(path) == original, "failed export preserves previous bytes")
	fields.name = "Reemplazo"
	check(CharacterDocument.save_file(path, fields).ok and CharacterDocument.load_file(path).document.character.name == "Reemplazo", "atomic replacement of an existing valid export")
	for forbidden in ["res://forbidden.json", ProjectSettings.globalize_path("res://forbidden.json"), "relative.json", "https://example.invalid/a.json", "user://missing-parent/template.json", "user://campaign.json", "user://campaign.json.bak", "user://campaign.json.bak.json", ExpeditionSystems.PATH, ExpeditionSystems.PATH + ".bak.json"]:
		check(not CharacterDocument.save_file(forbidden, fields).ok, "reject unsafe export path " + forbidden)
	var folder = "user://folder.json"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(folder))
	check(not CharacterDocument.save_file(folder, fields).ok and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)), "failed directory destination leaves directory intact")
	var oversized = "user://oversized-character.json"
	_write(oversized, " ".repeat(CharacterDocument.MAX_BYTES + 1))
	check(not CharacterDocument.load_file(oversized).ok, "oversized disk file rejected before content read")
	check(not CharacterDocument.load_file("user://absent-character.json").ok, "missing file yields validation error")
	var exact = JSON.stringify(CharacterDocument.document(fields))
	exact += " ".repeat(CharacterDocument.MAX_BYTES - exact.to_utf8_buffer().size())
	_write("user://exact-character.json", exact)
	check(CharacterDocument.load_file("user://exact-character.json").ok, "bounded read accepts exact 32 KiB file")
	for invalid_bytes in [[0xff], [0xc0, 0x80], [0xc2], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0xe2, 0x28, 0xa1]]:
		var file = FileAccess.open("user://invalid-utf8-character.json", FileAccess.WRITE)
		file.store_buffer(PackedByteArray(invalid_bytes))
		file.close()
		check(not CharacterDocument.load_file("user://invalid-utf8-character.json").ok, "invalid UTF-8 rejected without decoder errors: " + str(invalid_bytes))
	if OS.get_name() == "Linux":
		var locked_folder = ProjectSettings.globalize_path("user://locked-character")
		DirAccess.make_dir_absolute(locked_folder)
		var locked_target = locked_folder.path_join("previous.json")
		_write(locked_target, "previous fixture bytes")
		check(FileAccess.set_unix_permissions(locked_folder, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_EXECUTE_OWNER) == OK, "lock isolated directory to force a real temporary-write failure")
		var failed = CharacterDocument.save_file(locked_target, fields)
		FileAccess.set_unix_permissions(locked_folder, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER)
		check(not failed.ok and FileAccess.get_file_as_string(locked_target) == "previous fixture bytes", "real I/O failure preserves previous export bytes")
		var link = ProjectSettings.globalize_path("user://linked-character.json")
		var directory = DirAccess.open(OS.get_user_data_dir())
		check(directory.create_link(ProjectSettings.globalize_path(path), link) == OK, "create isolated symlink fixture")
		var before = FileAccess.get_file_as_bytes(path)
		check(not CharacterDocument.save_file(link, fields).ok and FileAccess.get_file_as_bytes(path) == before, "export refuses symlink without touching its target")

func _progression(profile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field in ["xp", "level", "condition", "focus"]: result[field] = int(profile[field])
	for field in ["traits", "milestones"]: result[field] = profile[field]
	return result.duplicate(true)

func _edit_name(editor: CharacterEditor, value: String) -> void:
	editor.fields.name.text = value
	editor.fields.name.text_changed.emit(value)

func _layout(editor: CharacterEditor) -> void:
	if DisplayServer.get_name() == "headless":
		check(editor.size.x >= editor.min_size.x and editor.size.y >= editor.min_size.y, "dummy display honors minimum editor size")
	else:
		check(editor.size == Vector2i(1040, 740), "rendered editor remains exactly 1040x740 at viewport 1600x900: " + str(editor.size))
	for key in editor.fields:
		var control: Control = editor.fields[key]
		var rect = control.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= editor.size.x and rect.position.y >= 0 and rect.end.y <= editor.size.y, "visible field inside actual editor: " + key)
		check(control.size.y >= 40, "readable field target: " + key)
	for control in [editor.apply_button, editor.import_button, editor.export_button, editor.status]:
		check(control.get_global_rect().end.x <= editor.size.x and control.get_global_rect().end.y <= editor.size.y, "action/status within actual editor viewport: " + control.name)

func _ui_tests() -> void:
	var f4 = InputEventKey.new()
	f4.keycode = KEY_F4
	f4.pressed = true
	crew._unhandled_key_input(f4)
	await settle()
	var console: CrewConsole = crew._window
	check(is_instance_valid(console) and console.visible, "F4 opens live CrewConsole")
	var edit_button: Button
	for button in console.find_children("*", "Button", true, false):
		if button.text == "Editar ficha": edit_button = button
	check(edit_button != null, "F4 exposes real Editar ficha action")
	if edit_button == null: return
	edit_button.pressed.emit()
	await settle()
	var editor: CharacterEditor = get_first_node_in_group(CharacterEditor.EDITOR_GROUP)
	check(editor != null and editor.visible and editor.get_parent() == root, "editor opens outside rebuilt console body")
	check(editor.read_document().character == CharacterDocument.editable_from_profile(crew.profile()), "editor starts from own authoritative profile")
	_layout(editor)
	_edit_name(editor, "Ane Editada")
	editor.fields.approach.select(ExpeditionSystems.APPROACHES.find("temple"))
	editor.fields.approach.item_selected.emit(editor.fields.approach.selected)
	for skill in ExpeditionSystems.SKILLS: editor.fields[skill].value = sample().skills[skill]
	check(editor.budget_label.text.begins_with("12 / 12") and not editor.apply_button.disabled, "live twelve point budget enables apply")
	editor.fields.combate.value = 3
	check(editor.budget_label.text.contains("exceso") and editor.apply_button.disabled, "over-budget UI blocks apply")
	var before = crew.profile().duplicate(true)
	editor.apply_changes()
	check(crew.profile() == before, "programmatic invalid apply cannot mutate profile")
	editor.fields.combate.value = 2
	var draft = editor.read_document()
	editor.fields.name.grab_focus()
	for _i in 4:
		expedition.updated.emit()
		crew.updated.emit()
		await settle()
	check(editor.read_document() == draft and editor.fields.name.has_focus(), "periodic console updates preserve draft and keyboard focus")
	check(console._open_character_editor() == editor and get_nodes_in_group(CharacterEditor.EDITOR_GROUP).size() == 1, "reopen action focuses a single editor without resetting draft")
	var bad = draft.duplicate(true)
	bad.character.xp = 999
	check(not editor.import_document(bad) and editor.read_document() == draft, "failed schema import never changes draft")
	check(not editor.import_file("user://oversized-character.json") and editor.read_document() == draft, "failed disk import never changes draft")
	var imported = CharacterDocument.document(sample())
	check(editor.import_document(imported) and editor.import_dialog.visible and editor.read_document() == draft, "valid import requires confirmation over dirty draft")
	editor.import_dialog.get_cancel_button().pressed.emit()
	await settle()
	check(editor.read_document() == draft, "cancel import preserves draft")
	editor.import_document(imported)
	editor.import_dialog.get_ok_button().pressed.emit()
	await settle()
	check(editor.read_document() == imported and editor.is_dirty(), "confirm import replaces only the draft")
	check(crew.profile() == before, "import alone leaves live profile untouched")
	_edit_name(editor, "Ane Editada")
	editor.fields.approach.select(ExpeditionSystems.APPROACHES.find("temple"))
	var exported_draft = editor.read_document()
	check(editor.export_file("user://ui-character.json").ok and editor.is_dirty(), "export does not mark an unapplied draft clean")
	check(CharacterDocument.load_file("user://ui-character.json").document == exported_draft, "UI export roundtrip contains visible editable draft")
	# Real crew commands mutate progression while the authored draft stays open.
	crew.profile().xp = 9
	check(crew.command("trait_add", {"trait": "jakinmina"}).ok, "real trait acquired during edit")
	check(crew.command("check", {"skill": "ciencia", "difficulty": 5, "focus": true}).ok, "real XP/level change during edit")
	check(crew.command("condition", {"delta": -25}).ok, "real condition change during edit")
	check(crew.command("check", {"skill": "pilotaje", "difficulty": 5, "focus": true}).ok, "real focus consumption after level change")
	var progression = _progression(crew.profile())
	check(progression.level == 2 and not progression.milestones.is_empty() and progression.condition == 75 and progression.focus == 2, "fixture has changed level, milestone, traits, condition and focus")
	var other = expedition.profile("other-fixture").duplicate(true)
	editor.apply_button.pressed.emit()
	await settle()
	check(editor.last_apply_state == "confirmed" and not editor.pending and not editor.is_dirty(), "offline apply confirms matching actual state, not just send")
	check(CharacterDocument.editable_from_profile(crew.profile()) == exported_draft.character, "controls change real own profile name/approach/all five skills")
	check(_progression(crew.profile()) == progression, "apply preserves all six progression fields at their latest values")
	check(expedition.profile("other-fixture") == other, "own apply leaves another actor profile untouched")
	check(FileAccess.file_exists(ExpeditionSystems.PATH), "profile_set persists standalone expedition state")
	expedition._load()
	check(_progression(crew.profile()) == progression and CharacterDocument.editable_from_profile(crew.profile()) == exported_draft.character, "persisted authored fields and live progression reload together")
	_layout(editor)
	var arguments = OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and "--capture-to" in arguments:
		await RenderingServer.frame_post_draw
		var capture_path = arguments[arguments.find("--capture-to") + 1]
		check(root.get_texture().get_image().save_png(capture_path) == OK, "capture rendered editor")
		print("CHARACTER_EDITOR_CAPTURE_OK ", capture_path)
	editor.request_close()
	await settle()
	check(not is_instance_valid(editor), "clean editor closes without discard prompt")
	editor = console._open_character_editor()
	await settle()
	check(editor.read_document() == exported_draft and not editor.is_dirty(), "reopen starts with applied persisted profile")
	_edit_name(editor, "Borrador que conservar")
	var retained = editor.read_document()
	# The historical F4 console may be destroyed independently of the root draft.
	crew._unhandled_key_input(f4)
	await settle()
	check(not is_instance_valid(console) and is_instance_valid(editor) and editor.read_document() == retained, "closing F4 console cannot destroy draft")
	editor.close_requested.emit()
	check(editor.discard_dialog.visible and not editor.is_queued_for_deletion(), "window close requires dirty discard confirmation")
	editor.discard_dialog.get_cancel_button().pressed.emit()
	await settle()
	check(is_instance_valid(editor) and editor.read_document() == retained, "cancel close preserves full draft")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	editor._input(escape)
	check(editor.discard_dialog.visible, "Escape follows same discard confirmation")
	editor.discard_dialog.get_ok_button().pressed.emit()
	await settle()
	check(not is_instance_valid(editor), "confirmed discard closes safely")
	crew._unhandled_key_input(f4)
	await settle()
	console = crew._window
	editor = console._open_character_editor()
	await settle()
	check(editor.read_document() == exported_draft, "discarded edits do not return on reopen")
	editor.request_close()
	crew._unhandled_key_input(f4)
	await settle()

func _pending_tests() -> void:
	var fake = DelayedExpedition.new()
	fake.data = {"profiles": {"self": sample()}}
	root.add_child(fake)
	var editor = CharacterEditor.new()
	editor.expedition = fake
	root.add_child(editor)
	editor.popup_centered(Vector2i(1040, 740))
	await settle()
	_edit_name(editor, "Pendiente")
	var draft = editor.read_document()
	editor.apply_changes()
	check(editor.pending and editor.last_apply_state == "pending", "send-only response never declares apply success")
	check(fake.received.operation == "profile_set" and fake.received.args == CharacterDocument.command_args(draft.character), "UI dispatches only profile_set with exact editable fields")
	check(editor.apply_button.disabled and not editor.fields.name.editable and editor.import_button.disabled, "pending request locks mutation and duplicate send")
	editor.apply_changes()
	check(fake.calls == 1, "pending apply cannot reenter command")
	fake.notice.emit("Orden enviada al anfitrión.", true)
	fake.updated.emit()
	check(editor.pending and editor.last_apply_state == "pending", "notice plus mismatched snapshot is not success")
	fake.notice.emit("Otra orden falló.", false)
	check(editor.pending, "uncorrelated negative notice cannot cancel an unrelated request")
	editor._process(CharacterEditor.CONFIRM_TIMEOUT)
	check(not editor.pending and editor.last_apply_state == "timeout" and editor.read_document() == draft and editor.is_dirty(), "timeout is explicit and preserves draft")
	check(editor.status.text.contains("no se ha cancelado"), "timeout explains possible late application")
	fake.data.profiles.self = draft.character.duplicate(true)
	fake.updated.emit()
	check(editor.last_apply_state == "confirmed" and not editor.is_dirty() and editor.status.text.contains("tardía"), "late matching snapshot confirms without overwriting draft")
	_edit_name(editor, "Otra solicitud")
	editor.apply_changes()
	editor.request_close()
	check(editor.discard_dialog.visible and editor.discard_dialog.dialog_text.contains("NO la cancela"), "pending close warns that host request cannot be canceled")
	editor.discard_dialog.get_cancel_button().pressed.emit()
	await settle()
	session.mode = "client"
	editor._process(0.0)
	check(editor.last_apply_state == "blocked" and not editor.pending and editor.apply_button.disabled, "session identity/mode change blocks accidental new target apply")
	editor.apply_changes()
	check(fake.calls == 2, "changed identity cannot dispatch another command")
	session.mode = "offline"
	editor.queue_free()
	fake.queue_free()
	await settle()

func run() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("Use the isolated runner: XDG_DATA_HOME must point at disposable test data.")
		quit(2)
		return
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	session = root.get_node("Session")
	expedition = root.get_node("Expedition")
	crew = root.get_node("Crew")
	session.set_process(false)
	expedition.set_process(false)
	crew.set_process(false)
	expedition.data = expedition._default_data()
	session.new_campaign()
	session.role = "mando"
	crew.profile()
	_schema_tests()
	_file_tests()
	await _ui_tests()
	await _pending_tests()
	print("CHARACTER_EDITOR_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
