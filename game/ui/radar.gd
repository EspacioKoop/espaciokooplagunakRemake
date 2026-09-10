class_name Radar
extends Control
signal contact_selected(id: String)
signal empty_clicked(position: Vector2)
signal contact_moved(id: String, position: Vector2)

var data: Dictionary = {}
var selected = ""
var range_m = 1600.0
var editable = false
var reduced_motion = false
var show_labels = false
var _drag = ""
var _ghost = Vector2.ZERO
var _clock = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO: custom_minimum_size = Vector2(240, 180)
	gui_input.connect(_input_radar)

func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()

func _scale() -> float:
	return (minf(size.x, size.y) * 0.5 - 28.0) / range_m

func to_screen(position: Array) -> Vector2:
	var center: Array = data.get("ship", {}).get("position", [0, 0])
	return size * 0.5 + Vector2(position[0] - center[0], position[1] - center[1]) * _scale()

func to_world(position: Vector2) -> Vector2:
	var center: Array = data.get("ship", {}).get("position", [0, 0])
	return (position - size * 0.5) / maxf(_scale(), 0.001) + Vector2(center[0], center[1])

func _draw() -> void:
	var center = size * 0.5
	var radius = minf(size.x, size.y) * 0.5 - 28.0
	if radius <= 0: return
	draw_rect(Rect2(Vector2.ZERO, size), Color("0a1823"))
	for i in range(1, 5):
		draw_arc(center, radius * i / 4.0, 0, TAU, 96, ConsoleUI.LINE, 1, true)
	for angle in range(0, 360, 30):
		var direction = Vector2.from_angle(deg_to_rad(angle))
		draw_line(center + direction * 10, center + direction * radius, Color("19313b"), 1, true)
	if not reduced_motion and not editable:
		var direction = Vector2.from_angle(_clock * 0.25)
		draw_line(center, center + direction * radius, Color(0.3, 0.7, 0.65, 0.28), 2, true)
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(14, 24), "%d m" % range_m, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ConsoleUI.MUTED)
	draw_string(font, Vector2(center.x - 5, 20), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ConsoleUI.MUTED)
	var heading = deg_to_rad(float(data.get("ship", {}).get("heading", 0)))
	var arrow = PackedVector2Array([Vector2(10, 0).rotated(heading), Vector2(-7, -6).rotated(heading), Vector2(-4, 0).rotated(heading), Vector2(-7, 6).rotated(heading)])
	for i in arrow.size(): arrow[i] += center
	draw_colored_polygon(arrow, ConsoleUI.TEAL)
	for c in data.get("contacts", []):
		if c.get("hull", 100) <= 0: continue
		var p = to_screen([_ghost.x, _ghost.y]) if _drag == c.id else to_screen(c.position)
		if p.distance_to(center) > radius: continue
		var color = {"hostile": ConsoleUI.RED, "station": ConsoleUI.TEAL, "friendly": ConsoleUI.TEAL, "unknown": ConsoleUI.MUTED, "anomaly": Color("bb9bde")}.get(c.kind, ConsoleUI.AMBER)
		if c.kind == "station": draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), color, false, 2)
		else: draw_circle(p, 4.5, color)
		if selected == c.id:
			draw_arc(p, 12, 0, TAU, 32, color, 2, true)
			draw_line(center, p, Color(color, 0.25), 1, true)
		if show_labels or selected == c.id: draw_string(font, p + Vector2(14, -7), c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

	for point in data.get("operations", {}).get("waypoints", []):
		var p = to_screen(point.position)
		if p.distance_to(center) <= radius:
			draw_line(p - Vector2(6, 0), p + Vector2(6, 0), ConsoleUI.AMBER, 2)
			draw_line(p - Vector2(0, 6), p + Vector2(0, 6), ConsoleUI.AMBER, 2)
			if show_labels: draw_string(font, p + Vector2(12, 0), point.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ConsoleUI.AMBER)

func _input_radar(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _drag.is_empty(): _ghost = to_world(event.position)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: range_m = maxf(250, range_m / 1.25)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: range_m = minf(16000, range_m * 1.25)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var closest = ""
				var distance = 20.0
				for c in data.get("contacts", []):
					var d = event.position.distance_to(to_screen(c.position))
					if d < distance:
						distance = d
						closest = c.id
				if closest.is_empty(): empty_clicked.emit(to_world(event.position))
				else:
					contact_selected.emit(closest)
					if editable:
						_drag = closest
						_ghost = to_world(event.position)
			elif not _drag.is_empty():
				contact_moved.emit(_drag, to_world(event.position))
				_drag = ""
