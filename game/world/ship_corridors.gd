class_name ShipCorridors
extends Node3D
## Always-loaded physical connectors. Layout owns transforms; this component
## owns corridor geometry and local hatches, never player movement or teleports.

var deck: Node
var doors: Array = []
var links: Array = []
var _materials: Dictionary = {}
var _label_clock = 0.0

func setup(owner: Node) -> void:
	deck = owner
	for index in ShipDeckLayout.SHIP_COUNT:
		deck._zone_models[index].rotation.y = ShipDeckLayout.ROOM_YAW[index]
	for spec in ShipDeckLayout.connectors():
		_add_link(spec.start, spec.source, spec.finish, spec.target)
	_seal_hallway()
	_install_social_tables()
	update_labels(0)

func _process(delta: float) -> void:
	_label_clock += delta
	if _label_clock >= 0.1 and is_instance_valid(deck):
		_label_clock = 0.0
		update_labels(deck.zone)

func _seal_hallway() -> void:
	# Close the spaces between branches: the hallway must not open into the void.
	# Branch portals remain centred between the authored pillars, at Z +/-10.
	var wall = _material(Color("101b30"), 0.55)
	for side in [-1.0, 1.0]:
		for span in [Vector2(-21, -11.8), Vector2(-8.2, 8.2), Vector2(11.8, 21)]:
			_solid_box(self, Vector3(side * 3.0, 1.55, (span.x + span.y) * 0.5), Vector3(0.18, 3.1, span.y - span.x), wall)
		for end in [-20.85, 20.85]:
			_solid_box(self, Vector3(side * 2.4, 1.55, end), Vector3(1.2, 3.1, 0.18), wall)
	# Ship-relative labels remain true when approached from the other direction.
	for spec in [[-6.0, "PROA · PUENTE\nCAMAROTES (BABOR) · ENFERMERÍA (ESTRIBOR)"], [6.0, "POPA · INGENIERÍA\nBODEGA (BABOR) · COMEDOR (ESTRIBOR)"]]:
		var sign = Label3D.new()
		sign.text = spec[1]
		sign.position = Vector3(0, 2.6, spec[0])
		sign.font_size = 28
		sign.pixel_size = 0.004
		sign.modulate = ConsoleUI.TEAL
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(sign)

func _install_social_tables() -> void:
	if deck._zone_models.size() <= 7: return
	var session = deck.get_tree().root.get_node_or_null("Session")
	if session == null: return
	var cantina: Node3D = deck._zone_models[7]
	for spec in [["poker", Vector3(-5, 1.08, 0)], ["blackjack", Vector3(5, 1.08, 0)], ["dados", Vector3(-5, 1.08, 6)]]:
		var display = SocialTableDisplay.new()
		display.table_id = spec[0]
		display.session = session
		display.position = spec[1]
		cantina.add_child(display)

func _add_link(start: Vector3, source: int, finish: Vector3, target: int) -> void:
	var delta = finish - start
	var length = Vector2(delta.x, delta.z).length()
	if length < 1.0: return
	var yaw = atan2(delta.x, delta.z)
	var tunnel = Node3D.new()
	tunnel.name = "Connector_%s_%s" % [source, target]
	tunnel.position = (start + finish) * 0.5
	tunnel.rotation.y = yaw
	add_child(tunnel)
	var floor_material = _material(Color("172c36"), 0.35)
	var wall_material = _material(Color("101b30"), 0.55)
	_solid_box(tunnel, Vector3(0, -0.15, 0), Vector3(ShipDeckLayout.CORRIDOR_WIDTH, 0.3, length + 0.5), floor_material)
	_solid_box(tunnel, Vector3(-1.75, 1.55, 0), Vector3(0.18, 3.1, length + 0.5), wall_material)
	_solid_box(tunnel, Vector3(1.75, 1.55, 0), Vector3(0.18, 3.1, length + 0.5), wall_material)
	_solid_box(tunnel, Vector3(0, 3.08, 0), Vector3(3.6, 0.16, length + 0.5), wall_material)
	# A continuous deck line reinforces the same route shown by the map.
	var guide = MeshInstance3D.new()
	var guide_mesh = BoxMesh.new()
	guide_mesh.size = Vector3(0.10, 0.008, length)
	guide.mesh = guide_mesh
	guide.material_override = _material(Color("62ddcc"), 0.0, 0.6)
	guide.position.y = 0.008
	tunnel.add_child(guide)
	var strips = maxi(1, int(length / 5.0))
	for i in strips:
		var strip = MeshInstance3D.new()
		var strip_mesh = BoxMesh.new()
		strip_mesh.size = Vector3(1.45, 0.035, 0.12)
		strip.mesh = strip_mesh
		strip.material_override = _material(Color("c3e8d9"), 0.15, 1.5)
		strip.position = Vector3(0, 2.96, -length * 0.5 + (i + 0.5) * length / strips)
		tunnel.add_child(strip)
		var light = OmniLight3D.new()
		light.position = strip.position + Vector3(0, -0.25, 0)
		light.omni_range = 5.0
		light.light_energy = 0.7
		light.light_color = Color("c6f2e9")
		tunnel.add_child(light)
	var a = _gate(start, source, target, yaw)
	var b = _gate(finish, target, source, yaw + PI)
	doors[a].paired = b
	doors[b].paired = a
	links.append({"source": source, "target": target, "start": start, "finish": finish, "a_door": a, "b_door": b, "length": length})

