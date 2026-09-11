class_name AssetPreview
extends SubViewportContainer
## Isolated inspection scene; never adds collision bodies to the live game.
var viewport_3d: SubViewport
var world: Node3D
var camera: Camera3D
var model: Node3D
var model_id = ""
var extent = AABB()
var _radius = 1.0
var _yaw = 0.65
var _pitch = 0.25
var _zoom = 1.0
var _players: Array[AnimationPlayer] = []

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(260, 240)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_3d = SubViewport.new()
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport_3d)
	world = Node3D.new()
	viewport_3d.add_child(world)
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101e2b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d6e6f5")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	for rotation in [Vector3(-40, -35, 0), Vector3(20, 145, 0)]:
		var light = DirectionalLight3D.new()
		light.rotation_degrees = rotation
		light.light_energy = 1.5 if rotation.x < 0 else 0.7
		world.add_child(light)
	camera = Camera3D.new()
	camera.fov = 45
	world.add_child(camera)
	camera.current = true
	gui_input.connect(_orbit)
	resized.connect(_camera)

func show_asset(id: String) -> bool:
	var instance = RuntimeAssetLibrary.instantiate(id)
	if instance == null: return false
	var box = RuntimeAssetLibrary.bounds(instance)
	if not box.size.is_finite() or box.size.length() <= 0:
		instance.free()
		return false
	if is_instance_valid(model):
		model.get_parent().remove_child(model)
		model.queue_free()
	model = instance
	model_id = id
	extent = box
	model.position -= box.get_center()
	world.add_child(model)
	_players.clear()
	for node in model.find_children("*", "AnimationPlayer", true, false):
		_players.append(node)
		node.stop()
	_radius = maxf(0.05, box.size.length() * 0.5)
	_zoom = 1.0
	_camera()
	return true

func set_animation(enabled: bool) -> void:
	for player in _players:
		if not enabled:
			player.pause()
			continue
		var clips = player.get_animation_list()
		for clip in clips:
			if clip == "RESET": continue
			player.play(clip)
			break

func reset_view() -> void:
	_yaw = 0.65
	_pitch = 0.25
	_zoom = 1.0
	_camera()

func _orbit(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch + event.relative.y * 0.008, -1.2, 1.2)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _zoom = maxf(0.65, _zoom / 1.1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _zoom = minf(4.0, _zoom * 1.1)
	_camera()

func _camera() -> void:
	if not is_instance_valid(camera): return
	var aspect = maxf(0.2, size.x / maxf(1.0, size.y))
	var half_fov = atan(tan(deg_to_rad(camera.fov) / 2.0) * minf(1.0, aspect))
	var distance = _radius / sin(half_fov) * 1.25 * _zoom
	var direction = Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	camera.position = direction * distance
	camera.near = maxf(0.001, _radius / 2000.0)
	camera.far = maxf(100.0, distance + _radius * 8.0)
	camera.look_at(Vector3.ZERO)
