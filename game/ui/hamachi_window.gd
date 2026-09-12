class_name HamachiWindow
extends Window
## A temporary native UI over Session; never installs or configures the VPN.

const Connection = preload("res://net/hamachi_connection.gd")
const UI = preload("res://ui/console_ui.gd")

var session: Node
var tabs: TabContainer
var host_address: LineEdit
var host_port: LineEdit
var create_button: Button
var copy_button: Button
var invitation_input: LineEdit
var paste_button: Button
var join_button: Button
var player_name: LineEdit
var role_menu: OptionButton
var status_label: Label
var detection_label: Label
var close_session_button: Button
var close_button: Button
var close_confirmation: ConfirmationDialog
var _last_mode = ""
var _joining = false
var _confirmed = false
var _closed = false

func configure(value: Node) -> void:
	# Configure before add_child: no singleton or duplicate network authority.
	session = value

func _ready() -> void:
	name = "HamachiWindow"
	title = "Jugar por Hamachi"
	size = Vector2i(700, 690)
	min_size = Vector2i(480, 420)
	transient = true
	theme = UI.make_theme()
	close_requested.connect(_close_window)
	get_tree().root.size_changed.connect(_fit_window)
	_fit_window()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var body = UI.column(margin, 10)
	body.add_child(UI.label("JUGAR POR HAMACHI", 24, UI.TEAL))
	body.add_child(UI.paragraph("1 · Abrid Hamachi.  2 · Entrad todos en la misma red.\n3 · El anfitrión crea la partida y comparte la invitación en privado.", 15))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	_build_host(_page("Anfitrión"))
	_build_crew(_page("Tripulante"))
	status_label = UI.paragraph("", 15)
	status_label.custom_minimum_size.y = 52
	body.add_child(status_label)
	close_session_button = UI.button("Cerrar partida para todos…", _request_close_session)
	body.add_child(close_session_button)
	close_button = UI.button("Cerrar ventana · la partida continúa", _close_window)
	body.add_child(close_button)
	close_confirmation = ConfirmationDialog.new()
	close_confirmation.title = "¿Cerrar la sesión de red?"
	close_confirmation.ok_button_text = "Cerrar sesión"
	close_confirmation.cancel_button_text = "Volver"
	close_confirmation.confirmed.connect(_close_active_session)
	add_child(close_confirmation)
	if not is_instance_valid(session):
		_set_status("No hay una sesión disponible. Cierra esta ventana y vuelve a intentarlo.", false)
		_refresh_state()
		return
	session.updated.connect(_refresh_state)
	session.notice.connect(_on_notice)
	session.joined.connect(_on_joined)
	session.disconnected.connect(_on_disconnected)
	# On reopening, this string is assigned by Session._accepted, never create_client.
	# Notices can replace the status text after authentication. JSON roster keys
	# are strings; authoritative membership survives those unrelated notices.
	var roster = session.get("roster")
	var member = roster is Dictionary and roster.has(str(session.multiplayer.get_unique_id()))
	_confirmed = session.mode == "client" and (member or str(session.connection_status).begins_with("Conectado ·"))
	if session.mode == "client": tabs.current_tab = 1
	_detect_address()
	_refresh_state()

func _fit_window() -> void:
	if not is_inside_tree(): return
	var available = get_tree().root.size - Vector2i(48, 80)
	size = Vector2i(mini(size.x, maxi(min_size.x, available.x)), mini(size.y, maxi(min_size.y, available.y)))
	if visible: popup_centered()

func _page(label: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = label
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12)
	scroll.add_child(margin)
	return UI.column(margin, 10)

func _build_host(body: VBoxContainer) -> void:
	body.add_child(UI.paragraph("Crea una partida en este equipo. La campaña y la simulación permanecen en el anfitrión.", 15))
	detection_label = UI.paragraph("Buscando una interfaz identificada como Hamachi…", 14)
	body.add_child(detection_label)
	host_address = _field(body, "Tu IPv4 de Hamachi", "Cópiala de la aplicación Hamachi", 15)
	body.add_child(UI.button("Volver a detectar Hamachi", _detect_address))
	host_port = _field(body, "Puerto UDP de la partida · normalmente no hace falta cambiarlo", "27840", 6)
	host_port.text = str(session.DEFAULT_PORT) if is_instance_valid(session) else "27840"
	create_button = UI.button("Crear partida", _create_game, true)
	body.add_child(create_button)
	copy_button = UI.button("Copiar invitación", _copy_invitation)
	body.add_child(copy_button)
	body.add_child(UI.paragraph("La invitación incluye la clave de ESTA partida. No la publiques ni la incluyas en capturas. No pedimos la contraseña de tu red Hamachi. Cerrar esta ventana no cierra la partida.", 14))
	body.add_child(UI.paragraph("Lagunak no instala la VPN ni modifica el router o el cortafuegos. ENet autentica, pero no cifra: usad una VPN conectada y una red de confianza.", 14))

