class_name GMInteriorTrigger
extends RefCounted
## Small, host-authoritative bridge from a real interior zone to GM live actions.
## The trigger is intentionally authored in code: it does not add a second GM state store.

const TRIGGER_ID := "cantina_arrival"
const ZONE_NAME := "Cantina"
const PUBLIC_MESSAGE := "La dirección registra la entrada de la tripulación en la cantina."

var _session: Node
var _last_run_id := ""
var _fired := false

func setup(session: Node) -> void:
	_session = session
	_last_run_id = ""
	_fired = false

func enter_zone(name: String) -> Dictionary:
	if name != ZONE_NAME:
		return {"ok": true, "triggered": false, "duplicate": false, "trigger_id": TRIGGER_ID, "reason": "zone_not_bound"}
	if not is_instance_valid(_session): return _rejected("No hay una sesión activa para el trigger de interior.")
	if not GMLiveActions.can_direct(_session): return _rejected("El trigger sólo se ejecuta en el anfitrión local.")
	var run_id := str(_session.sim.state.get("run_id", ""))
	if run_id.is_empty(): return _rejected("La misión activa no tiene identificador de ejecución.")
	if _last_run_id != run_id:
		_last_run_id = run_id
		_fired = false
	if _fired:
		return {"ok": true, "triggered": false, "duplicate": true, "trigger_id": TRIGGER_ID, "reason": "already_fired"}
	var result: Dictionary = GMLiveActions.dispatch(_session, "message", {"text": PUBLIC_MESSAGE}, run_id)
	result["trigger_id"] = TRIGGER_ID
	result["triggered"] = result.ok
	result["duplicate"] = false
	if result.ok: _fired = true
	return result

func _rejected(message: String) -> Dictionary:
	return {"ok": false, "message": message, "triggered": false, "duplicate": false, "trigger_id": TRIGGER_ID}
