class_name ControlProfile
extends RefCounted
## Local preferences only. Never contains campaign or multiplayer state.

const VERSION = 1
const MAX_BYTES = 32768
const ACTIONS = ["move_forward", "move_back", "move_left", "move_right", "look_up", "look_down", "look_left", "look_right", "sprint", "interact", "capture_pointer", "release_pointer", "controls_settings"]
const LABELS = {
	"move_forward": "Avanzar", "move_back": "Retroceder", "move_left": "Izquierda", "move_right": "Derecha",
	"look_up": "Mirar arriba", "look_down": "Mirar abajo", "look_left": "Mirar izquierda", "look_right": "Mirar derecha",
	"sprint": "Correr", "interact": "Interactuar / levantarse", "capture_pointer": "Controlar personaje", "release_pointer": "Liberar ratón", "controls_settings": "Controles"
}
const RESERVED = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F10, KEY_F11, KEY_F12]

static func defaults() -> Dictionary:
	var bindings = {}
	var keys = [KEY_W, KEY_S, KEY_A, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_E, KEY_C, KEY_ESCAPE, KEY_F9]
	var pads = [axis(JOY_AXIS_LEFT_Y, -1), axis(JOY_AXIS_LEFT_Y, 1), axis(JOY_AXIS_LEFT_X, -1), axis(JOY_AXIS_LEFT_X, 1), axis(JOY_AXIS_RIGHT_Y, -1), axis(JOY_AXIS_RIGHT_Y, 1), axis(JOY_AXIS_RIGHT_X, -1), axis(JOY_AXIS_RIGHT_X, 1), button(JOY_BUTTON_LEFT_STICK), button(JOY_BUTTON_A), button(JOY_BUTTON_START), button(JOY_BUTTON_B), button(JOY_BUTTON_BACK)]
	for i in ACTIONS.size(): bindings[ACTIONS[i]] = {"key": keys[i], "pad": pads[i]}
	return {"version": VERSION, "locale": "es", "mouse_sensitivity": 1.0, "gamepad_sensitivity": 1.0, "deadzone": 0.2, "invert_y": false, "bindings": bindings}

static func axis(code: int, direction: int) -> Dictionary:
	return {"kind": "axis", "code": code, "direction": direction}

static func button(code: int) -> Dictionary:
	return {"kind": "button", "code": code}

static func integral(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

static func valid_key(value: Variant) -> bool:
	if not integral(value, 1, KEY_SPECIAL + 255): return false
	var code = int(value)
	return (code >= KEY_SPACE and code <= KEY_ASCIITILDE) or code in [KEY_TAB, KEY_BACKSPACE, KEY_ENTER, KEY_INSERT, KEY_DELETE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_ESCAPE, KEY_F9]

static func valid_pad(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.get("kind") == "button": return value.size() == 2 and integral(value.get("code"), 0, JOY_BUTTON_MAX - 1)
	if value.get("kind") == "axis": return value.size() == 3 and integral(value.get("code"), 0, JOY_AXIS_TRIGGER_RIGHT) and integral(value.get("direction"), -1, 1) and int(value.direction) != 0
	return false

static func validate(data: Variant) -> String:
	if not data is Dictionary: return "Formato de controles inválido."
	if data.size() != 7 or not integral(data.get("version"), VERSION, VERSION): return "Versión de controles incompatible."
	if data.get("locale") not in ["es", "en"]: return "Idioma no válido."
	if not data.get("invert_y") is bool: return "Inversión no válida."
	for field in ["mouse_sensitivity", "gamepad_sensitivity", "deadzone"]:
		var value: Variant = data.get(field)
		var low = 0.05 if field == "deadzone" else 0.2
		var high = 0.6 if field == "deadzone" else 3.0
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < low or float(value) > high: return "Ajuste fuera de límites."
	var bindings: Variant = data.get("bindings")
	if not bindings is Dictionary or bindings.size() != ACTIONS.size(): return "Faltan acciones de entrada."
	var keys = {}
	var pads = {}
	for action in ACTIONS:
		var entry: Variant = bindings.get(action)
		if not entry is Dictionary or entry.size() != 2 or not valid_key(entry.get("key")) or not valid_pad(entry.get("pad")): return "Asignación no válida."
		var key = int(entry.key)
		if key == KEY_ESCAPE and action != "release_pointer": return "Escape se reserva para salir."
		if key == KEY_F9 and action != "controls_settings": return "F9 se reserva para recuperar controles."
		if key >= KEY_1 and key <= KEY_8: return "Las teclas 1–8 se reservan para los puestos."
		if keys.has(key): return "Tecla ya asignada."
		keys[key] = true
		var token = pad_token(entry.pad)
		if pads.has(token): return "Entrada de mando ya asignada."
		pads[token] = true
	return ""

static func pad_token(pad: Dictionary) -> String:
	return "%s:%d:%d" % [pad.kind, int(pad.code), int(pad.get("direction", 0))]

static func event_for_key(code: int) -> InputEventKey:
	var event = InputEventKey.new()
	event.physical_keycode = code
	return event

static func event_for_pad(pad: Dictionary) -> InputEvent:
	if pad.kind == "button":
		var event = InputEventJoypadButton.new()
		event.button_index = int(pad.code)
		event.device = -1
		return event
	var event = InputEventJoypadMotion.new()
	event.axis = int(pad.code)
	event.axis_value = int(pad.direction)
	event.device = -1
	return event

static func install(data: Dictionary) -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		Input.action_release(action)
		InputMap.action_erase_events(action)
		InputMap.action_set_deadzone(action, float(data.deadzone))
		InputMap.action_add_event(action, event_for_key(int(data.bindings[action].key)))
		InputMap.action_add_event(action, event_for_pad(data.bindings[action].pad))

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"profile": defaults(), "error": ""}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return {"profile": defaults(), "error": "No se pudo leer el perfil de controles."}
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK: return {"profile": defaults(), "error": "Formato de controles inválido."}
	var parsed: Variant = parser.data
	var error = validate(parsed)
	return {"profile": defaults() if not error.is_empty() else normalize(parsed), "error": error}

static func save_file(path: String, data: Dictionary) -> Error:
	if not validate(data).is_empty(): return ERR_INVALID_DATA
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

static func normalize(data: Dictionary) -> Dictionary:
	var result = data.duplicate(true)
	result.version = int(result.version)
	for action in ACTIONS:
		result.bindings[action].key = int(result.bindings[action].key)
		result.bindings[action].pad.code = int(result.bindings[action].pad.code)
		if result.bindings[action].pad.has("direction"): result.bindings[action].pad.direction = int(result.bindings[action].pad.direction)
	return result
