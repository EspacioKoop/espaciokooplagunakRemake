class_name ScreenShortcutProfile
extends RefCounted
## Keyboard shortcuts are local UI preferences, never campaign/network data.
## Movement/gamepad preferences retain their existing v1 document unchanged.

const Movement = preload("res://input/control_profile.gd")
const FORMAT = "lagunak-screen-shortcuts"
const VERSION = 1
const MAX_BYTES = 16384
const CTRL = 1
const ALT = 2
const SHIFT = 4
const PREFIX = "screen_"
const ACTIONS = [
	"help", "expedition", "sensors", "crew", "fleet", "combat", "armaments", "thrusters",
	"save", "fullscreen", "audio", "avatar",
	"page_home", "page_bridge", "page_deck", "page_atlas", "page_campaign", "page_editor", "page_sessions", "page_settings",
	"role_mando", "role_navegacion", "role_ingenieria", "role_armas", "role_sensores", "role_comunicaciones", "role_enlace", "role_danos"
]
const LABELS = {
	"help": "Guía de la tripulación", "expedition": "Crónica y bestiario", "sensors": "Sensores avanzados",
	"crew": "Ficha de tripulación", "fleet": "Flotas y facciones", "combat": "Combate táctico",
	"armaments": "Montajes y torretas", "thrusters": "Maniobra lateral", "save": "Guardar partida ahora",
	"fullscreen": "Pantalla completa", "audio": "Música y sonido", "avatar": "Personalizar avatar",
	"page_home": "Inicio", "page_bridge": "Puente", "page_deck": "Cubierta", "page_atlas": "Atlas",
	"page_campaign": "Campaña", "page_editor": "Editor", "page_sessions": "Sesión", "page_settings": "Ajustes",
	"role_mando": "Puesto: mando", "role_navegacion": "Puesto: navegación", "role_ingenieria": "Puesto: ingeniería",
	"role_armas": "Puesto: armas", "role_sensores": "Puesto: sensores", "role_comunicaciones": "Puesto: comunicaciones",
	"role_enlace": "Puesto: enlace", "role_danos": "Puesto: control de daños"
}

static func defaults() -> Dictionary:
	var bindings = {}
	var keys = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F10, KEY_F11, KEY_F12, KEY_A]
	for index in 12:
		bindings[ACTIONS[index]] = binding(keys[index], ALT if index == 11 else 0)
	for index in 8:
		bindings[ACTIONS[12 + index]] = binding(KEY_1 + index, ALT)
		bindings[ACTIONS[20 + index]] = binding(KEY_1 + index)
	return {"format": FORMAT, "version": VERSION, "bindings": bindings}

static func binding(key: int = 0, modifiers: int = 0) -> Dictionary:
	return {"key": key, "modifiers": modifiers}

static func valid_key(value: Variant) -> bool:
	if not Movement.integral(value, 0, KEY_SPECIAL + 255): return false
	var key = int(value)
	if key == 0: return true
	if key == KEY_F9: return false
	return (key >= KEY_A and key <= KEY_Z) or (key >= KEY_0 and key <= KEY_9) or (key >= KEY_F1 and key <= KEY_F24) or key in [KEY_INSERT, KEY_DELETE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]

static func validate(data: Variant, movement: Dictionary = {}) -> String:
	if not data is Dictionary or data.size() != 3 or data.get("format") != FORMAT:
		return "Formato de atajos inválido."
	if not Movement.integral(data.get("version"), VERSION, VERSION): return "Versión de atajos incompatible."
	if not movement.is_empty() and not Movement.validate(movement).is_empty(): return "Perfil de movimiento inválido."
	var bindings: Variant = data.get("bindings")
	if not bindings is Dictionary or bindings.size() != ACTIONS.size(): return "Faltan acciones de pantalla."
	var used = {}
	for action in ACTIONS:
		var entry: Variant = bindings.get(action)
		if not entry is Dictionary or entry.size() != 2 or not valid_key(entry.get("key")) or not Movement.integral(entry.get("modifiers"), 0, 7):
			return "Asignación de pantalla no válida."
		var key = int(entry.key)
		var modifiers = int(entry.modifiers)
		if key == 0:
			if modifiers != 0: return "Un atajo desactivado no puede tener modificadores."
			continue
		if key == KEY_F4 and (modifiers & ALT) != 0: return "Alt+F4 se reserva para cerrar la ventana."
		var token = "%d:%d" % [key, modifiers]
		if used.has(token): return "Atajo ya asignado a «%s»." % LABELS[used[token]]
		used[token] = action
		# Modified chords release character control before opening their target.
		# Plain movement keys must remain exclusive in both settings panels.
		if modifiers == 0 and not movement.is_empty():
			for move_action in Movement.ACTIONS:
				if int(movement.bindings[move_action].key) == key:
					return "La tecla ya se usa para «%s»." % Movement.LABELS[move_action]
	return ""

