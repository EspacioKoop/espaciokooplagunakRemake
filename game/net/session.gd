extends Node
## Local play and authoritative ENet sessions share exactly the same simulation.
signal updated
signal notice(text: String, ok: bool)
signal joined
signal disconnected

const DEFAULT_PORT = 27840
const PROTOCOL = 4
var sim = Simulation.new()
var view: Dictionary = {}
var mode = "offline"
var role = "mando"
var paused = true
var roster: Dictionary = {}
var poses: Dictionary = {}
var access_key = ""
var connection_status = "Partida local"
var save_status = "Sin cambios guardados"
var telemetry: Telemetry
var _challenges: Dictionary = {}
var _rates: Dictionary = {}
var _desired_role = "navegacion"
var _player_name = "Tripulante"
var _broadcast_clock = 0.0
var _save_clock = 0.0
var _previous_status = ""
var suppress_saves = false

func _ready() -> void:
	# Clients exchange orders and views only with the host. Avoid transport peer
	# announcements to connections that are still authenticating or closing.
	multiplayer.server_relay = false
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_connection_failed)
	telemetry = Telemetry.new()
	add_child(telemetry)
	telemetry.get_state = _telemetry_view
	telemetry.get_events = func(): return view.get("events", []).duplicate(true)
	suppress_saves = "--capture" in OS.get_cmdline_user_args() or "--test" in OS.get_cmdline_user_args()

func new_campaign() -> void:
	if mode == "client": return
	sim.state = {}
	start_mission(0)

func start_mission(index: int, custom: Dictionary = {}) -> Dictionary:
	if mode == "client": return {"ok": false, "message": "El anfitrión selecciona la misión."}
	var missions = Catalog.missions()
	var mission: Dictionary
	if custom.is_empty():
		if index < 0 or index >= missions.size(): return {"ok": false, "message": "Misión inexistente."}
		if index > 0 and missions[index-1].id not in sim.state.get("campaign", {}).get("completed", []): return {"ok": false, "message": "Completa la misión anterior."}
		mission = missions[index]
	else:
		var error = Catalog.validate_mission(custom)
		if not error.is_empty(): return {"ok": false, "message": error}
		mission = custom.duplicate(true)
		if not mission.id.begins_with("custom_"): mission.id = "custom_" + mission.id.left(57)
	sim.start(mission, sim.state)
	sim.state.run_id = Crypto.new().generate_random_bytes(12).hex_encode()
	paused = false
	_refresh_view()
	save_game()
	return {"ok": true, "message": "Misión iniciada."}

func resume_game() -> Dictionary:
	if mode == "client": return {"ok": false, "message": "El guardado pertenece al anfitrión."}
	var loaded = LocalStorage.read_state()
	var backup = false
	if not loaded.has("state"):
		loaded = LocalStorage.read_state("user://campaign.json.bak")
		backup = loaded.has("state")
	if not loaded.has("state"): return {"ok": false, "message": loaded.get("error", "Sin guardado.")}
	sim.state = loaded.state
	paused = false
	_refresh_view()
	return {"ok": true, "message": "Copia anterior recuperada." if backup else "Expedición recuperada."}

func save_game() -> Dictionary:
	if suppress_saves or mode == "client" or sim.state.is_empty(): return {"ok": false, "message": "No hay una partida local que guardar."}
	var error = LocalStorage.save_state(sim.state)
	save_status = "Guardado · " + Time.get_time_string_from_system() if error.is_empty() else error
	return {"ok": error.is_empty(), "message": save_status}

func order(operation: String, args: Dictionary = {}) -> Dictionary:
	if mode == "client":
		_receive_order.rpc_id(1, operation, args)
		return {"ok": true, "message": "Orden enviada al anfitrión."}
	var result = sim.command(role, operation, args, "local" if mode == "offline" else "1")
	notice.emit(result.message, result.ok)
	_refresh_view()
	return result

func select_role(requested: String) -> void:
	if requested not in Catalog.ROLES: return
	if mode == "client":
		_request_role.rpc_id(1, requested)
	elif mode == "host":
		_assign_role(1, requested)
	else:
		role = requested
		_refresh_view()

func host_session(port: int = DEFAULT_PORT, key: String = "") -> Dictionary:
	if port < 1024 or port > 65535: return {"ok": false, "message": "Puerto fuera de rango."}
	close_session()
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 8, 3)
	if error != OK: return {"ok": false, "message": "No se pudo abrir el puerto UDP: " + str(error)}
	access_key = key if key.length() >= 8 else Crypto.new().generate_random_bytes(16).hex_encode()
	mode = "host"
	multiplayer.multiplayer_peer = peer
	roster[1] = {"name": "Anfitrión", "role": role}
	paused = false
	connection_status = "Anfitrión · UDP %d" % port
	if sim.state.is_empty(): new_campaign()
	_refresh_view()
	return {"ok": true, "message": connection_status, "key": access_key}

