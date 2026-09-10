class_name CrewSystem
extends Node
## Native crew rules. Character outcomes are generated and resolved by the host.
## Profiles live in ExpeditionSystems so campaign, multiplayer and character UI share one source.

signal updated
signal notice(text: String, ok: bool)

const TRAITS = {
	"beteranoa": {"name": "Veteranía", "skill": "combate", "bonus": 2},
	"jakinmina": {"name": "Curiosidad", "skill": "ciencia", "bonus": 2},
	"mekanikaria": {"name": "Manos de mecánico", "skill": "ingenieria", "bonus": 2},
	"diplomazalea": {"name": "Voz tranquila", "skill": "negociacion", "bonus": 2},
	"nabigatzailea": {"name": "Instinto de ruta", "skill": "pilotaje", "bonus": 2}
}
const ABILITIES = {
	"azterketa": {"name": "Lectura de patrón", "skill": "ciencia", "cost": 1, "description": "Obtén ventaja en la siguiente prueba científica."},
	"overclock": {"name": "Overclock seguro", "skill": "ingenieria", "cost": 1, "description": "Recupera energía y reduce calor de un sistema."},
	"lasaitasuna": {"name": "Calma bajo presión", "skill": "negociacion", "cost": 1, "description": "Reduce la alerta y mejora reputación diplomática."},
	"maniobra": {"name": "Maniobra imposible", "skill": "pilotaje", "cost": 1, "description": "Reduce velocidad y estabiliza la nave al instante."},
	"adrenalina": {"name": "Adrenalina", "skill": "combate", "cost": 1, "description": "Otorga un bono de combate a la próxima acción terrestre."}
}
const MAX_FOCUS = 3
const MAX_LEVEL = 10

var _rng = RandomNumberGenerator.new()
var _broadcast_clock = 0.0
var _window: Window
var last_result: Dictionary = {}
var pending_advantage: Dictionary = {}
var combat_bonuses: Dictionary = {}

func _ready() -> void:
	_rng.randomize()
	set_process_unhandled_key_input(true)
	var expedition = _expedition()
	if expedition != null: _migrate_profiles(expedition)

func _session() -> Node:
	return get_tree().root.get_node_or_null("Session")

func _expedition() -> Node:
	return get_tree().root.get_node_or_null("Expedition")

func _authority() -> bool:
	var session = _session()
	return session == null or session.mode != "client"

func actor_id() -> String:
	var session = _session()
	if session == null or session.mode == "offline": return "self"
	return str(multiplayer.get_unique_id())

func _migrate_profiles(expedition: Node) -> void:
	for id in expedition.data.profiles:
		_ensure_fields(expedition.data.profiles[id])

func profile(actor: String = "") -> Dictionary:
	var expedition = _expedition()
	if expedition == null: return {}
	var id = actor if not actor.is_empty() else actor_id()
	var result: Dictionary = expedition.profile(id)
	_ensure_fields(result)
	return result

func _ensure_fields(profile_data: Dictionary) -> void:
	if not profile_data.has("traits"): profile_data.traits = []
	if not profile_data.has("level"): profile_data.level = 1
	if not profile_data.has("xp"): profile_data.xp = 0
	if not profile_data.has("focus"): profile_data.focus = MAX_FOCUS
	if not profile_data.has("condition"): profile_data.condition = 100
	if not profile_data.has("milestones"): profile_data.milestones = []

func command(operation: String, args: Dictionary = {}) -> Dictionary:
	if args.size() > 8: return _result(false, "Demasiados parámetros de personaje.")
	var session = _session()
	if session != null and session.mode == "client":
		_receive_command.rpc_id(1, operation, args)
		return _result(true, "Acción de personaje enviada al anfitrión.")
	var role = session.role if session != null else "mando"
	var response = _perform(operation, args, actor_id(), role)
	if response.ok:
		var expedition = _expedition()
		if expedition != null: expedition.save()
		updated.emit()
	notice.emit(response.message, response.ok)
	return response

@rpc("any_peer", "call_remote", "reliable", 3)
func _receive_command(operation: String, args: Dictionary) -> void:
	var session = _session()
	if session == null or session.mode != "host": return
	var peer_id = multiplayer.get_remote_sender_id()
	if not session.roster.has(peer_id): return
	var response = _perform(operation, args, str(peer_id), str(session.roster[peer_id].role))
	_response.rpc_id(peer_id, response.message, response.ok, last_result if response.ok else {})
	if response.ok:
		var expedition = _expedition()
		if expedition != null: expedition.save()
		updated.emit()

