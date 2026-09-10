extends CharacterBody3D
## Local inspection controller. Supports flat destinations or radial planets.
## No campaign, inventory, network or persistent state is changed.
var planet: Node3D
var view: Camera3D
var forward: Vector3 = Vector3.FORWARD
var pitch: float = 0.0
var enabled: bool = true
var scripted_input: Vector2 = Vector2.ZERO
var use_scripted_input: bool = false
var jump_requested: bool = false
var travelled: float = 0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 3
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(58.0)
	floor_constant_speed = true
	safe_margin = 0.015
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	collision.shape = capsule
	add_child(collision)
	view = Camera3D.new()
	view.name = "Eyes"
	view.position.y = 0.65
	view.near = 0.045
	view.far = 1800.0
	view.fov = 76.0
	add_child(view)

func radial_up() -> Vector3:
	if is_instance_valid(planet):
		var offset: Vector3 = global_position - planet.global_position
		if offset.length_squared() > 0.0001:
			return offset.normalized()
	return Vector3.UP

func place(position_value: Vector3, up: Vector3, direction: Vector3) -> bool:
	if not position_value.is_finite() or not up.is_finite() or not direction.is_finite() or up.length_squared() < 0.001:
		return false
	var normal: Vector3 = up.normalized()
	var heading: Vector3 = direction - normal * direction.dot(normal)
	if heading.length_squared() < 0.001:
		return false
	global_position = position_value
	forward = heading.normalized()
	up_direction = normal
	global_basis = Basis(forward.cross(normal).normalized(), normal, -forward)
	velocity = Vector3.ZERO
	pitch = 0.0
	if view != null:
		view.rotation.x = 0.0
	return true

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var normal: Vector3 = radial_up()
	forward = forward - normal * forward.dot(normal)
	if forward.length_squared() < 0.0001:
		forward = global_basis.x.cross(normal)
	forward = forward.normalized()
	var right: Vector3 = forward.cross(normal).normalized()
	up_direction = normal
	global_basis = Basis(right, normal, -forward)
	var command := Vector2.ZERO
	if use_scripted_input:
		command = scripted_input.limit_length()
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		command.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		command.y = float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		command = command.limit_length()
	var speed: float = 7.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 4.5
	var vertical: float = velocity.dot(normal)
	if is_on_floor() and vertical < 0.0:
		vertical = -1.5
	vertical -= 16.0 * delta
	if jump_requested and is_on_floor():
		vertical = 5.0
	jump_requested = false
	velocity = (right * command.x + forward * command.y) * speed + normal * vertical
	var before: Vector3 = global_position
	move_and_slide()
	travelled += before.distance_to(global_position)
	if not global_position.is_finite():
		enabled = false
		push_error("Inspection walker produced non-finite position")

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.physical_keycode == KEY_SPACE:
			jump_requested = true
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		forward = forward.rotated(radial_up(), -event.relative.x * 0.0025)
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.38, 1.38)
		view.rotation.x = pitch
