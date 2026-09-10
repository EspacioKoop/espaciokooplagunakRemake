extends Node3D
## Reusable room wrapper. All interactions are local; no campaign state. MIT.
var collision_count: int = 0
var doors: Array[Node3D] = []
var rest_x: Array[float] = []
var door_open: bool = false
var door_use: Node3D
var ready_ok: bool = false

func _ready() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		push_error("PORTU: missing room model")
		return
	for name in ["door_left", "door_right"]:
		var door := model.find_child(name, true, false) as Node3D
		if door == null:
			push_error("PORTU: missing door " + name)
			return
		doors.append(door)
		rest_x.append(door.position.x)
	door_use = model.find_child("socket_door_use", true, false) as Node3D
	_build_collision(model, false)
	ready_ok = door_use != null and collision_count > 0

func _build_collision(node: Node, moving: bool) -> void:
	var is_door := moving or str(node.name) in ["door_left", "door_right"]
	if node is MeshInstance3D and node.mesh != null:
		var body: PhysicsBody3D
		if is_door:
			body = AnimatableBody3D.new()
			body.sync_to_physics = false
		else:
			body = StaticBody3D.new()
		body.name = "RoomCollision"
		body.collision_layer = 1
		body.collision_mask = 2
		var shape := CollisionShape3D.new()
		if is_door:
			var bounds := node.get_aabb()
			var box := BoxShape3D.new()
			box.size = bounds.size
			shape.shape = box
			shape.position = bounds.position + bounds.size * 0.5
		else:
			shape.shape = node.mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)
		collision_count += 1
	for child in node.get_children():
		if not child is PhysicsBody3D:
			_build_collision(child, is_door)

func marker(name: String) -> Node3D:
	return get_node("Model").find_child("socket_" + name, true, false) as Node3D

func set_cutaway(enabled: bool) -> void:
	for name in ["roof_cutaway", "front_cutaway"]:
		var part := get_node("Model").find_child(name, true, false) as Node3D
		if part != null:
			part.visible = not enabled

func toggle_door(actor_position: Vector3) -> bool:
	if not ready_ok or not actor_position.is_finite():
		return false
	var local_actor := to_local(actor_position)
	var centre := to_local((doors[0].global_position + doors[1].global_position) * 0.5)
	var horizontal := Vector2(local_actor.x - centre.x, local_actor.z - centre.z)
	if horizontal.length() > 3.4:
		return false
	# Refuse closure while a person is in the swept aperture; never crush the visitor.
	if door_open and absf(local_actor.x - centre.x) < 2.5 and absf(local_actor.z - centre.z) < 1.2:
		return false
	door_open = not door_open
	return true

func _physics_process(delta: float) -> void:
	for i in range(doors.size()):
		var target: float = rest_x[i] + ((-2.12 if i == 0 else 2.12) if door_open else 0.0)
		doors[i].position.x = move_toward(doors[i].position.x, target, 5.0 * delta)
