class_name DeckMap
extends Control
## Read-only projection of the real deck. Selecting a room draws a walking
## route; it never moves a player, opens a door or changes simulation state.

var deck: Node
var destination = -1
var _redraw_clock = 0.0
const LABELS = ["PUENTE", "PASILLO", "INGENIERÍA", "CAMAROTES", "BODEGA", "COMEDOR", "ENFERMERÍA"]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(300, 340)
	tooltip_text = "Pulsa una sala para marcar la ruta.\nFlechas: cambiar · Esc: borrar."

func _process(delta: float) -> void:
	_redraw_clock += delta
	if _redraw_clock >= 0.1 and is_visible_in_tree():
		_redraw_clock = 0.0
		queue_redraw()

func _scale_factor() -> float:
	return maxf(0.01, minf((size.x - 88.0) / ShipDeckLayout.MAP_BOUNDS.size.x, (size.y - 120.0) / ShipDeckLayout.MAP_BOUNDS.size.y))

func _point(position: Vector3) -> Vector2:
	var center = Vector2(size.x * 0.5, 40.0 + (size.y - 120.0) * 0.5)
	return center + (ShipDeckLayout.xz(position) - ShipDeckLayout.MAP_BOUNDS.get_center()) * _scale_factor()

func _world(point: Vector2) -> Vector3:
	var center = Vector2(size.x * 0.5, 40.0 + (size.y - 120.0) * 0.5)
	var projected = (point - center) / _scale_factor() + ShipDeckLayout.MAP_BOUNDS.get_center()
	return Vector3(projected.x, 0, projected.y)

func _polygon(world_points: PackedVector2Array) -> PackedVector2Array:
	var points = PackedVector2Array()
	for point in world_points: points.append(_point(Vector3(point.x, 0, point.y)))
	return points

