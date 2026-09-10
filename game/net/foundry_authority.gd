class_name FoundryAuthority
extends RefCounted
## Host-issued capabilities delegate an existing native identity, never an HTTP role.
const SCHEMAS = {
	"alert": {"level": "alert"}, "helm": {"heading": "heading", "throttle": "throttle"},
	"autopilot": {"target": "target"}, "dock": {"target": "target"}, "undock": {},
	"power": {"system": "system", "value": "power"}, "coolant": {"system": "system"},
	"shields": {"enabled": "bool"}, "fire": {"target": "target"},
	"scan": {"target": "target"}, "hail": {"target": "target"}, "probe": {"target": "target"},
	"repair": {"system": "system"}
}
const TTL_MS = 60 * 60 * 1000
var session: Node
var _grants: Dictionary = {}

func _init(owner_session: Node = null) -> void:
	session = owner_session
	if session != null:
		session.updated.connect(func(): grants())
		session.multiplayer.peer_disconnected.connect(_disconnected)

func _disconnected(peer_id: int) -> void:
	for key in _grants.keys():
		if _grants[key].peer_id == peer_id: _grants.erase(key)

func clear() -> void:
	_grants.clear()

static func valid_user(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64: return false
	for c in value:
		if c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

func _context(peer_id: int) -> Dictionary:
	if session == null or session.mode not in ["offline", "host"] or session.sim.state.is_empty(): return {}
	if session.mode == "offline" and peer_id != 1: return {}
	if session.mode == "host" and (not session.roster.has(peer_id) or (peer_id != 1 and not session._peer_active(peer_id))): return {}
	return {"role": session.role if peer_id == 1 else session.roster[peer_id].role,
		"mode": session.mode, "run_id": session.sim.state.get("run_id", ""),
		"connection": session.multiplayer.multiplayer_peer.get_instance_id(),
		"identity": "self" if session.mode == "offline" else str(peer_id),
		"principal": "local" if session.mode == "offline" else str(peer_id)}

func issue(user_id: String, peer_id: int, control: bool = false) -> Dictionary:
	var context = _context(peer_id)
	if not valid_user(user_id) or context.is_empty(): return {"ok": false, "message": "Usuario o tripulante activo inválido."}
	# One live delegation per user and per native identity. Rotation revokes the old key.
	for key in _grants.keys():
		if _grants[key].user_id == user_id or _grants[key].peer_id == peer_id: _grants.erase(key)
	var secret = Crypto.new().generate_random_bytes(32).hex_encode()
	_grants[secret.sha256_text()] = {"user_id": user_id, "peer_id": peer_id, "control": control,
		"context": context, "until": Time.get_ticks_msec() + TTL_MS, "sequence": 1, "since": 0, "count": 0}
	return {"ok": true, "token": secret, "role": context.role, "message": "Acceso emitido por una hora; se revoca al cambiar misión, puesto o sesión."}

func revoke(user_id: String) -> void:
	for key in _grants.keys():
		if _grants[key].user_id == user_id: _grants.erase(key)

func authenticate(secret: String, user_id: String) -> Dictionary:
	if secret.length() != 64 or not valid_user(user_id): return {}
	var key = secret.sha256_text()
	var grant: Dictionary = _grants.get(key, {})
	if grant.is_empty(): return {}
	if Time.get_ticks_msec() >= grant.until or _context(grant.peer_id) != grant.context:
		_grants.erase(key)
		return {}
	if grant.user_id != user_id: return {}
	return grant

func grants() -> Array:
	var result: Array = []
	for key in _grants.keys():
		var grant: Dictionary = _grants[key]
		if Time.get_ticks_msec() >= grant.until or _context(grant.peer_id) != grant.context:
			_grants.erase(key)
		else: result.append({"user_id": grant.user_id, "role": grant.context.role, "control": grant.control})
	return result

func commands(grant: Dictionary) -> Array:
	var result: Array = []
	if grant.get("control", false):
		for operation in SCHEMAS:
			if operation in Catalog.PERMISSIONS.get(grant.context.role, []): result.append(operation)
	return result

func view(grant: Dictionary) -> Dictionary:
	var result = FoundryProjection.state(session.sim.snapshot())
	result.protocol = 2
	result.identity = {"user_id": grant.user_id, "role": grant.context.role}
	result.commands = commands(grant)
	result.sequence = grant.sequence
	result.log = FoundryProjection.events(session.sim.state.get("events", []))
	var expedition = session.get_tree().root.get_node_or_null("Expedition")
	var profile: Dictionary = {} if expedition == null else FoundryProjection.dictionary(FoundryProjection.dictionary(expedition.data.get("profiles")).get(grant.context.identity))
	result.crew = FoundryProjection.crew(profile)
	return result

func dispatch(grant: Dictionary, envelope: Variant) -> Dictionary:
	# Revalidate even for callers that authenticated earlier in the same frame.
	if not _grants.values().has(grant) or _context(grant.peer_id) != grant.context or Time.get_ticks_msec() >= grant.until: return _reply(401, "Acceso revocado.")
	var now = Time.get_ticks_msec()
	if now - grant.since >= 1000: grant.since = now; grant.count = 0
	grant.count += 1
	if grant.count > 5 or (session.mode == "host" and not session._allow_order(grant.peer_id)): return _reply(429, "Demasiadas órdenes; espera un segundo.")
	if not envelope is Dictionary or envelope.size() != 4 or not envelope.has_all(["run_id", "sequence", "operation", "args"]): return _reply(400, "Formato de orden inválido.")
	if not envelope.operation is String or envelope.operation not in commands(grant): return _reply(403, "Orden no autorizada para este acceso y puesto.")
	if not envelope.run_id is String or envelope.run_id != grant.context.run_id or not Catalog.finite_number(envelope.sequence) or envelope.sequence != grant.sequence: return _reply(409, "Misión o secuencia caducada; actualiza el panel.")
	var operation: String = envelope.operation
	if not _valid_args(operation, envelope.args): return _reply(400, "Parámetros inválidos.")
	if session.paused: return _reply(409, "La partida está pausada.")
	grant.sequence += 1
	var result: Dictionary = session.sim.command(grant.context.role, operation, envelope.args, grant.context.principal)
	session._refresh_view()
	return {"status": 200, "body": {"ok": result.ok, "message": result.message, "sequence": grant.sequence}}

static func _valid_args(operation: String, args: Variant) -> bool:
	if not args is Dictionary or args.size() != SCHEMAS[operation].size(): return false
	for key in SCHEMAS[operation]:
		if not args.has(key): return false
		var value: Variant = args[key]
		match SCHEMAS[operation][key]:
			"alert":
				if not value is String or value not in ["verde", "ambar", "roja"]: return false
			"system":
				if not value is String or value not in Catalog.SYSTEMS: return false
			"target":
				if not valid_user(value): return false
			"bool":
				if not value is bool: return false
			"heading":
				if not Catalog.finite_number(value) or value < 0 or value >= 360: return false
			"throttle":
				if not Catalog.finite_number(value) or value < -1 or value > 1: return false
			"power":
				if not Catalog.finite_number(value) or value != floorf(value) or value < 0 or value > 4: return false
	return true

static func _reply(status: int, message: String) -> Dictionary:
	return {"status": status, "body": {"ok": false, "message": message}}
