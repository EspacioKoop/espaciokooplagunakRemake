extends Node3D
## Isolated habitable-planet laboratory. Teleport is explicit, not seamless flight.
const WalkerScript = preload("res://asset_lab/aterpe_pack/walker.gd")
var entries: Array = []
var selected: int = -1
var surface: Node3D
var orbital: Node3D
var walker: CharacterBody3D
var camera: Camera3D
var orbit: Node3D
var sun: DirectionalLight3D
var planet_picker: OptionButton
var poi_picker: OptionButton
var status: Label
var transitioning: bool = false
var orbital_lod: String = "orbit"
var distance: float = 350.0
var on_surface: bool = false

func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/aterpe_pack/manifest.json"))
	if not data is Dictionary or not data.get("planets") is Array:
		push_error("Aterpe manifest missing")
		return
	entries = data["planets"]
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.07, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.67, 0.76, 0.88)
	environment.ambient_light_energy = 0.85
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.8
	sun.rotation_degrees = Vector3(-40, -25, 0)
	add_child(sun)
	orbit = Node3D.new()
	add_child(orbit)
	orbit.rotation_degrees = Vector3(-22, 35, 0)
	camera = Camera3D.new()
	orbit.add_child(camera)
	camera.near = 0.08
	camera.far = 2400
	camera.current = true
	walker = CharacterBody3D.new()
	walker.set_script(WalkerScript)
	add_child(walker)
	walker.enabled = false
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(490, 0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "ATERPE / PLANETAS HABITABLES"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	planet_picker = OptionButton.new()
	for entry in entries:
		planet_picker.add_item(str(entry["title"]))
	planet_picker.item_selected.connect(select_planet)
	column.add_child(planet_picker)
	poi_picker = OptionButton.new()
	column.add_child(poi_picker)
	var row := HBoxContainer.new()
	column.add_child(row)
	var land_button := Button.new()
	land_button.text = "Visitar lugar · teletransporte"
	land_button.pressed.connect(func() -> void: land(poi_picker.selected))
	row.add_child(land_button)
	var back_button := Button.new()
	back_button.text = "Volver a órbita"
	back_button.pressed.connect(return_to_orbit)
	row.add_child(back_button)
	status = Label.new()
	column.add_child(status)
	var help := Label.new()
	help.text = "Órbita: botón derecho y rueda. Superficie: clic, WASD, salto y Mayús.\nEsc libera ratón. Escena local: sin misiones, combate ni inventario."
	column.add_child(help)
	select_planet(0)
	if "--capture-aterpe" in OS.get_cmdline_user_args():
		_capture_all.call_deferred()

func select_planet(index: int) -> bool:
	if transitioning or index < 0 or index >= entries.size():
		return false
	walker.enabled = false
	walker.planet = null
	on_surface = false
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(surface):
		remove_child(surface)
		surface.queue_free()
		surface = null
	selected = index
	planet_picker.select(index)
	poi_picker.clear()
	for point in entries[index]["pois"]:
		poi_picker.add_item(str(point["title"]))
	distance = float(entries[index]["radius_metres"]) * 2.85
	camera.position.z = distance
	if not _orbital_model("orbit"):
		return false
	status.text = "HABITABLE · radio %.0f m · 16 lugares · LOD orbital" % float(entries[index]["radius_metres"])
	return true

func _orbital_model(lod: String) -> bool:
	if lod not in ["orbit", "approach"] or selected < 0:
		return false
	var slug: String = str(entries[selected]["slug"])
	var scene: PackedScene = load("res://assets/models/aterpe_pack/" + slug + "_" + lod + ".glb") as PackedScene
	if scene == null:
		return false
	if is_instance_valid(orbital):
		remove_child(orbital)
		orbital.queue_free()
	orbital = scene.instantiate() as Node3D
	add_child(orbital)
	orbital.visible = not on_surface
	orbital_lod = lod
	return true

func land(poi_index: int) -> bool:
	if transitioning or selected < 0 or poi_index < 0 or poi_index >= entries[selected]["pois"].size():
		return false
	transitioning = true
	walker.enabled = false
	if not is_instance_valid(surface):
		var slug: String = str(entries[selected]["slug"])
		var packed: PackedScene = load("res://assets/models/aterpe_pack/" + slug + "_surface.tscn") as PackedScene
		if packed == null:
			transitioning = false
			return false
		surface = packed.instantiate() as Node3D
		add_child(surface)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var spawn: Dictionary = surface.surface_spawn(poi_index)
	if spawn.is_empty():
		transitioning = false
		return false
	walker.planet = surface
	if not walker.place(spawn["position"], spawn["up"], spawn["forward"]):
		transitioning = false
		return false
	surface.visible = true
	orbital.visible = false
	on_surface = true
	walker.enabled = true
	walker.view.current = true
	poi_picker.select(poi_index)
	# Inspection daylight follows the selected site, not a simulated day/night system.
	var light_direction: Vector3 = (-Vector3(spawn["up"]) + Vector3(spawn["forward"]) * 0.45).normalized()
	sun.global_basis = Basis.looking_at(light_direction, Vector3(spawn["forward"]))
	status.text = "%s · suelo físico y gravedad radial\nVista de inspección; lugares preparados para futuros sistemas." % str(entries[selected]["pois"][poi_index]["title"])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	transitioning = false
	return true

func return_to_orbit() -> void:
	if transitioning or selected < 0:
		return
	walker.enabled = false
	walker.planet = null
	walker.velocity = Vector3.ZERO
	on_surface = false
	if is_instance_valid(surface):
		remove_child(surface)
		surface.queue_free()
		surface = null
	orbital.visible = true
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sun.rotation_degrees = Vector3(-40, -25, 0)
	status.text = "Órbita · %s · modelos alineados 1:1" % orbital_lod

func _unhandled_input(event: InputEvent) -> void:
	if on_surface or transitioning or selected < 0:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbit.rotation.y -= event.relative.x * 0.007
		orbit.rotation.x = clampf(orbit.rotation.x - event.relative.y * 0.007, -1.5, 1.5)
	if event is InputEventMouseButton and event.pressed:
		var radius: float = float(entries[selected]["radius_metres"])
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(radius * 1.35, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(radius * 6, distance * 1.1)
		camera.position.z = distance
		if orbital_lod == "orbit" and distance < radius * 2.2:
			_orbital_model("approach")
		elif orbital_lod == "approach" and distance > radius * 2.45:
			_orbital_model("orbit")
		status.text = "Órbita · %s · distancia al centro %.0f m" % [orbital_lod, distance]

func _save_capture(name_value: String) -> bool:
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path("res://../build/aterpe/" + name_value + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return get_viewport().get_texture().get_image().save_png(path) == OK

func _capture_all() -> void:
	for index in range(entries.size()):
		if not select_planet(index):
			get_tree().quit(1)
			return
		await _save_capture(str(entries[index]["slug"]) + "_godot_orbit")
		if not await land(1):
			get_tree().quit(1)
			return
		await _save_capture(str(entries[index]["slug"]) + "_godot_surface")
		return_to_orbit()
	print("ATERPE_CAPTURE_PASS frames=4")
	get_tree().quit()
