extends Node3D
## Isolated art viewer: no campaign, inventory or network state. MIT.
var entries: Array = []
var current_model: Node3D
var selected_index: int = -1
var camera: Camera3D
var info: Label
var selector: OptionButton
var yaw: float = 0.65
var pitch: float = 0.3
var distance: float = 4.0
var spinning: bool = false
var players: Array[AnimationPlayer] = []

func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/itsasargi_pack/manifest.json"))
	if not data is Dictionary or not data.get("assets") is Array:
		push_error("ITSASARGI: invalid manifest")
		return
	entries = data.assets
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.055, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.78, 0.9)
	env.ambient_light_energy = 0.65
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.6
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20, 130, 0)
	fill.light_energy = 0.65
	add_child(fill)
	camera = Camera3D.new()
	camera.near = 0.01
	camera.far = 100.0
	add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(22, 22)
	panel.custom_minimum_size = Vector2(370, 0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "ITSASARGI · BIBLIOTECA 3D"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	selector = OptionButton.new()
	for entry in entries:
		selector.add_item(str(entry.title))
	selector.item_selected.connect(select_asset)
	column.add_child(selector)
	info = Label.new()
	column.add_child(info)
	var animation := Button.new()
	animation.text = "Reproducir / detener mecanismo"
	animation.pressed.connect(toggle_animation)
	column.add_child(animation)
	var reset := Button.new()
	reset.text = "Restablecer cámara"
	reset.pressed.connect(func() -> void:
		yaw = 0.65
		pitch = 0.3
		distance = 4.0
		_update_camera())
	column.add_child(reset)
	var help := Label.new()
	help.text = "Botón derecho: orbitar · Rueda: acercar\nModelos reutilizables, no nuevas reglas de juego."
	column.add_child(help)
	select_asset(0)

func _bounds(node: Node3D, relative: Transform3D) -> AABB:
	var result := AABB()
	if node is MeshInstance3D and node.mesh != null:
		result = relative * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var box := _bounds(child, relative * child.transform)
			if box.size != Vector3.ZERO:
				result = box if result.size == Vector3.ZERO else result.merge(box)
	return result

func _collect_players(node: Node) -> void:
	if node is AnimationPlayer:
		players.append(node)
	for child in node.get_children():
		_collect_players(child)

func select_asset(index: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	if is_instance_valid(current_model):
		remove_child(current_model)
		current_model.queue_free()
	players.clear()
	spinning = false
	var path := "res://" + str(entries[index].runtime).trim_prefix("game/")
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("ITSASARGI: could not load " + path)
		return false
	current_model = scene.instantiate() as Node3D
	add_child(current_model)
	var bounds := _bounds(current_model, current_model.transform)
	var size := bounds.size.length()
	if size <= 0.0001:
		push_error("ITSASARGI: empty model")
		return false
	var factor := 2.6 / size
	current_model.scale *= factor
	current_model.position = -(bounds.position + bounds.size * 0.5) * factor
	_collect_players(current_model)
	selected_index = index
	selector.select(index)
	info.text = "%s\n%d triángulos · %d anclajes\nEscala original: metros · presentación normalizada" % [entries[index].id, int(entries[index].triangles), entries[index].sockets.size()]
	_update_camera()
	return true

func toggle_animation() -> void:
	spinning = not spinning
	for player in players:
		if not spinning:
			player.stop()
			continue
		for animation_name in player.get_animation_list():
			if animation_name != "RESET":
				player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
				player.play(animation_name)
				break

func _update_camera() -> void:
	camera.position = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(Vector3.ZERO, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.007
		pitch = clampf(pitch + event.relative.y * 0.007, -1.3, 1.3)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(1.6, distance * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(12.0, distance * 1.12)
		_update_camera()
