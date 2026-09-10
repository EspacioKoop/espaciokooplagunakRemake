extends SceneTree
var checks = 0
var failures = 0
var session: Node
var avatars: Node
var case_name = ""
var port = 0
var observed: Dictionary = {}
const TEST_KEY = "avatar-network-fixture"

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("AVATAR_NETWORK_FAIL " + case_name + " " + label)

func until(condition: Callable, seconds: float = 5.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await create_timer(0.05).timeout
	return false

func selected(suit: String, gear: String = "none") -> Dictionary:
	var value = AvatarProfile.defaults()
	value.suit = suit
	value.gear = gear
	return value

func run() -> void:
	var args = OS.get_cmdline_user_args()
	case_name = args[args.find("--case") + 1]
	port = int(args[args.find("--port") + 1])
	session = root.get_node("Session")
	avatars = root.get_node("Avatars")
	avatars.storage_path = "user://network-avatar.json"
	session.suppress_saves = true
	if case_name == "legacy_host":
		await legacy_host_case()
	elif case_name == "legacy_client":
		await legacy_client_case()
	elif case_name == "host": await host_case()
	elif case_name == "intruder": await intruder_case()
	else: await client_case()
	session.close_session()
	await create_timer(0.15).timeout
	if is_instance_valid(avatars): check(avatars.profiles.is_empty(), "session close clears remote cosmetics")
	print("AVATAR_NETWORK_RESULT %s checks=%d failures=%d" % [case_name, checks, failures])
	quit(1 if failures else 0)

func legacy_host_case() -> void:
	avatars.queue_free()
	await process_frame
	check(root.get_node_or_null("Avatars") == null, "legacy host has no cosmetic RPC node")
	check(session.host_session(port, TEST_KEY).ok, "legacy host opens session")
	print("AVATAR_NETWORK_READY")
	check(await until(func(): return session.roster.size() == 2), "new client joins legacy host")
	check(not session.roster[1].has("avatar_protocol"), "legacy host has no capability marker")
	await create_timer(2.5).timeout

func legacy_client_case() -> void:
	check(avatars.save_local(selected("ember")).ok, "legacy pairing keeps editable local appearance")
	check(session.join_session("127.0.0.1", port, TEST_KEY, "new-client", "navegacion").ok, "new client joins legacy session")
	check(await until(func(): return session.roster.size() == 2), "legacy host authenticates client normally")
	await create_timer(1.5).timeout
	check(avatars.profiles.is_empty(), "absent capability sends no cosmetic RPC or snapshot")
	check(avatars.profile_for(1) == AvatarProfile.defaults(), "legacy host uses original crew fallback")
	check(avatars.local_profile.suit == "ember", "legacy session preserves saved local preference")

func host_case() -> void:
	check(avatars.save_local(selected("tide")).ok, "host persists its avatar")
	check(session.host_session(port, TEST_KEY).ok, "host opens real ENet session")
	avatars.changed.connect(func():
		for key in avatars.profiles: observed[key] = avatars.profiles[key].duplicate(true))
	print("AVATAR_NETWORK_READY")
	check(await until(func(): return avatars.profiles.size() == 3), "two authenticated client avatars received")
	check(avatars.profiles[1] == selected("tide"), "host profile retained")
	var peer_id = 0
	for key in session.roster:
		if session.roster[key].name == "player": peer_id = int(key)
	check(peer_id > 1 and avatars.profile_for(peer_id).suit == "orchid", "appearance belongs to transport sender")
	var crew = SpaceView.model("crew")
	root.add_child(crew)
	avatars.bind_avatar(crew, peer_id)
	check(crew.get_meta("avatar_profile").suit == "orchid", "host renders client's chosen crew material")
	check(await until(func(): return avatars.profile_for(peer_id).gear == "workpack", 8), "client edit reaches host avatar")
	check(crew.get_node_or_null("AvatarGear/Pack") != null, "edit changes already bound crew geometry")
	check(await until(func(): return not avatars.profiles.has(peer_id), 6), "disconnect removes old connection avatar")
	check(await until(func():
		for key in avatars.profiles:
			if int(key) != peer_id and avatars.profiles[key].gear == "workpack": return true
		return false, 5), "reconnect restores local appearance under new peer id")
	await create_timer(4.5).timeout
	check(avatars.profiles[1] == selected("tide"), "clients cannot impersonate host appearance")
	check(await until(func(): return avatars.profiles.size() == 1, 6), "all disconnected client profiles removed")
	check(observed.size() == 4, "only host, two authenticated peers and reconnect accepted")
	check(not JSON.stringify(avatars.profiles).contains("peer_id"), "profile schema excludes identity or authority fields")
	crew.queue_free()

func intruder_case() -> void:
	# Connect at transport level but never answer Session's authentication challenge.
	# Both the transport and the cosmetic node are real; no fake sender injection.
	var peer = ENetMultiplayerPeer.new()
	check(peer.create_client("127.0.0.1", port, 3) == OK, "intruder opens transport")
	session.mode = "unauthenticated"
	root.multiplayer.multiplayer_peer = peer
	check(await until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "intruder reaches transport without authentication")
	for i in 3:
		avatars._submit.rpc_id(1, JSON.stringify(selected("ember", "workpack")).to_utf8_buffer())
		await create_timer(0.35).timeout
	check(avatars.profiles.is_empty(), "unauthenticated peer receives no cosmetic snapshot")
	check(session.roster.is_empty(), "intruder never joins authenticated roster")

func client_case() -> void:
	var value = selected("orchid" if case_name == "player" else "classic")
	check(avatars.save_local(value).ok, "client persists own avatar before joining")
	check(session.join_session("127.0.0.1", port, TEST_KEY, case_name, "navegacion" if case_name == "player" else "ingenieria").ok, "client joins real ENet")
	check(await until(func(): return avatars.profiles.size() == 3), "full appearance snapshot received after authentication")
	check(avatars.profile_for(1) == selected("tide"), "client sees chosen host avatar")
	if case_name == "spectator":
		check(await until(func():
			for key in avatars.profiles:
				if avatars.profiles[key].gear == "workpack": return true
			return false, 8), "other client sees player appearance edit")
		await create_timer(4).timeout
		return
	var self_id = root.multiplayer.get_unique_id()
	avatars.set_process(false)
	await create_timer(0.4).timeout
	var impersonation = value.duplicate(true)
	impersonation.peer_id = 1
	for packet in [JSON.stringify(impersonation).to_utf8_buffer(), "{broken".to_utf8_buffer(), "x".repeat(1024).to_utf8_buffer()]:
		avatars._submit.rpc_id(1, packet)
		await create_timer(0.35).timeout
		check(avatars.profiles[self_id] == value, "malformed/oversized/impersonating request leaves accepted appearance")
	# Two valid requests in one frame: host accepts first and throttles second.
	avatars._submit.rpc_id(1, JSON.stringify(selected("orchid", "survey")).to_utf8_buffer())
	avatars._submit.rpc_id(1, JSON.stringify(selected("ember", "workpack")).to_utf8_buffer())
	await create_timer(0.15).timeout
	check(avatars.profiles[self_id] == selected("orchid", "survey"), "host limits cosmetic changes per sender")
	await create_timer(0.35).timeout
	value = selected("orchid", "workpack")
	check(avatars.save_local(value).ok, "persist real appearance edit")
	avatars.set_process(true)
	check(await until(func(): return avatars.profiles.get(self_id, {}) == value), "host accepts saved edit")
	check(AvatarProfile.read_profile(avatars.storage_path).profile == value, "accepted appearance is locally persistent")
	await create_timer(0.3).timeout
	# join_session closes and replaces the transport in the same frame.
	check(session.join_session("127.0.0.1", port, TEST_KEY, case_name, "navegacion").ok, "same-frame reconnect authenticated player")
	check(avatars.profiles.is_empty(), "transport replacement drops old roster cosmetics")
	check(await until(func(): return avatars.profiles.get(root.multiplayer.get_unique_id(), {}) == value), "reconnect resubmits persisted appearance")
	check(root.multiplayer.get_unique_id() != self_id, "reconnect has distinct peer identity")
	await create_timer(1).timeout