func _outline(points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	var closed = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func _text(at: Vector2, text: String, color: Color, font_size: int = 10) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func select_destination(index: int) -> void:
	if index < -1 or index >= ShipDeckLayout.SHIP_COUNT: return
	destination = index
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var room = ShipDeckLayout.room_at(_world(event.position))
		if room >= 0: select_destination(-1 if room == destination else room)
		grab_focus()
		accept_event()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		select_destination(posmod(destination - 1, ShipDeckLayout.SHIP_COUNT))
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		select_destination(posmod(destination + 1, ShipDeckLayout.SHIP_COUNT))
		accept_event()
	elif event.is_action_pressed("ui_cancel"):
		select_destination(-1)
		release_focus()
		accept_event()

func _draw() -> void:
	if not is_instance_valid(deck): return
	draw_rect(Rect2(Vector2.ZERO, size), Color("101729ed"), true)
	draw_rect(Rect2(Vector2.ZERO, size), ConsoleUI.AMBER if has_focus() else ConsoleUI.LINE, false, 1.0)
	_text(Vector2(12, 20), "ITSASO  /  CUBIERTA 01", ConsoleUI.TEAL, 13)
	_text(Vector2(12, 35), "BABOR", ConsoleUI.MUTED, 9)
	_text(Vector2(size.x - 65, 35), "ESTRIBOR", ConsoleUI.MUTED, 9)
	var hull = _polygon(PackedVector2Array(ShipDeckLayout.HULL))
	draw_colored_polygon(hull, Color("192441"))
	_outline(hull, Color("6975ad"), 1.5)
	_text(_point(Vector3(0, 0, -50)) + Vector2(-14, -6), "PROA", ConsoleUI.TEAL, 9)
	_text(_point(Vector3(0, 0, 46)) + Vector2(-34, 8), "POPA · MOTORES", ConsoleUI.MUTED, 9)
	# The exterior nacelles are reference silhouettes, not fictitious walkable rooms.
	for x in [-23.0, 16.0]:
		var a = _point(Vector3(x, 0, 27))
		var b = _point(Vector3(x + 7.0, 0, 39))
		draw_rect(Rect2(a, b - a), Color("6975ad"), false, 1.0)
		for z in [31.0, 35.0, 39.0]:
			draw_line(_point(Vector3(x, 0, z)), _point(Vector3(x + 7.0, 0, z)), Color("6975ad"), 1.0)
	for link in deck._corridors.links:
		var points = _polygon(ShipDeckLayout.corridor_polygon(link))
		draw_colored_polygon(points, Color("345160"))
		_outline(points, ConsoleUI.MUTED)
	for i in ShipDeckLayout.SHIP_COUNT:
		var points = _polygon(ShipDeckLayout.room_polygon(i))
		draw_colored_polygon(points, Color("365866") if i == deck.zone else Color("233844"))
		_outline(points, ConsoleUI.AMBER if i == destination else ConsoleUI.TEAL, 1.5 if i == destination else 1.0)
		var point = _point(ShipDeckLayout.ZONES[i].at)
		_text(point + Vector2(-6, 4), "%02d" % (i + 1), ConsoleUI.TEXT)
		if i in [3, 4]:
			_text(Vector2(9, point.y + 4), LABELS[i], ConsoleUI.TEXT, 9)
			draw_line(Vector2(77, point.y), point - Vector2(17, 0), ConsoleUI.MUTED, 1.0)
		elif i in [5, 6]:
			_text(Vector2(size.x - 77, point.y + 4), LABELS[i], ConsoleUI.TEXT, 9)
			draw_line(point + Vector2(17, 0), Vector2(size.x - 81, point.y), ConsoleUI.MUTED, 1.0)
		elif i != 1:
			_text(point + Vector2(-26, 17), LABELS[i], ConsoleUI.TEXT, 9)
	if is_instance_valid(deck.body):
		var route = ShipDeckLayout.route(deck.body.position, destination)
		if route.size() > 1:
			var points = PackedVector2Array()
			for waypoint in route: points.append(_point(waypoint))
			draw_polyline(points, ConsoleUI.AMBER, 2.0, true)
			var distance = 0.0
			for i in range(1, route.size()): distance += route[i - 1].distance_to(route[i])
			_text(Vector2(12, size.y - 48), "Ruta: %s · %.0f m" % [ShipDeckLayout.ZONES[destination].name, distance], ConsoleUI.AMBER)
		else:
			_text(Vector2(12, size.y - 48), "Pulsa una sala para marcar el recorrido", ConsoleUI.MUTED)
		_draw_people()
	# A crossbar is closed; a displaced leaf is open. Not colour-only information.
	for door in deck._corridors.doors:
		var center = _point(door.position)
		var side = Vector2(cos(door.yaw), -sin(door.yaw)) * 1.55 * _scale_factor()
		if door.open:
			draw_line(center - side, center - side + side.orthogonal(), ConsoleUI.TEAL, 1.5, true)
		else:
			draw_line(center - side, center + side, ConsoleUI.AMBER, 2.0, true)
	_text(Vector2(12, size.y - 65), "Estás en: " + ShipDeckLayout.ZONES[deck.zone].name, ConsoleUI.TEXT, 11)
	_text(Vector2(12, size.y - 30), "Blanco: tú · Rojo: tripulación · Ámbar: ruta", ConsoleUI.MUTED, 9)
	_text(Vector2(12, size.y - 14), "Casco orientativo · Ocio: acceso desde pasillo", ConsoleUI.MUTED, 9)

func _draw_people() -> void:
	var player = _point(deck.body.position)
	var forward = Vector2(-sin(deck.body.rotation.y), -cos(deck.body.rotation.y))
	var side = forward.orthogonal()
	draw_colored_polygon(PackedVector2Array([player + forward * 6, player - forward * 3 + side * 3, player - forward * 3 - side * 3]), Color.WHITE)
	var session = get_tree().root.get_node_or_null("Session")
	if session == null: return
	for key in session.poses:
		if int(key) == multiplayer.get_unique_id(): continue
		var pose: Dictionary = session.poses[key]
		var coordinates: Array = pose.get("position", [])
		if coordinates.size() != 3: continue
		var remote = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		if ShipDeckLayout.contains(remote): draw_circle(_point(remote), 2.8, ConsoleUI.RED)
