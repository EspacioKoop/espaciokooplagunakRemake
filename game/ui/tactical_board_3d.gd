class_name TacticalBoard3D
extends SubViewportContainer
## A view of GroundCombat, not another simulation. Input emits the existing board signals.

signal cell_pressed(x: int, y: int)
signal unit_pressed(id: String)

const CELL = 2.8
const MAX_UNITS = 32
var combat: Node
var viewport_3d: SubViewport
var world: Node3D
var camera: Camera3D
var pawns: Dictionary = {}
var covers: Dictionary = {}
var tiles: Dictionary = {}
var caption: Label
var _camera_mode = "tactical"
var _focus = Vector3.ZERO
var _forward = Vector3.RIGHT
var _active_id = ""
var _selected_id = ""
var _cell_mesh: BoxMesh
var _tile_material: StandardMaterial3D
var _blocked_material: StandardMaterial3D
var _hover_material: StandardMaterial3D
var _hover = Vector2i(-1, -1)
var _yaw = 0.0
var _zoom = 1.0
var _dragging = false

static func cell_position(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5 - GroundCombat.WIDTH / 2.0) * CELL, 0, (cell.y + 0.5 - GroundCombat.HEIGHT / 2.0) * CELL)

static func valid_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and Catalog.finite_number(value[0]) and Catalog.finite_number(value[1]) and value[0] == floorf(value[0]) and value[1] == floorf(value[1]) and value[0] >= 0 and value[0] < GroundCombat.WIDTH and value[1] >= 0 and value[1] < GroundCombat.HEIGHT

static func position_cell(point: Vector3) -> Vector2i:
	if not point.is_finite(): return Vector2i(-1, -1)
	var x = floori(point.x / CELL + GroundCombat.WIDTH / 2.0)
	var y = floori(point.z / CELL + GroundCombat.HEIGHT / 2.0)
	return Vector2i(x, y) if x >= 0 and x < GroundCombat.WIDTH and y >= 0 and y < GroundCombat.HEIGHT else Vector2i(-1, -1)

func _ready() -> void:
	custom_minimum_size = Vector2(650, 520)
	mouse_filter = Control.MOUSE_FILTER_STOP
	stretch = true
	viewport_3d = SubViewport.new()
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	add_child(viewport_3d)
	world = Node3D.new()
	viewport_3d.add_child(world)
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("08131d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c4dce5")
	environment.environment.ambient_light_energy = 0.5
	world.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.25
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 75.0
	world.add_child(light)
	camera = Camera3D.new()
	camera.near = 0.08
	camera.far = 160
	camera.current = true
	world.add_child(camera)
	_cell_mesh = BoxMesh.new()
	_cell_mesh.size = Vector3(CELL - 0.06, 0.1, CELL - 0.06)
	_tile_material = _material(Color("233b49"))
	_blocked_material = _material(Color("534939"))
	_hover_material = _material(Color("426675"))
	for y in GroundCombat.HEIGHT:
		for x in GroundCombat.WIDTH:
			var cell = Vector2i(x, y)
			var tile = MeshInstance3D.new()
			tile.mesh = _cell_mesh
			tile.material_override = _tile_material
			tile.position = cell_position(cell) - Vector3(0, 0.06, 0)
			world.add_child(tile)
			tiles[cell] = tile
	caption = ConsoleUI.label("3D · selecciona unidades o casillas", 13, ConsoleUI.TEXT)
	caption.position = Vector2(12, 8)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	var reset = ConsoleUI.button("Recentrar", _reset_camera)
	reset.position = Vector2(12, 34)
	add_child(reset)
	gui_input.connect(_input_board)
	resized.connect(_frame_camera)
	_frame_camera()

