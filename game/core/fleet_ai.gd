class_name FleetAI
extends Node
## Strategic contact AI. Simulation retains close-range combat; this layer owns long-range fleet intent.

signal updated
signal notice(text: String, ok: bool)

const ORDERS = ["patrol", "escort", "hold", "retreat", "intercept"]
const MAX_STRATEGIC_RANGE = 2600.0
const SPEEDS = {"friendly": 16.0, "hostile": 20.0, "derelict": 0.0}

var _broadcast_clock = 0.0
var _window: Window
var last_report = ""

func _ready() -> void:
	set_process_unhandled_key_input(true)

func _session() -> Node:
	return get_tree().root.get_node_or_null("Session")

func _expedition() -> Node:
	return get_tree().root.get_node_or_null("Expedition")

func _authority() -> bool:
	var session = _session()
	return session == null or session.mode != "client"

func command(operation: String, args: Dictionary = {}) -> Dictionary:
	var session = _session()
	if session != null and session.mode == "client":
		_receive_command.rpc_id(1, operation, args)
		return _result(true, "Orden de flota enviada al anfitrión.")
	var response = _perform(operation, args, session.role if session != null else "mando")
	notice.emit(response.message, response.ok)
	if response.ok: updated.emit()
	return response

@rpc("any_peer", "call_remote", "reliable", 3)
func _receive_command(operation: String, args: Dictionary) -> void:
	var session = _session()
	if session == null or session.mode != "host": return
	var peer_id = multiplayer.get_remote_sender_id()
	if not session.roster.has(peer_id): return
	var response = _perform(operation, args, str(session.roster[peer_id].role))
	_response.rpc_id(peer_id, response.message, response.ok)
	if response.ok: updated.emit()

@rpc("authority", "call_remote", "reliable", 3)
func _response(text: String, ok: bool) -> void:
	notice.emit(text, ok)

func _perform(operation: String, args: Dictionary, role: String) -> Dictionary:
	var session = _session()
	if session == null or session.sim.state.is_empty(): return _result(false, "No hay una misión activa.")
	_bootstrap(session.sim.state.contacts)
	match operation:
		"order":
			if role not in ["mando", "comunicaciones"]: return _result(false, "Mando o Comunicaciones transmiten órdenes de flota.")
			var id = str(args.get("target", "")); var order = str(args.get("order", "")); var objective = str(args.get("objective", ""))
			if order not in ORDERS: return _result(false, "Orden de flota inválida.")
			var contact = session.sim.contact(id)
			if contact.is_empty() or contact.kind != "friendly" or not contact.identified: return _result(false, "Solo una nave aliada identificada acepta órdenes.")
			if not _allied(contact): return _result(false, "La relación con esa facción no permite órdenes directas.")
			if order == "intercept":
				var enemy = session.sim.contact(objective)
				if enemy.is_empty() or enemy.kind != "hostile": return _result(false, "Selecciona un hostil válido para interceptar.")
			contact.ai_order = order
			contact.ai_objective = objective
			last_report = "%s recibe orden %s." % [contact.name, order]
			session.sim.log_event("Flota", last_report)
			return _result(true, last_report)
		"form_convoy":
			if role != "mando": return _result(false, "Solo Mando forma convoyes temporales.")
			var members = args.get("members", [])
			if not members is Array or members.size() < 2 or members.size() > 6: return _result(false, "Un convoy necesita entre 2 y 6 contactos.")
			var convoy = "convoy_" + Crypto.new().generate_random_bytes(5).hex_encode()
			for id in members:
				var contact = session.sim.contact(str(id))
				if contact.is_empty() or contact.kind != "friendly" or not _allied(contact): return _result(false, "Todos los miembros deben ser aliados controlables.")
				contact.fleet_id = convoy
				contact.ai_order = "escort"
			last_report = "Convoy %s formado con %d naves." % [convoy, members.size()]
			session.sim.log_event("Flota", last_report)
			return _result(true, last_report)
		"release_convoy":
			if role != "mando": return _result(false, "Solo Mando disuelve convoyes.")
			var fleet_id = str(args.get("fleet", ""))
			var changed = 0
			for contact in session.sim.state.contacts:
				if str(contact.get("fleet_id", "")) == fleet_id:
					contact.fleet_id = ""
					contact.ai_order = "patrol"
					changed += 1
			if changed == 0: return _result(false, "Convoy inexistente.")
			return _result(true, "Convoy disuelto; las naves vuelven a patrulla.")
	return _result(false, "Orden estratégica desconocida.")

func _bootstrap(contacts: Array) -> void:
	for contact in contacts:
		if contact.kind not in ["friendly", "hostile", "derelict"]: continue
		if not contact.has("faction"):
			contact.faction = "itzal" if contact.kind == "hostile" else ("haize" if posmod(str(contact.id).hash(), 2) == 0 else "itsasargi")
		if not contact.has("ai_order"): contact.ai_order = "patrol" if contact.kind != "derelict" else "hold"
		if not contact.has("ai_objective"): contact.ai_objective = ""
		if not contact.has("fleet_id"): contact.fleet_id = ""
		if not contact.has("morale"): contact.morale = 100.0
		if not contact.has("anchor"): contact.anchor = contact.position.duplicate()
		if not contact.has("ai_phase"): contact.ai_phase = float(posmod(str(contact.id).hash(), 628)) / 100.0

func _allied(contact: Dictionary) -> bool:
	var expedition = _expedition()
	if expedition == null: return true
	var faction = str(contact.get("faction", "haize"))
	return int(expedition.data.factions.get(faction, {"reputation":0}).reputation) >= -10

