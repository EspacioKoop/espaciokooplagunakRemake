class_name GroundCombat
extends Node
## Standalone tactical character combat. The host owns initiative, hit rolls, damage and AI.
## It is intentionally independent from Foundry and feeds results back into crew progression.

signal updated
signal notice(text: String, ok: bool)

const WIDTH = 10
const HEIGHT = 7
const MAX_RANGE = 7
const WEAPONS = {
	"pistola": {"name": "Pistola de pulso", "range": 5, "damage": [4, 8], "accuracy": 1},
	"carabina": {"name": "Carabina de expedición", "range": 7, "damage": [5, 10], "accuracy": 0},
	"escopeta": {"name": "Dispersor magnético", "range": 3, "damage": [6, 12], "accuracy": 2},
	"baston": {"name": "Bastón de arco", "range": 1, "damage": [5, 9], "accuracy": 2}
}
const ENEMIES = {
	"corsario": {"name": "Corsario Itzal", "hp": 24, "armor": 11, "weapon": "pistola", "skill": 2},
	"centinela": {"name": "Centinela", "hp": 32, "armor": 13, "weapon": "carabina", "skill": 3},
	"enjambre": {"name": "Enjambre de drones", "hp": 18, "armor": 10, "weapon": "escopeta", "skill": 1}
}

var state: Dictionary = {}
var _rng = RandomNumberGenerator.new()
var _ai_clock = 0.0
var _broadcast_clock = 0.0
var _window: Window

func _ready() -> void:
	_rng.randomize()
	set_process_unhandled_key_input(true)

func _session() -> Node:
	return get_tree().root.get_node_or_null("Session")

func _crew() -> Node:
	return get_tree().root.get_node_or_null("Crew")

func _expedition() -> Node:
	return get_tree().root.get_node_or_null("Expedition")

func _authority() -> bool:
	var session = _session()
	return session == null or session.mode != "client"

func actor_id() -> String:
	var session = _session()
	if session == null or session.mode == "offline": return "self"
	return str(multiplayer.get_unique_id())

func start_encounter(kind: String = "corsario", count: int = 2) -> Dictionary:
	var session = _session()
	if session != null and session.mode == "client":
		_receive_command.rpc_id(1, "start", {"kind": kind, "count": count})
		return _result(true, "Solicitud de combate enviada a Mando.")
	var role = session.role if session != null else "mando"
	return _perform("start", {"kind": kind, "count": count}, actor_id(), role)

func command(operation: String, args: Dictionary = {}) -> Dictionary:
	if args.size() > 8: return _result(false, "Demasiados parámetros de combate.")
	var session = _session()
	if session != null and session.mode == "client":
		_receive_command.rpc_id(1, operation, args)
		return _result(true, "Acción táctica enviada al anfitrión.")
	var response = _perform(operation, args, actor_id(), session.role if session != null else "mando")
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
	if JSON.stringify(incoming).length() > 128000: return
	state = incoming.duplicate(true)
	updated.emit()

func _perform(operation: String, args: Dictionary, actor: String, role: String) -> Dictionary:
	match operation:
		"start": return _start(args, actor, role)
		"move": return _move(actor, args)
		"attack": return _attack(actor, str(args.get("target", "")))
		"guard": return _guard(actor)
		"help": return _help(actor, str(args.get("target", "")))
		"medkit": return _medkit(actor, str(args.get("target", actor)))
		"end": return _end_turn(actor)
		"flee": return _flee(actor)
		"close":
			if role != "mando": return _result(false, "Solo Mando puede cerrar un encuentro táctico.")
			state = {}
			return _result(true, "Encuentro táctico cerrado.")
	return _result(false, "Acción táctica desconocida.")

