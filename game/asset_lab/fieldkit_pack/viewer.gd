extends Node3D
## Local asset laboratory. No inventory, combat, campaign, save or network writes.

const MANIFEST := "res://assets/models/fieldkit_pack/manifest.json"
var entries: Array = []
var current_index: int = -1
var current_model: Node3D
var camera: Camera3D
var stage: Node3D
var floor_mesh: MeshInstance3D
var selector: OptionButton
var equipment_button: Button
var animation_button: CheckButton
var info: Label
var players: Array[AnimationPlayer] = []
var equipped: bool = false
var animating: bool = true
var yaw: float = 0.65
var pitch: float = 0.30
var distance: float = 2.0
var radius: float = 1.0
var centre := Vector3.ZERO

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or not parsed.get("assets") is Array:
		push_error("Fieldkit manifest unavailable")
		return
	entries = parsed["assets"]
	stage = Node3D.new()
	stage.name = "AssetStage"
	add_child(stage)
	camera = Camera3D.new()
	camera.name = "InspectionCamera"
	camera.near = 0.008
	camera.far = 1000.0
	camera.fov = 58.0
	add_child(camera)
	camera.make_current()
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.025, 0.043, 0.060)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.64, 0.76, 0.85)
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	add_child(environment)
	for rotation: Vector3 in [Vector3(-48, -35, 0), Vector3(-20, 135, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = rotation
		light.light_energy = 1.8 if rotation.y < 0.0 else 0.9
		add_child(light)
	floor_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.073, 0.10, 0.125)
	material.roughness = 0.88
	floor_mesh.material_override = material
	add_child(floor_mesh)
	_build_ui()
	select_asset(0)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(365, 0)
	canvas.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "FIELDKIT / BIBLIOTECA 3D"
	heading.add_theme_font_size_override("font_size", 21)
	column.add_child(heading)
	selector = OptionButton.new()
	selector.custom_minimum_size.x = 335
	for entry: Dictionary in entries:
		selector.add_item(str(entry["title"]))
	selector.item_selected.connect(func(index: int) -> void: select_asset(index))
	column.add_child(selector)
	equipment_button = Button.new()
	equipment_button.text = "Vista de equipo 1:1 [V]"
	equipment_button.toggle_mode = true
	equipment_button.toggled.connect(set_equipped)
	column.add_child(equipment_button)
	animation_button = CheckButton.new()
	animation_button.text = "Animación mecánica [Espacio]"
	animation_button.button_pressed = true
	animation_button.toggled.connect(set_animating)
	column.add_child(animation_button)
	var reset_button := Button.new()
	reset_button.text = "Restablecer cámara [R]"
	reset_button.pressed.connect(reset_camera)
	column.add_child(reset_button)
	info = Label.new()
	info.custom_minimum_size.x = 335
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 16)
	column.add_child(info)
	var help := Label.new()
	help.text = "Botón derecho: órbita · Rueda: zoom\nIzquierda/derecha: cambiar modelo\n\nModelos 3D a escala real. La vista de equipo\nes visual: no añade daño, inventario ni IA."
	help.add_theme_font_size_override("font_size", 14)
	column.add_child(help)

func select_asset(index: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	var entry: Dictionary = entries[index]
	var resource: Resource = load("res://" + str(entry["scene"]).trim_prefix("game/"))
	if not resource is PackedScene:
		return false
	var replacement := (resource as PackedScene).instantiate() as Node3D
	if replacement == null:
		return false
	if is_instance_valid(current_model):
		current_model.free()
	players.clear()
	current_model = replacement
	current_index = index
	stage.add_child(current_model)
	_collect_players(current_model)
	var low: Array = entry["aabb_min"]
	var high: Array = entry["aabb_max"]
	var minimum := Vector3(float(low[0]), float(low[1]), float(low[2]))
	var maximum := Vector3(float(high[0]), float(high[1]), float(high[2]))
	centre = (minimum + maximum) * 0.5
	radius = maxf((maximum - minimum).length() * 0.5, 0.1)
	floor_mesh.position = Vector3(centre.x, minimum.y - radius * 0.025, centre.z)
	floor_mesh.scale = Vector3.ONE * radius * 5.0
	selector.select(index)
	equipment_button.disabled = str(entry["category"]) == "ships"
	if equipment_button.disabled:
		equipped = false
	info.text = "%s\n\n%s\n\n%s triángulos · %s anclajes\nDimensiones: %.3f × %.3f × %.3f m\nOrigen: %s\nClip GLB: field_cycle · Godot: field" % [entry["id"], entry["description"], entry["triangles"], entry["sockets"].size(), maximum.x-minimum.x, maximum.y-minimum.y, maximum.z-minimum.z, entry["pivot"]]
	set_equipped(equipped)
	set_animating(animating)
	return true

func _collect_players(node: Node) -> void:
	if node is AnimationPlayer:
		players.append(node as AnimationPlayer)
	for child: Node in node.get_children():
		_collect_players(child)

func set_animating(enabled: bool) -> void:
	animating = enabled
	animation_button.set_pressed_no_signal(enabled)
	for player: AnimationPlayer in players:
		if not enabled:
			player.pause()
			continue
		for clip: StringName in player.get_animation_list():
			if str(clip) == "RESET":
				continue
			# The imported resource is shared. Duplicate before changing loop behavior.
			var library := player.get_animation_library("")
			if library != null and library.has_animation(clip):
				var animation := library.get_animation(clip)
				if animation.loop_mode == Animation.LOOP_NONE:
					var local := animation.duplicate() as Animation
					local.loop_mode = Animation.LOOP_LINEAR
					var local_library := AnimationLibrary.new()
					local_library.add_animation(clip, local)
					player.remove_animation_library("")
					player.add_animation_library("", local_library)
			player.play(clip)
			break

func set_equipped(enabled: bool) -> void:
	if current_index < 0:
		return
	equipped = enabled and str(entries[current_index]["category"]) != "ships"
	equipment_button.set_pressed_no_signal(equipped)
	current_model.reparent(camera if equipped else stage, false)
	current_model.transform = Transform3D.IDENTITY
	floor_mesh.visible = not equipped
	if equipped:
		camera.position = Vector3(0, 1.7, 3.0)
		camera.rotation = Vector3.ZERO
		var anchor := current_model.find_child(str(entries[current_index]["attachment_socket"]), true, false) as Node3D
		var local_anchor := Vector3.ZERO
		if anchor != null:
			local_anchor = current_model.to_local(anchor.global_position)
		# Inspection distance leaves room for the hanging medkit and rear stock.
		# Preserve metre scale and authored pivots; only presentation is translated.
		current_model.position = Vector3(0.19, -0.08, -0.95) - local_anchor
	else:
		reset_camera()

func reset_camera() -> void:
	if equipped:
		set_equipped(false)
		return
	yaw = 0.65
	pitch = 0.30
	distance = maxf(radius * 3.2, 0.4)
	_update_camera()

func _update_camera() -> void:
	if equipped:
		return
	camera.position = centre + Vector3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch)) * distance
	camera.look_at(centre, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not equipped:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.008, -1.1, 1.25)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed and not equipped:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance * 0.9, radius * 1.3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance * 1.1, radius * 10.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V:
				set_equipped(not equipped)
			KEY_R:
				reset_camera()
			KEY_SPACE:
				set_animating(not animating)
			KEY_RIGHT:
				select_asset((current_index + 1) % entries.size())
			KEY_LEFT:
				select_asset(posmod(current_index - 1, entries.size()))