@rpc("authority", "call_remote", "reliable", 3)
func _response(text: String, ok: bool, result: Dictionary) -> void:
	if ok and not result.is_empty(): last_result = result
	notice.emit(text, ok)
	updated.emit()

func _perform(operation: String, args: Dictionary, actor: String, role: String) -> Dictionary:
	var profile_data = profile(actor)
	if profile_data.is_empty(): return _result(false, "No hay ficha de tripulación.")
	match operation:
		"trait_add":
			var trait_id = str(args.get("trait", ""))
			if trait_id not in TRAITS: return _result(false, "Rasgo desconocido.")
			if trait_id in profile_data.traits: return _result(false, "Ya tienes ese rasgo.")
			if profile_data.traits.size() >= 2 + int(profile_data.level >= 5): return _result(false, "No quedan huecos de rasgo en este nivel.")
			profile_data.traits.append(trait_id)
			return _result(true, "Rasgo adquirido: " + TRAITS[trait_id].name + ".")
		"check":
			var skill = str(args.get("skill", ""))
			var difficulty = int(args.get("difficulty", 10))
			var spend_focus = bool(args.get("focus", false))
			if skill not in ExpeditionSystems.SKILLS or difficulty < 5 or difficulty > 25: return _result(false, "Prueba de habilidad inválida.")
			if spend_focus and int(profile_data.focus) <= 0: return _result(false, "No quedan puntos de concentración.")
			if spend_focus: profile_data.focus -= 1
			var modifier = int(profile_data.skills.get(skill, 0)) * 2 + _trait_bonus(profile_data, skill) + _level_bonus(profile_data.level)
			var advantage = bool(pending_advantage.get(actor + ":" + skill, false))
			pending_advantage.erase(actor + ":" + skill)
			var first = _rng.randi_range(1, 20)
			var second = _rng.randi_range(1, 20) if advantage else first
			var roll = maxi(first, second) if advantage else first
			if spend_focus: modifier += 3
			var total = roll + modifier
			var success = total >= difficulty
			last_result = {"actor": actor, "skill": skill, "roll": roll, "second": second, "modifier": modifier, "total": total, "difficulty": difficulty, "success": success, "advantage": advantage}
			_award_xp(profile_data, 2 if success else 1, "Prueba de " + skill)
			_log("Tripulación", "%s: %s %d + %d = %d contra %d." % [profile_data.name, "éxito" if success else "fallo", roll, modifier, total, difficulty])
			return _result(true, "%s · %d contra %d" % ["ÉXITO" if success else "FALLO", total, difficulty])
		"ability":
			var ability = str(args.get("ability", ""))
			if ability not in ABILITIES: return _result(false, "Capacidad desconocida.")
			var definition: Dictionary = ABILITIES[ability]
			if int(profile_data.focus) < int(definition.cost): return _result(false, "Concentración insuficiente.")
			if int(profile_data.skills.get(definition.skill, 0)) <= 0: return _result(false, "Tu ficha no permite usar esa capacidad.")
			profile_data.focus -= int(definition.cost)
			var effect = _apply_ability(actor, role, ability, args)
			if not effect.ok:
				profile_data.focus += int(definition.cost)
				return effect
			_award_xp(profile_data, 1, definition.name)
			return effect
		"rest":
			if role != "mando": return _result(false, "Mando autoriza el descanso de la tripulación.")
			var expedition = _expedition()
			for id in expedition.data.profiles:
				_ensure_fields(expedition.data.profiles[id])
				expedition.data.profiles[id].focus = MAX_FOCUS
				expedition.data.profiles[id].condition = mini(100, int(expedition.data.profiles[id].condition) + 20)
			return _result(true, "Guardia de descanso completada: concentración recuperada.")
		"condition":
			if role != "mando": return _result(false, "Solo Mando puede registrar condición fuera de combate.")
			var delta = int(args.get("delta", 0))
			if delta < -100 or delta > 100: return _result(false, "Cambio de condición inválido.")
			profile_data.condition = clampi(int(profile_data.condition) + delta, 0, 100)
			return _result(true, "Condición de %s: %d%%." % [profile_data.name, profile_data.condition])
		_:
			return _result(false, "Acción de personaje desconocida.")