func _gate(position: Vector3, source: int, target: int, yaw: float) -> int:
	var root = StaticBody3D.new()
	root.name = "Door_%s_%s" % [source, target]
	root.position = position
	root.rotation.y = yaw
	add_child(root)
	var panel = MeshInstance3D.new()
	var panel_mesh = BoxMesh.new()
	panel_mesh.size = Vector3(3.1, 2.7, 0.14)
	panel.mesh = panel_mesh
	panel.material_override = _material(Color("26414b"), 0.72)
	panel.position.y = 1.35
	root.add_child(panel)
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(3.1, 2.7, 0.18)
	collider.shape = shape
	collider.position.y = 1.35
	root.add_child(collider)
	var label = Label3D.new()
	label.position = position + Vector3(0, 2.65, 0)
	label.pixel_size = 0.004
	label.font_size = 32
	label.modulate = ConsoleUI.AMBER
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Owned here so social destinations cannot leave detached hatch labels visible.
	add_child(label)
	var title: String = ShipDeckLayout.ZONES[target].name.to_upper()
	doors.append({"position": position, "yaw": yaw, "source": source, "target": target, "title": title, "open": false, "paired": -1, "panel": panel, "collider": collider, "label": label, "tween": null, "blocked": false})
	return doors.size() - 1

func _material(color: Color, metallic: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	var key = "%s:%s:%s" % [color.to_html(), metallic, emission]
	if _materials.has(key): return _materials[key]
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.72
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_materials[key] = material
	return material

func _solid_box(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> void:
	var solid = StaticBody3D.new()
	solid.position = position
	parent.add_child(solid)
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	solid.add_child(mesh)
	var collider = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	solid.add_child(collider)

func near_door(position: Vector3, source_zone: int) -> int:
	if source_zone >= ShipDeckLayout.SHIP_COUNT or not position.is_finite(): return -1
	var result = -1
	var best = 2.45
	for i in doors.size():
		var door: Dictionary = doors[i]
		if absf(position.y - door.position.y) > 2.0: continue
		# A hatch can be operated from either side, independently of zone ownership.
		var distance = ShipDeckLayout.xz(position - door.position).length()
		if distance < best:
			best = distance
			result = i
	return result

func toggle(index: int) -> void:
	if index < 0 or index >= doors.size(): return
	set_open(index, not bool(doors[index].open))

func _in_threshold(door: Dictionary, position: Vector3) -> bool:
	var local: Vector3 = (position - door.position).rotated(Vector3.UP, -door.yaw)
	return absf(local.x) < 1.9 and absf(local.z) < 0.55 and local.y > -0.5 and local.y < 2.8

func _occupied(door: Dictionary) -> bool:
	if is_instance_valid(deck.body) and _in_threshold(door, deck.body.position): return true
	var session = deck.get_tree().root.get_node_or_null("Session")
	if session == null: return false
	for pose in session.poses.values():
		var coordinates = pose.get("position", [])
		if coordinates.size() == 3 and _in_threshold(door, Vector3(coordinates[0], coordinates[1], coordinates[2])): return true
	return false

func set_open(index: int, opened: bool) -> bool:
	if index < 0 or index >= doors.size(): return false
	var door: Dictionary = doors[index]
	if door.open == opened: return true
	if not opened and _occupied(door):
		door.blocked = true
		return false
	door.blocked = false
	door.open = opened
	var collider: CollisionShape3D = door.collider
	collider.set_deferred("disabled", opened)
	var panel: MeshInstance3D = door.panel
	var old_tween: Tween = door.tween
	if old_tween != null and old_tween.is_valid(): old_tween.kill()
	if is_instance_valid(panel):
		var height = 4.5 if opened else 1.35
		if deck.reduced_motion:
			panel.position.y = height
		else:
			var tween = create_tween()
			door.tween = tween
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(panel, "position:y", height, 0.24)
	update_labels(deck.zone)
	return true

func destination_for(index: int, position: Vector3) -> int:
	var door: Dictionary = doors[index]
	var local: Vector3 = (position - door.position).rotated(Vector3.UP, -door.yaw)
	return int(door.source) if local.z > 0 else int(door.target)

func update_labels(active_zone: int) -> void:
	for i in doors.size():
		var door: Dictionary = doors[i]
		var label: Label3D = door.label
		label.visible = active_zone < ShipDeckLayout.SHIP_COUNT and is_instance_valid(deck.body) and deck.body.position.distance_to(door.position) < 6.5
		if not label.visible: continue
		var destination: String = ShipDeckLayout.ZONES[destination_for(i, deck.body.position)].name
		label.text = "%02d · %s\n%s · %s" % [i + 1, destination.to_upper(), deck._binding("interact", "E"), "CERRAR" if door.open else "ABRIR"]

func zone_for(position: Vector3, current: int) -> int:
	return ShipDeckLayout.zone_for(position, current)

func prompt_for(index: int) -> String:
	if index < 0 or index >= doors.size(): return ""
	var door: Dictionary = doors[index]
	if door.blocked and _occupied(door): return "Paso ocupado · apártate para cerrar la escotilla"
	var destination: String = ShipDeckLayout.ZONES[destination_for(index, deck.body.position)].name
	return "E · %s escotilla %02d hacia %s · continúa andando" % ["Cerrar" if door.open else "Abrir", index + 1, destination]
