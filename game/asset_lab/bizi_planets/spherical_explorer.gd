extends CharacterBody3D
## Local preview controller. Does not replace the campaign player or network authority.
## Foot origin, metre units, radial gravity, real static terrain/prop collisions. MIT.
var view_camera: Camera3D
var radius_m: float = 100.0
var pitch: float = 0.0
var arrival := Vector3(0, 104, 0)
var rescue_count: int = 0
var test_motion := Vector2.ZERO
var controls_enabled: bool = true

func _ready() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.7
	collision.shape = shape
	collision.position.y = 0.86
	add_child(collision)
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(55.0)
	floor_stop_on_slope = true
	safe_margin = 0.025
	view_camera = Camera3D.new()
	view_camera.position.y = 1.58
	view_camera.near = 0.04
	view_camera.far = 1500.0
	view_camera.fov = 82.0
	add_child(view_camera)
	set_physics_process(false)

func teleport_to(point: Vector3) -> bool:
	if not point.is_finite() or point.length() < radius_m * 0.7:
		return false
	global_position = point
	velocity = Vector3.ZERO
	var up := point.normalized()
	var forward := Vector3.FORWARD.slide(up)
	if forward.length_squared() < 0.01:
		forward = Vector3.RIGHT.slide(up)
	forward = forward.normalized()
	global_basis = Basis(forward.cross(up).normalized(), up, -forward).orthonormalized()
	up_direction = up
	pitch = 0.0
	view_camera.rotation.x = 0.0
	reset_physics_interpolation()
	return true

func activate(point: Vector3, planet_radius: float) -> bool:
	if not is_finite(planet_radius) or planet_radius < 60.0 or planet_radius > 160.0:
		return false
	radius_m = planet_radius
	arrival = point
	if not teleport_to(point):
		return false
	set_physics_process(true)
	view_camera.make_current()
	return true

func _physics_process(delta: float) -> void:
	if global_position.length() < radius_m * 0.7 or global_position.length() > radius_m * 2.0:
		rescue_count += 1
		teleport_to(arrival)
		return
	var up := global_position.normalized()
	var alignment := Quaternion(global_basis.y.normalized(), up)
	global_basis = (Basis(alignment) * global_basis).orthonormalized()
	up_direction = up
	var move := test_motion
	if controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		move = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if move.length_squared() > 1.0:
		move = move.normalized()
	var tangent := (global_basis.x * move.x + global_basis.z * move.y).slide(up)
	var speed := 9.0 if controls_enabled and Input.is_physical_key_pressed(KEY_SHIFT) else 4.8
	var radial_velocity := velocity.dot(up)
	if is_on_floor() and radial_velocity < 0.0:
		radial_velocity = -1.0
	if controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
		radial_velocity = 7.0
	radial_velocity -= 18.0 * delta
	velocity = tangent * speed + up * radial_velocity
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if not is_physics_processing() or not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_object_local(Vector3.UP, -event.relative.x * 0.0025)
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.35, 1.35)
		view_camera.rotation.x = pitch