func _start(args: Dictionary, actor: String, role: String) -> Dictionary:
	if not state.is_empty() and state.get("status", "") == "active": return _result(false, "Ya hay un combate activo.")
	if role != "mando" and actor != "self": return _result(false, "Mando inicia las expediciones tácticas.")
	var kind = str(args.get("kind", "corsario"))
	var count = int(args.get("count", 2))
	if kind not in ENEMIES or count < 1 or count > 6: return _result(false, "Configuración de encuentro inválida.")
	var participants: Array = []
	var expedition = _expedition()
	var session = _session()
	var actors: Array = ["self"]
	if session != null and session.mode == "host":
		actors = []
		for key in session.roster:
			actors.append(str(key))
	if expedition != null:
		for id in actors:
			var profile: Dictionary = expedition.profile(id)
			var crew = _crew()
			if crew != null: crew._ensure_fields(profile)
			participants.append(_crew_unit(id, profile, participants.size()))
	if participants.is_empty():
		participants.append({"id":"self", "name":"Tripulante", "team":"crew", "position":[1, HEIGHT / 2], "hp":30, "max_hp":30, "armor":11, "weapon":"pistola", "skill":1, "move":4, "guard":false, "help":0, "acted":false, "down":false, "initiative":0})
	for i in count:
		participants.append(_enemy_unit(kind, i))
	var obstacles = _obstacles()
	for unit in participants:
		unit.initiative = _rng.randi_range(1, 20) + int(unit.skill)
	participants.sort_custom(func(a, b): return int(a.initiative) > int(b.initiative))
	state = {"status":"active", "round":1, "turn":0, "units":participants, "obstacles":obstacles, "log":[], "winner":"", "camera":"tactical", "selected":""}
	_advance_to_live_turn()
	_log("Encuentro iniciado: %d tripulantes contra %d %s." % [_alive("crew").size(), count, ENEMIES[kind].name])
	return _result(true, "Combate táctico iniciado.")

func _crew_unit(id: String, profile: Dictionary, index: int) -> Dictionary:
	var combat = int(profile.skills.get("combate", 1))
	var hp = clampi(26 + int(profile.get("level", 1)) * 2 + combat * 2, 28, 60)
	var condition = clampi(int(profile.get("condition", 100)), 0, 100)
	hp = maxi(1, int(round(float(hp) * maxf(0.25, condition / 100.0))))
	var weapon = "carabina" if combat >= 3 else ("escopeta" if profile.approach == "temple" else "pistola")
	return {"id":id, "name":profile.name, "team":"crew", "position":[1, clampi(1 + index * 2, 0, HEIGHT - 1)], "hp":hp, "max_hp":hp, "armor":10 + combat, "weapon":weapon, "skill":combat, "move":4, "guard":false, "help":0, "acted":false, "down":false, "initiative":0}

func _enemy_unit(kind: String, index: int) -> Dictionary:
	var definition: Dictionary = ENEMIES[kind]
	return {"id":"enemy_%d_%s" % [index, kind], "name":definition.name + " %d" % (index + 1), "team":"enemy", "position":[WIDTH - 2, clampi(1 + index, 0, HEIGHT - 1)], "hp":definition.hp, "max_hp":definition.hp, "armor":definition.armor, "weapon":definition.weapon, "skill":definition.skill, "move":3, "guard":false, "help":0, "acted":false, "down":false, "initiative":0}

func _obstacles() -> Array:
	var cells: Array = []
	for cell in [[4,1],[4,2],[4,4],[4,5],[6,3],[2,0],[7,6]]: cells.append(cell)
	return cells

func _turn_unit() -> Dictionary:
	if state.is_empty() or state.get("status", "") != "active": return {}
	if int(state.turn) < 0 or int(state.turn) >= state.units.size(): return {}
	return state.units[int(state.turn)]

func _owns_turn(actor: String) -> bool:
	var unit = _turn_unit()
	return not unit.is_empty() and unit.team == "crew" and str(unit.id) == actor and not unit.down

