class_name AdvancedSensors
extends Node
## Native short/long-range sensor suite with probe-origin analysis and hacking challenges.
## The host owns outcomes; each client receives only its own active challenge.

signal updated
signal notice(text: String, ok: bool)

const SHORT_RANGE = 1200.0
const LONG_RANGE = 4200.0
const ANALYSIS_LEVELS = ["Eco", "Firma", "Clase", "Identidad"]
const SYMBOLS = ["△", "○", "□", "◇"]

var state: Dictionary = {"operators": {}, "levels": {}, "hacks": {}}
var _broadcast_clock = 0.0
var _window: Window

func _ready() -> void:
	set_process_unhandled_key_input(true)

func _session() -> Node:
	return get_tree().root.get_node_or_null("Session")

func _authority() -> bool:
	var session = _session()
	return session == null or session.mode != "client"

func actor_id() -> String:
	var session = _session()
	if session == null or session.mode == "offline": return "self"
	return str(multiplayer.get_unique_id())

func operator(actor: String = "") -> Dictionary:
	var id = actor if not actor.is_empty() else actor_id()
	if not state.operators.has(id): state.operators[id] = {"band": "short", "origin": "", "task": {}}
	return state.operators[id]

func analysis_level(target: String) -> int:
	return clampi(int(state.levels.get(target, 0)), 0, 3)

func command(operation: String, args: Dictionary = {}) -> Dictionary:
	if args.size() > 8: return _result(false, "Demasiados parámetros de sensores.")
	var session = _session()
	if session != null and session.mode == "client":
		_receive_command.rpc_id(1, operation, args)
		return _result(true, "Orden de sensores enviada al anfitrión.")
	var response = _perform(operation, args, actor_id(), session.role if session != null else "sensores")
	notice.emit(response.message, response.ok)
	if response.ok: updated.emit()
	return response

@rpc("any_peer", "call_remote", "reliable", 3)
func _receive_command(operation: String, args: Dictionary) -> void:
	var session = _session()
	if session == null or session.mode != "host": return
	var peer_id = multiplayer.get_remote_sender_id()
	if not session.roster.has(peer_id): return
	var role = str(session.roster[peer_id].role)
	var response = _perform(operation, args, str(peer_id), role)
	_response.rpc_id(peer_id, response.message, response.ok)
	if response.ok: updated.emit()

@rpc("authority", "call_remote", "reliable", 3)
func _response(text: String, ok: bool) -> void:
	notice.emit(text, ok)

@rpc("authority", "call_remote", "reliable", 3)
func _snapshot(incoming: Dictionary) -> void:
	var session = _session()
	if session == null or session.mode != "client": return
	if JSON.stringify(incoming).length() > 64000: return
	state = incoming.duplicate(true)
	updated.emit()

func _view_for(actor: String) -> Dictionary:
	var safe = {"operators": {}, "levels": state.levels.duplicate(true), "hacks": state.hacks.duplicate(true)}
	if state.operators.has(actor): safe.operators[actor] = state.operators[actor].duplicate(true)
	return safe

func _perform(operation: String, args: Dictionary, actor: String, role: String) -> Dictionary:
	if role != "sensores": return _result(false, "Esta función pertenece al puesto de Sensores.")
	var session = _session()
	if session == null or session.sim.state.is_empty() or session.sim.state.status != "active": return _result(false, "No hay una misión activa.")
	var sim = session.sim
	var op = operator(actor)
	match operation:
		"band":
			var band = str(args.get("band", ""))
			if band not in ["short", "long"]: return _result(false, "Selecciona banda corta o larga.")
			op.band = band
			op.task = {}
			return _result(true, "Sensores en banda " + ("corta." if band == "short" else "larga."))
		"probe_origin":
			var target = sim.contact(str(args.get("target", "")))
			if target.is_empty() or not target.probed: return _result(false, "Selecciona un contacto con una sonda desplegada.")
			op.origin = target.id
			op.task = {}
			return _result(true, "Vista remota enlazada a la sonda de " + target.name + ".")
		"probe_clear":
			op.origin = ""
			op.task = {}
			return _result(true, "Sensores vuelven al origen de la Itsaso.")
		"analysis_begin":
			var target = sim.contact(str(args.get("target", "")))
			if target.is_empty() or target.hull <= 0: return _result(false, "Selecciona un contacto activo.")
			var current = analysis_level(target.id)
			if current >= 3 or target.identified: return _result(false, "Ese contacto ya está identificado por completo.")
			if not _in_range(sim, op, target): return _result(false, "El contacto queda fuera del alcance de la banda seleccionada.")
			if op.band == "long" and current >= 2: return _result(false, "La identidad final exige banda corta.")
			op.task = _challenge(target.id, "analysis", 3 + current, sim.state.sequence + current * 31)
			return _result(true, "Patrón de análisis preparado. Reproduce la secuencia.")
		"hack_begin":
			var target = sim.contact(str(args.get("target", "")))
			if target.is_empty() or not target.identified or target.kind not in ["hostile", "station"] or target.hull <= 0: return _result(false, "Hackeo: hostil o estación identificados y activos.")
			if op.band != "short" or not _in_range(sim, op, target): return _result(false, "El hackeo exige banda corta y contacto en alcance.")
			op.task = _challenge(target.id, "hack", 6, sim.state.sequence + target.frequency * 17)
			return _result(true, "Handshake capturado. Completa la secuencia de intrusión.")
		"input":
			if op.task.is_empty(): return _result(false, "No hay un reto de sensores activo.")
			var value = args.get("value", -1)
			if not Catalog.finite_number(value) or int(value) != float(value) or int(value) < 0 or int(value) > 3: return _result(false, "Pulso de sensores inválido.")
			var progress = int(op.task.progress)
			if progress >= op.task.pattern.size(): return _result(false, "El reto ya ha terminado.")
			if int(value) != int(op.task.pattern[progress]):
				op.task.progress = 0
				op.task.errors = int(op.task.errors) + 1
				if op.task.errors >= 3:
					op.task = {}
					return _result(false, "Tres errores: el patrón se ha perdido. Inicia otro análisis.")
				return _result(false, "Pulso incorrecto. La secuencia vuelve al inicio.")
			op.task.progress = progress + 1
			if op.task.progress < op.task.pattern.size(): return _result(true, "Pulso correcto · %d/%d" % [op.task.progress, op.task.pattern.size()])
			var task = op.task.duplicate(true)
			op.task = {}
			return _resolve(sim, task)
		"cancel":
			if op.task.is_empty(): return _result(false, "No hay un reto activo.")
			op.task = {}
			return _result(true, "Reto de sensores cancelado.")
		_:
			return _result(false, "Orden de sensores desconocida.")

