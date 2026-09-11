extends CharacterBody3D
## Isolated first-person inspector; does not alter InputMap or campaign controls. MIT.
var camera: Camera3D
var test_motion := Vector2.ZERO
var controls_enabled: bool = true
var pitch: float = 0.0
var spawn := Vector3(0, 1, 14)
var rescued: int = 0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.4
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = 0.86
	add_child(collision)
	camera = Camera3D.new()
	camera.position.y = 1.58
	camera.near = 0.03
	camera.far = 250.0
	camera.fov = 85.0
	add_child(camera)
	set_physics_process(false)

func place(point: Vector3) -> bool:
	if not point.is_finite() or absf(point.x) > 12.0 or absf(point.z) > 18.0 or point.y < 0.0 or point.y > 5.0:
		return false
	global_position = point
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	pitch = 0.0
	reset_physics_interpolation()
	return true

func _physics_process(delta: float) -> void:
	if position.y < -2.0 or absf(position.x) > 14.0 or absf(position.z) > 19.0:
		rescued += 1
		place(spawn)
		return
	var input := test_motion
	if controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if input.length_squared() > 1.0:
		input = input.normalized()
	var direction := basis * Vector3(input.x, 0, input.y)
	var speed := 6.5 if controls_enabled and Input.is_physical_key_pressed(KEY_SHIFT) else 4.0
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		velocity.y = -1.0
		if controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = 5.0
	else:
		velocity.y -= 18.0 * delta
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or not is_physics_processing():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * 0.0025
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.3, 1.3)
		camera.rotation.x = pitch
