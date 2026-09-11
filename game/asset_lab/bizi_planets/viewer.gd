extends Node3D
## Bizi HABITABLE planet lab. Isolated from campaign, saves, combat and networking. MIT.
const Explorer = preload("res://asset_lab/bizi_planets/spherical_explorer.gd")
var planets: Array = []
var selected_index: int = -1
var orbital_model: Node3D
var surface_model: Node3D
var explorer: CharacterBody3D
var orbit_camera: Camera3D
var environment: Environment
var info: Label
var planet_selector: OptionButton
var poi_selector: OptionButton
var surface_mode: bool = false
var collected: Dictionary = {}
var yaw: float = 0.6
var pitch: float = 0.25
var zoom: float = 3.0
var collision_count: int = 0

func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/bizi_planets/manifest.json"))
	if not data is Dictionary or not data.get("planets") is Array:
		push_error("BIZI: invalid habitable-planet manifest")
		return
	planets = data.planets
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.035, 0.065)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.64, 0.80, 0.88)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -32, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(35, 145, 0)
	fill.light_energy = 0.7
	add_child(fill)
	orbit_camera = Camera3D.new()
	orbit_camera.near = 0.5
	orbit_camera.far = 3000.0
	add_child(orbit_camera)
	explorer = Explorer.new()
	add_child(explorer)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(410, 0)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	var title := Label.new()
	title.text = "BIZI · PLANETAS HABITABLES"
	title.add_theme_font_size_override("font_size", 23)
	column.add_child(title)
	planet_selector = OptionButton.new()
	for planet in planets:
		planet_selector.add_item(str(planet.title))
	planet_selector.item_selected.connect(select_planet)
	column.add_child(planet_selector)
	var land := Button.new()
	land.text = "Bajar al puerto (teletransporte)"
	land.pressed.connect(func() -> void: enter_surface(-1))
	column.add_child(land)
	poi_selector = OptionButton.new()
	column.add_child(poi_selector)
	var inspect := Button.new()
	inspect.text = "Visitar punto de interés"
	inspect.pressed.connect(func() -> void: enter_surface(poi_selector.selected))
	column.add_child(inspect)
	var back := Button.new()
	back.text = "Volver a órbita"
	back.pressed.connect(return_to_orbit)
	column.add_child(back)
	info = Label.new()
	column.add_child(info)
	var help := Label.new()
	help.text = "Órbita: botón derecho y rueda\nSuelo: clic para mirar · WASD · Mayús · Espacio\nE: recoger muestra cercana · Esc: liberar ratón\nRecorrido local de arte, sin misiones ni combate."
	column.add_child(help)
	select_planet(0)

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func select_planet(index: int) -> bool:
	if index < 0 or index >= planets.size():
		return false
	explorer.set_physics_process(false)
	for model in [orbital_model, surface_model]:
		if is_instance_valid(model):
			remove_child(model)
			model.queue_free()
	orbital_model = null
	surface_model = null
	collected.clear()
	collision_count = 0
	selected_index = index
	planet_selector.select(index)
	poi_selector.clear()
	for poi in planets[index].pois:
		poi_selector.add_item(str(poi.title))
	var scene := load("res://" + str(planets[index].orbit_path).trim_prefix("game/")) as PackedScene
	if scene == null:
		push_error("BIZI: orbital GLB could not load")
		return false
	orbital_model = scene.instantiate() as Node3D
	add_child(orbital_model)
	return_to_orbit()
	return true

func _terrain_faces(node: Node3D, relative: Transform3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	if node is MeshInstance3D and str(node.name).begins_with("terrain_chunk"):
		for point in node.mesh.get_faces():
			result.append((relative * point).snapped(Vector3.ONE * 0.00001))
	for child in node.get_children():
		if child is Node3D:
			result.append_array(_terrain_faces(child, relative * child.transform))
	return result

func _add_terrain_collision() -> void:
	# The eight VISUAL sectors remain independently reusable. Physics sees one
	# welded shell, not eight independent trimeshes whose boundary rays can miss.
	var faces := _terrain_faces(surface_model, Transform3D.IDENTITY)
	if faces.is_empty():
		push_error("BIZI: missing terrain physics shell")
		return
	var mesh_shape := ConcavePolygonShape3D.new()
	mesh_shape.set_faces(faces)
	mesh_shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := CollisionShape3D.new()
	shape.shape = mesh_shape
	body.add_child(shape)
	surface_model.add_child(body)
	collision_count += 1

func _add_collisions(node: Node, ignore: bool = false) -> void:
	var skip := ignore or str(node.name).begins_with("resource_") or str(node.name).begins_with("water_visual") or str(node.name).begins_with("terrain_chunk")
	if node is MeshInstance3D and node.mesh != null and not skip:
		var body := StaticBody3D.new()
		body.name = "PreviewCollision"
		body.collision_layer = 1
		body.collision_mask = 2
		var shape := CollisionShape3D.new()
		shape.shape = node.mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)
		collision_count += 1
	for child in node.get_children():
		if not child is StaticBody3D:
			_add_collisions(child, skip)

func enter_surface(poi_index: int = -1) -> bool:
	if selected_index < 0 or poi_index < -1 or poi_index >= planets[selected_index].pois.size():
		return false
	if surface_model == null:
		var scene := load("res://" + str(planets[selected_index].surface_path).trim_prefix("game/")) as PackedScene
		if scene == null:
			push_error("BIZI: surface GLB could not load")
			return false
		surface_model = scene.instantiate() as Node3D
		add_child(surface_model)
		_add_collisions(surface_model)
		_add_terrain_collision()
	orbital_model.hide()
	surface_model.show()
	surface_mode = true
	environment.background_color = Color(0.17, 0.34, 0.44)
	var point := _vector(planets[selected_index].arrival_position)
	if poi_index >= 0:
		point = _vector(planets[selected_index].pois[poi_index].position)
	if not explorer.activate(point, float(planets[selected_index].radius_m)):
		return false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_info()
	return true

func return_to_orbit() -> void:
	surface_mode = false
	explorer.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(surface_model):
		surface_model.hide()
	if is_instance_valid(orbital_model):
		orbital_model.show()
	environment.background_color = Color(0.018, 0.035, 0.065)
	orbit_camera.make_current()
	_update_camera()
	_update_info()

func collect_nearby() -> bool:
	if not surface_mode:
		return false
	for resource in planets[selected_index].resources:
		var key := str(resource.socket)
		if collected.has(key):
			continue
		var point := _vector(resource.position)
		if explorer.global_position.distance_to(point) <= 3.2:
			collected[key] = true
			var anchor := surface_model.find_child(key, true, false)
			if anchor != null and anchor.get_parent() is Node3D:
				anchor.get_parent().hide()
			_update_info()
			return true
	return false

func _update_info() -> void:
	if info == null or selected_index < 0:
		return
	var planet: Dictionary = planets[selected_index]
	info.text = "HABITABLE · radio %.0f m · esfera completa\n14 lugares · 28 muestras de prueba\n%s · muestras locales %d/28\nEstado local temporal; no afecta a la campaña." % [float(planet.radius_m), "Superficie" if surface_mode else "Representación espacial", collected.size()]

func _update_camera() -> void:
	if selected_index < 0:
		return
	var distance := float(planets[selected_index].radius_m) * zoom
	orbit_camera.position = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	orbit_camera.look_at(Vector3.ZERO, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_E:
			collect_nearby()
	if surface_mode:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.006, -1.35, 1.35)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(1.4, zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(8.0, zoom * 1.1)
		_update_camera()
