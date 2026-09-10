class_name TacticalBoard
extends Control
## Interactive tactical board. Camera modes alter visibility and framing, not combat authority.

signal cell_pressed(x: int, y: int)
signal unit_pressed(id: String)

var combat: Node
var hover = Vector2i(-1, -1)

func _ready() -> void:
	custom_minimum_size = Vector2(650, 520)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_input_board)

func _process(_delta: float) -> void:
	queue_redraw()

func _rect_for_grid() -> Rect2:
	return Rect2(Vector2(18, 42), size - Vector2(36, 60))

func _cell_size() -> Vector2:
	var rect = _rect_for_grid()
	return Vector2(rect.size.x / GroundCombat.WIDTH, rect.size.y / GroundCombat.HEIGHT)

func _cell_at(position: Vector2) -> Vector2i:
	var rect = _rect_for_grid()
	if not rect.has_point(position): return Vector2i(-1, -1)
	var cell = _cell_size()
	return Vector2i(clampi(int((position.x - rect.position.x) / cell.x), 0, GroundCombat.WIDTH - 1), clampi(int((position.y - rect.position.y) / cell.y), 0, GroundCombat.HEIGHT - 1))

func _input_board(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = _cell_at(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell = _cell_at(event.position)
		if cell.x < 0: return
		if combat != null and not combat.state.is_empty():
			for unit in combat.state.units:
				if not unit.down and int(unit.position[0]) == cell.x and int(unit.position[1]) == cell.y:
					unit_pressed.emit(str(unit.id))
					return
		cell_pressed.emit(cell.x, cell.y)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("08131d"), true)
	draw_string(ThemeDB.fallback_font, Vector2(18, 25), "ARENA TÁCTICA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ConsoleUI.TEAL)
	if combat == null or combat.state.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(18, 64), "Sin encuentro activo", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ConsoleUI.MUTED)
		return
	var state: Dictionary = combat.state
	var rect = _rect_for_grid()
	var cell = _cell_size()
	var active: Dictionary = combat._turn_unit()
	var camera_mode = str(state.get("camera", "tactical"))
	for y in GroundCombat.HEIGHT:
		for x in GroundCombat.WIDTH:
			var pos = rect.position + Vector2(x * cell.x, y * cell.y)
			var box = Rect2(pos + Vector2.ONE, cell - Vector2.ONE * 2)
			var hidden = camera_mode == "pov" and not active.is_empty() and combat._distance_cells(active.position, [x, y]) > 4
			var base = Color("101f29") if not hidden else Color("071017")
			if [x, y] in state.obstacles: base = Color("3a3430") if not hidden else Color("171310")
			if hover == Vector2i(x, y) and not hidden: base = base.lightened(0.12)
			draw_rect(box, base, true)
			draw_rect(box, Color("29414d"), false, 1.0)
			if [x, y] in state.obstacles and not hidden:
				draw_string(ThemeDB.fallback_font, box.get_center() + Vector2(-7, 6), "▰", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ConsoleUI.MUTED)
	for unit in state.units:
		if unit.down: continue
		var distance = combat._distance_cells(active.position, unit.position) if not active.is_empty() else 0
		if camera_mode == "pov" and unit.team == "enemy" and distance > 4: continue
		var center = rect.position + Vector2((float(unit.position[0]) + 0.5) * cell.x, (float(unit.position[1]) + 0.5) * cell.y)
		if camera_mode == "third" and not active.is_empty():
			var relative = Vector2(int(unit.position[0]) - int(active.position[0]), int(unit.position[1]) - int(active.position[1]))
			if relative.length() > 5.5: continue
		var radius = minf(cell.x, cell.y) * (0.31 if str(unit.id) != str(active.get("id", "")) else 0.38)
		var color = ConsoleUI.TEAL if unit.team == "crew" else ConsoleUI.RED
		if str(unit.id) == str(active.get("id", "")): color = ConsoleUI.AMBER
		draw_circle(center, radius, color)
		draw_circle(center, radius, Color.WHITE if str(unit.id) == str(state.get("selected", "")) else Color("16242c"), false, 2.0)
		var initials = str(unit.name).left(2).to_upper()
		draw_string(ThemeDB.fallback_font, center + Vector2(-9, 5), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("081018"))
		var health_width = radius * 1.8
		var health_rect = Rect2(center + Vector2(-health_width * 0.5, radius + 5), Vector2(health_width, 4))
		draw_rect(health_rect, Color("142029"), true)
		draw_rect(Rect2(health_rect.position, Vector2(health_rect.size.x * float(unit.hp) / maxf(1.0, float(unit.max_hp)), 4)), ConsoleUI.TEAL if unit.team == "crew" else ConsoleUI.RED, true)
	if camera_mode == "third" and not active.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(18, size.y - 8), "3ª PERSONA · cámara centrada en " + active.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ConsoleUI.MUTED)
	elif camera_mode == "pov" and not active.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(18, size.y - 8), "POV · contactos fuera de 4 casillas ocultos", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ConsoleUI.MUTED)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(18, size.y - 8), "TÁCTICA · visión completa del tablero", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ConsoleUI.MUTED)
