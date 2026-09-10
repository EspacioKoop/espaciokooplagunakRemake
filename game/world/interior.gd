class_name WorldDeck
extends SubViewportContainer
signal station_requested(role: String)
signal zone_changed(name: String)
signal interaction_requested(entry: Dictionary)

const ZONES = ShipDeckLayout.ZONES
var zone = 0
var prompt = "Pulsa sobre la vista para mirar y caminar."
var viewport_3d: SubViewport
var world: Node3D
var body: CharacterBody3D
var camera: Camera3D
var _doors: Array = []
var _near_door = -1
var _near_corridor_door = -1
var _near_station = false
var _pose_clock = 0.0
var _avatars: Dictionary = {}
var _zone_models: Array = []
var _interactions: Array = []
var _near_interaction: Dictionary = {}
var _physical_seats: Dictionary = {}
var _environment: Environment
var _sun: DirectionalLight3D
var _animation_time = 0.0
var _corridors: ShipCorridors
var _map: DeckMap
var reduced_motion = false
var seated = false
var _standing_position = Vector3.ZERO
var _leaving_seat = false
var _seat_requested = false
var _seat_notice = ""
var _seat_notice_until = 0
var _book_page = 0
var _page_turn = 0.0
var _studio_lights: Array = []
var _studio_mode = 0
var book_open = false

func _session() -> Node:
	return get_tree().root.get_node_or_null("Session") if is_inside_tree() else null

func _presence() -> Node:
	return get_tree().root.get_node_or_null("SeatPresence") if is_inside_tree() else null

