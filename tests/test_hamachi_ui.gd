extends SceneTree

const WindowScript = preload("res://ui/hamachi_window.gd")
const Connection = preload("res://net/hamachi_connection.gd")
const HelperSuite = preload("test_hamachi_connection.gd")

# Only the transport boundary is doubled for signal ordering/hostile notices.
# Every action below uses production HamachiWindow controls, not a duplicate UI.
class PendingSession extends Node:
	signal updated
	signal notice(text: String, ok: bool)
	signal joined
	signal disconnected
	const DEFAULT_PORT = 27840
	var mode = "offline"
	var access_key = ""
	var connection_status = "Partida local"
	var calls = 0
	var requested_role = ""
	var roster = {}
	func join_session(_address: String, _port: int, key: String, _player_name: String, role: String) -> Dictionary:
		calls += 1
		mode = "client"
		access_key = key
		requested_role = role
		connection_status = "Conectando…"
		return {"ok": true, "message": connection_status}
	func close_session() -> void:
		mode = "offline"
		access_key = ""
		roster = {}
		connection_status = "Partida local"
		updated.emit()

func _initialize() -> void:
	call_deferred("_run_standalone")

func _run_standalone() -> void:
	root.size = Vector2i(1440, 900)
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await _settle(self)
	var result = await verify(self, app)
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await _settle(self)
	print("HAMACHI_DIRECT_OK ", result.checks, " checks; ", result.failures, " failures")
	quit(1 if result.failures else 0)