func join_session(address: String, port: int, key: String, player_name: String, requested_role: String) -> Dictionary:
	if address.strip_edges().is_empty() or address.length() > 253 or port < 1024 or port > 65535 or key.length() < 8 or key.length() > 128 or requested_role not in Catalog.ROLES: return {"ok": false, "message": "Comprueba la dirección, el puerto, la clave y el puesto."}
	close_session()
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address.strip_edges(), port, 3)
	if error != OK: return {"ok": false, "message": "No se pudo iniciar la conexión."}
	mode = "client"
	access_key = key
	_desired_role = requested_role
	_player_name = player_name.strip_edges().left(32)
	if _player_name.is_empty(): _player_name = "Tripulante"
	connection_status = "Conectando…"
	view = {}
	multiplayer.multiplayer_peer = peer
	return {"ok": true, "message": connection_status}

func close_session() -> void:
	if multiplayer.multiplayer_peer != null: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "offline"
	access_key = ""
	_challenges.clear()
	_rates.clear()
	roster.clear()
	poses.clear()
	connection_status = "Partida local"
	_refresh_view()

func _peer_connected(id: int) -> void:
	if mode != "host": return
	var nonce = Crypto.new().generate_random_bytes(24).hex_encode()
	_challenges[id] = {"nonce": nonce, "until": Time.get_ticks_msec() + 8000}
	_challenge.rpc_id(id, nonce, PROTOCOL)

@rpc("authority", "call_remote", "reliable", 0)
func _challenge(nonce: String, protocol: int) -> void:
	if mode != "client" or nonce.length() != 48: return
	if protocol != PROTOCOL:
		connection_status = "La versión de red no coincide. Usad la misma compilación de Lagunak."
		_connection_failed()
		return
	var proof = Crypto.new().hmac_digest(HashingContext.HASH_SHA256, access_key.to_utf8_buffer(), nonce.to_utf8_buffer())
	_authenticate.rpc_id(1, proof, _player_name, _desired_role)

@rpc("any_peer", "call_remote", "reliable", 0)
func _authenticate(proof: PackedByteArray, player_name: String, requested_role: String) -> void:
	if mode != "host": return
	var id = multiplayer.get_remote_sender_id()
	if not _challenges.has(id): return
	var challenge: Dictionary = _challenges[id]
	_challenges.erase(id)
	var expected = Crypto.new().hmac_digest(HashingContext.HASH_SHA256, access_key.to_utf8_buffer(), challenge.nonce.to_utf8_buffer())
	if Time.get_ticks_msec() > challenge.until or proof.size() != 32 or not Crypto.new().constant_time_compare(expected, proof):
		_reject_peer(id, "La clave de la sesión no coincide.")
		return
	if requested_role not in Catalog.ROLES or player_name.length() > 32:
		_reject_peer(id, "Datos de tripulación inválidos.")
		return
	for entry in roster.values():
		if entry.role == requested_role:
			_reject_peer(id, "Ese puesto ya está ocupado. Elige otro puesto.")
			return
	roster[id] = {"name": player_name if not player_name.is_empty() else "Tripulante", "role": requested_role}
	_accepted.rpc_id(id, requested_role)
	_refresh_view()

func _reject_peer(id: int, message: String) -> void:
	if not _peer_active(id): return
	_response.rpc_id(id, message, false)
	await get_tree().create_timer(0.15).timeout
	if _peer_active(id): multiplayer.multiplayer_peer.get_peer(id).peer_disconnect_later()

@rpc("authority", "call_remote", "reliable", 0)
func _accepted(assigned_role: String) -> void:
	role = assigned_role
	connection_status = "Conectado · " + Catalog.role_name(role)
	joined.emit()

func _assign_role(id: int, requested: String) -> void:
	for other in roster:
		if int(other) != id and roster[other].role == requested:
			if id == 1: notice.emit("Ese puesto ya está ocupado.", false)
			else: _response.rpc_id(id, "Ese puesto ya está ocupado.", false)
			return
	if not roster.has(id): return
	roster[id].role = requested
	if id == 1: role = requested
	else: _accepted.rpc_id(id, requested)
	_refresh_view()

@rpc("any_peer", "call_remote", "reliable", 0)
func _request_role(requested: String) -> void:
	if mode == "host" and requested in Catalog.ROLES:
		var id = multiplayer.get_remote_sender_id()
		if roster.has(id) and _allow_order(id): _assign_role(id, requested)

func _allow_order(id: int) -> bool:
	var now = Time.get_ticks_msec()
	var rate: Dictionary = _rates.get(id, {"since": now, "count": 0})
	if now - int(rate.since) >= 1000: rate = {"since": now, "count": 0}
	rate.count += 1
	_rates[id] = rate
	return rate.count <= 20

