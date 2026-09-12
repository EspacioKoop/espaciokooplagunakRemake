extends SceneTree
## Real ENet processes using the production Hamachi window. No VPN is simulated.
const Connection = preload("res://net/hamachi_connection.gd")
var failures = 0
var checks = 0
var accepted = false
var rejected = false
var app: Control
var session: Node
var exchange = ""
var case_name = ""
var port = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HAMACHI_FAIL " + str(checks) + " " + label)

func settle() -> void:
	for i in 4: await process_frame

func wait_for(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(0.04).timeout
	return bool(predicate.call())

func flag(name: String) -> void:
	var file = FileAccess.open(exchange.path_join(name), FileAccess.WRITE)
	if file: file.store_string("ready\n")

func open_window() -> Window:
	app._go("sessions")
	await settle()
	var button = app.find_child("HamachiSessionButton", true, false)
	check(button is Button and not button.disabled, "production launcher enabled")
	if button == null: return null
	button.pressed.emit()
	await settle()
	return app._hamachi_window

func fill_join(window: Window, invitation: String, station: String) -> void:
	window.tabs.current_tab = 1
	window.invitation_input.text = invitation
	if window.invitation_input is LineEdit:
		window.invitation_input.text_changed.emit(invitation)
	else:
		window.invitation_input.text_changed.emit()
	window.player_name.text = "Tripulante QA"
	window.role_menu.select(Catalog.ROLES.find(station))
	window.role_menu.item_selected.emit(window.role_menu.selected)

func run() -> void:
	var args = OS.get_cmdline_user_args()
	case_name = args[args.find("--case") + 1]
	port = int(args[args.find("--port") + 1])
	exchange = args[args.find("--exchange") + 1]
	root.size = Vector2i(1600, 900)
	session = root.get_node("Session")
	session.joined.connect(func(): accepted = true)
	session.disconnected.connect(func(): rejected = true)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle()
	if case_name == "host": await host_case()
	else: await client_case()
	session.close_session()
	if is_instance_valid(app._hamachi_window):
		app._hamachi_window.close_requested.emit()
		await settle()
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle()
	print("HAMACHI_RESULT %s checks=%d failures=%d" % [case_name, checks, failures])
	quit(1 if failures else 0)

func host_case() -> void:
	var window = await open_window()
	if window == null: return
	var address = ""
	for candidate in IP.get_local_addresses():
		if Connection.is_valid_address(candidate):
			address = candidate
			break
	check(not address.is_empty(), "local IPv4 available for same-machine network test")
	if address.is_empty(): return
	# Explicit manual address: not represented as automatic Hamachi detection.
	window.host_address.text = address
	window.host_address.text_changed.emit(address)
	window.host_port.text = str(port)
	await settle()
	check(not window.create_button.disabled, "production create action enabled")
	window.create_button.pressed.emit()
	await settle()
	check(session.mode == "host", "production create action starts ENet host")
	check(Connection.active_host_port(session) == port, "invitation reflects actual socket port")
	var invitation = Connection.create_invitation(address, Connection.active_host_port(session), session.access_key)
	check(not invitation.is_empty(), "production invitation builder accepts actual host")
	var file = FileAccess.open(exchange.path_join("invitation"), FileAccess.WRITE)
	if file: file.store_string(invitation); file.close()
	check(file != null, "private test handoff written")
	print("HAMACHI_HOST_READY")
	var saw_member = false
	var deadline = Time.get_ticks_msec() + 26000
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(exchange.path_join("good.done")):
		if session.roster.size() == 2: saw_member = true
		if FileAccess.file_exists(exchange.path_join("reconnect.request")) and session.roster.size() == 1:
			flag("reconnect.ready")
		await create_timer(0.04).timeout
	check(FileAccess.file_exists(exchange.path_join("good.done")), "authenticated client finishes both connections")
	check(FileAccess.file_exists(exchange.path_join("bad.done")), "wrong-key client completes rejection check")
	check(FileAccess.file_exists(exchange.path_join("busy.done")), "occupied-station client completes rejection check")
	check(saw_member, "host observes authenticated member")
	check(session.sim.state.ship.throttle == 0.25, "UI client order reaches authoritative simulation")
	check(session.role == "mando", "host station remains reserved")

func client_case() -> void:
	var file = FileAccess.open(exchange.path_join("invitation"), FileAccess.READ)
	check(file != null, "private invitation exists")
	if file == null: return
	var invitation = file.get_as_text()
	file.close()
	var decoded = Connection.parse_invitation(invitation)
	check(decoded.ok, "production parser accepts host invitation")
	if not decoded.ok: return
	if case_name == "bad": invitation = Connection.create_invitation(decoded.address, decoded.port, "deliberately-wrong-test-key")
	var window = await open_window()
	if window == null: return
	fill_join(window, invitation, "mando" if case_name == "busy" else "navegacion")
	await settle()
	check(not window.join_button.disabled, "production join action enabled after valid input")
	window.join_button.pressed.emit()
	check(not accepted, "starting a connection is not reported as authenticated")
	if case_name == "good": check(window.invitation_input.text.is_empty(), "join clears private invitation from input")
	await wait_for(func(): return rejected or (accepted and not session.view.is_empty()))
	print("HAMACHI_STATE %s accepted=%s rejected=%s mode=%s" % [case_name, accepted, rejected, session.mode])
	if case_name in ["bad", "busy"]:
		check(not accepted, "wrong key or occupied station is never accepted")
		check(rejected and session.mode == "offline", "rejected client returns offline")
		flag(case_name + ".done")
		return
	check(accepted and session.mode == "client", "real UI authenticates client")
	check(not session.view.is_empty(), "client receives authoritative snapshot")
	check(app._page == "bridge", "successful guided join reaches bridge")
	if session.view.is_empty(): return
	check(not session.view.mission.has("contacts"), "hidden mission catalogue excluded")
	check(session.view.operations.destruct.codes.is_empty(), "captain confirmation secrets excluded")
	check(session.role == "navegacion", "selected station assigned")
	check(session.roster.has(str(session.multiplayer.get_unique_id())), "authenticated player appears in JSON roster")
	session.order("helm", {"heading": 0.0, "throttle": 0.25})
	check(await wait_for(func(): return session.view.get("ship", {}).get("throttle", -1) == 0.25), "authoritative order acknowledgement received")
	session.close_session()
	accepted = false
	rejected = false
	flag("reconnect.request")
	check(await wait_for(func(): return FileAccess.file_exists(exchange.path_join("reconnect.ready"))), "host observes disconnect before reconnect")
	if is_instance_valid(app._hamachi_window):
		app._hamachi_window.close_requested.emit()
		await settle()
	window = await open_window()
	if window == null: return
	fill_join(window, invitation, "navegacion")
	await settle()
	window.join_button.pressed.emit()
	check(await wait_for(func(): return accepted and not session.view.is_empty()), "same private invitation reconnects through real UI")
	check(session.role == "navegacion", "station restored after reconnect")
	flag("good.done")
