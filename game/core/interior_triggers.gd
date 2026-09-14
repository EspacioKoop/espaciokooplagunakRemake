class_name InteriorTriggers
extends RefCounted

## System for managing zone triggers in interior ship and deck spaces.
## Allows GM and scripts to place event triggers (enter zone, exit zone, interact, sit)
## with configurable conditions and live direction consequences.

const TRIGGER_EVENTS = ["enter_zone", "exit_zone", "interact", "sit"]
const CONSEQUENCE_ACTIONS = ["alert", "message", "damage", "repair", "reinforcements", "fact", "custom"]

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

static func register_trigger(sim: Simulation, trigger: Dictionary) -> Dictionary:
	if sim == null or sim.state.is_empty():
		return {"ok": false, "message": "Simulación no válida."}
	ensure_state(sim)
	if not trigger.has("id") or not trigger.id is String or trigger.id.strip_edges().is_empty():
		return {"ok": false, "message": "ID de trigger no válido."}
	for existing in sim.state["interior_triggers"]:
		if existing.get("id") == trigger.id:
			return {"ok": false, "message": "Ya existe un trigger con este ID."}
	sim.state["interior_triggers"].append(trigger.duplicate(true))
	return {"ok": true, "message": "Trigger registrado: " + str(trigger.id)}

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

static func evaluate_interaction(sim: Simulation, zone: int, interaction_id: String) -> Array:
	if sim == null or sim.state.is_empty(): return []
	ensure_state(sim)
	var executed: Array = []
	for trigger in sim.state["interior_triggers"]:
		if trigger.get("fired", false) and trigger.get("one_shot", true):
			continue
		if trigger.get("event_type", "") == "interact" and trigger.get("zone", -1) == zone:
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
	
	match action:
		"alert":
			if value is String and value in ["verde", "ambar", "roja"]:
				sim.state.ship.alert = value
				sim.log_event("Alerta", "Estado de alerta cambiado a " + value.to_upper() + " por evento de zona.")
		"message":
			if value is String:
				sim.log_event("Transmisión", value)
		"damage":
			var amount = float(value) if (value is float or value is int) else 25.0
			sim.state.ship.hull = maxf(0.0, sim.state.ship.hull - amount)
			sim.log_event("Daño", "Impacto interno en cubierta: -%d integridad." % int(amount))
		"repair":
			var amount = float(value) if (value is float or value is int) else 25.0
			sim.state.ship.hull = minf(sim.state.ship.max_hull, sim.state.ship.hull + amount)
			sim.log_event("Reparación", "Reparación de cubierta efectuada: +%d integridad." % int(amount))
		"fact":
			if value is String:
				sim.fact("fact", value)
		_:
			pass
			
	return {"ok": true, "message": msg, "trigger": trigger.id, "action": action}