@rpc("any_peer", "call_remote", "reliable", 0)
func _receive_order(operation: String, args: Dictionary) -> void:
	if mode != "host": return
	var id = multiplayer.get_remote_sender_id()
	if not roster.has(id) or not _allow_order(id): return
	var result = sim.command(roster[id].role, operation, args, str(id))
	_response.rpc_id(id, result.message, result.ok)
	_refresh_view()

@rpc("authority", "call_remote", "reliable", 0)
func _response(text: String, ok: bool) -> void:
	if not ok: connection_status = text
	notice.emit(text, ok)

@rpc("authority", "call_remote", "reliable", 2)
func _snapshot(data: PackedByteArray) -> void:
	if mode != "client" or data.size() < 5 or data.size() > 256 * 1024: return
	var length = data.decode_u32(0)
	if length < 2 or length > 256 * 1024: return
	var decoded = data.slice(4).decompress(length, FileAccess.COMPRESSION_DEFLATE)
	if decoded.size() != length: return
	var incoming = JSON.parse_string(decoded.get_string_from_utf8())
	if not incoming is Dictionary or not incoming.get("ship") is Dictionary or not incoming.get("contacts") is Array or not incoming.get("mission") is Dictionary: return
	view = incoming
	roster = view.get("roster", {})
	poses = view.get("poses", {})
	updated.emit()

func update_pose(position: Vector3, yaw: float) -> void:
	var coordinates = [position.x, position.y, position.z]
	if mode == "client": _receive_pose.rpc_id(1, coordinates, yaw)
	elif mode == "host": poses[1] = {"position": coordinates, "yaw": yaw}

@rpc("any_peer", "call_remote", "unreliable", 1)
func _receive_pose(position: Array, yaw: float) -> void:
	if mode != "host": return
	var id = multiplayer.get_remote_sender_id()
	if not roster.has(id) or position.size() != 3 or not is_finite(yaw): return
	for coordinate in position:
		if not Catalog.finite_number(coordinate) or absf(coordinate) > 400: return
	poses[id] = {"position": position, "yaw": fposmod(yaw, TAU)}

func _peer_disconnected(id: int) -> void:
	roster.erase(id)
	poses.erase(id)
	_challenges.erase(id)
	_rates.erase(id)
	if mode == "host": _refresh_view()

func _connection_failed() -> void:
	var reason = connection_status
	close_session()
	paused = true
	connection_status = "Conexión cerrada. " + (reason if not reason.begins_with("Conect") else "El anfitrión no está disponible.")
	notice.emit(connection_status, false)
	disconnected.emit()

func _refresh_view() -> void:
	if mode == "client": return
	view = sim.snapshot(role, "local" if mode == "offline" else "1")
	if not view.is_empty():
		view.roster = roster.duplicate(true)
		view.poses = poses.duplicate(true)
	updated.emit()

func _physics_process(delta: float) -> void:
	if mode == "client": return
	if not paused or mode == "host": sim.tick(delta)
	_broadcast_clock += delta
	_save_clock += delta
	if _broadcast_clock >= 0.1:
		_broadcast_clock = 0.0
		_refresh_view()
		if mode == "host" and not view.is_empty():
			for id in roster:
				if int(id) == 1: continue
				var recipient_view = sim.snapshot(roster[id].role, str(id))
				recipient_view.roster = roster.duplicate(true)
				recipient_view.poses = poses.duplicate(true)
				var raw = JSON.stringify(recipient_view, "", false).to_utf8_buffer()
				if raw.size() <= 256 * 1024:
					var packet = PackedByteArray()
					packet.resize(4)
					packet.encode_u32(0, raw.size())
					packet.append_array(raw.compress(FileAccess.COMPRESSION_DEFLATE))
					_snapshot.rpc_id(int(id), packet)
			for id in _challenges.keys():
				if Time.get_ticks_msec() > _challenges[id].until:
					_challenges.erase(id)
					multiplayer.multiplayer_peer.disconnect_peer(int(id))
	var status = sim.state.get("status", "")
	if _save_clock >= 30 or (status != _previous_status and status in ["won", "lost"]):
		_save_clock = 0.0
		if not paused or status in ["won", "lost"]: save_game()
	_previous_status = status

func _exit_tree() -> void:
	if telemetry != null: telemetry.stop()
	if not suppress_saves and mode != "client" and not sim.state.is_empty(): save_game()
	if multiplayer.multiplayer_peer != null: multiplayer.multiplayer_peer.close()

func _telemetry_view() -> Dictionary:
	var public_view: Dictionary = view.duplicate(true) if mode == "client" else sim.snapshot()
	ShipOperations.redact(public_view, "")
	Cooperation.redact(public_view, "")
	return public_view

func _peer_active(id: int) -> bool:
	if mode != "host" or id not in multiplayer.get_peers(): return false
	var peer: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(id)
	return peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED
