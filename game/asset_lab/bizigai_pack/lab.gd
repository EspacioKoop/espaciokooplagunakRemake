extends Node3D
## Isolated asset laboratory, deliberately not a campaign/flight integration.
const MANIFEST := "res://assets/models/bizigai_pack/manifest.json"
const Walker = preload("res://asset_lab/bizigai_pack/radial_walker.gd")
var worlds: Array = []
var world_index := -1
var poi_index := 0
var representation := "orbital"
var model: Node3D
var walker: CharacterBody3D
var orbit_camera: Camera3D
var world_picker: OptionButton
var poi_picker: OptionButton
var title_label: Label
var info_label: Label
var environment: Environment
var yaw := 0.5
var elevation := 0.48
var distance_factor := 3.1

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or parsed.get("schema", "") != "bizigai-planets":
		push_error("Bizigai: invalid or missing asset manifest")
		return
	worlds = parsed.get("worlds", [])
	if worlds.size() != 2:
		push_error("Bizigai: expected two worlds")
		return
	var env_node := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.04, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.80, 0.88)
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = environment
	add_child(env_node)
	for settings in [[Vector3(-36, -28, 0), 1.5], [Vector3(25, 145, 0), 0.6]]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = settings[0]
		sun.light_energy = settings[1]
		sun.shadow_enabled = false
		add_child(sun)
	orbit_camera = Camera3D.new()
	orbit_camera.near = 0.1
	orbit_camera.far = 12000
	orbit_camera.fov = 47.0
	add_child(orbit_camera)
	walker = Walker.new()
	walker.name = "RadialWalker"
	add_child(walker)
	_build_ui()
	select_world(0)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(410, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.065, 0.94)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.set_corner_radius_all(9)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 23)
	box.add_child(title_label)
	world_picker = OptionButton.new()
	for entry in worlds:
		world_picker.add_item(str(entry["name"]) + " · HABITABLE")
	world_picker.item_selected.connect(select_world)
	box.add_child(world_picker)
	poi_picker = OptionButton.new()
	poi_picker.item_selected.connect(func(i: int): poi_index = i)
	box.add_child(poi_picker)
	var row := HBoxContainer.new()
	box.add_child(row)
	for item in [["Órbita", "orbital"], ["Aproximación", "approach"], ["Recorrer", "surface"]]:
		var button := Button.new()
		button.text = item[0]
		var mode: String = item[1]
		button.pressed.connect(func():
			if mode == "surface":
				teleport_to_poi(poi_index, true)
			else:
				set_representation(mode))
		row.add_child(button)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 15)
	box.add_child(info_label)
	var controls := Label.new()
	controls.text = "Órbita: botón derecho + ratón · rueda: zoom\nSuperficie: WASD · Mayús: correr · Espacio: saltar\nEsc: liberar/capturar ratón · F: volver a órbita\nModelo de biblioteca: sin vuelo, misiones ni combate"
	controls.add_theme_font_size_override("font_size", 13)
	box.add_child(controls)

func select_world(index: int) -> bool:
	if index < 0 or index >= worlds.size():
		return false
	var old := world_index
	world_index = index
	if not set_representation("orbital"):
		world_index = old
		return false
	poi_index = 0
	world_picker.select(index)
	poi_picker.clear()
	for poi in worlds[index]["pois"]:
		poi_picker.add_item(str(poi["name"]))
	poi_picker.select(0)
	_refresh_labels()
	return true

func set_representation(tier: String) -> bool:
	if world_index < 0 or world_index >= worlds.size() or tier not in ["orbital", "approach", "surface"]:
		return false
	var path: String = worlds[world_index]["representations"][tier]["res_path"]
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false
	var replacement := packed.instantiate() as Node3D
	if replacement == null:
		return false
	walker.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	model = replacement
	add_child(model)
	representation = tier
	distance_factor = 3.1 if tier == "orbital" else 1.8
	orbit_camera.current = true
	environment.background_color = Color(0.025, 0.04, 0.07)
	_update_orbit()
	_refresh_labels()
	return true

func teleport_to_poi(index: int, capture_mouse := false) -> bool:
	if world_index < 0 or index < 0 or index >= worlds[world_index]["pois"].size():
		return false
	if representation != "surface" and not set_representation("surface"):
		return false
	var poi: Dictionary = worlds[world_index]["pois"][index]
	var p: Array = poi["arrival_m"]
	var f: Array = poi["focus_m"]
	if not walker.place_at(Vector3(p[0],p[1],p[2]), Vector3(f[0],f[1],f[2])):
		return false
	poi_index = index
	poi_picker.select(index)
	walker.gravity_strength = float(worlds[world_index]["gravity_m_s2"])
	walker.enabled = true
	walker.camera.current = true
	environment.background_color = Color(0.22, 0.33, 0.40)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture_mouse else Input.MOUSE_MODE_VISIBLE
	_refresh_labels()
	return true

func _refresh_labels() -> void:
	if not is_instance_valid(title_label) or world_index < 0:
		return
	var world: Dictionary = worlds[world_index]
	title_label.text = str(world["name"]).to_upper() + "  /  BIZIGAI"
	info_label.text = "HABITABLE · radio base %d m · 16 lugares\n%s · %s triángulos\n%s" % [
		int(world["radius_m"]), representation,
		str(world["representations"][representation]["triangles"]),
		str(world["pois"][poi_index]["name"]) if representation == "surface" else "Misma esfera y coordenadas en los tres niveles"]

func _update_orbit() -> void:
	if world_index < 0:
		return
	var radius := float(worlds[world_index]["radius_m"])
	orbit_camera.position = Vector3(sin(yaw)*cos(elevation), sin(elevation), cos(yaw)*cos(elevation)) * radius * distance_factor
	orbit_camera.look_at(Vector3.ZERO, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			set_representation("orbital")
		elif event.physical_keycode == KEY_ESCAPE and walker.enabled:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if walker.enabled:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.005
		elevation = clampf(elevation + event.relative.y * 0.005, -1.35, 1.35)
		_update_orbit()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance_factor = maxf(1.18, distance_factor * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance_factor = minf(8, distance_factor * 1.1)
		_update_orbit()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
