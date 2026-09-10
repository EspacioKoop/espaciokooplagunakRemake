extends Node3D
## Asset inspection only: does not mutate campaign, inventory or combat state.

var entries: Array = []
var selected: int = -1
var current_model: Node3D
var holder: Node3D
var orbit: Node3D
var camera: Camera3D
var picker: OptionButton
var caption: Label
var playing: bool = true

func _ready() -> void:
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/lantegi_pack/manifest.json"))
	if not document is Dictionary or not document.get("assets") is Array:
		push_error("Lantegi manifest missing or invalid")
		return
	entries = document["assets"]
	holder = Node3D.new()
	add_child(holder)
	orbit = Node3D.new()
	add_child(orbit)
	orbit.rotation = Vector3(-0.25, 0.5, 0)
	camera = Camera3D.new()
	orbit.add_child(camera)
	camera.position.z = 4.5
	camera.near = 0.01
	camera.current = true
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.035, 0.065, 0.09)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.69, 0.81, 0.93)
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	for i in range(3):
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = Vector3(-40.0 + i * 25.0, -35.0 + i * 115.0, 0)
		lamp.light_energy = 1.2 if i == 0 else 0.5
		add_child(lamp)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(480, 0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "LANTEGI / EQUIPO DE CAMPO"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	picker = OptionButton.new()
	for entry in entries:
		picker.add_item(str(entry["title"]))
	picker.item_selected.connect(select_asset)
	column.add_child(picker)
	caption = Label.new()
	column.add_child(caption)
	var controls := HBoxContainer.new()
	column.add_child(controls)
	var animation_button := Button.new()
	animation_button.text = "Pausar / reproducir articulación"
	animation_button.pressed.connect(toggle_animation)
	controls.add_child(animation_button)
	var reset_button := Button.new()
	reset_button.text = "Restablecer cámara"
	reset_button.pressed.connect(func() -> void:
		orbit.rotation = Vector3(-0.25, 0.5, 0)
		camera.position.z = 4.5)
	controls.add_child(reset_button)
	var help := Label.new()
	help.text = "Botón derecho: orbitar · rueda: zoom\nEscala normalizada sólo en el visor. Sin reglas de juego."
	column.add_child(help)
	select_asset(0)
	if "--capture-lantegi" in OS.get_cmdline_user_args():
		select_asset(9)
		_capture.call_deferred()

func select_asset(index: int) -> bool:
	if index < 0 or index >= entries.size() or not is_instance_valid(holder):
		return false
	var path: String = str(entries[index]["runtime"]).trim_prefix("game/")
	if not path.begins_with("assets/models/lantegi_pack/") or not path.ends_with(".glb"):
		return false
	var packed: PackedScene = load("res://" + path) as PackedScene
	if packed == null:
		return false
	if is_instance_valid(current_model):
		holder.remove_child(current_model)
		current_model.queue_free()
	current_model = packed.instantiate() as Node3D
	holder.add_child(current_model)
	var aggregate := AABB()
	var has_mesh: bool = false
	for node in current_model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var measured: AABB = mesh.global_transform * mesh.get_aabb()
		aggregate = aggregate.merge(measured) if has_mesh else measured
		has_mesh = true
	if not has_mesh:
		return false
	var factor: float = 2.5 / maxf(aggregate.size.length(), 0.01)
	current_model.scale *= factor
	current_model.position -= aggregate.get_center() * factor
	selected = index
	picker.select(index)
	caption.text = "%s\n%d triángulos · %d anclajes · %s" % [entries[index]["description"], int(entries[index]["triangles"]), entries[index]["sockets"].size(), entries[index]["id"]]
	for node in current_model.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for clip in player.get_animation_list():
			if clip != "RESET":
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				player.play(clip)
				if not playing:
					player.pause()
				break
	return true

func toggle_animation() -> void:
	playing = not playing
	if not is_instance_valid(current_model):
		return
	for node in current_model.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if playing:
			player.play()
		else:
			player.pause()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbit.rotation.y -= event.relative.x * 0.008
		orbit.rotation.x = clampf(orbit.rotation.x - event.relative.y * 0.008, -1.4, 1.4)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.position.z = maxf(1.6, camera.position.z * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.position.z = minf(10.0, camera.position.z * 1.1)

func _capture() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../build/lantegi/godot_viewer.png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Lantegi screenshot failed")
		get_tree().quit(1)
		return
	print("LANTEGI_CAPTURE_PASS")
	get_tree().quit()