func _trait_bonus(profile_data: Dictionary, skill: String) -> int:
	var bonus = 0
	for trait_id in profile_data.traits:
		if trait_id in TRAITS and TRAITS[trait_id].skill == skill: bonus += int(TRAITS[trait_id].bonus)
	return bonus

func _level_bonus(level: int) -> int:
	return maxi(0, (int(level) - 1) / 3)

func _award_xp(profile_data: Dictionary, amount: int, milestone: String) -> void:
	profile_data.xp += amount
	var threshold = int(profile_data.level) * 10
	while profile_data.xp >= threshold and profile_data.level < MAX_LEVEL:
		profile_data.xp -= threshold
		profile_data.level += 1
		profile_data.focus = MAX_FOCUS
		profile_data.milestones.append("Nivel %d · %s" % [profile_data.level, milestone])
		threshold = int(profile_data.level) * 10
	if profile_data.milestones.size() > 20: profile_data.milestones.pop_front()

func _apply_ability(actor: String, role: String, ability: String, args: Dictionary) -> Dictionary:
	var session = _session()
	if session == null or session.sim.state.is_empty(): return _result(false, "No hay una nave activa.")
	var ship: Dictionary = session.sim.state.ship
	match ability:
		"azterketa":
			pending_advantage[actor + ":ciencia"] = true
			return _result(true, "Lectura de patrón preparada: ventaja en Ciencia.")
		"overclock":
			if role != "ingenieria" and role != "reparaciones": return _result(false, "Overclock requiere Ingeniería o Reparaciones.")
			var system = str(args.get("system", "motores"))
			if system not in Catalog.SYSTEMS: return _result(false, "Sistema inválido.")
			ship.energy = minf(100.0, float(ship.energy) + 8.0)
			ship.systems[system].heat = maxf(0.0, float(ship.systems[system].heat) - 18.0)
			return _result(true, "Overclock seguro: +8 energía y −18 °C en " + Catalog.SYSTEM_NAMES[system] + ".")
		"lasaitasuna":
			if role != "comunicaciones" and role != "mando": return _result(false, "Calma bajo presión requiere Comunicaciones o Mando.")
			ship.alert = "verde"
			var expedition = _expedition()
			if expedition != null: expedition.data.factions.itsasargi.reputation = clampi(int(expedition.data.factions.itsasargi.reputation) + 1, -100, 100)
			return _result(true, "Alerta rebajada y vínculo diplomático reforzado.")
		"maniobra":
			if role != "navegacion": return _result(false, "La maniobra requiere Navegación.")
			ship.speed *= 0.65
			ship.throttle = 0.0
			ship.turn_rate = 0.0
			return _result(true, "Maniobra de estabilización completada.")
		"adrenalina":
			combat_bonuses[actor] = 3
			return _result(true, "Adrenalina preparada: +3 a la próxima acción terrestre.")
	return _result(false, "Capacidad sin implementación.")

func consume_combat_bonus(actor: String) -> int:
	var bonus = int(combat_bonuses.get(actor, 0))
	combat_bonuses.erase(actor)
	return bonus

func _log(source: String, text: String) -> void:
	var expedition = _expedition()
	if expedition != null: expedition._append_chronicle(source, text)
	var session = _session()
	if session != null and not session.sim.state.is_empty(): session.sim.log_event(source, text)

func _process(delta: float) -> void:
	var session = _session()
	if session == null or not _authority() or session.mode != "host": return
	_broadcast_clock += delta
	if _broadcast_clock < 0.5: return
	_broadcast_clock = 0.0
	for key in session.roster:
		var peer_id = int(key)
		if peer_id == 1 or peer_id not in multiplayer.get_peers(): continue
		_sync_result.rpc_id(peer_id, last_result if str(last_result.get("actor", "")) == str(peer_id) else {})

@rpc("authority", "call_remote", "reliable", 3)
func _sync_result(result: Dictionary) -> void:
	if not result.is_empty(): last_result = result
	updated.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_F4: return
	if _window != null and is_instance_valid(_window):
		_window.queue_free()
		_window = null
	else:
		_window = CrewConsole.new()
		_window.crew = self
		get_tree().root.add_child(_window)
		_window.close_requested.connect(func(): _window.queue_free(); _window = null)
		_window.popup_centered()
	get_viewport().set_input_as_handled()

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
