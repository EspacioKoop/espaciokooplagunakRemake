class_name InteriorTriggers
extends RefCounted

## System for managing zone triggers in interior ship and deck spaces.
## Allows GM and scripts to place event triggers (enter zone, exit zone, interact, sit)
## with configurable conditions and live direction consequences.

const InteriorEventActions = preload("res://core/gm_live_actions.gd")
const TRIGGER_EVENTS = ["enter_zone", "exit_zone", "interact", "sit"]
const CONSEQUENCE_ACTIONS = ["alert", "message", "damage", "repair", "reinforcements", "fact", "custom"]
const MAX_TRIGGERS := 64

static func validate_trigger(trigger: Variant) -> String:
	if not trigger is Dictionary: return "Trigger inválido."
	for key in trigger.keys():
		if key not in ["id", "zone", "event_type", "consequence", "one_shot", "fired", "target_id", "created_at"]:
			return "Campo de trigger no permitido."
	for key in ["id", "zone", "event_type", "consequence", "one_shot"]:
		if not trigger.has(key): return "Trigger incompleto: falta " + key + "."
	if not GMLiveState.identifier(trigger.id): return "ID de trigger no válido."
	if not GMLiveState.number(trigger.zone, -1, 12, true): return "Zona de trigger fuera de rango."
	if not trigger.event_type is String or trigger.event_type not in TRIGGER_EVENTS: return "Evento de trigger no admitido."
	if not trigger.consequence is Dictionary or trigger.consequence.size() != 2 or not trigger.consequence.has_all(["action", "value"]): return "Consecuencia de trigger incompleta."
	var action: String = str(trigger.consequence.action)
	if action not in CONSEQUENCE_ACTIONS: return "Consecuencia de trigger no admitida."
	if action in ["alert"] and (not trigger.consequence.value is String or trigger.consequence.value not in ["verde", "ambar", "roja"]): return "Alerta de trigger no válida."
	if action in ["damage", "repair"] and not GMLiveState.number(trigger.consequence.value, 0.001, 1000): return "Cantidad de trigger fuera de rango."
	if action == "reinforcements" and not GMLiveState.number(trigger.consequence.value, 1, 12, true): return "Refuerzos de trigger fuera de rango."
	if action in ["message", "fact", "custom"] and (not trigger.consequence.value is String or trigger.consequence.value.strip_edges().is_empty() or trigger.consequence.value.length() > 240): return "Texto de trigger no válido."
	if not trigger.one_shot is bool: return "one_shot de trigger debe ser booleano."
	if trigger.has("fired") and not trigger.fired is bool: return "Estado fired de trigger no válido."
	if trigger.has("target_id") and (not trigger.target_id is String or (not trigger.target_id.is_empty() and not GMLiveState.identifier(trigger.target_id))): return "Destino de trigger no válido."
	if trigger.has("created_at") and not GMLiveState.number(trigger.created_at, 0, 1e15, true): return "Marca temporal de trigger no válida."
	return ""

static func _normalized_trigger(trigger: Dictionary) -> Dictionary:
	var result := {
		"id": str(trigger.id).strip_edges(),
		"zone": int(trigger.zone),
		"event_type": str(trigger.event_type),
		"consequence": trigger.consequence.duplicate(true),
		"one_shot": bool(trigger.one_shot),
		"fired": bool(trigger.get("fired", false)),
		"created_at": int(trigger.get("created_at", Time.get_ticks_msec()))
	}
	if trigger.has("target_id"): result.target_id = str(trigger.target_id)
	return result

static func _state_error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func create_trigger(id: String, zone: int, event_type: String, consequence: Dictionary, one_shot: bool = true) -> Dictionary:
	return {
		"id": id,
		"zone": zone,
		"event_type": event_type,
		"consequence": consequence,
		"one_shot": one_shot,
		"fired": false,
		"created_at": Time.get_ticks_msec()
	}

static func ensure_state(sim: Simulation) -> void:
	if sim == null or sim.state.is_empty(): return
	if not sim.state.has("interior_triggers"):
		sim.state["interior_triggers"] = []

static func validate_state(state: Dictionary) -> String:
	if not state.has("interior_triggers"): return ""
	var triggers = state.get("interior_triggers")
	if not triggers is Array or triggers.size() > MAX_TRIGGERS:
		return "Lista de triggers de interior inválida."
	var ids: Array = []
	for index in triggers.size():
		var trigger = triggers[index]
		var error := validate_trigger(trigger)
		if not error.is_empty(): return "Trigger %d inválido: %s" % [index, error]
		if trigger.id in ids: return "ID de trigger duplicado: " + str(trigger.id)
		ids.append(trigger.id)
	return ""

static func register_trigger(sim: Simulation, trigger: Dictionary) -> Dictionary:
	if sim == null or sim.state.is_empty():
		return _state_error("Simulación no válida.")
	var validation := validate_trigger(trigger)
	if not validation.is_empty(): return _state_error(validation)
	ensure_state(sim)
	if sim.state["interior_triggers"].size() >= MAX_TRIGGERS: return _state_error("Se ha alcanzado el límite de triggers de interior.")
	for existing in sim.state["interior_triggers"]:
		if existing.get("id") == trigger.id:
			return _state_error("Ya existe un trigger con este ID.")
	sim.state["interior_triggers"].append(_normalized_trigger(trigger))
	return {"ok": true, "message": "Trigger registrado: " + str(trigger.id)}

