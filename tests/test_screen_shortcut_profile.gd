extends SceneTree

const Profile = preload("res://input/screen_shortcut_profile.gd")
const Movement = preload("res://input/control_profile.gd")
var checks = 0
var failures = 0
var path = "user://screen-shortcut-model-test.json"

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ", message)

func _event(key: int, modifiers: int = 0) -> InputEventKey:
	var event = Profile.event_for(Profile.binding(key, modifiers))
	event.keycode = key
	event.pressed = true
	return event

func _invalid(candidate: Variant, message: String) -> void:
	check(not Profile.validate(candidate, Movement.defaults()).is_empty(), message)

func _run() -> void:
	if "--test" not in OS.get_cmdline_user_args():
		print("FAIL test flag required")
		quit(1)
		return
	var defaults = Profile.defaults()
	check(Profile.validate(defaults, Movement.defaults()).is_empty(), "defaults coexist with old movement profile")
	check(Profile.ACTIONS.size() == 28, "28 explicit screen/page/station actions")
	check(Profile.LABELS.size() == Profile.ACTIONS.size(), "every action has a label")
	check(defaults.bindings.save.key == KEY_F10 and defaults.bindings.fleet.key == KEY_F5, "save and fleet do not share F5")
	check(defaults.bindings.avatar == Profile.binding(KEY_A, Profile.ALT), "avatar default is retained")
	var first = Profile.defaults()
	first.bindings.help.key = KEY_F24
	check(Profile.defaults().bindings.help.key == KEY_F1, "defaults do not alias")
	for value in [null, [], true, 1, "secret", {}]: _invalid(value, "reject non-document")
	for field in ["format", "version", "bindings"]:
		var candidate = defaults.duplicate(true)
		candidate.erase(field)
		_invalid(candidate, "required field " + field)
	for version in [0, 2, 1.5, true, "1", NAN, INF]:
		var candidate = defaults.duplicate(true)
		candidate.version = version
		_invalid(candidate, "unsupported/nonintegral version")
	var candidate = defaults.duplicate(true)
	candidate.extra = "not allowed"
	_invalid(candidate, "unknown document field")
	candidate = defaults.duplicate(true)
	candidate.bindings.erase("help")
	candidate.bindings.unknown = Profile.binding(KEY_F1)
	_invalid(candidate, "same-sized unknown action is rejected")
	for bad_key in [-1, true, "A", 65.5, NAN, INF, KEY_ESCAPE, KEY_F9, KEY_SHIFT, KEY_SPACE, KEY_TAB, KEY_ENTER]:
		candidate = defaults.duplicate(true)
		candidate.bindings.help.key = bad_key
		_invalid(candidate, "invalid/reserved key")
	for bad_modifiers in [-1, 8, true, "1", 0.5, NAN, INF]:
		candidate = defaults.duplicate(true)
		candidate.bindings.help.modifiers = bad_modifiers
		_invalid(candidate, "invalid modifiers")
	candidate = defaults.duplicate(true)
	candidate.bindings.help = Profile.binding(KEY_F4, Profile.ALT)
	_invalid(candidate, "OS close chord remains reserved")
	candidate = defaults.duplicate(true)
	candidate.bindings.help = Profile.binding(KEY_F2)
	_invalid(candidate, "duplicate key")
	candidate = defaults.duplicate(true)
	candidate.bindings.help = Profile.binding(KEY_W)
	_invalid(candidate, "unmodified movement collision")
	candidate.bindings.help = Profile.binding(KEY_W, Profile.CTRL)
	check(Profile.validate(candidate, Movement.defaults()).is_empty(), "explicit modified chord is distinct")
	candidate = defaults.duplicate(true)
	candidate.bindings.help = Profile.binding()
	candidate.bindings.sensors = Profile.binding()
	check(Profile.validate(candidate, Movement.defaults()).is_empty(), "multiple unbound actions allowed")
	candidate.bindings.help.modifiers = 1
	_invalid(candidate, "unbound chord cannot contain modifiers")
	candidate = defaults.duplicate(true)
	candidate.bindings.help = {"key": KEY_F1, "modifiers": 0, "method": "quit"}
	_invalid(candidate, "profile cannot inject callback names")
	var old_movement = Movement.defaults()
	var old_bytes = JSON.stringify(old_movement)
	check(Profile.validate(defaults, old_movement).is_empty(), "movement profile accepted")
	check(JSON.stringify(old_movement) == old_bytes, "validation does not mutate movement")
	var numeric = JSON.parse_string(JSON.stringify(defaults))
	check(Profile.validate(numeric).is_empty(), "JSON numeric representation accepted")
	var normalized = Profile.normalize(numeric)
	check(normalized.version is int and normalized.bindings.help.key is int, "normalization restores integers")
	normalized.bindings.help.key = KEY_F24
	check(numeric.bindings.help.key == KEY_F1, "normalization does not alias source")
	check(Profile.event_binding(_event(KEY_R, 7)) == Profile.binding(KEY_R, 7), "capture all supported modifiers")
	var event = _event(KEY_R)
	event.echo = true
	check(Profile.event_binding(event).is_empty(), "ignore repeated capture")
	event.echo = false
	event.pressed = false
	check(Profile.event_binding(event).is_empty(), "ignore release capture")
	event.pressed = true
	event.meta_pressed = true
	check(Profile.event_binding(event).is_empty(), "do not capture platform command chords")
	check(Profile.event_binding(InputEventMouseButton.new()).is_empty(), "ignore mouse capture")
	check(Profile.label(Profile.binding()) == "Sin asignar", "unbound label")
	check(Profile.label(Profile.binding(KEY_R, 7)) == "Ctrl+Alt+Mayús+R", "readable modifier label")
	check(Profile.install(defaults), "install valid InputMap")
	for action in Profile.ACTIONS:
		var key_event = Profile.event_for(defaults.bindings[action])
		key_event.pressed = true
		check(Profile.action_for(key_event) == action, "exact InputMap dispatch " + action)
	check(Profile.action_for(_event(KEY_F1, Profile.SHIFT)).is_empty(), "extra modifiers cannot activate plain shortcut")
	check(Profile.action_for(_event(KEY_F9)).is_empty(), "F9 belongs to recovery")
	event = _event(KEY_F1)
	event.echo = true
	check(Profile.action_for(event).is_empty(), "held shortcut does not repeat")
	candidate = defaults.duplicate(true)
	candidate.bindings.help = Profile.binding(KEY_R, Profile.CTRL)
	check(Profile.install(candidate), "install remapping")
	check(Profile.action_for(_event(KEY_F1)).is_empty(), "old binding removed from InputMap")
	check(Profile.action_for(_event(KEY_R, Profile.CTRL)) == "help", "new chord active")
	candidate.bindings.help = Profile.binding()
	check(Profile.install(candidate), "install disabled action")
	check(InputMap.action_get_events(Profile.PREFIX + "help").is_empty(), "disabled action erases old binding")
	candidate.version = 99
	check(not Profile.install(candidate), "invalid install rejected before changing actions")
	check(InputMap.action_get_events(Profile.PREFIX + "help").is_empty(), "invalid install preserves previous actions")
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(Profile.load_file(path).error.is_empty(), "missing profile is not an error")
	check(Profile.save_file(path, defaults, Movement.defaults()) == OK, "save valid local profile")
	var loaded = Profile.load_file(path, Movement.defaults())
	check(loaded.error.is_empty() and loaded.profile == defaults, "persistent round trip")
	var original = FileAccess.get_file_as_string(path)
	check(Profile.save_file(path, candidate) == ERR_INVALID_DATA, "invalid save refused")
	check(FileAccess.get_file_as_string(path) == original, "invalid save preserves previous bytes")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	loaded = Profile.load_file(path)
	check(not loaded.error.is_empty() and loaded.profile == defaults, "corrupt JSON safely falls back")
	check(FileAccess.get_file_as_string(path) == "{broken", "loading corruption does not overwrite evidence")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("x".repeat(Profile.MAX_BYTES + 1))
	file.close()
	check(not Profile.load_file(path).error.is_empty(), "oversized file rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.install(defaults)
	print("SCREEN_SHORTCUT_MODEL_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