func _move(actor: String, args: Dictionary) -> Dictionary:
	if not _owns_turn(actor): return _result(false, "No es tu turno táctico.")
	var unit = _turn_unit()
	var x = int(args.get("x", -1)); var y = int(args.get("y", -1))
	if not _inside(x, y) or [x, y] in state.obstacles or _occupied(x, y): return _result(false, "Casilla ocupada o bloqueada.")
	var distance = _distance_cells(unit.position, [x, y])
	if distance > int(unit.move): return _result(false, "La casilla queda fuera de tu movimiento.")
	unit.position = [x, y]
	unit.move -= distance
	unit.guard = false
	_log(unit.name + " se desplaza a %d,%d." % [x, y])
	return _result(true, "Movimiento realizado.")

func _attack(actor: String, target_id: String) -> Dictionary:
	if not _owns_turn(actor): return _result(false, "No es tu turno táctico.")
	var attacker = _turn_unit()
	if attacker.acted: return _result(false, "Ya has realizado tu acción principal.")
	var target = _unit(target_id)
	if target.is_empty() or target.down or target.team == attacker.team: return _result(false, "Objetivo de ataque inválido.")
	var weapon: Dictionary = WEAPONS[attacker.weapon]
	var distance = _distance_cells(attacker.position, target.position)
	if distance > int(weapon.range): return _result(false, "Objetivo fuera de alcance.")
	var cover = _cover(target.position, attacker.position)
	var crew = _crew()
	var bonus = crew.consume_combat_bonus(actor) if crew != null else 0
	var roll = _rng.randi_range(1, 20)
	var total = roll + int(attacker.skill) * 2 + int(weapon.accuracy) + bonus + int(attacker.help)
	attacker.help = 0
	attacker.acted = true
	var defense = int(target.armor) + cover + (2 if target.guard else 0)
	if roll == 1 or (roll != 20 and total < defense):
		_log("%s falla contra %s (%d vs %d)." % [attacker.name, target.name, total, defense])
		_check_end()
		return _result(true, "Disparo fallido · %d vs %d." % [total, defense])
	var minimum = int(weapon.damage[0]); var maximum = int(weapon.damage[1])
	var damage = _rng.randi_range(minimum, maximum) + (maximum / 2 if roll == 20 else 0)
	target.hp = maxi(0, int(target.hp) - damage)
	if target.hp <= 0:
		target.down = true
		_log("%s derriba a %s con %d de daño." % [attacker.name, target.name, damage])
	else:
		_log("%s hiere a %s: %d de daño." % [attacker.name, target.name, damage])
	_check_end()
	return _result(true, "Impacto · %d de daño%s." % [damage, " CRÍTICO" if roll == 20 else ""])

func _guard(actor: String) -> Dictionary:
	if not _owns_turn(actor): return _result(false, "No es tu turno táctico.")
	var unit = _turn_unit()
	if unit.acted: return _result(false, "Ya has realizado tu acción principal.")
	unit.guard = true
	unit.acted = true
	_log(unit.name + " adopta cobertura defensiva.")
	return _result(true, "Guardia activa: +2 defensa hasta tu siguiente turno.")

func _help(actor: String, target_id: String) -> Dictionary:
	if not _owns_turn(actor): return _result(false, "No es tu turno táctico.")
	var unit = _turn_unit()
	if unit.acted: return _result(false, "Ya has realizado tu acción principal.")
	var target = _unit(target_id)
	if target.is_empty() or target.down or target.team != "crew": return _result(false, "Solo puedes asistir a un aliado activo.")
	if _distance_cells(unit.position, target.position) > 3: return _result(false, "Tu aliado queda demasiado lejos para asistirle.")
	target.help = 2
	unit.acted = true
	_log(unit.name + " coordina a " + target.name + ".")
	return _result(true, "Asistencia preparada: +2 a su próximo ataque.")