static func update_trigger(sim: Simulation, id: String, changes: Dictionary) -> Dictionary:
	if sim == null or sim.state.is_empty(): return _state_error("Simulación no válida.")
	if not GMLiveState.identifier(id): return _state_error("ID de trigger no válido.")
	ensure_state(sim)
	for index in sim.state["interior_triggers"].size():
		var current: Dictionary = sim.state["interior_triggers"][index]
		if current.get("id", "") != id: continue
		for key in changes:
			if key not in ["zone", "event_type", "consequence", "one_shot", "target_id"]: return _state_error("Campo de modificación no permitido.")
		var candidate: Dictionary = current.duplicate(true)
		for key in changes: candidate[key] = changes[key]
		candidate.fired = false
		var validation := validate_trigger(candidate)
		if not validation.is_empty(): return _state_error(validation)
		sim.state["interior_triggers"][index] = _normalized_trigger(candidate)
		return {"ok": true, "message": "Trigger modificado: " + id}
	return _state_error("Trigger no encontrado.")
static func remove_trigger(sim: Simulation, id: String) -> Dictionary:
	if sim == null or sim.state.is_empty():
		return {"ok": false, "message": "Simulación no válida."}
	ensure_state(sim)
	for i in sim.state["interior_triggers"].size():
		if sim.state["interior_triggers"][i].get("id") == id:
			sim.state["interior_triggers"].remove_at(i)
			return {"ok": true, "message": "Trigger retirado: " + id}
	return {"ok": false, "message": "Trigger no encontrado."}

static func list_triggers(sim: Simulation) -> Array:
	if sim == null or sim.state.is_empty(): return []
	ensure_state(sim)
	return sim.state["interior_triggers"]

static func evaluate_zone_movement(sim: Simulation, previous_zone: int, new_zone: int) -> Array:
	if sim == null or sim.state.is_empty(): return []
	ensure_state(sim)
	var executed: Array = []
	for trigger in sim.state["interior_triggers"]:
		if trigger.get("fired", false) and trigger.get("one_shot", true):
			continue
		var zone_matches = trigger.get("zone", -1) == new_zone or trigger.get("zone", -1) == -1
		var event_type = trigger.get("event_type", "")
		if event_type == "enter_zone" and zone_matches and previous_zone != new_zone:
			var res = execute_trigger(sim, trigger)
			if res.ok: executed.append(res)
		elif event_type == "exit_zone" and trigger.get("zone", -1) == previous_zone and previous_zone != new_zone:
			var res = execute_trigger(sim, trigger)
			if res.ok: executed.append(res)
	return executed

static func evaluate_interaction(sim: Simulation, zone: int, interaction_id: String, event_type: String = "interact") -> Array:
	if sim == null or sim.state.is_empty(): return []
	ensure_state(sim)
	var executed: Array = []
	for trigger in sim.state["interior_triggers"]:
		if trigger.get("fired", false) and trigger.get("one_shot", true):
			continue
		if trigger.get("event_type", "") == event_type and (trigger.get("zone", -1) == zone or trigger.get("zone", -1) == -1):
			var target_interact = trigger.get("target_id", "")
			if target_interact.is_empty() or target_interact == interaction_id:
				var res = execute_trigger(sim, trigger)
				if res.ok: executed.append(res)
	return executed

static func execute_trigger(sim: Simulation, trigger: Dictionary) -> Dictionary:
	if sim == null or sim.state.is_empty():
		return {"ok": false, "message": "Simulación no activa."}
	trigger["fired"] = true
	var cons: Dictionary = trigger.get("consequence", {})
	var action: String = cons.get("action", "")
	var value: Variant = cons.get("value", "")
	var msg = "Trigger ejecutado: " + str(trigger.get("id"))
	GMLiveState.ensure(sim.state)
	sim.log_event("Dirección", msg)
	sim.state.gm_live.audit.append({"seq": sim.state.sequence, "time": sim.state.time, "operation": "interior_trigger", "target": ""})
	while sim.state.gm_live.audit.size() > GMLiveState.MAX_AUDIT: sim.state.gm_live.audit.pop_front()
	
	var applied: Dictionary = {"ok": true, "message": "Evento aplicado."}
	match action:
		"alert": applied = InteriorEventActions.trigger_event(sim, "alert", {"level": value})
		"message": applied = InteriorEventActions.trigger_event(sim, "message", {"text": value})
		"damage", "repair": applied = InteriorEventActions.trigger_event(sim, action, {"amount": value})
		"reinforcements": applied = InteriorEventActions.trigger_event(sim, "reinforcements", {"count": value})
		"fact":
			sim.fact("fact", value)
			sim.log_event("Dirección", "Hecho de misión registrado por trigger de interior.")
		"custom":
			sim.log_event("Dirección", "Evento personalizado de interior ejecutado.")
	if not applied.get("ok", false):
		trigger["fired"] = false
		return applied
	return {"ok": true, "message": msg, "trigger": trigger.id, "action": action}
