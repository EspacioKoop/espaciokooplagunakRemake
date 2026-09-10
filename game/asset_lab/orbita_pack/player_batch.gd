extends "res://asset_lab/orbita_pack/viewer.gd"
## Visor conjunto: doce modelos originales + diez de equipo/apoyo.
## El montaje 1:1 es inspección visual, no inventario ni mecánicas de campaña.

const PLAYER_MANIFEST := "res://assets/models/orbita_pack/player_batch/manifest.json"
var attachment_view: bool = false
var attachment_button: CheckButton
var first_player_index: int = 0

func _ready() -> void:
	super._ready()
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_MANIFEST))
	if not document is Dictionary or not document.get("assets") is Array:
		push_error("ORBITA: catálogo de equipo no válido")
		return
	first_player_index = entries.size()
	entries.append_array(document["assets"])
	picker.clear()
	for entry: Dictionary in entries:
		picker.add_item(str(entry.get("title", entry.get("id", "Modelo"))))
	attachment_button = CheckButton.new()
	attachment_button.text = "Anclaje a escala 1:1"
	attachment_button.toggled.connect(set_attachment_view)
	picker.get_parent().add_child(attachment_button)
	select_asset(first_player_index)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--orbita-select="):
			var wanted: String = arg.trim_prefix("--orbita-select=")
			for index: int in range(entries.size()):
				if str(entries[index].get("id", "")) == wanted:
					select_asset(index)
					break

func select_asset(index: int) -> void:
	if index < 0 or index >= entries.size():
		return
	if is_instance_valid(holder):
		holder.transform = Transform3D.IDENTITY
	super.select_asset(index)
	if not is_instance_valid(model):
		return
	var entry: Dictionary = entries[selected_index]
	var can_mount: bool = not str(entry.get("attachment_socket", "")).is_empty()
	if not can_mount:
		attachment_view = false
	if is_instance_valid(attachment_button):
		attachment_button.disabled = not can_mount
		attachment_button.set_pressed_no_signal(attachment_view)
	if attachment_view:
		_place_attachment()
	_update_camera()

func set_attachment_view(enabled: bool) -> void:
	if not is_instance_valid(model) or selected_index < 0 or selected_index >= entries.size():
		return
	var entry: Dictionary = entries[selected_index]
	attachment_view = enabled and not str(entry.get("attachment_socket", "")).is_empty()
	select_asset(selected_index)

func _place_attachment() -> void:
	var entry: Dictionary = entries[selected_index]
	var anchor: Node3D = model.find_child(str(entry["attachment_socket"]), true, false) as Node3D
	if anchor == null:
		push_error("ORBITA: falta el anclaje de equipo")
		attachment_view = false
		return
	# Remove the parent's studio-only scale. Align the real exported socket,
	# not a hard-coded mesh centre, to the hand/back attachment frame.
	holder.transform = Transform3D.IDENTITY
	var relative: Transform3D = model.global_transform.affine_inverse() * anchor.global_transform
	model.transform = relative.affine_inverse()
	holder.position = Vector3(0.23, -0.21, -0.68)
	if entry.get("attachment_kind") == "back":
		holder.position = Vector3(0.0, -0.04, -1.10)
	info.text += "\nAnclaje: %s · escala real 1:1. Inspección visual; no añade mecánicas." % str(entry["attachment_socket"])

func _update_camera() -> void:
	if not is_instance_valid(camera):
		return
	if attachment_view:
		camera.transform = Transform3D.IDENTITY
		camera.fov = 65.0
		return
	camera.fov = 75.0
	super._update_camera()

func _reset_camera() -> void:
	if attachment_view:
		set_attachment_view(false)
	super._reset_camera()

func _unhandled_input(event: InputEvent) -> void:
	if attachment_view:
		return
	super._unhandled_input(event)
