extends CharacterBody3D
var enabled := false
var test_drive := false
var drive := Vector2.ZERO
var pitch := -0.03
var jump_held := false
var camera: Camera3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.5
	safe_margin = 0.01
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.3
	shape.shape = capsule
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 0.72
	camera.near = 0.04
	camera.far = 250.0
	camera.fov = 76.0
	add_child(camera)

func reset_at(point: Vector3) -> bool:
	if not point.is_finite() or absf(point.x)>17.5 or absf(point.z)>19.0 or point.y<0.9 or point.y>4:
		return false
	position = point
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	pitch = -0.03
	camera.rotation.x = pitch
	return true

func _unhandled_input(event: InputEvent) -> void:
	if enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		rotation.y -= event.relative.x * 0.0024
		pitch = clampf(pitch-event.relative.y*0.0024,-1.35,1.35)
		camera.rotation.x = pitch

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var movement := drive if test_drive else Vector2(
		float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
	movement = movement.limit_length()
	var speed := 6.0
	if not test_drive and Input.is_physical_key_pressed(KEY_SHIFT):
		speed = 9.0
	var desired := (basis.x*movement.x-basis.z*movement.y)*speed
	velocity.x = move_toward(velocity.x,desired.x,delta*24)
	velocity.z = move_toward(velocity.z,desired.z,delta*24)
	velocity.y = -0.6 if is_on_floor() else velocity.y-12.0*delta
	var jump := Input.is_physical_key_pressed(KEY_SPACE) and not test_drive
	if jump and not jump_held and is_on_floor():
		velocity.y = 5.5
	jump_held = jump
	move_and_slide()
	# The asset ends at its modular connectors; leaving the isolated lab resets arrival.
	if position.y < -6 or absf(position.x)>19 or absf(position.z)>21:
		reset_at(Vector3(0,0.98,17))
