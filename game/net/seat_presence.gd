extends Node
## Additive, opt-in public seating protocol. Session alone authenticates peers
## and owns walking position/yaw. This node owns only peer -> physical seat.
signal changed
signal result_received(ok: bool, message: String)
const VERSION = 1
const MAX_REQUESTS_PER_SECOND = 12
var _seats: Dictionary = {}
var _occupants: Dictionary = {}
var _subscribers: Dictionary = {}
var _sequences: Dictionary = {}
var _rates: Dictionary = {}
var _revision = 0
var _received_revision = -1
var _request_sequence = 0
var _hello_sent = false
var _negotiated = false
var _transport = 0
var _mode = ""
var _local_body: Node3D
var _session: Node

func _ready() -> void:
	_session = get_tree().root.get_node("Session")
	_seats = PhysicalSeatCatalog.all_seats()
	process_physics_priority = -20
	_session.joined.connect(_hello_host)
	_session.updated.connect(_session_changed)
	multiplayer.peer_disconnected.connect(_peer_left)
	_sync_transport()

func bind_body(body: Node3D) -> void:
	_local_body = body

func local_peer() -> int:
	return multiplayer.get_unique_id() if _session.mode != "offline" else 1

func seat_for(peer: int) -> Dictionary:
	for id in _occupants:
		if int(_occupants[id]) == peer: return _seats[id].duplicate()
	return {}

func occupant(seat_id: String) -> int:
	return int(_occupants.get(seat_id, 0))

func request_sit(seat_id: String) -> Dictionary:
	return _request("sit", seat_id)

func request_stand() -> Dictionary:
	return _request("stand", "")

func _request(operation: String, seat_id: String) -> Dictionary:
	_sync_transport()
	if _session.mode == "client":
		if not _negotiated or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			var result = {"ok": false, "message": "Este anfitrión aún no ofrece asientos compartidos."}
			result_received.emit(result.ok, result.message)
			return result
		_request_sequence += 1
		_receive_request.rpc_id(1, VERSION, _request_sequence, operation, seat_id)
		return {"ok": true, "pending": true, "message": "Esperando al anfitrión…"}
	var result = _command(1, operation, seat_id)
	result_received.emit(result.ok, result.message)
	return result

func _position(peer: int) -> Variant:
	if _session.mode == "offline" and peer == 1:
		return _local_body.position if is_instance_valid(_local_body) else null
	var pose: Dictionary = _session.poses.get(peer, _session.poses.get(str(peer), {}))
	var coordinates = pose.get("position")
	if not coordinates is Array or coordinates.size() != 3: return null
	for value in coordinates:
		if not Catalog.finite_number(value): return null
	return Vector3(coordinates[0], coordinates[1], coordinates[2])

func _command(peer: int, operation: String, seat_id: String) -> Dictionary:
	if operation == "stand":
		_release(peer)
		return {"ok": true, "message": "De pie."}
	if operation != "sit" or not _seats.has(seat_id): return {"ok": false, "message": "Asiento inexistente."}
	var current = seat_for(peer)
	if not current.is_empty():
		return {"ok": current.id == seat_id, "message": "Levántate antes de cambiar de asiento."}
	if occupant(seat_id) != 0: return {"ok": false, "message": "Este asiento está ocupado."}
	var position = _position(peer)
	if position == null or not PhysicalSeatCatalog.reachable(_seats[seat_id], position):
		return {"ok": false, "message": "Acércate al frente del asiento para sentarte."}
	_occupants[seat_id] = peer
	_publish()
	return {"ok": true, "message": "Sentado. Interactúa para levantarte."}

func _release(peer: int) -> void:
	for id in _occupants.keys():
		if int(_occupants[id]) == peer:
			_occupants.erase(id)
			_publish()
			return

func _sync_transport() -> void:
	var transport = multiplayer.multiplayer_peer.get_instance_id()
	if _transport == transport and _mode == _session.mode: return
	_transport = transport
	_mode = _session.mode
	_occupants.clear()
	_subscribers.clear()
	_sequences.clear()
	_rates.clear()
	_revision = 0
	_received_revision = -1
	_request_sequence = 0
	_hello_sent = false
	_negotiated = false
	changed.emit()

