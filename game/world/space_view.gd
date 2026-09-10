class_name SpaceView
extends SubViewportContainer

var showcase = false
var reduced_motion = false
var selected = ""
var viewport_3d: SubViewport
var world: Node3D
var camera: Camera3D
var vessel: Node3D
var contacts: Dictionary = {}
var _angle = 0.0
var _zoom = 1.0
var _clock = 0.0
var _beam: MeshInstance3D

static func model(name: String) -> Node3D:
	if name in LeisurePlaces.MODELS:
		var bundle = load("res://assets/models/leisure_bundle.glb") as PackedScene
		var temporary = bundle.instantiate()
		var instance = temporary.get_node(NodePath(name)) as Node3D
		temporary.remove_child(instance)
		temporary.free()
		return instance
	var path = "res://assets/models/" + name + ".glb"
	var packed = load(path) as PackedScene
	assert(packed != null, "Missing model: " + path)
	return packed.instantiate() as Node3D

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
	env.background_color = Color("070f1c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("93b9c8")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world.add_child(env_node)
	var light = DirectionalLight3D.new()
	light.light_color = Color("fff2d9")
	light.light_energy = 1.5
	light.rotation_degrees = Vector3(-35, -35, 0)
	world.add_child(light)
	var fill = DirectionalLight3D.new()
	fill.light_color = Color("4fc4cf")
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(25, 135, 0)
	world.add_child(fill)
	_stars()
	vessel = model("itsaso")
	vessel.scale = Vector3.ONE * (1.0 if showcase else 0.6)
	world.add_child(vessel)
	var planet = model("planet")
	planet.position = Vector3(-150, -95, -310) if showcase else Vector3(-210, -180, -420)
	planet.scale = Vector3.ONE * (55 if showcase else 80)
	var surface = ShaderMaterial.new()
	surface.shader = load("res://world/planet.gdshader")
	for mesh in planet.find_children("*", "MeshInstance3D", true, false): mesh.material_override = surface
	world.add_child(planet)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 69 if showcase else 98
	torus.outer_radius = 72 if showcase else 102
	torus.rings = 96
	torus.ring_segments = 8
	ring.mesh = torus
	ring.position = planet.position
	ring.rotation_degrees = Vector3(20, 0, -15)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("507c81")
	material.metallic = 0.3
	ring.material_override = material
	world.add_child(ring)
	var random = RandomNumberGenerator.new()
	random.seed = 2046
	for i in 16:
		var rock = model("asteroid")
		rock.position = Vector3(random.randf_range(-70, 80), random.randf_range(-30, 20), random.randf_range(-100, -40))
		rock.scale = Vector3.ONE * random.randf_range(0.5, 2.0)
		rock.rotation = Vector3(random.randf() * TAU, random.randf() * TAU, 0)
		world.add_child(rock)
	camera = Camera3D.new()
	camera.fov = 42 if showcase else 55
	camera.far = 5000
	world.add_child(camera)
	camera.current = true
	_beam = MeshInstance3D.new()
	world.add_child(_beam)
	gui_input.connect(_orbit_input)
	_update_camera()
	var avatars = get_node_or_null("/root/Avatars")
	if avatars != null:
		var button = ConsoleUI.button("Mi avatar", avatars.open_editor)
		button.name = "AvatarButton"
		button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		button.offset_left = -164
		button.offset_right = -16
		button.offset_top = 16
		button.offset_bottom = 60
		button.tooltip_text = "Traje, visor y equipo · Alt+A"
		add_child(button)

func _stars() -> void:
	var instance = MultiMeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 6
	mesh.rings = 3
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = 800
	var random = RandomNumberGenerator.new()
	random.seed = 710
	for i in 800:
		var direction = Vector3(random.randf_range(-1, 1), random.randf_range(-1, 1), random.randf_range(-1, 1)).normalized()
		var transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * random.randf_range(0.6, 2.4)), direction * random.randf_range(300, 900))
		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_color(i, Color("a1c7d0").lerp(Color("fff0cf"), random.randf()))
	instance.multimesh = multimesh
	world.add_child(instance)

func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_angle -= event.relative.x * 0.006
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _zoom = maxf(0.65, _zoom - 0.1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _zoom = minf(2.4, _zoom + 0.1)
		_update_camera()

func _update_camera() -> void:
	if camera == null: return
	var base = Vector3(24, 15, 27) if showcase else Vector3(10, 11, 16)
	camera.position = base.rotated(Vector3.UP, _angle) * _zoom
	camera.look_at(Vector3(0, 1, 0))

func _session_view() -> Dictionary:
	var session = get_tree().root.get_node_or_null("Session")
	return session.view if session != null else {}

func _process(delta: float) -> void:
	if vessel == null: return
	_clock += delta
	if showcase:
		vessel.rotation.y = -0.35 + (sin(_clock * 0.10) * 0.12 if not reduced_motion else 0.0)
		vessel.position.y = sin(_clock * 0.4) * 0.2 if not reduced_motion else 0.0
		return
	var data: Dictionary = _session_view()
	if data.is_empty(): return
	vessel.rotation.y = -deg_to_rad(data.ship.heading) - PI / 2
	var active: Array = []
	for c in data.contacts:
		active.append(c.id)
		if contacts.has(c.id) and contacts[c.id].kind != c.kind:
			contacts[c.id].node.queue_free()
			contacts.erase(c.id)
		if not contacts.has(c.id):
			var mapped = {"station": "station", "friendly": "transport", "hostile": "sentinel", "derelict": "transport", "anomaly": "anomaly", "beacon": "beacon", "unknown": "beacon", "asteroid": "asteroid", "planet": "planet", "blackhole": "anomaly", "wormhole": "anomaly", "nebula": "anomaly"}
			var node = Node3D.new()
			var object = PickupModel.create(c.kind) if c.kind in SpacePickups.KINDS else model(mapped[c.kind])
			var scale_value = {"station": 0.7, "beacon": 0.35, "unknown": 0.20}.get(c.kind, 0.7)
			if c.kind in SpacePhysics.KINDS: scale_value = SpacePhysics.radius(c) * 0.04
			object.scale = Vector3.ONE * scale_value
			node.add_child(object)
			var title = Label3D.new()
			title.text = c.name
			title.font_size = 42
			title.pixel_size = 0.006
			title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			title.position.y = 7
			title.modulate = ConsoleUI.RED if c.kind == "hostile" else ConsoleUI.TEAL
			title.no_depth_test = true
			node.add_child(title)
			world.add_child(node)
			contacts[c.id] = {"node": node, "kind": c.kind, "label": title}
		var node: Node3D = contacts[c.id].node
		node.position = Vector3(c.position[0] - data.ship.position[0], 0, c.position[1] - data.ship.position[1]) * 0.04
		node.visible = c.hull > 0 and node.position.length() < 300
		contacts[c.id].label.text = ("◆ " if selected == c.id else "") + c.name
	for id in contacts.keys():
		if id not in active:
			contacts[id].node.queue_free()
			contacts.erase(id)
	_beam.visible = false
	if data.ship.weapon_ready - data.time > 2.6 and contacts.has(selected):
		var mesh = ImmediateMesh.new()
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = ConsoleUI.AMBER
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		mesh.surface_add_vertex(Vector3(0, 0.8, 0))
		mesh.surface_add_vertex(contacts[selected].node.position)
		mesh.surface_end()
		_beam.mesh = mesh
		_beam.visible = true