func _medkit(actor: String, target_id: String) -> Dictionary:
	if not _owns_turn(actor): return _result(false, "No es tu turno táctico.")
	var unit = _turn_unit()
	if unit.acted: return _result(false, "Ya has realizado tu acción principal.")
	var target = _unit(target_id)
	if target.is_empty() or target.team != "crew": return _result(false, "Objetivo médico inválido.")
	if _distance_cells(unit.position, target.position) > 1: return _result(false, "El objetivo debe estar adyacente.")
	var expedition = _expedition()
	if expedition == null: return _result(false, "Inventario de expedición no disponible.")
	var stock: Dictionary = expedition.inventory(actor)
	if int(stock.get("sendagaiak", 0)) <= 0: return _result(false, "No llevas medicinas.")
	stock.sendagaiak -= 1
	target.hp = mini(int(target.max_hp), int(target.hp) + 12)
	if target.hp > 0: target.down = false
	unit.acted = true
	_log("%s atiende a %s (+12)." % [unit.name, target.name])
	return _result(true, "Tratamiento aplicado: +12 salud.")

func _end_turn(actor: String) -> Dictionary:
	if not _owns_turn(actor): return _result(false, "No es tu turno táctico.")
	_next_turn()
	return _result(true, "Turno finalizado.")

func _flee(actor: String) -> Dictionary:
	if not _owns_turn(actor): return _result(false, "No es tu turno táctico.")
	var unit = _turn_unit()
	if int(unit.position[0]) > 1: return _result(false, "Debes alcanzar el borde de extracción para huir.")
	state.status = "fled"
	state.winner = "enemy"
	_log("La tripulación abandona el encuentro.")
	_apply_outcome(false)
	return _result(true, "Retirada completada.")

func _next_turn() -> void:
	if state.get("status", "") != "active": return
	var previous = _turn_unit()
	if not previous.is_empty():
		previous.move = 4 if previous.team == "crew" else 3
		previous.acted = false
		previous.guard = false
	for step in range(1, state.units.size() + 1):
		var index = (int(state.turn) + step) % state.units.size()
		if index <= int(state.turn): state.round += 1
		if not state.units[index].down:
			state.turn = index
			state.selected = state.units[index].id
			_ai_clock = 0.0
			return
	_check_end()

func _advance_to_live_turn() -> void:
	while not state.is_empty() and state.status == "active" and _turn_unit().down:
		_next_turn()
	if not _turn_unit().is_empty(): state.selected = _turn_unit().id

func _process(delta: float) -> void:
	var session = _session()
	if not _authority(): return
	if not state.is_empty() and state.get("status", "") == "active":
		var unit = _turn_unit()
		if not unit.is_empty() and unit.team == "enemy":
			_ai_clock += delta
			if _ai_clock >= 0.55:
				_ai_clock = 0.0
				_enemy_turn(unit)
	if session != null and session.mode == "host":
		_broadcast_clock += delta
		if _broadcast_clock >= 0.2:
			_broadcast_clock = 0.0
			for key in session.roster:
				var peer_id = int(key)
				if peer_id == 1 or peer_id not in multiplayer.get_peers(): continue
				_snapshot.rpc_id(peer_id, state)

func _enemy_turn(enemy: Dictionary) -> void:
	var targets = _alive("crew")
	if targets.is_empty(): _check_end(); return
	var target = targets[0]
	for candidate in targets:
		if _distance_cells(enemy.position, candidate.position) < _distance_cells(enemy.position, target.position): target = candidate
	var weapon: Dictionary = WEAPONS[enemy.weapon]
	if _distance_cells(enemy.position, target.position) <= int(weapon.range):
		_enemy_attack(enemy, target)
	else:
		var best = enemy.position.duplicate()
		var best_distance = _distance_cells(enemy.position, target.position)
		for dx in range(-int(enemy.move), int(enemy.move) + 1):
			for dy in range(-int(enemy.move), int(enemy.move) + 1):
				var candidate = [int(enemy.position[0]) + dx, int(enemy.position[1]) + dy]
				if abs(dx) + abs(dy) > int(enemy.move) or not _inside(candidate[0], candidate[1]) or candidate in state.obstacles or _occupied(candidate[0], candidate[1]): continue
				var distance = _distance_cells(candidate, target.position)
				if distance < best_distance:
					best = candidate
					best_distance = distance
		enemy.position = best
		_log(enemy.name + " avanza.")
		if best_distance <= int(weapon.range): _enemy_attack(enemy, target)
	_next_turn()

