extends Node3D
## Asset inspection only: no Session access, network changes or campaign registration.

const MANIFEST_PATH := "res://assets/models/frontier_pack/manifest.json"
const RESOURCE_PREFIX := "res://assets/models/frontier_pack/"
var entries: Array[Dictionary] = []
var selected_index: int = 0
var display_root: Node3D
var model: Node3D
var camera: Camera3D
var picker: ItemList
var details: Label
var animation_picker: OptionButton
var animation_player: AnimationPlayer
var current_animation: StringName = &""
var yaw: float = 0.6
var pitch: float = 0.32
var distance: float = 6.2
var turntable: bool = false
var playing: bool = true
var dragging: bool = false
var capture_path: String = ""
var frame_count: int = 0


func _ready() -> void:
	_build_stage()
	_build_interface()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--frontier-capture="):
			capture_path = argument.trim_prefix("--frontier-capture=")
	if not _read_catalogue():
		return
	for entry: Dictionary in entries:
		picker.add_item("%s  ·  %s" % [str(entry["category"]).to_upper(), entry["title"]])
	_select_asset(0)


func _read_catalogue() -> bool:
	if not FileAccess.file_exists(MANIFEST_PATH):
		details.text = "Falta manifest.json. Genera o descarga el pack antes de abrir la galería."
		return false
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null or file.get_length() > 2097152:
		details.text = "No se puede leer el catálogo del pack."
		return false
	var document: Variant = JSON.parse_string(file.get_as_text())
	if not document is Dictionary or document.get("format", "") != "lagunak-frontier-library":
		details.text = "Formato de catálogo no válido."
		return false
	var source: Variant = document.get("assets", [])
	if not source is Array or source.size() != 24:
		details.text = "El catálogo debe contener los 24 recursos de esta edición."
		return false
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-z][a-z0-9_]{1,63}$")
	for value: Variant in source:
		if not value is Dictionary:
			return false
		var identifier: String = str(value.get("id", ""))
		if id_pattern.search(identifier) == null:
			return false
		if value.get("glb", "") != RESOURCE_PREFIX + identifier + ".glb":
			return false
		entries.append(value)
	return true


func _build_stage() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0b1620")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("91b6c7")
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -30, 0)
	key.light_color = Color("ffe8ca")
	key.light_energy = 1.8
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 140, 0)
	rim.light_color = Color("63ddcf")
	rim.light_energy = 1.1
	add_child(rim)
	display_root = Node3D.new()
	display_root.name = "DisplayRoot"
	add_child(display_root)
	camera = Camera3D.new()
	camera.fov = 39
	camera.near = 0.01
	camera.far = 100
	camera.h_offset = -0.55
	add_child(camera)
	camera.make_current()


func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var top := Label.new()
	top.text = "FRONTERA  /  VOLUMEN 01"
	top.position = Vector2(24, 20)
	top.add_theme_font_size_override("font_size", 28)
	canvas.add_child(top)
	var subtitle := Label.new()
	subtitle.text = "Biblioteca 3D de desarrollo · no modifica la campaña"
	subtitle.position = Vector2(26, 60)
	subtitle.add_theme_color_override("font_color", Color("83b8b2"))
	canvas.add_child(subtitle)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 100)
	panel.size = Vector2(320, 590)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	picker = ItemList.new()
	picker.custom_minimum_size = Vector2(310, 305)
	picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker.add_theme_font_size_override("font_size", 13)
	picker.item_selected.connect(_select_asset)
	column.add_child(picker)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size = Vector2(300, 118)
	details.add_theme_font_size_override("font_size", 14)
	column.add_child(details)
	animation_picker = OptionButton.new()
	animation_picker.item_selected.connect(_choose_animation)
	column.add_child(animation_picker)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var rotate_button := Button.new()
	rotate_button.text = "Giro"
	rotate_button.toggle_mode = true
	rotate_button.toggled.connect(func(enabled: bool) -> void: turntable = enabled)
	buttons.add_child(rotate_button)
	var play_button := Button.new()
	play_button.text = "Animar"
	play_button.toggle_mode = true
	play_button.button_pressed = true
	play_button.toggled.connect(_set_playing)
	buttons.add_child(play_button)
	var reset_button := Button.new()
	reset_button.text = "Centrar"
	reset_button.pressed.connect(func() -> void:
		yaw = 0.6
		pitch = 0.32
		distance = 6.2)
	buttons.add_child(reset_button)
	var help := Label.new()
	help.text = "Arrastrar: orbitar  ·  Rueda: zoom  ·  Flechas: modelo  ·  Espacio: giro  ·  C: clip  ·  Esc: salir\nVista normalizada para comparar siluetas. Las medidas reales se muestran en la ficha."
	help.position = Vector2(24, 716)
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color("b3c7cd"))
	canvas.add_child(help)