static func verify(tree: SceneTree, app: Control) -> Dictionary:
	var result: Dictionary = HelperSuite.verify()
	var session = tree.root.get_node("Session")
	session.close_session()
	var before_connections = session.joined.get_connections().size()
	var original_size = tree.root.size
	tree.root.size = Vector2i(1440, 900)
	var window = _open(app, session)
	await _settle(tree)
	_check(result, window.title == "Jugar por Hamachi" and window.tabs.get_tab_count() == 2, "native titled host and crew tabs")
	_check(result, window.size.x <= 1440 and window.size.y <= 900, "component inside requested 1440x900")
	_check(result, ProjectSettings.get_setting("display/window/size/window_width_override") == 1440 and ProjectSettings.get_setting("display/window/size/window_height_override") == 810, "configured default is actually 1440x810")
	_check(result, session.joined.get_connections().size() == before_connections + 1, "window observes Session authentication")
	_check(result, window.create_button.text == "Crear partida" and window.join_button.text == "Unirse", "production primary actions")
	_check(result, window.invitation_input.secret, "private invitation masked in native input")
	_check(result, window.copy_button.disabled and not window.create_button.disabled, "offline availability")
	window.host_address.text = "127.0.0.1"
	window.create_button.pressed.emit()
	_check(result, session.mode == "offline" and window.status_label.text.contains("IPv4"), "production Create rejects loopback without opening Session")
	window.host_address.text = "192.0.2.1"
	await _capture_if_requested(window, "host-default")
	window.host_port.text = "2e4"
	window.create_button.pressed.emit()
	_check(result, session.mode == "offline" and window.status_label.text.contains("puerto"), "production Create rejects coercion before Session")
	window.tabs.current_tab = 1
	window.invitation_input.text = "https://example.invalid/"
	window.join_button.pressed.emit()
	_check(result, session.mode == "offline" and window.status_label.text.contains("invitación"), "production Join rejects hostile invitation")
	for viewport in [Vector2i(1440, 810), Vector2i(960, 600)]:
		tree.root.size = viewport
		await _settle(tree)
		_check(result, window.size.y <= viewport.y - 40, "automatic parent resize keeps native window within available height")
		window.size = Vector2i(700, 690) if viewport.y > 600 else Vector2i(480, 420)
		window.popup_centered()
		for tab in 2:
			window.tabs.current_tab = tab
			await _settle(tree)
			_check(result, window.close_button.get_global_rect().end.y <= window.size.y + 1 and window.close_button.get_global_rect().end.x <= window.size.x + 1, "close control remains inside compact viewport")
			await _capture_if_requested(window, ("host-" if tab == 0 else "crew-") + str(viewport.y))
			var scroll: ScrollContainer = window.tabs.get_child(tab)
			_check(result, scroll.size.x <= window.size.x and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "production page has no horizontal scrolling")
			var action: Button = window.copy_button if tab == 0 else window.join_button
			scroll.ensure_control_visible(action)
			await _settle(tree)
			_check(result, action.get_global_rect().position.y >= scroll.get_global_rect().position.y - 1 and action.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1, "primary action reachable with actual scroll")
	# Real ENet server, real Session, production Create. No VPN claim is made.
	tree.root.size = Vector2i(1440, 900)
	window.size = Vector2i(700, 690)
	window.popup_centered()
	window.tabs.current_tab = 0
	var probe = ENetMultiplayerPeer.new()
	var bound = probe.create_server(0)
	_check(result, bound == OK, "ephemeral UDP probe opens")
	var port = 0
	if bound == OK: port = probe.host.get_local_port()
	probe.close()
	window.host_port.text = str(port)
	window.create_button.pressed.emit()
	await _settle(tree)
	_check(result, session.mode == "host", "production Create opens actual ENet Session")
	if session.mode == "host":
		_check(result, Connection.active_host_port(session) == port, "actual ENetConnection get_local_port contract")
		_check(result, window.create_button.disabled and window.join_button.disabled and not window.copy_button.disabled, "active session blocks destructive replacement")
		var key: String = session.access_key
		window.create_button.pressed.emit()
		_check(result, session.access_key == key and Connection.active_host_port(session) == port, "handler also refuses bypass of disabled Create")
		if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			DisplayServer.clipboard_set("fixture-before-explicit-copy")
			_check(result, DisplayServer.clipboard_get() == "fixture-before-explicit-copy", "no automatic clipboard write")
			window.copy_button.pressed.emit()
			var invitation = Connection.parse_invitation(DisplayServer.clipboard_get())
			_check(result, invitation.ok and invitation.port == port and invitation.key == key, "production Copy uses actual active port and key")
			DisplayServer.clipboard_set("")
		window.close_button.pressed.emit()
		await _settle(tree)
		_check(result, not is_instance_valid(window) and session.mode == "host", "window close frees node, preserves active host")
		_check(result, session.joined.get_connections().size() == before_connections, "signals disconnected after window close")
		window = _open(app, session)
		await _settle(tree)
		window.host_address.text = "192.0.2.1"
		_check(result, not window.copy_button.disabled and window.host_port.text == str(port), "reopen preserves active nondefault ENet port")
		window.close_session_button.pressed.emit()
		await _settle(tree)
		_check(result, window.close_confirmation.visible and window.close_confirmation.dialog_text.contains("TODOS") and session.mode == "host", "explicit host closure warns all players before acting")
		window.close_confirmation.get_cancel_button().pressed.emit()
		window.close_confirmation.hide()
		_check(result, session.mode == "host", "cancel leaves host intact")
		window.close_session_button.pressed.emit()
		window.close_confirmation.get_ok_button().pressed.emit()
		await _settle(tree)
		_check(result, session.mode == "offline" and session.access_key.is_empty(), "confirmation button closes actual Session and clears its key")
		_check(result, not window.create_button.disabled and window.copy_button.disabled, "offline controls restored after closure")
	if is_instance_valid(window):
		window.close_requested.emit()
		await _settle(tree)
	session.close_session()
	session.paused = true
	# Pending transport return is NOT Session.joined; rejection text is allowlisted.
	var pending = PendingSession.new()
	app.add_child(pending)
	window = _open(app, pending)
	await _settle(tree)
	window.tabs.current_tab = 1
	window.invitation_input.text = Connection.create_invitation("198.51.100.17", 27840, "fixture-private-key")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set("javascript:fixture")
		window.paste_button.pressed.emit()
		_check(result, window.invitation_input.text.is_empty() and pending.calls == 0, "production Paste refuses hostile clipboard without connecting")
		DisplayServer.clipboard_set(Connection.create_invitation("198.51.100.17", 27840, "fixture-private-key"))
		window.paste_button.pressed.emit()
		_check(result, not window.invitation_input.text.is_empty() and pending.calls == 0, "production Paste validates but never autojoins")
		DisplayServer.clipboard_set("")
	window.join_button.pressed.emit()
	_check(result, pending.calls == 1 and pending.requested_role == "navegacion" and window.status_label.text.contains("Conectando"), "production Join requests selected role and waits for authentication")
	_check(result, not window._confirmed and window.join_button.disabled and window.invitation_input.text.is_empty(), "no premature success, no retained invitation")
	window.join_button.pressed.emit()
	_check(result, pending.calls == 1, "double Join cannot replace pending session")
	pending.notice.emit("La clave no coincide. fixture-private-key", false)
	_check(result, window.status_label.text.contains("clave") and not window.status_label.text.contains("fixture-private-key"), "wrong key message does not reflect network input")
	pending.close_session()
	_check(result, not window.join_button.disabled and not window._joining, "external Session close updates pending UI without disconnected signal")
	pending.connection_status = "Conexión cerrada. La clave no coincide."
	pending.disconnected.emit()
	_check(result, not window.join_button.disabled and window.status_label.text.contains("clave"), "disconnect clears pending state while preserving useful rejection category")
	window.invitation_input.text = Connection.create_invitation("192.0.2.1", 27840, "fixture-private-key")
	window.join_button.pressed.emit()
	pending.connection_status = "Conectado · Navegación"
	pending.joined.emit()
	_check(result, window._confirmed and window.status_label.text.contains("autenticado"), "only Session joined signal confirms authentication")
	window.close_requested.emit()
	_check(result, window.invitation_input.text.is_empty() and window.host_address.text.is_empty(), "close clears temporary private controls immediately")
	await _settle(tree)
	_check(result, not is_instance_valid(window) and pending.joined.get_connections().is_empty(), "closed node and bound signal handlers released")
	# A notice must not turn an authenticated participant into a pending connection.
	pending.roster[str(pending.multiplayer.get_unique_id())] = {"name": "Tripulante QA", "role": "navegacion"}
	pending.connection_status = "No tienes permiso para esa orden."
	window = _open(app, pending)
	await _settle(tree)
	_check(result, window._confirmed and window.status_label.text.contains("autenticado"), "reopening uses authoritative JSON roster after unrelated notice")
	window.close_requested.emit()
	await _settle(tree)
	pending.close_session()
	pending.queue_free()
	tree.root.size = original_size
	await _settle(tree)
	print("HAMACHI_UI_OK ", result.checks, " checks; ", result.failures, " failures; clipboard=", DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD))
	return result

static func _capture_if_requested(window: Window, label: String) -> void:
	var args = OS.get_cmdline_user_args()
	var index = args.find("--hamachi-capture-dir")
	if index < 0 or index + 1 >= args.size() or DisplayServer.get_name() == "headless": return
	var path = args[index + 1]
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	window.get_texture().get_image().save_png(path.path_join(label + ".png"))

static func _open(app: Control, session: Node) -> Window:
	var window = WindowScript.new()
	window.configure(session)
	app.add_child(window)
	window.popup_centered()
	return window

static func _settle(tree: SceneTree) -> void:
	for i in 4: await tree.process_frame

static func _check(result: Dictionary, ok: bool, label: String) -> void:
	result.checks += 1
	if not ok:
		result.failures += 1
		push_error("HAMACHI_UI_FAIL " + label)