func _material(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

func _process(_delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): _dragging = false
	if combat != null and is_instance_valid(combat): present(combat.state)

func present(state: Dictionary) -> void:
	if world == null: return
	var units = state.get("units", [])
	var obstacles = state.get("obstacles", [])
	if not units is Array or not obstacles is Array:
		_clear_models()
		return
	_camera_mode = str(state.get("camera", "tactical"))
	if _camera_mode not in ["tactical", "third", "pov"]: _camera_mode = "tactical"
	var active: Dictionary = {}
	var turn = state.get("turn", -1)
	if state.get("status") == "active" and Catalog.finite_number(turn) and turn == floorf(turn) and turn >= 0 and turn < mini(units.size(), MAX_UNITS) and units[int(turn)] is Dictionary and valid_cell(units[int(turn)].get("position")):
		active = units[int(turn)]
	_active_id = str(active.get("id", ""))
	_selected_id = str(state.get("selected", ""))
	_focus = cell_position(Vector2i(int(active.position[0]), int(active.position[1]))) if not active.is_empty() else Vector3.ZERO
	_forward = Vector3.LEFT if active.get("team") == "enemy" else Vector3.RIGHT
	var seen: Dictionary = {}
	for unit in units.slice(0, MAX_UNITS):
		if not unit is Dictionary or not valid_cell(unit.get("position")) or unit.get("team") not in ["crew", "enemy"] or not unit.get("id") is String: continue
		var id: String = unit.id
		if id.is_empty() or id.length() > 80 or seen.has(id): continue
		seen[id] = true
		var key = TacticalModels.body_key(unit) + ":" + str(unit.get("weapon", ""))
		if pawns.has(id) and pawns[id].key != key: _remove_pawn(id)
		if not pawns.has(id): _add_pawn(id, key, unit)
		var entry: Dictionary = pawns[id]
		var position = Vector2i(int(unit.position[0]), int(unit.position[1]))
		entry.node.position = cell_position(position)
		entry.node.rotation.y = PI / 2.0 if unit.team == "enemy" else -PI / 2.0
		var hidden = unit.get("down", false) == true
		if not active.is_empty():
			var delta = Vector2(float(unit.position[0]) - float(active.position[0]), float(unit.position[1]) - float(active.position[1]))
			if _camera_mode == "pov": hidden = hidden or id == _active_id or (unit.team == "enemy" and absf(delta.x) + absf(delta.y) > 4)
			elif _camera_mode == "third": hidden = hidden or delta.length() > 5.5
		entry.node.visible = not hidden
		var hp = unit.get("hp", 0)
		var max_hp = unit.get("max_hp", 1)
		entry.label.text = str(unit.get("name", "Unidad")).left(18) + ("\n%d/%d" % [int(hp), int(max_hp)] if Catalog.finite_number(hp) and Catalog.finite_number(max_hp) and absf(hp) < 1e6 and absf(max_hp) < 1e6 else "")
		entry.marker.material_override.albedo_color = ConsoleUI.AMBER if id == _active_id else (ConsoleUI.TEAL if unit.team == "crew" else ConsoleUI.RED)
		entry.selection.visible = id == _selected_id
	for id in pawns.keys():
		if not seen.has(id): _remove_pawn(id)
	var occupied: Dictionary = {}
	for value in obstacles.slice(0, GroundCombat.WIDTH * GroundCombat.HEIGHT):
		if not valid_cell(value): continue
		var cell = Vector2i(int(value[0]), int(value[1]))
		occupied[cell] = true
		if not covers.has(cell):
			var cover = TacticalModels.create_cover()
			cover.position = cell_position(cell)
			world.add_child(cover)
			covers[cell] = cover
	for cell in covers.keys():
		if not occupied.has(cell):
			covers[cell].queue_free()
			covers.erase(cell)
	for cell in tiles:
		tiles[cell].material_override = _blocked_material if occupied.has(cell) else (_hover_material if cell == _hover else _tile_material)
	caption.text = "3D · " + {"tactical": "Táctica", "third": "3ª persona", "pov": "POV · alcance visual de 4 casillas"}[_camera_mode]
	_frame_camera()

func _add_pawn(id: String, key: String, unit: Dictionary) -> void:
	var pawn = TacticalModels.create_unit(unit)
	var marker = _ring(0.85, ConsoleUI.TEAL)
	marker.position.y = 0.035
	pawn.add_child(marker)
	var selection = _ring(1.07, Color.WHITE)
	selection.position.y = 0.055
	pawn.add_child(selection)
	var label = Label3D.new()
	label.font_size = 32
	label.pixel_size = 0.018
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.5
	pawn.add_child(label)
	world.add_child(pawn)
	pawns[id] = {"node": pawn, "key": key, "marker": marker, "selection": selection, "label": label}

func _ring(radius: float, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - 0.06
	mesh.outer_radius = radius
	mesh.rings = 24
	mesh.ring_segments = 6
	node.mesh = mesh
	node.material_override = _material(color)
	node.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return node

func _remove_pawn(id: String) -> void:
	pawns[id].node.visible = false
	pawns[id].node.queue_free()
	pawns.erase(id)

func _clear_models() -> void:
	for id in pawns.keys(): _remove_pawn(id)
	for node in covers.values(): node.queue_free()
	covers.clear()

func _frame_camera() -> void:
	if camera == null or not camera.is_inside_tree(): return
	if _camera_mode == "tactical" or _active_id.is_empty():
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(GroundCombat.WIDTH * CELL / maxf(size.x / maxf(size.y, 1.0), 0.5), GroundCombat.HEIGHT * CELL) * 1.1 * _zoom
		camera.position = Vector3(0, 28, 23).rotated(Vector3.UP, _yaw)
		camera.look_at(Vector3.ZERO)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 68
		if _camera_mode == "third":
			camera.position = _focus + (-_forward * 7.0 + Vector3(0, 6, 5)).rotated(Vector3.UP, _yaw) * _zoom
			camera.look_at(_focus + Vector3(0, 0.7, 0))
		else:
			camera.position = _focus + Vector3(0, 1.65, 0)
			camera.look_at(camera.position + _forward.rotated(Vector3.UP, _yaw) * 8.0 - Vector3(0, 0.3, 0))

func pick(screen: Vector2) -> Dictionary:
	if camera == null or not screen.is_finite() or not Rect2(Vector2.ZERO, size).has_point(screen): return {}
	var point = screen * Vector2(viewport_3d.size) / size
	var origin = camera.project_ray_origin(point)
	var direction = camera.project_ray_normal(point)
	var nearest = INF
	var target = ""
	for id in pawns:
		var pawn: Node3D = pawns[id].node
		if not pawn.visible: continue
		var box = AABB(pawn.position + Vector3(-1.2, 0, -1.2), Vector3(2.4, 2.4, 2.4))
		var hit = box.intersects_ray(origin, direction)
		if hit is Vector3 and origin.distance_squared_to(hit) < nearest:
			nearest = origin.distance_squared_to(hit)
			target = id
	for cover in covers.values():
		var box = cover.transform * TacticalModels.geometry_bounds(cover)
		var hit = box.intersects_ray(origin, direction)
		if hit is Vector3 and origin.distance_squared_to(hit) < nearest:
			nearest = origin.distance_squared_to(hit)
			target = ""
	if not target.is_empty(): return {"unit": target}
	var ground = Plane(Vector3.UP, 0).intersects_ray(origin, direction)
	if not ground is Vector3: return {}
	var cell = position_cell(ground)
	return {"cell": cell} if cell.x >= 0 else {}

func _input_board(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_zoom = clampf(_zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.55, 1.6)
		_frame_camera()
		accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			_yaw = wrapf(_yaw - event.relative.x * 0.008, -PI, PI)
			_frame_camera()
		_hover = pick(event.position).get("cell", Vector2i(-1, -1))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit = pick(event.position)
		if hit.has("unit"): unit_pressed.emit(hit.unit)
		elif hit.has("cell"): cell_pressed.emit(hit.cell.x, hit.cell.y)
		if not hit.is_empty(): accept_event()

func _reset_camera() -> void:
	_yaw = 0.0
	_zoom = 1.0
	_frame_camera()
