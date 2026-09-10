extends Control
## Local pointer ownership; never writes shared InputMap state or game state.
var controls: Node
var enabled = false
var walking = false
var movement = Vector2.ZERO
var sprinting = false
var _look_delta = Vector2.ZERO
var _pointers: Dictionary = {}
var _stick_origin = Vector2.ZERO
var _deck: Node
var _swallowed: Dictionary = {}
var _suppress_mouse = false
const STICK_RADIUS = 78.0

func _ready() -> void:
	name = "TouchControls"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	enabled = DisplayServer.is_touchscreen_available()
	visible = false

func set_enabled(value: bool) -> void:
	stop_walking()
	enabled = value
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var app = get_tree().root.get_node_or_null("Lagunak")
	_deck = app.get("_deck") if app != null else null
	var usable = enabled and is_instance_valid(_deck) and _deck.is_visible_in_tree() and not controls.gameplay_blocked()
	if not usable: stop_walking()
	visible = usable
	queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		stop_walking()
		_swallowed.clear()
		_suppress_mouse = false

func stop_walking() -> void:
	walking = false
	movement = Vector2.ZERO
	_look_delta = Vector2.ZERO
	sprinting = false
	_pointers.clear()
	queue_redraw()

func take_look_delta() -> Vector2:
	var delta = _look_delta
	_look_delta = Vector2.ZERO
	return delta

func regions() -> Dictionary:
	# Anchored in logical viewport coordinates, independent of stretch/physical DPI.
	var width = size.x
	var height = size.y
	return {
		"mode": Rect2(Vector2(width * 0.5 - 90, height - 82), Vector2(180, 62)),
		"settings": Rect2(Vector2(width - 180, 24), Vector2(156, 62)),
		"interact": Rect2(Vector2(width - 186, height - 172), Vector2(162, 64)),
		"sprint": Rect2(Vector2(width - 186, height - 250), Vector2(162, 64)),
		"move": Rect2(Vector2(24, height - 300), Vector2(240, 204)),
		"look": Rect2(Vector2(width * 0.45, 110), Vector2(width * 0.55 - 24, height - 206))
	}

func consume(event: InputEvent) -> bool:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION and (walking or _suppress_mouse): return true
	if event is InputEventScreenTouch and (not event.pressed or event.canceled) and _swallowed.has(event.index):
		_release(event.index)
		_swallowed.erase(event.index)
		_clear_mouse_suppression.call_deferred()
		return true
	if not enabled or not is_visible_in_tree(): return false
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag): return false
	if event.index < 0 or event.index > 31: return true
	if event is InputEventScreenTouch and (not event.pressed or event.canceled):
		var owned = _pointers.has(event.index)
		_release(event.index)
		return owned or walking
	if not event.position.is_finite(): return true
	if controls.gameplay_blocked():
		stop_walking()
		return false
	if event is InputEventScreenTouch:
		if _pointers.has(event.index): return true
		var area = regions()
		if walking or area.mode.has_point(event.position):
			_swallowed[event.index] = true
			_suppress_mouse = true
		if area.mode.has_point(event.position):
			if walking: stop_walking()
			else:
				walking = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				get_viewport().gui_release_focus()
			return true
		if not walking: return false
		if area.settings.has_point(event.position):
			stop_walking()
			controls.open_settings()
			return true
		if area.interact.has_point(event.position):
			_pointers[event.index] = "interact"
			_emit_action.call_deferred("interact")
			return true
		if area.sprint.has_point(event.position) and not _pointers.values().has("sprint"):
			_pointers[event.index] = "sprint"
			sprinting = true
			return true
		if area.move.has_point(event.position) and not _pointers.values().has("move"):
			_pointers[event.index] = "move"
			_stick_origin = event.position
			return true
		if area.look.has_point(event.position) and not _pointers.values().has("look"):
			_pointers[event.index] = "look"
			return true
		return true
	if not _pointers.has(event.index): return walking
	match _pointers[event.index]:
		"move": movement = ((event.position - _stick_origin) / STICK_RADIUS).limit_length()
		"look":
			if event.relative.is_finite(): _look_delta = (_look_delta + event.relative).limit_length(400)
	queue_redraw()
	return true

func _release(index: int) -> void:
	match _pointers.get(index, ""):
		"move": movement = Vector2.ZERO
		"sprint": sprinting = false
	_pointers.erase(index)

func _clear_mouse_suppression() -> void:
	_suppress_mouse = not _swallowed.is_empty()

func _emit_action(action: String) -> void:
	if not walking or not enabled or controls.gameplay_blocked(): return
	var event = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var release = InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

func _draw() -> void:
	if not enabled: return
	var area = regions()
	_button(area.mode, "Menús" if walking else "Caminar")
	if not walking: return
	_button(area.settings, "Controles")
	_button(area.interact, "Interactuar")
	_button(area.sprint, "Correr", sprinting)
	var center: Vector2 = area.move.get_center()
	draw_circle(center, STICK_RADIUS, Color(0.04, 0.12, 0.17, 0.8))
	draw_arc(center, STICK_RADIUS, 0, TAU, 64, ConsoleUI.TEAL, 2.0, true)
	draw_circle(center + movement * (STICK_RADIUS - 24), 24, ConsoleUI.TEAL)
	_text(center + Vector2(-42, STICK_RADIUS + 27), "Caminar")
	_text(area.look.position + Vector2(16, 28), "Desliza para mirar")

func _button(rect: Rect2, label: String, active: bool = false) -> void:
	draw_style_box(ConsoleUI.button_style(ConsoleUI.TEAL if active else Color(0.04, 0.12, 0.17, 0.94), ConsoleUI.TEAL), rect)
	var font = ThemeDB.fallback_font
	var width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, rect.get_center() + Vector2(-width * 0.5, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ConsoleUI.BG if active else ConsoleUI.TEXT)

func _text(position: Vector2, label: String) -> void:
	draw_string(ThemeDB.fallback_font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ConsoleUI.TEXT)
