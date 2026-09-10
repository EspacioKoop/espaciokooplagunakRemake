extends Node3D
## Visor aislado. No modifica campaña, simulación, red, guardados ni recursos.

const MANIFEST := "res://assets/models/orbita_pack/manifest.json"
var entries: Array = []
var selected_index: int = 0
var holder: Node3D
var camera: Camera3D
var model: Node3D
var picker: OptionButton
var info: Label
var motion: CheckButton
var yaw: float = -0.55
var pitch: float = 0.32
var distance: float = 8.0

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or not parsed.get("assets") is Array:
		push_error("ORBITA: catálogo no válido")
		return
	entries = parsed["assets"]
	holder = Node3D.new()
	add_child(holder)
	camera = Camera3D.new()
	camera.near = 0.03
	camera.far = 100.0
	camera.current = true
	add_child(camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.032, 0.06, 0.092)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.56, 0.69, 0.8)
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	for angles: Vector3 in [Vector3(-48, -35, 0), Vector3(-22, 120, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = angles
		light.light_energy = 1.6 if angles.y < 0 else 0.8
		add_child(light)
	_build_ui()
	select_asset(0)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--orbita-capture="):
			_capture(arg.trim_prefix("--orbita-capture="))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	layer.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var title := Label.new()
	title.text = "ÓRBITA · Biblioteca 3D / #52"
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	picker = OptionButton.new()
	picker.custom_minimum_size.x = 345
	for entry: Dictionary in entries:
		picker.add_item(str(entry.get("title", entry.get("id", "Modelo"))))
	picker.item_selected.connect(select_asset)
	row.add_child(picker)
	var previous := Button.new()
	previous.text = "Anterior"
	previous.pressed.connect(func() -> void: select_asset(posmod(selected_index - 1, entries.size())))
	row.add_child(previous)
	var next := Button.new()
	next.text = "Siguiente"
	next.pressed.connect(func() -> void: select_asset((selected_index + 1) % entries.size()))
	row.add_child(next)
	var reset := Button.new()
	reset.text = "Restablecer vista"
	reset.pressed.connect(_reset_camera)
	row.add_child(reset)
	motion = CheckButton.new()
	motion.text = "Animación mecánica"
	motion.button_pressed = true
	motion.toggled.connect(_set_motion)
	row.add_child(motion)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 16)
	column.add_child(info)
	var footer := Label.new()
	footer.text = "Botón derecho + arrastrar: orbitar · Rueda: acercar\nEscala normalizada sólo en este visor. No representa integración en campaña."
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(24, -62)
	layer.add_child(footer)

func select_asset(index: int) -> void:
	if index < 0 or index >= entries.size():
		return
	var entry: Dictionary = entries[index]
	var path: String = str(entry.get("resource", ""))
	# El visor sólo carga GLB de su propio directorio, nunca URIs ni rutas arbitrarias.
	if not path.begins_with("res://assets/models/orbita_pack/") or not path.ends_with(".glb") or ".." in path:
		push_error("ORBITA: ruta rechazada")
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return
	if is_instance_valid(model):
		holder.remove_child(model)
		model.queue_free()
	holder.scale = Vector3.ONE
	model = packed.instantiate() as Node3D
	if model == null:
		return
	holder.add_child(model)
	var box: AABB = model_bounds(model)
	model.position -= box.get_center()
	var largest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	holder.scale = Vector3.ONE * (4.8 / maxf(largest, 0.001))
	selected_index = index
	picker.select(index)
	var unit_text := "m" if entry.get("units") == "metres" else "unidades de representación"
	info.text = "%s\n%d triángulos · %s · anclajes: %d\n%s" % [str(entry.get("description", "")), int(entry.get("triangles", 0)), unit_text, entry.get("sockets", []).size(), str(entry.get("id", ""))]
	_set_motion(motion.button_pressed)
	_update_camera()

static func model_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for item: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := item as MeshInstance3D
		if mesh.mesh == null:
			continue
		var relative: Transform3D = root.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = relative * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _set_motion(enabled: bool) -> void:
	if not is_instance_valid(model):
		return
	for item: Node in model.find_children("*", "AnimationPlayer", true, false):
		var player := item as AnimationPlayer
		for animation_name: StringName in player.get_animation_list():
			if animation_name == &"RESET":
				continue
			if enabled:
				player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
				player.play(animation_name)
			else:
				player.seek(0.0, true)
				player.stop()
			break

func _reset_camera() -> void:
	yaw = -0.55
	pitch = 0.32
	distance = 8.0
	_update_camera()

func _update_camera() -> void:
	camera.position = Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * distance
	camera.look_at(Vector3.ZERO)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		yaw -= event.relative.x * 0.007
		pitch = clampf(pitch + event.relative.y * 0.006, -1.2, 1.2)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(3.2, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(18.0, distance / 0.9)
		_update_camera()

func _capture(path: String) -> void:
	if not path.ends_with(".png"):
		push_error("ORBITA: la captura requiere PNG")
		get_tree().quit(1)
		return
	for i: int in range(60):
		await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("ORBITA: no se pudo guardar la captura")
		get_tree().quit(1)
		return
	print("ORBITA_CAPTURE_PASS")
	get_tree().quit()