func _enemy_attack(enemy: Dictionary, target: Dictionary) -> void:
	var weapon: Dictionary = WEAPONS[enemy.weapon]
	var roll = _rng.randi_range(1, 20)
	var total = roll + int(enemy.skill) * 2 + int(weapon.accuracy)
	var defense = int(target.armor) + _cover(target.position, enemy.position) + (2 if target.guard else 0)
	if roll != 1 and (roll == 20 or total >= defense):
		var damage = _rng.randi_range(int(weapon.damage[0]), int(weapon.damage[1]))
		target.hp = maxi(0, int(target.hp) - damage)
		if target.hp <= 0: target.down = true
		_log("%s impacta a %s por %d." % [enemy.name, target.name, damage])
	else:
		_log(enemy.name + " falla contra " + target.name + ".")
	_check_end()

func _check_end() -> void:
	if state.is_empty() or state.get("status", "") != "active": return
	if _alive("enemy").is_empty():
		state.status = "won"
		state.winner = "crew"
		_log("Zona asegurada por la tripulación.")
		_apply_outcome(true)
	elif _alive("crew").is_empty():
		state.status = "lost"
		state.winner = "enemy"
		_log("La expedición ha quedado fuera de combate.")
		_apply_outcome(false)

func _apply_outcome(victory: bool) -> void:
	var crew = _crew()
	var expedition = _expedition()
	if expedition == null: return
	for unit in state.units:
		if unit.team != "crew": continue
		var profile: Dictionary = expedition.profile(str(unit.id))
		if crew != null: crew._ensure_fields(profile)
		var ratio = float(unit.hp) / maxf(1.0, float(unit.max_hp))
		profile.condition = clampi(int(round(ratio * 100.0)), 0, 100)
		if crew != null: crew._award_xp(profile, 6 if victory else 2, "Combate táctico")
	if victory:
		expedition.data.factions.itzal.reputation = clampi(int(expedition.data.factions.itzal.reputation) - 2, -100, 100)
		var session = _session()
		if session != null and not session.sim.state.is_empty(): session.sim.state.campaign.credits += 20
	expedition._append_chronicle("Expedición", "Combate terrestre " + ("ganado." if victory else "perdido o abandonado."))
	expedition.save()

func _unit(id: String) -> Dictionary:
	if state.is_empty(): return {}
	for unit in state.units:
		if str(unit.id) == id: return unit
	return {}

func _alive(team: String) -> Array:
	if state.is_empty(): return []
	return state.units.filter(func(unit): return unit.team == team and not unit.down and int(unit.hp) > 0)

func _occupied(x: int, y: int) -> bool:
	if state.is_empty(): return false
	for unit in state.units:
		if not unit.down and int(unit.position[0]) == x and int(unit.position[1]) == y: return true
	return false

func _inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < WIDTH and y < HEIGHT

func _distance_cells(a: Array, b: Array) -> int:
	return abs(int(a[0]) - int(b[0])) + abs(int(a[1]) - int(b[1]))

func _cover(target: Array, attacker: Array) -> int:
	var bonus = 0
	for obstacle in state.get("obstacles", []):
		if _distance_cells(obstacle, target) == 1 and _distance_cells(obstacle, attacker) > 1: bonus = maxi(bonus, 2)
	return bonus

func _log(text: String) -> void:
	if state.is_empty(): return
	state.log.append(text.left(220))
	if state.log.size() > 80: state.log.pop_front()
	var expedition = _expedition()
	if expedition != null: expedition._append_chronicle("Táctico", text)

func set_camera(mode: String) -> void:
	if mode not in ["tactical", "third", "pov"]: return
	if state.is_empty(): return
	state.camera = mode
	updated.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_F6: return
	if _window != null and is_instance_valid(_window):
		_window.queue_free()
		_window = null
	else:
		_window = TacticalCombatWindow.new()
		_window.combat = self
		get_tree().root.add_child(_window)
		_window.close_requested.connect(func(): _window.queue_free(); _window = null)
		_window.popup_centered()
	get_viewport().set_input_as_handled()

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