func _session_changed() -> void:
	_sync_transport()
	# Only this optional capability key belongs to this component. Session keeps
	# ownership of names, roles, authentication and the position/yaw channel.
	if _session.mode == "host" and _session.roster.has(1): _session.roster[1].seat_protocol = VERSION
	elif _session.mode == "client": _hello_host()
	_cleanup()

func _physics_process(_delta: float) -> void:
	_sync_transport()
	_cleanup()

func _cleanup() -> void:
	if _session.mode == "client": return
	for id in _occupants.keys():
		var peer = int(_occupants[id])
		var position = _position(peer)
		if (_session.mode == "host" and not _session.roster.has(peer)) or position == null or not PhysicalSeatCatalog.in_zone(_seats[id], position):
			_release(peer)

func _peer_left(peer: int) -> void:
	_subscribers.erase(peer)
	_sequences.erase(peer)
	_rates.erase(peer)
	if _session.mode == "host": _release(peer)

func _authenticated(peer: int) -> bool:
	return _session.mode == "host" and peer != 1 and _session.roster.has(peer) and _session._peer_active(peer)

func _allow(peer: int) -> bool:
	var now = Time.get_ticks_msec()
	var rate: Dictionary = _rates.get(peer, {"since": now, "count": 0})
	if now - int(rate.since) >= 1000: rate = {"since": now, "count": 0}
	rate.count += 1
	_rates[peer] = rate
	return rate.count <= MAX_REQUESTS_PER_SECOND

func _hello_host() -> void:
	_sync_transport()
	if _session.mode != "client" or _hello_sent: return
	var host: Dictionary = _session.roster.get("1", _session.roster.get(1, {}))
	var version = host.get("seat_protocol", 0)
	if not Catalog.finite_number(version) or float(version) != float(VERSION): return
	_hello_sent = true
	_hello.rpc_id(1, VERSION)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(version: int) -> void:
	_sync_transport()
	var peer = multiplayer.get_remote_sender_id()
	if not _authenticated(peer) or not _allow(peer) or version != VERSION: return
	_subscribers[peer] = true
	_send_snapshot(peer)

@rpc("any_peer", "call_remote", "reliable", 0)
func _receive_request(version: int, sequence: int, operation: String, seat_id: String) -> void:
	_sync_transport()
	var peer = multiplayer.get_remote_sender_id()
	if not _authenticated(peer) or not _subscribers.has(peer) or not _allow(peer): return
	if version != VERSION or sequence <= int(_sequences.get(peer, 0)) or sequence > 2147483647: return
	_sequences[peer] = sequence
	if operation.length() > 8 or seat_id.length() > 32: return
	var result = _command(peer, operation, seat_id)
	_response.rpc_id(peer, result.ok, result.message)

func _publish() -> void:
	_revision += 1
	changed.emit()
	if _session.mode != "host": return
	for peer in _subscribers:
		if _authenticated(int(peer)): _send_snapshot(int(peer))

func _send_snapshot(peer: int) -> void:
	_receive_snapshot.rpc_id(peer, VERSION, _revision, _occupants)

@rpc("authority", "call_remote", "reliable", 0)
func _receive_snapshot(version: int, revision: int, occupants: Dictionary) -> void:
	_sync_transport()
	if _session.mode != "client" or version != VERSION or revision < _received_revision or occupants.size() > _seats.size(): return
	var owners: Array = []
	for id in occupants:
		if not id is String or not _seats.has(id) or not occupants[id] is int or occupants[id] <= 0 or occupants[id] in owners: return
		owners.append(occupants[id])
	_received_revision = revision
	_negotiated = true
	_occupants = occupants.duplicate()
	changed.emit()

@rpc("authority", "call_remote", "reliable", 0)
func _response(ok: bool, message: String) -> void:
	if _session.mode == "client": result_received.emit(ok, message.left(160))

func _exit_tree() -> void:
	if is_instance_valid(_session) and _session.mode == "host" and _session.roster.has(1):
		_session.roster[1].erase("seat_protocol")