func _build_crew(body: VBoxContainer) -> void:
	body.add_child(UI.paragraph("Pide al anfitrión una invitación privada de Lagunak. No es un enlace web ni el nombre o la contraseña de la red Hamachi.", 15))
	invitation_input = _field(body, "Invitación privada de la partida", "lagunak:v1:…", Connection.MAX_INVITATION_LENGTH + 1)
	invitation_input.secret = true
	invitation_input.context_menu_enabled = false
	paste_button = UI.button("Pegar invitación", _paste_invitation)
	body.add_child(paste_button)
	player_name = _field(body, "Tu nombre de tripulante", "Tripulante", 32)
	body.add_child(UI.label("Puesto solicitado", 15, UI.MUTED))
	role_menu = OptionButton.new()
	for role in Catalog.ROLES:
		role_menu.add_item(Catalog.role_name(role))
		role_menu.set_item_metadata(role_menu.item_count - 1, role)
	role_menu.select(maxi(0, Catalog.ROLES.find("navegacion")))
	body.add_child(role_menu)
	join_button = UI.button("Unirse", _join_game, true)
	body.add_child(join_button)
	body.add_child(UI.paragraph("Si no conecta: comprobad que todos aparecéis conectados en la misma red Hamachi, que el anfitrión mantiene la partida abierta y que usáis la misma versión del juego. Pedid una invitación nueva si se ha cerrado y vuelto a crear la partida.", 14))

func _field(body: VBoxContainer, label: String, placeholder: String, limit: int) -> LineEdit:
	body.add_child(UI.label(label, 15, UI.MUTED))
	# Wrap field captions too: long Spanish text must not expand a small window.
	var caption: Label = body.get_child(body.get_child_count() - 1)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var field = LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = limit
	field.custom_minimum_size.y = 38
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(field)
	return field

func _detect_address() -> void:
	var addresses = Connection.detect_addresses(IP.get_local_interfaces())
	if addresses.size() == 1:
		host_address.text = addresses[0]
		detection_label.text = "IPv4 detectada en una interfaz Hamachi. Comprueba en Hamachi que la red esté conectada antes de compartirla."
	elif addresses.is_empty():
		detection_label.text = "No se ha detectado una IPv4 de Hamachi. Abre Hamachi, conecta tu red y copia aquí su IPv4 manualmente. No uses la IP pública del router."
	else:
		detection_label.text = "Hay varias IPv4 en interfaces Hamachi. Copia manualmente la IPv4 de la red que compartes con tus compañeros."

func _create_game() -> void:
	if not _can_start(): return
	if not Connection.is_valid_address(host_address.text):
		_set_status("Introduce una IPv4 de Hamachi válida. Abre la VPN y copia la dirección de tu equipo, no una dirección local de bucle invertido.", false)
		return
	if not Connection.is_valid_port(host_port.text):
		_set_status("El puerto debe ser un entero entre 1024 y 65535; normalmente basta con el predeterminado.", false)
		return
	var result: Dictionary = session.host_session(host_port.text.to_int())
	_refresh_state()
	if not result.get("ok", false):
		_set_status("No se pudo crear la partida. El puerto UDP puede estar ocupado; cierra la otra partida o prueba otro puerto.", false)
		return
	_set_status("Partida creada. Pulsa Copiar invitación y compártela en privado. La VPN debe estar conectada.", true)

func _copy_invitation() -> void:
	if not is_instance_valid(session) or session.mode != "host": return
	var port = Connection.active_host_port(session)
	if port == 0:
		_set_status("No se pudo comprobar el puerto de la partida activa. No se ha copiado una invitación; cierra y crea la partida de nuevo.", false)
		return
	var invitation = Connection.create_invitation(host_address.text, port, str(session.access_key))
	if invitation.is_empty():
		_set_status("Comprueba tu IPv4 de Hamachi antes de copiar. La partida activa no se ha cerrado ni modificado.", false)
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_set_status("Este entorno no permite usar el portapapeles. Abre el juego en un escritorio para copiar la invitación.", false)
		return
	DisplayServer.clipboard_set(invitation)
	_set_status("Invitación copiada. Compártela solo en privado y borra el portapapeles cuando ya no la necesites.", true)

func _paste_invitation() -> void:
	if not _can_start(): return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_set_status("Este entorno no permite pegar del portapapeles. Introduce la invitación en el campo privado.", false)
		return
	var text = DisplayServer.clipboard_get()
	var result = Connection.parse_invitation(text)
	invitation_input.clear()
	if result.ok: invitation_input.text = text.strip_edges()
	_set_status(result.message, result.ok)

func _join_game() -> void:
	if not _can_start(): return
	var parsed = Connection.parse_invitation(invitation_input.text)
	if not parsed.ok:
		_set_status(parsed.message, false)
		return
	_joining = true
	_confirmed = false
	var result: Dictionary = session.join_session(parsed.address, parsed.port, parsed.key, player_name.text, str(role_menu.get_item_metadata(role_menu.selected)))
	invitation_input.clear()
	_refresh_state()
	if result.get("ok", false):
		_set_status("Conectando… Esperando la autenticación del anfitrión; todavía no estás dentro de la partida.", true)
	else:
		_joining = false
		_refresh_state()
		_set_status("No se pudo iniciar la conexión. Comprueba la VPN, la partida del anfitrión y pide una invitación nueva.", false)

func _can_start() -> bool:
	if not is_instance_valid(session): return false
	if session.mode != "offline" or _joining:
		_set_status("Ya hay una sesión activa. Usa el botón de cierre de sesión antes de crear o unirte a otra partida.", false)
		return false
	return true

func _refresh_state() -> void:
	if _closed or create_button == null: return
	var mode: String = str(session.mode) if is_instance_valid(session) else "unavailable"
	if mode == "offline" and _last_mode in ["host", "client"]:
		_joining = false
		_confirmed = false
		invitation_input.clear()
	var idle = mode == "offline" and not _joining
	create_button.disabled = not idle
	join_button.disabled = not idle
	paste_button.disabled = not idle
	invitation_input.editable = idle
	player_name.editable = idle
	role_menu.disabled = not idle
	host_port.editable = idle
	copy_button.disabled = mode != "host"
	close_session_button.visible = mode in ["host", "client"]
	close_session_button.text = "Cerrar partida para todos…" if mode == "host" else "Desconectarme de la partida…"
	if mode == "host":
		var port = Connection.active_host_port(session)
		host_port.text = str(port) if port != 0 else ""
	if mode == _last_mode: return
	_last_mode = mode
	if mode == "host":
		_set_status("Anfitrión activo. Puedes copiar otra invitación; crear otra partida está bloqueado hasta cerrar esta.", true)
	elif mode == "client":
		_set_status("Conectado y autenticado en la partida." if _confirmed else "Conectando… Esperando la autenticación del anfitrión.", true)
	elif mode == "offline" and not _joining:
		_confirmed = false
		invitation_input.clear()
		_set_status("Sin sesión de red. Prepara Hamachi y elige Anfitrión o Tripulante.", true)

func _on_joined() -> void:
	if session.mode != "client": return
	_joining = false
	_confirmed = true
	invitation_input.clear()
	_refresh_state()
	_set_status("Conectado y autenticado. Ya puedes cerrar esta ventana y ocupar tu puesto.", true)

func _on_notice(text: String, ok: bool) -> void:
	if ok or (not _joining and session.mode != "client"): return
	# Allowlist categories, not arbitrary RPC text (which may contain private data).
	var explanation = "No se pudo conectar. Comprueba la VPN, la partida del anfitrión y que usáis la misma versión."
	if text.contains("clave"): explanation = "La clave de la partida no coincide. Pide una invitación nueva al anfitrión. No necesitas la contraseña de la red Hamachi aquí."
	elif text.contains("puesto") and text.contains("ocupado"): explanation = "El puesto solicitado está ocupado. Tras desconectarte, elige otro puesto y pega de nuevo la invitación."
	elif text.contains("versión"): explanation = "La versión de red no coincide. Usad la misma versión del juego."
	_set_status(explanation, false)

func _on_disconnected() -> void:
	_joining = false
	_confirmed = false
	invitation_input.clear()
	_refresh_state()
	_on_notice_after_disconnect()

func _on_notice_after_disconnect() -> void:
	# Session keeps its sanitized failure category in connection_status.
	var text = str(session.connection_status)
	_joining = true
	_on_notice(text, false)
	_joining = false

func _request_close_session() -> void:
	if not is_instance_valid(session) or session.mode not in ["host", "client"]: return
	close_confirmation.dialog_text = "Cerrar la partida desconectará a TODOS los tripulantes.\nLa campaña se queda en este equipo. ¿Quieres continuar?" if session.mode == "host" else "Saldrás de la partida. Los demás seguirán con el anfitrión.\n¿Quieres desconectarte?"
	close_confirmation.popup_centered(Vector2i(450, 180))

func _close_active_session() -> void:
	if not is_instance_valid(session): return
	_joining = false
	_confirmed = false
	session.close_session()
	invitation_input.clear()
	_refresh_state()
	_set_status("Sesión de red cerrada. Puedes crear otra partida o pegar una invitación nueva.", true)

func _set_status(text: String, ok: bool) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", UI.MUTED if ok else UI.RED)

func _clear_private_fields() -> void:
	for field in [host_address, invitation_input, player_name]:
		if is_instance_valid(field): field.clear()

func _close_window() -> void:
	_closed = true
	_clear_private_fields()
	_disconnect_signals()
	hide()
	queue_free()

func _disconnect_signals() -> void:
	if is_inside_tree() and get_tree().root.size_changed.is_connected(_fit_window):
		get_tree().root.size_changed.disconnect(_fit_window)
	if not is_instance_valid(session): return
	for binding in [["updated", _refresh_state], ["notice", _on_notice], ["joined", _on_joined], ["disconnected", _on_disconnected]]:
		if session.is_connected(binding[0], binding[1]): session.disconnect(binding[0], binding[1])

func _exit_tree() -> void:
	_clear_private_fields()
	_disconnect_signals()
