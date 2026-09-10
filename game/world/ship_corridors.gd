class_name ShipCorridors
extends Node3D
## Physical, always-loaded connectors between the seven compartments of the Itsaso.
## WorldDeck owns the player and room state; this node owns corridor geometry and doors.

var deck: Node
var doors: Array = []
var links: Array = []

func setup(owner: Node) -> void:
	deck = owner
	var zones: Array = deck.get_script().get_script_constant_map().ZONES
	var specs = [
		[Vector3(0, 0, -19), 1, zones[0].at + Vector3(0, 0, zones[0].depth * 0.5 - 0.6), 0, "PUENTE", "PASILLO CENTRAL"],
		[Vector3(-2, 0, -12), 1, zones[2].at + Vector3(0, 0, zones[2].depth * 0.5 - 0.6), 2, "INGENIERÍA", "PASILLO CENTRAL"],
		[Vector3(2, 0, -12), 1, zones[3].at + Vector3(0, 0, zones[3].depth * 0.5 - 0.6), 3, "CAMAROTES", "PASILLO CENTRAL"],
		[Vector3(-2, 0, 12), 1, zones[4].at + Vector3(0, 0, zones[4].depth * 0.5 - 0.6), 4, "BODEGA", "PASILLO CENTRAL"],
		[Vector3(2, 0, 12), 1, zones[5].at + Vector3(0, 0, zones[5].depth * 0.5 - 0.6), 5, "COMEDOR", "PASILLO CENTRAL"],
		[Vector3(0, 0, 19), 1, zones[6].at + Vector3(0, 0, zones[6].depth * 0.5 - 0.6), 6, "ENFERMERÍA", "PASILLO CENTRAL"]
	]
	for spec in specs:
		_add_link(spec[0], spec[1], spec[2], spec[3], spec[4], spec[5])
	update_labels(0)

func _add_link(start: Vector3, source: int, finish: Vector3, target: int, source_title: String, target_title: String) -> void:
	var delta = finish - start
	var length = Vector2(delta.x, delta.z).length()
	if length < 1.0: return
	var yaw = atan2(delta.x, delta.z)
	var tunnel = Node3D.new()
	tunnel.name = "Connector_%s_%s" % [source, target]
	tunnel.position = (start + finish) * 0.5
	tunnel.rotation.y = yaw
	add_child(tunnel)
	_solid_box(tunnel, Vector3(0, -0.15, 0), Vector3(3.6, 0.3, length + 0.5), _material(Color("172c36"), 0.35))
	_solid_box(tunnel, Vector3(-1.75, 1.55, 0), Vector3(0.18, 3.1, length + 0.5), _material(Color("0a1722"), 0.55))
	_solid_box(tunnel, Vector3(1.75, 1.55, 0), Vector3(0.18, 3.1, length + 0.5), _material(Color("0a1722"), 0.55))
	_solid_box(tunnel, Vector3(0, 3.08, 0), Vector3(3.6, 0.16, length + 0.5), _material(Color("0a1722"), 0.55))
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
	var a = _gate(start, source, target, source_title, yaw)
	var b = _gate(finish, target, source, target_title, yaw)
	doors[a].paired = b
	doors[b].paired = a
	links.append({"source": source, "target": target, "start": start, "finish": finish, "a_door": a, "b_door": b, "length": length})

func _gate(position: Vector3, source: int, target: int, title: String, yaw: float) -> int:
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
	label.text = title + "\nE · ABRIR"
	label.position = position + Vector3(0, 2.5, 0)
	label.pixel_size = 0.004
	label.font_size = 32
	label.modulate = ConsoleUI.AMBER
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	deck.world.add_child(label)
	doors.append({"position": position, "source": source, "target": target, "title": title, "open": false, "paired": -1, "panel": panel, "collider": collider, "label": label})
	return doors.size() - 1

func _material(color: Color, metallic: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.72
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
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
	var result = -1
	var best = 2.45
	for i in doors.size():
		var door: Dictionary = doors[i]
		if door.source != source_zone: continue
		var distance = Vector2(position.x - door.position.x, position.z - door.position.z).length()
		if distance < best:
			best = distance
			result = i
	return result

func toggle(index: int) -> void:
	if index < 0 or index >= doors.size(): return
	set_open(index, not bool(doors[index].open))

func set_open(index: int, opened: bool) -> void:
	if index < 0 or index >= doors.size(): return
	var door: Dictionary = doors[index]
	if door.open == opened: return
	door.open = opened
	doors[index] = door
	var collider: CollisionShape3D = door.collider
	collider.set_deferred("disabled", opened)
	var panel: MeshInstance3D = door.panel
	if is_instance_valid(panel):
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "position:y", 3.25 if opened else 1.35, 0.24)
	var label: Label3D = door.label
	label.text = door.title + ("\nE · CERRAR" if opened else "\nE · ABRIR")

func update_labels(active_zone: int) -> void:
	for door in doors:
		door.label.visible = door.source == active_zone

func zone_for(position: Vector3, current: int) -> int:
	if current >= 7: return current
	var zones: Array = deck.get_script().get_script_constant_map().ZONES
	var nearest = current
	var best = INF
	for i in range(7):
		var center: Vector3 = zones[i].at
		var distance = Vector2(position.x - center.x, position.z - center.z).length()
		if distance < best:
			best = distance
			nearest = i
	return nearest

func prompt_for(index: int) -> String:
	if index < 0 or index >= doors.size(): return ""
	var door: Dictionary = doors[index]
	var zones: Array = deck.get_script().get_script_constant_map().ZONES
	return "E · %s escotilla hacia %s · continúa andando" % ["Cerrar" if door.open else "Abrir", zones[door.target].name]
