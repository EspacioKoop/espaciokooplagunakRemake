class_name AvatarPortrait
extends SubViewportContainer
## Portrait and full-body preview render the same crew asset and appearance.

var avatar: Node3D
var camera: Camera3D
var portrait = false
var _profile = AvatarProfile.defaults()
var _yaw = 0.0

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var world = Node3D.new()
	viewport.add_child(world)
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("0d2330")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b7d4dd")
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	world.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 155, 0)
	light.light_energy = 1.5
	world.add_child(light)
	avatar = SpaceView.model("crew")
	world.add_child(avatar)
	AvatarAppearance.apply(avatar, _profile)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.87 if portrait else 2.35
	camera.position = Vector3(0, 1.61 if portrait else 1.2, -4)
	world.add_child(camera)
	camera.look_at(Vector3(0, 1.61 if portrait else 1.03, 0))
	camera.current = true
	gui_input.connect(_orbit)

func set_profile(value: Dictionary) -> void:
	_profile = value.duplicate(true)
	if avatar != null: AvatarAppearance.apply(avatar, value)

func turn(amount: float) -> void:
	_yaw = wrapf(_yaw + amount, -PI, PI)
	if avatar != null: avatar.rotation.y = _yaw

func _orbit(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		turn(event.relative.x * 0.012)
