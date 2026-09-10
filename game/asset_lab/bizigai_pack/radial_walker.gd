extends CharacterBody3D
## Local asset-inspection controller. No Session, inventory or campaign state.
var enabled := false
var gravity_strength := 9.0
var walk_speed := 7.0
var drive_override := Vector2.ZERO
var test_drive := false
var pitch := -0.08
var jumped := false
var camera: Camera3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.65
	floor_max_angle = deg_to_rad(58.0)
	floor_constant_speed = true
	safe_margin = 0.01
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 0.72
	camera.near = 0.04
	camera.far = 1600.0
	camera.fov = 78.0
	add_child(camera)

func align_to_surface(preferred_forward := Vector3.FORWARD) -> bool:
	if not position.is_finite() or position.length_squared() < 1.0:
		return false
	var up := position.normalized()
	var forward := preferred_forward.slide(up)
	if forward.length_squared() < 0.00001:
		var helper := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		forward = helper.cross(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	basis = Basis(right, up, -forward).orthonormalized()
	up_direction = up
	return true

func place_at(point: Vector3, focus: Vector3) -> bool:
	if not point.is_finite() or not focus.is_finite() or point.length_squared() < 1.0:
		return false
	position = point
	velocity = Vector3.ZERO
	pitch = -0.08
	align_to_surface(focus - point)
	camera.rotation.x = pitch
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		basis = basis.rotated(up_direction, -motion.relative.x * 0.0024).orthonormalized()
		pitch = clampf(pitch - motion.relative.y * 0.0024, -1.35, 1.35)
		camera.rotation.x = pitch

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if not align_to_surface(-basis.z):
		enabled = false
		return
	var movement := drive_override if test_drive else Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
	movement = movement.limit_length()
	var speed := walk_speed
	if not test_drive and Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= 1.8
	var desired := (basis.x * movement.x - basis.z * movement.y) * speed
	var tangent := velocity.slide(up_direction).move_toward(desired, delta * 28.0)
	var radial := velocity.dot(up_direction)
	if is_on_floor() and radial < 0.0:
		radial = -0.6
	else:
		radial -= gravity_strength * delta
	var jump_now := Input.is_physical_key_pressed(KEY_SPACE) and not test_drive
	if jump_now and not jumped and is_on_floor():
		radial = 5.1
	jumped = jump_now
	velocity = tangent + up_direction * radial
	move_and_slide()
