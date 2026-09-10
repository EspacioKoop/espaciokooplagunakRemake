extends Node
## Scale 2D text per Control, without modifying shared Theme resources or 3D views.
## Baselines and weak references prevent cumulative scaling and retain no freed UI.
signal changed
const Profile = preload("res://input/readability_profile.gd")
var profile_path = "user://readability-v1.json"
var profile: Dictionary = Profile.defaults()
var load_error = ""
var _entries: Dictionary = {}
var _applying = false
var _stopping = false

func _ready() -> void:
	name = "Readability"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--test" in OS.get_cmdline_user_args(): profile_path = "user://readability-test-v1.json"
	var loaded = Profile.load_file(profile_path)
	profile = loaded.profile
	load_error = loaded.error
	get_tree().node_added.connect(_node_added)
	call_deferred("_scan_existing")

func commit_text_percent(value: Variant) -> String:
	var candidate = Profile.defaults()
	candidate.text_percent = value
	var error = Profile.validate(candidate)
	if not error.is_empty(): return error
	if Profile.save_file(profile_path, candidate) != OK:
		return "No se pudo guardar el tamaño del texto. Se conserva el ajuste anterior."
	profile = candidate
	load_error = ""
	for id in _entries.keys(): _refresh(id)
	changed.emit()
	return ""

func _scan_existing() -> void:
	if not _stopping and is_inside_tree(): _walk(get_tree().root)

func _walk(node: Node) -> void:
	_register(weakref(node))
	for child in node.get_children(true): _walk(child)

func _node_added(node: Node) -> void:
	# Ready-time themes and explicit overrides must exist before taking a baseline.
	if node is Control: call_deferred("_register", weakref(node))

func _fonts(control: Control) -> Array:
	if control is RichTextLabel:
		return ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]
	if control is Label or control is Button or control is LineEdit or control is TextEdit or control is ItemList or control is Tree or control is TabBar or control is MenuBar:
		return ["font_size"]
	return []

func _eligible(control: Control) -> bool:
	if not control.is_inside_tree() or control.is_queued_for_deletion(): return false
	# SubViewport text can be physical table cards or world art; leave it untouched.
	if not control.get_viewport() is Window: return false
	var ancestor: Node = control
	while ancestor != null:
		if ancestor.get_meta("readability_exempt", false): return false
		ancestor = ancestor.get_parent()
	return true

func _register(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if _stopping or not is_instance_valid(node) or not node is Control: return
	if not _eligible(node): return
	var id = node.get_instance_id()
	if _entries.has(id): return
	var fields = {}
	for font in _fonts(node):
		fields[font] = {"had": node.has_theme_font_size_override(font), "base": node.get_theme_font_size(font), "owned": false, "expected": 0}
	if fields.is_empty(): return
	_entries[id] = {"reference": reference, "fonts": fields, "queued": false}
	node.theme_changed.connect(_queue_refresh.bind(id))
	node.tree_exiting.connect(_remove.bind(id))
	_refresh(id)

func _queue_refresh(id: int) -> void:
	if _applying or _stopping or not _entries.has(id) or _entries[id].queued: return
	_entries[id].queued = true
	call_deferred("_refresh", id)

func _refresh(id: int) -> void:
	if _stopping or not _entries.has(id): return
	var entry: Dictionary = _entries[id]
	entry.queued = false
	var control = entry.reference.get_ref()
	if not is_instance_valid(control):
		_entries.erase(id)
		return
	_applying = true
	for font in entry.fonts:
		var field: Dictionary = entry.fonts[font]
		var has_override: bool = control.has_theme_font_size_override(font)
		var current: int = control.get_theme_font_size(font)
		var ours: bool = field.owned and has_override and current == field.expected
		if not ours:
			# Respect an explicit size changed by the owning screen after registration.
			field.had = has_override
			field.base = current
		elif not field.had:
			# Remove only our override to observe a changed inherited Theme baseline.
			control.remove_theme_font_size_override(font)
			field.base = control.get_theme_font_size(font)
		var percent: int = int(profile.text_percent) if _eligible(control) else 100
		if percent == 100:
			if ours:
				if field.had: control.add_theme_font_size_override(font, field.base)
				else: control.remove_theme_font_size_override(font)
			field.owned = false
			field.expected = field.base
		else:
			field.expected = maxi(1, roundi(float(field.base) * percent / 100.0))
			if not control.has_theme_font_size_override(font) or control.get_theme_font_size(font) != field.expected:
				control.add_theme_font_size_override(font, field.expected)
			field.owned = true
	_applying = false

func _restore(entry: Dictionary) -> void:
	var control = entry.reference.get_ref()
	if not is_instance_valid(control): return
	for font in entry.fonts:
		var field: Dictionary = entry.fonts[font]
		if not field.owned or not control.has_theme_font_size_override(font) or control.get_theme_font_size(font) != field.expected: continue
		if field.had: control.add_theme_font_size_override(font, field.base)
		else: control.remove_theme_font_size_override(font)

func _remove(id: int) -> void:
	if not _entries.has(id): return
	var entry: Dictionary = _entries[id]
	var control = entry.reference.get_ref()
	_applying = true
	_restore(entry)
	if is_instance_valid(control):
		control.theme_changed.disconnect(_queue_refresh.bind(id))
		control.tree_exiting.disconnect(_remove.bind(id))
	_entries.erase(id)
	_applying = false

func _exit_tree() -> void:
	_stopping = true
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
	for id in _entries.keys(): _remove(id)
