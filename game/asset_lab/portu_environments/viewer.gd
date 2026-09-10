extends Node3D
## Destination library browser. No campaign navigation or network commands. MIT.
const Walker = preload("res://asset_lab/portu_environments/walker.gd")
var entries: Array = []
var selected_index: int = -1
var current_room: Node3D
var walker: CharacterBody3D
var camera: Camera3D
var info: Label
var selector: OptionButton
var walking: bool = false

func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/portu_environments/manifest.json"))
	if not data is Dictionary or not data.get("assets") is Array:
		push_error("PORTU: invalid library manifest")
		return
	entries = data.assets
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.028, 0.043, 0.059)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.78, 0.84)
	env.ambient_light_energy = 0.65
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -27, 0)
	key.light_energy = 1.25
	add_child(key)
	for z in [-8.0, 2.0, 12.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(0, 4.8, z)
		light.omni_range = 25.0
		light.light_energy = 1.6
		add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 43.0
	camera.far = 300.0
	camera.position = Vector3(29, 33, 38)
	add_child(camera)
	camera.look_at(Vector3(0, 1.5, -1))
	walker = Walker.new()
	add_child(walker)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(365, 0)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	var title := Label.new()
	title.text = "PORTU · DESTINOS REUTILIZABLES"
	title.add_theme_font_size_override("font_size", 21)
	column.add_child(title)
	selector = OptionButton.new()
	for entry in entries:
		selector.add_item(str(entry.title))
	selector.item_selected.connect(select_environment)
	column.add_child(selector)
	var walk := Button.new()
	walk.text = "Desembarcar / recorrer"
	walk.pressed.connect(enter_walk)
	column.add_child(walk)
	var overview := Button.new()
	overview.text = "Vista seccionada del entorno"
	overview.pressed.connect(enter_overview)
	column.add_child(overview)
	info = Label.new()
	column.add_child(info)
	var help := Label.new()
	help.text = "WASD · Ratón · Mayús · Espacio\nE: puerta cercana · Esc: liberar ratón\nConectores y puntos de contenido para el futuro.\nSin misiones, comercio ni estado de campaña."
	column.add_child(help)
	select_environment(0)

func select_environment(index: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	walker.set_physics_process(false)
	if is_instance_valid(current_room):
		remove_child(current_room)
		current_room.queue_free()
	var scene := load("res://" + str(entries[index].scene).trim_prefix("game/")) as PackedScene
	if scene == null:
		push_error("PORTU: cannot load environment")
		return false
	current_room = scene.instantiate() as Node3D
	add_child(current_room)
	selected_index = index
	selector.select(index)
	info.text = "%s\n%d triángulos · %d anclajes\nEscala 1:1 · suelo, techo y puertas reales" % [entries[index].id, int(entries[index].triangles), entries[index].sockets.size()]
	enter_overview()
	return current_room.ready_ok

func enter_walk() -> void:
	if not is_instance_valid(current_room):
		return
	var arrival := current_room.find_child("socket_arrival", true, false) as Node3D
	if arrival == null:
		push_error("PORTU: no arrival point")
		return
	current_room.set_cutaway(false)
	walker.place(arrival.global_position)
	walker.spawn = arrival.global_position
	walker.test_motion = Vector2.ZERO
	walker.set_physics_process(true)
	walker.camera.make_current()
	walking = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func enter_overview() -> void:
	walking = false
	walker.set_physics_process(false)
	if is_instance_valid(current_room):
		current_room.set_cutaway(true)
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_E and walking:
			current_room.toggle_door(walker.global_position)
	if walking and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