func _ready() -> void:
	_physical_seats = PhysicalSeatCatalog.all_seats()
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
	_environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("091b31")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9c5d3")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world.add_child(env_node)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-18, -70, 0)
	_sun.light_color = Color("ffdbab")
	_sun.light_energy = 0.6
	_sun.shadow_enabled = true
	world.add_child(_sun)
	for area in ZONES:
		var model = SpaceView.model(area.model)
		model.position = area.at
		world.add_child(model)
		_zone_models.append(model)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			if not mesh.name.begins_with("Decor_"): mesh.create_trimesh_collision()
			if mesh.name.begins_with("Decor_Water"):
				var water = ShaderMaterial.new()
				water.shader = load("res://world/sea.gdshader")
				water.set_shader_parameter("movement", 0.0 if reduced_motion else 1.0)
				mesh.material_override = water
		for sign_x in [-1, 1]:
			var light = OmniLight3D.new()
			light.position = area.at + Vector3(sign_x * 3.5, 3.5, 1)
			light.omni_range = 16
			light.light_energy = 1.8
			light.light_color = Color("bbe9e5") if sign_x == 1 else Color("f4c98a")
			world.add_child(light)
	_corridors = ShipCorridors.new()
	world.add_child(_corridors)
	_corridors.setup(self)
	_add_door(Vector3(2, 0, 0), 7, "CANTINA", 1)
	_add_door(ZONES[7].at + Vector3(0, 0, 10.5), 1, "VOLVER A LA NAVE", 7)
	var connections = [Vector3(-10, 0, -7), Vector3(-10, 0, 1), Vector3(10, 0, -7), Vector3(10, 0, 1), Vector3(0, 0, -10.5)]
	for i in range(8, ZONES.size()):
		_add_door(ZONES[7].at + connections[i - 8], i, ZONES[i].name.to_upper(), 7)
		var exit_position = Vector3(-7, 0, 49.2) if i == 9 else Vector3(0, 0, ZONES[i].depth * 0.5 - 0.7)
		_add_door(ZONES[i].at + exit_position, 7, "CABINA · VOLVER A CANTINA" if i == 9 else "VOLVER A CANTINA", i)
		for entry in LeisurePlaces.interactions(i):
			entry.zone = i
			entry.position += ZONES[i].at
			_interactions.append(entry)
	for entry in LeisurePlaces.interactions(7):
		entry.zone = 7
		entry.position += ZONES[7].at
		_interactions.append(entry)
	for entry in _interactions:
		if entry.kind == "seat": continue
		var sign = Label3D.new()
		sign.text = entry.title + "\nE · " + ("LEER" if entry.kind in ["plaque", "book"] else "INTERACTUAR")
		sign.position = entry.position - ZONES[entry.zone].at + Vector3(0, 1.45, 0)
		sign.font_size = 32
		sign.pixel_size = 0.006
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.modulate = ConsoleUI.AMBER
		_zone_models[entry.zone].add_child(sign)
	for i in 3:
		var light = SpotLight3D.new()
		light.position = Vector3(-5 + i * 5, 4.5, -2)
		light.light_color = [Color("ffbd7d"), Color("83cee8"), Color("d5a7ff")][i]
		light.light_energy = 5
		light.spot_range = 18
		light.spot_angle = 40
		_zone_models[11].add_child(light)
		light.look_at(ZONES[11].at + Vector3(0, 1, -6))
		_studio_lights.append(light)
	for boundary in [[Vector3(12.1, 1.5, 0), Vector3(0.25, 3, 112)], [Vector3(-20, 2, 0), Vector3(0.25, 4, 112)], [Vector3(-4, 2, -56), Vector3(32, 4, 0.25)], [Vector3(-4, 2, 56), Vector3(32, 4, 0.25)]]:
		var wall = StaticBody3D.new()
		var collider = CollisionShape3D.new()
		var barrier = BoxShape3D.new()
		barrier.size = boundary[1]
		collider.shape = barrier
		wall.add_child(collider)
		wall.position = boundary[0]
		_zone_models[9].add_child(wall)
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
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _controls_blocked(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_map = DeckMap.new()
	_map.deck = self
	_map.anchor_left = 1.0
	_map.anchor_right = 1.0
	_map.offset_left = -316
	_map.offset_right = -16
	_map.offset_top = 16
	_map.offset_bottom = 356
	add_child(_map)
	var presence = _presence()
	if presence != null:
		presence.bind_body(body)
		presence.changed.connect(_sync_seat)
		presence.result_received.connect(_seat_result)
		presence.request_finished.connect(_seat_finished)
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
	_doors.back().label = label

func teleport_zone(index: int) -> void:
	stand_up()
	zone = clampi(index, 0, ZONES.size() - 1)
	if body == null: return
	if zone < ShipDeckLayout.SHIP_COUNT:
		body.position = ShipDeckLayout.spawn(zone)
	else:
		body.position = ZONES[zone].at + Vector3(4.8, 0.4, ZONES[zone].depth * 0.5 - 2.0)
	body.velocity = Vector3.ZERO
	body.rotation.y = 0
	if zone != 1: body.look_at(ZONES[zone].at + Vector3(0, 0.4, 0))
	camera.rotation.x = -0.06
	_apply_zone_visibility()
	_sun.visible = true
	_sun.light_energy = 0.55 if zone in [9, 10] else 0.7
	_sun.rotation_degrees = Vector3(-18, -70, 0) if zone in [9, 10] else Vector3(-40, -25, 0)
	_environment.background_color = Color("719aab") if zone in [9, 10] else Color("091b31")
	_environment.ambient_light_color = Color("b7d7ef") if zone in [9, 10] else Color("a9c5d3")
	_environment.ambient_light_energy = 0.22 if zone in [9, 10] else 0.25
	zone_changed.emit(ZONES[zone].name)
	var session = _session()
	if session != null: session.update_pose(body.position, body.rotation.y)

func _apply_zone_visibility() -> void:
	var on_ship = zone < 7
	for i in _zone_models.size(): _zone_models[i].visible = (on_ship and i < 7) or (not on_ship and i == zone)
	for door in _doors: door.label.visible = door.source == zone
	if _corridors != null:
		_corridors.visible = on_ship
		_corridors.update_labels(zone)
	if _map != null: _map.visible = on_ship

func _controls() -> Node:
	return get_tree().root.get_node_or_null("Controls")

func _controls_blocked() -> bool:
	var controls = _controls()
	return controls != null and controls.gameplay_blocked()

func _input_action(event: InputEvent, action: String, fallback: int) -> bool:
	if _controls() != null and InputMap.has_action(action): return event.is_action_pressed(action)
	if action == "capture_pointer": return event is InputEventMouseButton and event.button_index == fallback and event.pressed
	return event is InputEventKey and event.keycode == fallback and event.pressed and not event.echo

func _binding(action: String, fallback: String) -> String:
	var controls = _controls()
	return controls.binding_label(action) if controls != null else fallback

func _character_control_active() -> bool:
	var controls = _controls()
	return controls.character_control_active() if controls != null else Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_visible_in_tree() or not is_instance_valid(body) or _controls_blocked(): return
	if _input_action(event, "release_pointer", KEY_ESCAPE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _map != null and _map.has_focus():
			_map.select_destination(-1)
			_map.release_focus()
		get_viewport().set_input_as_handled()
		return
	if _input_action(event, "capture_pointer", MOUSE_BUTTON_LEFT):
		if _map != null and _map.is_visible_in_tree() and _map.get_global_rect().has_point(get_global_mouse_position()): return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _character_control_active():
		if event is InputEventMouseMotion:
			var controls = _controls()
			var look: Vector2 = controls.mouse_look(event.relative) if controls != null else event.relative * 0.0022
			_apply_look(look)
		if _input_action(event, "interact", KEY_E):
			# A station callback can synchronously detach this viewport (#29).
			get_viewport().set_input_as_handled()
			interact()

func interact() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(body): return
	if seated: stand_up()
	elif _near_corridor_door >= 0: _corridors.toggle(_near_corridor_door)
	elif _near_door >= 0: teleport_zone(_near_door)
	elif not _near_interaction.is_empty():
		if _near_interaction.kind == "seat":
			var presence = _presence()
			if presence == null: return
			_standing_position = body.position
			_leaving_seat = false
			var session = _session()
			if session != null: session.update_pose(body.position, body.rotation.y)
			_seat_requested = true
			presence.request_sit(_near_interaction.id)
		elif _near_interaction.kind == "lights":
			_studio_mode = (_studio_mode + 1) % 4
			for i in _studio_lights.size(): _studio_lights[i].visible = _studio_mode == 0 or i == _studio_mode - 1
		else: interaction_requested.emit(_near_interaction.duplicate())
	elif _near_station: station_requested.emit(ZONES[zone].role)

func _apply_look(look: Vector2) -> void:
	if seated: camera.rotation.y = clampf(camera.rotation.y - look.x, -1.2, 1.2)
	else: body.rotation.y -= look.x
	camera.rotation.x = clampf(camera.rotation.x - look.y, -1.25, 1.25)

func _seat_result(ok: bool, message: String) -> void:
	if not ok:
		_seat_notice = message
		_seat_notice_until = Time.get_ticks_msec() + 2500
	_sync_seat()

func _seat_finished(operation: String, _ok: bool, _message: String) -> void:
	if operation == "sit": _seat_requested = false
	elif operation == "stand": _leaving_seat = false
	_sync_seat()

func _sync_seat() -> void:
	if not is_instance_valid(body): return
	var presence = _presence()
	if presence == null: return
	var seat: Dictionary = presence.seat_for(presence.local_peer())
	if seat.is_empty():
		_restore_standing()
	elif not _leaving_seat:
		if not seated:
			_standing_position = body.position
			camera.rotation.y = 0
		seated = true
		body.position = seat.anchor
		body.rotation.y = seat.yaw
		body.velocity = Vector3.ZERO
		camera.position.y = 1.15
		body.collision_mask = 0

func _restore_standing() -> void:
	if not seated or not is_instance_valid(body): return
	seated = false
	body.position = _standing_position
	body.velocity = Vector3.ZERO
	body.collision_mask = 1
	camera.position.y = 1.65
	camera.rotation.y = 0

func stand_up() -> void:
	# Cancel even a pending reservation when leaving the zone or closing the deck.
	var presence = _presence()
	var must_release = _seat_requested or seated or (presence != null and not presence.seat_for(presence.local_peer()).is_empty())
	_leaving_seat = must_release
	_restore_standing()
	if presence != null and must_release: presence.request_stand()

func turn_book(page: int) -> void:
	_book_page = page
	_page_turn = 1.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(body): return
	_animation_time += delta if not reduced_motion else 0.0
	_animate_decor(delta)
	_sync_seat()
	var input = Vector2.ZERO
	var controls = _controls()
	if _character_control_active() and not _controls_blocked():
		if controls != null:
			input = controls.movement_vector()
			var look: Vector2 = controls.look_vector() * delta
			_apply_look(look)
		else:
			input.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
			input.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var direction = body.basis * Vector3(input.x, 0, input.y).limit_length()
	var sprint = controls.action_pressed("sprint") if controls != null else Input.is_physical_key_pressed(KEY_SHIFT)
	var speed = 5.0 if sprint else 3.1
	body.velocity.x = direction.x * speed
	body.velocity.z = direction.z * speed
	if not body.is_on_floor(): body.velocity.y -= 9.8 * delta
	else: body.velocity.y = 0
	if not seated: body.move_and_slide()
	else: body.velocity = Vector3.ZERO
	if body.position.y < -5: teleport_zone(zone)
	if zone < 7:
		var detected = _corridors.zone_for(body.position, zone)
		if detected != zone:
			zone = detected
			_apply_zone_visibility()
			zone_changed.emit(ZONES[zone].name)
	_near_door = -1
	_near_corridor_door = _corridors.near_door(body.position, zone) if zone < 7 else -1
	_near_station = false
	_near_interaction = {}
	var closest = 2.2
	for entry in _interactions:
		if entry.zone != zone: continue
		if entry.kind == "seat" and not PhysicalSeatCatalog.reachable(_physical_seats.get(entry.id, {}), body.position): continue
		var distance = Vector2(body.position.x - entry.position.x, body.position.z - entry.position.z).length()
		if distance < closest:
			closest = distance
			_near_interaction = entry
	for door in _doors:
		if door.source == zone and Vector2(body.position.x - door.position.x, body.position.z - door.position.z).length() < 2.4: _near_door = door.target
	var center: Vector3 = ZONES[zone].at
	_near_station = zone < 7 and zone != 1 and Vector2(body.position.x - center.x, body.position.z - center.z).length() < 4.0
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: prompt = "Pulsa en la vista · WASD para caminar · Ratón para mirar"
	elif seated: prompt = "E · Levantarse     Ratón · Mirar alrededor"
	elif _near_corridor_door >= 0: prompt = _corridors.prompt_for(_near_corridor_door)
	elif _near_door >= 0: prompt = "E · Acceder a " + ZONES[_near_door].name
	elif not _near_interaction.is_empty(): prompt = "E · " + _near_interaction.title
	elif _near_station: prompt = "E · Operar " + Catalog.role_name(ZONES[zone].role)
	else: prompt = "WASD · Caminar     Mayús · Correr     Esc · Liberar el ratón"
	if not seated and _near_interaction.get("kind") == "seat" and _presence() != null and _presence().occupant(_near_interaction.id) != 0:
		prompt = "Asiento ocupado"
	if Time.get_ticks_msec() < _seat_notice_until: prompt = _seat_notice
	if controls != null:
		prompt = prompt.replace("E ·", _binding("interact", "E") + " ·").replace("Mayús ·", _binding("sprint", "Mayús") + " ·").replace("Esc ·", _binding("release_pointer", "Esc") + " ·")
		prompt = prompt.replace("WASD", "/".join([_binding("move_forward", "W"), _binding("move_left", "A"), _binding("move_back", "S"), _binding("move_right", "D")]))
	_pose_clock += delta
	if _pose_clock > 0.1:
		_pose_clock = 0.0
		var session = _session()
		if session != null:
			session.update_pose(body.position, body.rotation.y)
			_update_avatars(session)

func _animate_decor(delta: float) -> void:
	if _zone_models.size() < 13: return
	if zone == 9:
		for node in _zone_models[9].find_children("*", "Node3D", true, false):
			if node.name.begins_with("wind_rotor_"): node.rotation = Vector3(0, PI / 2, _animation_time * 0.35)
			elif node.name == "second_hand": node.rotation.z = -_animation_time * TAU / 60
			elif node.name == "minute_hand": node.rotation.z = -_animation_time * TAU / 3600
			elif node.name == "hour_hand": node.rotation.z = -_animation_time * TAU / 43200
	if zone == 8:
		_page_turn = maxf(0, _page_turn - delta * 1.5)
		var page_node = _zone_models[8].find_child("turning_page", true, false) as Node3D
		if page_node != null:
			page_node.visible = book_open
			page_node.rotation.z = -sin(_page_turn * PI) * PI * 0.8
		for cover_name in ["cover_left", "cover_right"]:
			var cover = _zone_models[8].find_child(cover_name, true, false) as Node3D
			if cover != null: cover.rotation.z = move_toward(cover.rotation.z, 0.0 if book_open else (-PI / 2 if cover_name == "cover_left" else PI / 2), delta * 3)
		var pages = _zone_models[8].find_child("Pages", true, false) as Node3D
		if pages != null: pages.visible = book_open

func _update_avatars(session: Node) -> void:
	var active: Array = []
	for key in session.poses:
		var id = int(key)
		if id == multiplayer.get_unique_id(): continue
		active.append(id)
		if not _avatars.has(id):
			var avatar = SpaceView.model("crew")
			world.add_child(avatar)
			_avatars[id] = avatar
			var avatars = get_tree().root.get_node_or_null("Avatars")
			if avatars != null: avatars.bind_avatar(avatar, id)
		var pose: Dictionary = session.poses[key]
		var presence = _presence()
		var seat: Dictionary = presence.seat_for(id) if presence != null else {}
		_avatars[id].position = Vector3(pose.position[0], pose.position[1], pose.position[2]) if seat.is_empty() else seat.anchor + Vector3(0, -0.4, 0)
		_avatars[id].rotation.y = float(pose.yaw) if seat.is_empty() else seat.yaw
		PhysicalSeatCatalog.apply_pose(_avatars[id], not seat.is_empty())
	for id in _avatars.keys():
		if id not in active:
			_avatars[id].queue_free()
			_avatars.erase(id)

func _exit_tree() -> void:
	stand_up()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
