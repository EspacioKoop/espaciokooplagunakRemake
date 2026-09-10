class_name FoundryAccessPanel
extends Window
## Local-only delegation UI; never reachable through an HTTP route or RPC.
var telemetry: Node
var users: OptionButton
var user_id: LineEdit
var control: CheckBox
var credential: LineEdit
var status: Label
var access_list: VBoxContainer

func setup(source: Node) -> void:
	telemetry = source
	title = "Foundry · Accesos por usuario"
	theme = ConsoleUI.make_theme()
	size = Vector2i(700, 600)
	min_size = Vector2i(580, 460)
	close_requested.connect(hide)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	margin.add_child(body)
	var description = Label.new()
	description.text = "Vincula un usuario de Foundry a un tripulante nativo activo.\nEl token de Sesión conserva únicamente consulta pública.\nLos accesos caducan tras una hora o al cambiar misión, puesto o sesión."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(description)
	user_id = LineEdit.new()
	user_id.placeholder_text = "ID de usuario que muestra el panel de Foundry"
	user_id.max_length = 64
	body.add_child(user_id)
	users = OptionButton.new()
	body.add_child(users)
	var refresh = Button.new()
	refresh.text = "Actualizar tripulantes"
	refresh.pressed.connect(refresh_users)
	body.add_child(refresh)
	control = CheckBox.new()
	control.text = "Permitir órdenes básicas del puesto (además de ficha propia)"
	body.add_child(control)
	var issue_button = Button.new()
	issue_button.text = "Emitir / sustituir acceso"
	issue_button.pressed.connect(_issue)
	body.add_child(issue_button)
	credential = LineEdit.new()
	credential.editable = false
	credential.secret = true
	credential.placeholder_text = "El token nuevo aparece aquí una sola vez"
	body.add_child(credential)
	var copy_button = Button.new()
	copy_button.text = "Copiar token para entregarlo sólo a esa persona"
	copy_button.pressed.connect(func():
		if not credential.text.is_empty(): DisplayServer.clipboard_set(credential.text))
	body.add_child(copy_button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status)
	access_list = VBoxContainer.new()
	body.add_child(access_list)
	var revoke_all = Button.new()
	revoke_all.text = "Revocar todos los accesos personales"
	revoke_all.pressed.connect(func(): telemetry.authority.clear(); credential.clear(); refresh_users())
	body.add_child(revoke_all)
	visibility_changed.connect(func():
		credential.clear()
		if visible: refresh_users())
	refresh_users()

func refresh_users() -> void:
	users.clear()
	var session: Node = telemetry.authority.session
	if session != null and session.mode == "offline": users.add_item("Tú · " + Catalog.role_name(session.role), 1)
	elif session != null and session.mode == "host":
		for id in session.roster:
			users.add_item(str(session.roster[id].name) + " · " + Catalog.role_name(session.roster[id].role), int(id))
	for child in access_list.get_children(): child.queue_free()
	for grant in telemetry.authority.grants():
		var revoke_button = Button.new()
		revoke_button.text = "Revocar " + grant.user_id + " · " + Catalog.role_name(grant.role) + (" · control" if grant.control else " · lectura")
		revoke_button.pressed.connect(func(): telemetry.authority.revoke(grant.user_id); credential.clear(); refresh_users())
		access_list.add_child(revoke_button)

func _issue() -> void:
	if users.selected < 0: status.text = "No hay tripulantes activos."; return
	var result: Dictionary = telemetry.authority.issue(user_id.text.strip_edges(), users.get_selected_id(), control.button_pressed)
	credential.text = result.get("token", "")
	status.text = result.message
	refresh_users()