func _hostile_relation(contact: Dictionary) -> bool:
	var expedition = _expedition()
	if expedition == null: return contact.kind == "hostile"
	var faction = str(contact.get("faction", "itzal"))
	return int(expedition.data.factions.get(faction, {"reputation":0}).reputation) < 20

func _process(delta: float) -> void:
	if not _authority(): return
	var session = _session()
	if session == null or session.sim.state.is_empty() or session.sim.state.status != "active": return
	_bootstrap(session.sim.state.contacts)
	var ship: Dictionary = session.sim.state.ship
	for contact in session.sim.state.contacts:
		if contact.kind not in ["friendly", "hostile"] or contact.hull <= 0 or contact.pacified: continue
		_update_morale(contact)
		var distance = Vector2(contact.position[0], contact.position[1]).distance_to(Vector2(ship.position[0], ship.position[1]))
		if contact.kind == "hostile":
			if not _hostile_relation(contact):
				contact.pacified = true
				session.sim.log_event("Flota", contact.name + " suspende hostilidades por la relación con su facción.")
				continue
			if contact.morale < 22.0: contact.ai_order = "retreat"
			if distance < 700.0 and contact.ai_order != "retreat": continue
		_update_contact(contact, ship, session.sim.state.contacts, delta)
	for contact in session.sim.state.contacts:
		if contact.kind == "friendly" and contact.hull > 0: _update_contact(contact, ship, session.sim.state.contacts, delta)
	if session.mode == "host":
		_broadcast_clock += delta
		if _broadcast_clock >= 0.5:
			_broadcast_clock = 0.0
			_status.rpc()
	updated.emit()

func _update_morale(contact: Dictionary) -> void:
	var hull_fraction = clampf(float(contact.hull) / 100.0, 0.0, 1.0)
	var target = 25.0 + hull_fraction * 75.0
	if contact.kind == "friendly" and _allied(contact): target += 10.0
	contact.morale = move_toward(float(contact.morale), clampf(target, 0.0, 100.0), 0.08)

func _update_contact(contact: Dictionary, ship: Dictionary, contacts: Array, delta: float) -> void:
	var current = Vector2(contact.position[0], contact.position[1])
	var target = current
	var order = str(contact.ai_order)
	if order == "hold": return
	elif order == "escort":
		target = Vector2(ship.position[0], ship.position[1]) + Vector2.from_angle(float(contact.ai_phase)) * 240.0
	elif order == "intercept":
		var objective = _find_contact(contacts, str(contact.ai_objective))
		if objective.is_empty() or objective.hull <= 0:
			contact.ai_order = "escort"
			return
		target = Vector2(objective.position[0], objective.position[1])
		if current.distance_to(target) < 260.0:
			objective.hull = maxf(0.0, float(objective.hull) - 3.5 * delta)
			contact.hull = maxf(0.0, float(contact.hull) - 1.2 * delta)
	elif order == "retreat":
		var away = (current - Vector2(ship.position[0], ship.position[1])).normalized()
		if away == Vector2.ZERO: away = Vector2.RIGHT
		target = current + away * 1000.0
	else:
		var anchor = Vector2(contact.anchor[0], contact.anchor[1])
		var phase = float(contact.ai_phase) + Time.get_ticks_msec() / 1000.0 * 0.08
		target = anchor + Vector2.from_angle(phase) * 320.0
		if contact.kind == "hostile":
			var to_ship = Vector2(ship.position[0], ship.position[1])
			if current.distance_to(to_ship) < MAX_STRATEGIC_RANGE: target = to_ship
	var offset = target - current
	if offset.length() < 5.0: return
	var speed = float(SPEEDS.get(contact.kind, 12.0))
	if order == "retreat": speed *= 1.4
	var step = offset.normalized() * minf(offset.length(), speed * delta)
	var proposed = current + step
	if _clear_position(contact, proposed, contacts, ship): contact.position = [proposed.x, proposed.y]

func _clear_position(contact: Dictionary, position: Vector2, contacts: Array, ship: Dictionary) -> bool:
	if position.distance_to(Vector2(ship.position[0], ship.position[1])) < 80.0: return false
	for other in contacts:
		if other == contact or other.hull <= 0: continue
		if position.distance_to(Vector2(other.position[0], other.position[1])) < 45.0: return false
	return true

func _find_contact(contacts: Array, id: String) -> Dictionary:
	for contact in contacts:
		if str(contact.id) == id: return contact
	return {}

@rpc("authority", "call_remote", "unreliable", 3)
func _status() -> void:
	updated.emit()

func report() -> Array:
	var session = _session()
	if session == null or session.view.is_empty(): return []
	var rows: Array = []
	for visible in session.view.contacts:
		var source = session.sim.contact(str(visible.id)) if session.mode != "client" else visible
		if source.kind not in ["friendly", "hostile"]: continue
		rows.append({"id":source.id, "name":source.name, "kind":source.kind, "faction":source.get("faction", "desconocida"), "order":source.get("ai_order", "patrol"), "fleet":source.get("fleet_id", ""), "morale":source.get("morale", 100.0), "hull":source.hull})
	return rows

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_F7: return
	if _window != null and is_instance_valid(_window):
		_window.queue_free()
		_window = null
	else:
		_window = FleetConsole.new()
		_window.fleet = self
		get_tree().root.add_child(_window)
		_window.close_requested.connect(func(): _window.queue_free(); _window = null)
		_window.popup_centered()
	get_viewport().set_input_as_handled()

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok, "message":message}
