extends Node3D
const Walker = preload("res://asset_lab/egonaldi_pack/walker.gd")
var assets: Array = []
var selected := -1
var model: Node3D
var walker: CharacterBody3D
var camera: Camera3D
var picker: OptionButton
var title_label: Label
var info_label: Label
var cutaway := true
var yaw := 0.62
var elevation := 0.64
var distance := 68.0

func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/egonaldi_pack/manifest.json"))
	if not data is Dictionary or data.get("schema", "") != "egonaldi-destinations":
		push_error("Egonaldi: missing or invalid manifest")
		return
	assets = data.get("assets", [])
	if assets.size() != 6:
		push_error("Egonaldi: expected six destinations")
		return
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.025,0.04,0.06)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.72,0.79,0.83)
	settings.ambient_light_energy = 0.6
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-25,0)
	sun.light_energy = 1.25
	add_child(sun)
	for x in [-9.0,9.0]:
		for z in [-12.0,0.0,12.0]:
			var light := OmniLight3D.new()
			light.position = Vector3(x,6.8,z)
			light.omni_range = 18
			light.light_energy = 1.4
			add_child(light)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 400
	camera.fov = 52
	add_child(camera)
	walker = Walker.new()
	add_child(walker)
	_build_ui()
	select_asset(0)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16,16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.04,0.06,0.94)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	panel.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size",24)
	box.add_child(title_label)
	picker = OptionButton.new()
	for entry in assets:
		picker.add_item(str(entry["name"])+" · "+str(entry["description"]))
	picker.item_selected.connect(select_asset)
	box.add_child(picker)
	var row := HBoxContainer.new()
	box.add_child(row)
	for item in [["Recorrer",0],["Vista seccionada",1],["Edificio completo",2]]:
		var button := Button.new()
		button.text = item[0]
		var mode: int = item[1]
		button.pressed.connect(func():
			if mode == 0:
				enter(true)
			else:
				inspect(mode == 1))
		row.add_child(button)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size",14)
	box.add_child(info_label)
	var help := Label.new()
	help.text = "WASD · ratón · Mayús · Espacio\nEsc: liberar/capturar ratón · F: vista seccionada\nÓrbita: botón derecho + ratón · rueda: zoom\nConectores y anclajes de contenido, sin reglas de campaña"
	help.add_theme_font_size_override("font_size",13)
	box.add_child(help)

func select_asset(index: int) -> bool:
	if index < 0 or index >= assets.size():
		return false
	var packed: PackedScene = load(str(assets[index]["res_path"])) as PackedScene
	if packed == null:
		return false
	var next := packed.instantiate() as Node3D
	if next == null:
		return false
	walker.enabled = false
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	model = next
	add_child(model)
	selected = index
	picker.select(index)
	title_label.text = str(assets[index]["name"]).to_upper()+" / EGONALDI"
	info_label.text = "36 × 40 m · conectores N/S · 8 anclajes\n%s triángulos · GLB Blender, colisión incluida" % str(int(assets[index]["triangles"]))
	inspect(true)
	return true

func set_cutaway(active: bool) -> void:
	cutaway = active
	if not is_instance_valid(model):
		return
	for node in model.find_children("*","MeshInstance3D",true,false):
		if str(node.name).begins_with("roof") or str(node.name).begins_with("front_wall"):
			node.visible = not active

func inspect(sectioned := true) -> void:
	walker.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_cutaway(sectioned)
	camera.current = true
	_update_camera()

func enter(capture_mouse := false) -> bool:
	if selected < 0:
		return false
	var pos: Array = assets[selected]["arrival_m"]
	if not walker.reset_at(Vector3(pos[0],pos[1],pos[2])):
		return false
	set_cutaway(false)
	walker.enabled = true
	walker.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture_mouse else Input.MOUSE_MODE_VISIBLE
	return true

func _update_camera() -> void:
	camera.position = Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*distance
	camera.look_at(Vector3(0,2,0),Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			inspect(true)
		elif event.physical_keycode == KEY_ESCAPE and walker.enabled:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if walker.enabled:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x*0.005
		elevation = clampf(elevation+event.relative.y*0.005,0.12,1.4)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(20,distance*.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(120,distance*1.1)
		_update_camera()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