static func normalize(data: Dictionary) -> Dictionary:
	var result = data.duplicate(true)
	result.version = int(result.version)
	for action in ACTIONS:
		result.bindings[action].key = int(result.bindings[action].key)
		result.bindings[action].modifiers = int(result.bindings[action].modifiers)
	return result

static func event_binding(event: InputEvent) -> Dictionary:
	if not event is InputEventKey or not event.pressed or event.echo or event.meta_pressed: return {}
	var key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == 0 or not valid_key(key): return {}
	var modifiers = (CTRL if event.ctrl_pressed else 0) | (ALT if event.alt_pressed else 0) | (SHIFT if event.shift_pressed else 0)
	return binding(key, modifiers)

static func event_for(entry: Dictionary) -> InputEventKey:
	var event = InputEventKey.new()
	event.physical_keycode = int(entry.key)
	event.ctrl_pressed = (int(entry.modifiers) & CTRL) != 0
	event.alt_pressed = (int(entry.modifiers) & ALT) != 0
	event.shift_pressed = (int(entry.modifiers) & SHIFT) != 0
	return event

static func install(data: Dictionary) -> bool:
	if not validate(data).is_empty(): return false
	for action in ACTIONS:
		var name = PREFIX + action
		if not InputMap.has_action(name): InputMap.add_action(name)
		Input.action_release(name)
		InputMap.action_erase_events(name)
		if int(data.bindings[action].key) != 0:
			InputMap.action_add_event(name, event_for(data.bindings[action]))
	return true

static func action_for(event: InputEvent) -> String:
	if not event is InputEventKey or not event.pressed or event.echo or event.meta_pressed: return ""
	var candidate = event.duplicate() as InputEventKey
	if candidate.physical_keycode == 0: candidate.physical_keycode = candidate.keycode
	for action in ACTIONS:
		var name = PREFIX + action
		if InputMap.has_action(name) and candidate.is_action_pressed(name, false, true): return action
	return ""

static func label(entry: Dictionary) -> String:
	if int(entry.key) == 0: return "Sin asignar"
	var text = ""
	if (int(entry.modifiers) & CTRL) != 0: text += "Ctrl+"
	if (int(entry.modifiers) & ALT) != 0: text += "Alt+"
	if (int(entry.modifiers) & SHIFT) != 0: text += "Mayús+"
	return text + OS.get_keycode_string(int(entry.key))

static func load_file(path: String, movement: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path): return {"profile": defaults(), "error": ""}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"profile": defaults(), "error": "No se pudo leer el perfil de atajos."}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"profile": defaults(), "error": "El perfil de atajos supera el límite permitido."}
	var text = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(text) != OK: return {"profile": defaults(), "error": "Formato de atajos inválido."}
	var error = validate(parser.data, movement)
	return {"profile": defaults() if not error.is_empty() else normalize(parser.data), "error": error}

static func save_file(path: String, data: Dictionary, movement: Dictionary = {}) -> Error:
	if not validate(data, movement).is_empty(): return ERR_INVALID_DATA
	var text = JSON.stringify(normalize(data), "\t")
	if text.to_utf8_buffer().size() > MAX_BYTES: return ERR_INVALID_DATA
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK: DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return error
