class_name WorldDeck
extends SubViewportContainer
signal station_requested(role: String)
signal zone_changed(name: String)

const ZONES = [
	{"name": "Puente", "model": "bridge_room", "at": Vector3(0, 0, -42), "role": "navegacion", "depth": 20.0},
	{"name": "Pasillo central", "model": "hallway", "at": Vector3.ZERO, "role": "mando", "depth": 42.0},
	{"name": "Ingeniería", "model": "engineering_room", "at": Vector3(-24, 0, -12), "role": "ingenieria", "depth": 14.0},
	{"name": "Camarotes", "model": "quarters_room", "at": Vector3(24, 0, -12), "role": "comunicaciones", "depth": 14.0},
	{"name": "Bodega", "model": "cargo_room", "at": Vector3(-24, 0, 12), "role": "enlace", "depth": 14.0},
	{"name": "Comedor", "model": "mess_room", "at": Vector3(24, 0, 12), "role": "mando", "depth": 14.0},
	{"name": "Enfermería", "model": "medbay_room", "at": Vector3(0, 0, 42), "role": "reparaciones", "depth": 14.0}
]
var zone = 0
var prompt = "Pulsa sobre la vista para mirar y caminar."
var viewport_3d: SubViewport
var world: Node3D
var body: CharacterBody3D
var camera: Camera3D
var _doors: Array = []
var _near_door = -1
var _near_station = false
var _pose_clock = 0.0
var _avatars: Dictionary = {}

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_3d = SubViewport.new()
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	add_child(viewport_3d)
	world = Node3D.new()
	viewport_3d.add_child(world)
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("091b31")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9c5d3")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world.add_child(env_node)
	for area in ZONES:
		var model = SpaceView.model(area.model)
		model.position = area.at
		world.add_child(model)
		for mesh in model.find_children("*", "MeshInstance3D", true, false): mesh.create_trimesh_collision()
		for sign_x in [-1, 1]:
			var light = OmniLight3D.new()
			light.position = area.at + Vector3(sign_x * 3.5, 3.5, 1)
			light.omni_range = 16
			light.light_energy = 1.8
			light.light_color = Color("bbe9e5") if sign_x == 1 else Color("f4c98a")
			world.add_child(light)
	for i in ZONES.size():
		if i == 1: continue
		var destination = ZONES[i]
		var location: Vector3
		match i:
			0: location = Vector3(0, 0, -19)
			2: location = Vector3(-2, 0, -12)
			3: location = Vector3(2, 0, -12)
			4: location = Vector3(-2, 0, 12)
			5: location = Vector3(2, 0, 12)
			_: location = Vector3(0, 0, 19)
		_add_door(location, i, "ESCOTILLA · " + destination.name.to_upper(), 1)
		_add_door(destination.at + Vector3(0, 0, destination.depth * 0.5 - 0.6), 1, "PASILLO CENTRAL", i)
	body = CharacterBody3D.new()
	body.safe_margin = 0.025
	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.65
	shape.shape = capsule
	shape.position.y = 0.9
	body.add_child(shape)
	world.add_child(body)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.fov = 75
	camera.near = 0.05
	body.add_child(camera)
	camera.current = true
	gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	teleport_zone(0)

func _add_door(position: Vector3, destination: int, title: String, source: int) -> void:
	_doors.append({"position": position, "target": destination, "source": source})
	var label = Label3D.new()
	label.text = title + "\nE · ACCEDER"
	label.position = position + Vector3(0, 2.5, 0)
	label.pixel_size = 0.004
	label.font_size = 32
	label.modulate = ConsoleUI.AMBER
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	world.add_child(label)

func teleport_zone(index: int) -> void:
	zone = clampi(index, 0, ZONES.size() - 1)
	if body == null: return
	body.position = ZONES[zone].at + Vector3(0 if zone == 1 else 4.8, 0.4, ZONES[zone].depth * 0.5 - 2.0)
	body.velocity = Vector3.ZERO
	body.rotation.y = 0
	if zone != 1: body.look_at(ZONES[zone].at + Vector3(0, 0.4, 0))
	camera.rotation.x = -0.06
	zone_changed.emit(ZONES[zone].name)
	Session.update_pose(body.position, body.rotation.y)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			body.rotation.y -= event.relative.x * 0.0022
			camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.0022, -1.25, 1.25)
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_E:
				if _near_door >= 0: teleport_zone(_near_door)
				elif _near_station: station_requested.emit(ZONES[zone].role)

func _physics_process(delta: float) -> void:
	if body == null: return
	var input = Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		input.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var direction = body.basis * Vector3(input.x, 0, input.y).normalized()
	var speed = 5.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 3.1
	body.velocity.x = direction.x * speed
	body.velocity.z = direction.z * speed
	if not body.is_on_floor(): body.velocity.y -= 9.8 * delta
	else: body.velocity.y = 0
	body.move_and_slide()
	if body.position.y < -5: teleport_zone(zone)
	_near_door = -1
	_near_station = false
	for door in _doors:
		if door.source == zone and Vector2(body.position.x - door.position.x, body.position.z - door.position.z).length() < 2.4: _near_door = door.target
	var center: Vector3 = ZONES[zone].at
	_near_station = zone != 1 and Vector2(body.position.x - center.x, body.position.z - center.z).length() < 4.0
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: prompt = "Pulsa en la vista · WASD para caminar · Ratón para mirar"
	elif _near_door >= 0: prompt = "E · Acceder a " + ZONES[_near_door].name
	elif _near_station: prompt = "E · Operar " + Catalog.role_name(ZONES[zone].role)
	else: prompt = "WASD · Caminar     Mayús · Correr     Esc · Liberar el ratón"
	_pose_clock += delta
	if _pose_clock > 0.1:
		_pose_clock = 0.0
		Session.update_pose(body.position, body.rotation.y)
		_update_avatars()

func _update_avatars() -> void:
	var active: Array = []
	for key in Session.poses:
		var id = int(key)
		if id == multiplayer.get_unique_id(): continue
		active.append(id)
		if not _avatars.has(id):
			var avatar = SpaceView.model("crew")
			world.add_child(avatar)
			_avatars[id] = avatar
		var pose: Dictionary = Session.poses[key]
		_avatars[id].position = Vector3(pose.position[0], pose.position[1], pose.position[2])
		_avatars[id].rotation.y = float(pose.yaw)
	for id in _avatars.keys():
		if id not in active:
			_avatars[id].queue_free()
			_avatars.erase(id)

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