func _select_asset(index: int) -> void:
	if index < 0 or index >= entries.size():
		return
	selected_index = index
	picker.select(index)
	picker.ensure_current_is_visible()
	animation_player = null
	current_animation = &""
	animation_picker.clear()
	if is_instance_valid(model):
		display_root.remove_child(model)
		model.queue_free()
	var entry: Dictionary = entries[index]
	var scene := load(str(entry["glb"])) as PackedScene
	if scene == null:
		details.text = "No se ha podido importar " + str(entry["id"])
		return
	model = scene.instantiate() as Node3D
	if model == null:
		details.text = "La raíz del modelo no es Node3D."
		return
	display_root.scale = Vector3.ONE
	display_root.rotation = Vector3.ZERO
	display_root.add_child(model)
	var merged := AABB()
	var first: bool = true
	var inverse: Transform3D = model.global_transform.affine_inverse()
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var transformed: AABB = (inverse * instance.global_transform) * instance.get_aabb()
		if first:
			merged = transformed
			first = false
		else:
			merged = merged.merge(transformed)
	if not first:
		model.position -= merged.get_center()
		var largest: float = maxf(merged.size.x, maxf(merged.size.y, merged.size.z))
		display_root.scale = Vector3.ONE * (3.0 / maxf(largest, 0.001))
	var dimensions: Array = entry.get("dimensions_m", [0, 0, 0])
	details.text = "%s\n%s\n\n%d triángulos · %d materiales\n%.2f × %.2f × %.2f m\n%s" % [
		entry["title"], entry["description"], int(entry["triangles"]), int(entry["materials"]),
		float(dimensions[0]), float(dimensions[1]), float(dimensions[2]),
		"Globo orbital normalizado; no es terreno caminable." if entry["category"] == "worlds" else "Pivotes y anclajes incluidos. Licencia MIT."]
	for child: Node in model.find_children("*", "AnimationPlayer", true, false):
		animation_player = child as AnimationPlayer
		break
	if animation_player != null:
		for animation: StringName in animation_player.get_animation_list():
			if animation != &"RESET":
				animation_picker.add_item(str(animation))
	if animation_picker.item_count > 0:
		animation_picker.disabled = false
		_choose_animation(0)
	else:
		animation_picker.add_item("Malla estática")
		animation_picker.disabled = true


func _choose_animation(index: int) -> void:
	if animation_player == null or index < 0 or index >= animation_picker.item_count:
		return
	animation_picker.select(index)
	current_animation = StringName(animation_picker.get_item_text(index))
	animation_player.play(current_animation)
	if not playing:
		animation_player.pause()


func _set_playing(enabled: bool) -> void:
	playing = enabled
	if animation_player == null:
		return
	if enabled and current_animation != &"":
		animation_player.play(current_animation)
	else:
		animation_player.pause()


func _process(delta: float) -> void:
	if turntable:
		yaw += delta * 0.25
	camera.position = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(Vector3.ZERO)
	if animation_player != null and playing and current_animation != &"" and not animation_player.is_playing():
		animation_player.play(current_animation)
	frame_count += 1
	if capture_path != "" and frame_count == 90:
		var image: Image = get_viewport().get_texture().get_image()
		var result: Error = image.save_png(capture_path)
		if result != OK:
			push_error("Could not save asset lab capture")
		get_tree().quit(0 if result == OK else 1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(3.4, distance - 0.4)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(12, distance + 0.4)
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.006, -0.8, 1.3)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_LEFT:
				_select_asset(posmod(selected_index - 1, entries.size()))
			KEY_RIGHT:
				_select_asset(posmod(selected_index + 1, entries.size()))
			KEY_SPACE:
				turntable = not turntable
			KEY_C:
				if animation_player != null and animation_picker.item_count > 0:
					_choose_animation((animation_picker.selected + 1) % animation_picker.item_count)