func _challenge(target: String, mode: String, length: int, seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = int(seed_value) ^ target.hash() ^ mode.hash()
	var pattern: Array = []
	for i in length: pattern.append(rng.randi_range(0, 3))
	return {"target": target, "mode": mode, "pattern": pattern, "progress": 0, "errors": 0}

func _origin(sim, op: Dictionary) -> Array:
	if not str(op.origin).is_empty():
		var probe = sim.contact(str(op.origin))
		if not probe.is_empty() and probe.probed: return probe.position
	return sim.state.ship.position

func _in_range(sim, op: Dictionary, target: Dictionary) -> bool:
	var origin = _origin(sim, op)
	var distance = Vector2(origin[0], origin[1]).distance_to(Vector2(target.position[0], target.position[1]))
	var reach = SHORT_RANGE if op.band == "short" else LONG_RANGE
	if ShipModel.efficiency(sim.state.ship, "sensores") <= 0: return false
	if distance > 300 and SpacePhysics.obscured(sim.state.contacts, origin, target.position): reach *= 0.35
	return distance <= reach * maxf(0.25, ShipModel.efficiency(sim.state.ship, "sensores"))

func _resolve(sim, task: Dictionary) -> Dictionary:
	var target = sim.contact(str(task.target))
	if target.is_empty(): return _result(false, "El contacto ya no está disponible.")
	if task.mode == "hack":
		target.attack_at = maxf(float(target.attack_at), sim.state.time + 22.0)
		target.jammed = false
		target.hacked_until = sim.state.time + 22.0
		state.hacks[target.id] = {"until": target.hacked_until, "frequency": int(target.frequency)}
		sim.log_event("Sensores", "Intrusión completada sobre " + target.name + ": enlace hostil inhibido durante 22 s.")
		return _result(true, "Hackeo completado: frecuencia %d e inhibición temporal." % int(target.frequency))
	var next_level = mini(3, analysis_level(target.id) + 1)
	state.levels[target.id] = next_level
	if next_level >= 3:
		target.identified = true
		sim.fact("scan", target.id)
		sim.log_event("Sensores", "Identidad confirmada: " + target.name + ".")
		var expedition = get_tree().root.get_node_or_null("Expedition")
		if expedition != null: expedition._consume_session(_session())
		return _result(true, "Análisis completo: identidad confirmada.")
	sim.log_event("Sensores", "Análisis de %s elevado a nivel %d (%s)." % [target.name, next_level, ANALYSIS_LEVELS[next_level]])
	return _result(true, "Nivel de análisis %d: %s." % [next_level, ANALYSIS_LEVELS[next_level]])

func contact_readout(contact: Dictionary) -> Dictionary:
	var level = analysis_level(str(contact.get("id", "")))
	if contact.get("identified", false): level = 3
	var result = {"level": level, "name": contact.get("name", "Eco"), "kind": "unknown", "frequency": -1}
	if level >= 2: result.kind = contact.get("kind", "unknown")
	if level >= 3:
		result.name = contact.get("name", "Contacto")
		result.frequency = int(contact.get("frequency", -1))
	return result

func _process(delta: float) -> void:
	var session = _session()
	if session == null: return
	if _authority():
		for target in state.hacks.keys():
			if float(state.hacks[target].until) <= session.sim.state.get("time", 0.0): state.hacks.erase(target)
		_broadcast_clock += delta
		if _broadcast_clock >= 0.25 and session.mode == "host":
			_broadcast_clock = 0.0
			for key in session.roster:
				var peer_id = int(key)
				if peer_id == 1 or peer_id not in multiplayer.get_peers(): continue
				_snapshot.rpc_id(peer_id, _view_for(str(peer_id)))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_F3: return
	if _window != null and is_instance_valid(_window):
		_window.queue_free()
		_window = null
	else:
		_window = SensorConsole.new()
		_window.sensors = self
		get_tree().root.add_child(_window)
		_window.close_requested.connect(func(): _window.queue_free(); _window = null)
		_window.popup_centered()
	get_viewport().set_input_as_handled()

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
