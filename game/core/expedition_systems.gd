class_name ExpeditionSystems
extends Node
## Persistent standalone systems that complement the flight simulation.
## Authority follows the ENet host; Foundry is never consulted.

signal updated
signal notice(text: String, ok: bool)

const FORMAT = "lagunak-expedition"
const VERSION = 1
const PATH = "user://expedition-systems.json"
const FACTIONS = {
	"itsasargi": {"name": "Itsasargi", "description": "Cartógrafos y estaciones civiles del corredor."},
	"burdin": {"name": "Burdin", "description": "Consorcio industrial de salvamento y astilleros."},
	"haize": {"name": "Haize", "description": "Navegantes independientes y convoyes de frontera."},
	"itzal": {"name": "Itzal", "description": "Células hostiles y corsarios de rutas exteriores."}
}
const COMMODITIES = {
	"hornidurak": {"name": "Suministros", "buy": 18, "sell": 11},
	"aleazioak": {"name": "Aleaciones", "buy": 34, "sell": 23},
	"datuak": {"name": "Datos científicos", "buy": 46, "sell": 31},
	"sendagaiak": {"name": "Medicinas", "buy": 28, "sell": 19}
}
const SKILLS = ["pilotaje", "ciencia", "ingenieria", "negociacion", "combate"]
const APPROACHES = ["ingenio", "temple", "empatia", "tecnica"]
const DIRECTOR_KINDS = ["hostile", "friendly", "derelict", "anomaly", "beacon", "asteroid"]

var data: Dictionary = {}
var _last_seq = 0
var _broadcast_clock = 0.0
var _save_clock = 0.0
var _window: Window

func _ready() -> void:
	_load()
	set_process_unhandled_key_input(true)
	updated.emit()

func _session() -> Node:
	return get_tree().root.get_node_or_null("Session")

func _default_data() -> Dictionary:
	var factions = {}
	for id in FACTIONS:
		factions[id] = {"reputation": 0, "encounters": 0, "trades": 0}
	return {
		"format": FORMAT, "version": VERSION,
		"factions": factions,
		"profiles": {}, "inventory": {},
		"atlas": {"sectors": {}, "markers": []},
		"bestiary": {}, "chronicle": [],
		"director": {"tempo": 1.0, "auto_events": false, "threat": 0.0, "spawned": 0}
	}

func _load() -> void:
	data = _default_data()
	if not FileAccess.file_exists(PATH): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary or parsed.get("format", "") != FORMAT or int(parsed.get("version", 0)) != VERSION: return
	for key in data:
		if parsed.has(key) and typeof(parsed[key]) == typeof(data[key]): data[key] = parsed[key]
	for id in FACTIONS:
		if not data.factions.has(id): data.factions[id] = {"reputation": 0, "encounters": 0, "trades": 0}

func save() -> void:
	if not _authority(): return
	var file = FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(data, "\t", false))
	file.close()
	var absolute = ProjectSettings.globalize_path(PATH)
	var temporary = ProjectSettings.globalize_path(PATH + ".tmp")
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(absolute + ".bak")
		DirAccess.rename_absolute(absolute, absolute + ".bak")
	DirAccess.rename_absolute(temporary, absolute)

func _authority() -> bool:
	var session = _session()
	return session == null or session.mode != "client"

func actor_id() -> String:
	var session = _session()
	if session == null or session.mode == "offline": return "self"
	return str(multiplayer.get_unique_id())

func _role_for(peer_id: int) -> String:
	var session = _session()
	if session == null: return "mando"
	if peer_id == 1: return session.role
	return str(session.roster.get(peer_id, {}).get("role", ""))

func profile(actor: String = "") -> Dictionary:
	var id = actor if not actor.is_empty() else actor_id()
	if not data.profiles.has(id):
		data.profiles[id] = {
			"name": "Tripulante", "approach": "ingenio", "focus": 3,
			"skills": {"pilotaje": 1, "ciencia": 1, "ingenieria": 1, "negociacion": 1, "combate": 1},
			"traits": [], "level": 1, "xp": 0, "condition": 100, "milestones": []
		}
	return data.profiles[id]

func inventory(actor: String = "") -> Dictionary:
	var id = actor if not actor.is_empty() else actor_id()
	if not data.inventory.has(id):
		data.inventory[id] = {"hornidurak": 0, "aleazioak": 0, "datuak": 0, "sendagaiak": 0}
	return data.inventory[id]

func command(operation: String, args: Dictionary = {}) -> Dictionary:
	if args.size() > 12: return _result(false, "Demasiados parámetros.")
	var session = _session()
	if session != null and session.mode == "client":
		_receive_command.rpc_id(1, operation, args)
		return _result(true, "Orden enviada al anfitrión.")
	var response = _perform(operation, args, actor_id(), session.role if session != null else "mando")
	if response.ok:
		save()
		updated.emit()
		if session != null: session._refresh_view()
	notice.emit(response.message, response.ok)
	return response

@rpc("any_peer", "call_remote", "reliable", 3)
func _receive_command(operation: String, args: Dictionary) -> void:
	var session = _session()
	if session == null or session.mode != "host": return
	var peer_id = multiplayer.get_remote_sender_id()
	if not session.roster.has(peer_id): return
	var response = _perform(operation, args, str(peer_id), _role_for(peer_id))
	_response.rpc_id(peer_id, response.message, response.ok)
	if response.ok:
		save()
		updated.emit()
		session._refresh_view()

@rpc("authority", "call_remote", "reliable", 3)
func _response(text: String, ok: bool) -> void:
	notice.emit(text, ok)

@rpc("authority", "call_remote", "reliable", 3)
func _snapshot(incoming: Dictionary) -> void:
	var session = _session()
	if session == null or session.mode != "client": return
	if incoming.get("format", "") != FORMAT or int(incoming.get("version", 0)) != VERSION: return
	if JSON.stringify(incoming).length() > 196000: return
	data = incoming.duplicate(true)
	updated.emit()

func _view_for(actor: String) -> Dictionary:
	var safe = data.duplicate(true)
	var own = safe.inventory.get(actor, {})
	safe.inventory = {}
	if not own.is_empty(): safe.inventory[actor] = own
	return safe

func _perform(operation: String, args: Dictionary, actor: String, role: String) -> Dictionary:
	var session = _session()
	var sim = session.sim if session != null else null
	match operation:
		"profile_set":
			var name = str(args.get("name", "Tripulante")).strip_edges().left(32)
			var approach = str(args.get("approach", "ingenio"))
			if name.is_empty() or approach not in APPROACHES: return _result(false, "Ficha de tripulación inválida.")
			var skills = {}
			var total = 0
			for skill in SKILLS:
				var value = args.get(skill, 1)
				if not Catalog.finite_number(value) or int(value) != float(value) or int(value) < 0 or int(value) > 4: return _result(false, "Las habilidades van de 0 a 4.")
				skills[skill] = int(value)
				total += int(value)
			if total > 12: return _result(false, "La ficha admite un máximo de 12 puntos de habilidad.")
			var previous = profile(actor)
			previous.name = name
			previous.approach = approach
			previous.skills = skills
			if not previous.has("focus"): previous.focus = 3
			if not previous.has("traits"): previous.traits = []
			if not previous.has("level"): previous.level = 1
			if not previous.has("xp"): previous.xp = 0
			if not previous.has("condition"): previous.condition = 100
			if not previous.has("milestones"): previous.milestones = []
			return _result(true, "Ficha de tripulación actualizada sin perder progresión.")
		"focus_restore":
			if role != "mando": return _result(false, "Solo Mando puede ordenar descanso de la tripulación.")
			for id in data.profiles:
				data.profiles[id].focus = 3
			return _result(true, "La tripulación recupera sus puntos de concentración.")
		"marker_add":
			var x = args.get("x", 0.0); var y = args.get("y", 0.0)
			var label = str(args.get("label", "Marca")).strip_edges().left(48)
			if not Catalog.finite_number(x) or not Catalog.finite_number(y) or absf(float(x)) > 12000 or absf(float(y)) > 12000 or label.is_empty(): return _result(false, "Marcador fuera del atlas.")
			if data.atlas.markers.size() >= 128: return _result(false, "El atlas ya tiene 128 marcadores.")
			data.atlas.markers.append({"id": Crypto.new().generate_random_bytes(6).hex_encode(), "sector": _sector(), "label": label, "position": [float(x), float(y)], "author": actor})
			return _result(true, "Marcador añadido al atlas.")
		"marker_remove":
			var id = str(args.get("id", ""))
			for i in range(data.atlas.markers.size() - 1, -1, -1):
				if data.atlas.markers[i].id == id and (data.atlas.markers[i].author == actor or role == "mando"):
					data.atlas.markers.remove_at(i)
					return _result(true, "Marcador retirado.")
			return _result(false, "Marcador inexistente o de otro tripulante.")
		"trade_buy", "trade_sell":
			if session == null or sim == null or sim.state.is_empty() or sim.state.ship.docked.is_empty(): return _result(false, "El comercio solo está disponible atracado en una estación.")
			var item = str(args.get("item", "")); var amount = int(args.get("amount", 1))
			if item not in COMMODITIES or amount < 1 or amount > 20: return _result(false, "Mercancía o cantidad inválida.")
			var stock = inventory(actor); var price = int(COMMODITIES[item].buy if operation == "trade_buy" else COMMODITIES[item].sell) * amount
			if operation == "trade_buy":
				if sim.state.campaign.credits < price: return _result(false, "Créditos insuficientes.")
				sim.state.campaign.credits -= price; stock[item] += amount
			else:
				if int(stock[item]) < amount: return _result(false, "No llevas suficiente mercancía.")
				stock[item] -= amount; sim.state.campaign.credits += price
			data.factions.burdin.reputation = clampi(int(data.factions.burdin.reputation) + 1, -100, 100)
			data.factions.burdin.trades += 1
			return _result(true, ("Compra" if operation == "trade_buy" else "Venta") + " registrada: %d créditos." % price)
		"director_tempo":
			if role != "mando" or not Catalog.finite_number(args.get("value")) or float(args.value) < 0.25 or float(args.value) > 3.0: return _result(false, "Mando ajusta el tempo entre 0,25 y 3.")
			data.director.tempo = float(args.value)
			return _result(true, "Tempo de dirección ajustado a %.2f." % data.director.tempo)
		"director_auto":
			if role != "mando" or not args.get("enabled") is bool: return _result(false, "Solo Mando controla los encuentros automáticos.")
			data.director.auto_events = args.enabled
			return _result(true, "Encuentros automáticos " + ("activados." if args.enabled else "desactivados."))
		"director_spawn":
			if role != "mando" or session == null or sim == null or sim.state.is_empty(): return _result(false, "Solo Mando puede convocar un encuentro durante una misión.")
			var kind = str(args.get("kind", "hostile")); var name = str(args.get("name", "Contacto")).strip_edges().left(48)
			var dx = args.get("x", 700.0); var dy = args.get("y", 0.0)
			if kind not in DIRECTOR_KINDS or name.is_empty() or not Catalog.finite_number(dx) or not Catalog.finite_number(dy) or Vector2(float(dx), float(dy)).length() > 3500: return _result(false, "Encuentro fuera de límites.")
			var identifier = "dir_" + Crypto.new().generate_random_bytes(7).hex_encode()
			var p = sim.state.ship.position
			var contact = {"id": identifier, "name": name, "kind": kind, "position": [float(p[0]) + float(dx), float(p[1]) + float(dy)], "identified": false, "jammed": false, "known": false, "hull": 100.0, "hailed": false, "negotiated": false, "rescued": false, "salvaged": false, "probed": false, "pacified": false, "attack_at": sim.state.time + 4.0, "survivors": 4, "frequency": posmod(identifier.hash(), 21)}
			sim.state.contacts.append(contact)
			data.director.spawned += 1
			_append_chronicle("Dirección", "Encuentro convocado: %s (%s)." % [name, kind])
			return _result(true, "Encuentro añadido al sector sin cambiar de escena.")
		"director_supply":
			if role != "mando" or sim == null or sim.state.is_empty(): return _result(false, "Solo Mando puede autorizar suministros.")
			if sim.state.campaign.credits < 25: return _result(false, "La reposición de emergencia cuesta 25 créditos.")
			sim.state.campaign.credits -= 25
			sim.state.ship.parts = mini(40, int(sim.state.ship.parts) + 4)
			sim.state.ship.probes = mini(8, int(sim.state.ship.probes) + 1)
			return _result(true, "Reposición: +4 repuestos y +1 sonda.")
		_:
			return _result(false, "Orden avanzada desconocida.")

func _sector() -> String:
	var session = _session()
	if session == null or session.view.is_empty(): return "desconocido"
	return str(session.view.get("mission", {}).get("sector", "desconocido"))

func _process(delta: float) -> void:
	var session = _session()
	if session == null: return
	if _authority():
		_consume_session(session)
		_broadcast_clock += delta
		_save_clock += delta
		if data.director.auto_events and not session.sim.state.is_empty() and session.sim.state.status == "active":
			data.director.threat += delta * float(data.director.tempo)
			if data.director.threat >= 90.0:
				data.director.threat = 0.0
				_auto_encounter(session)
		if _broadcast_clock >= 0.5 and session.mode == "host":
			_broadcast_clock = 0.0
			for key in session.roster:
				var peer_id = int(key)
				if peer_id == 1 or peer_id not in multiplayer.get_peers(): continue
				_snapshot.rpc_id(peer_id, _view_for(str(peer_id)))
		if _save_clock >= 30.0:
			_save_clock = 0.0
			save()

func _consume_session(session: Node) -> void:
	if session.view.is_empty(): return
	var sector = _sector()
	if not data.atlas.sectors.has(sector): data.atlas.sectors[sector] = {"visits": 0, "contacts": {}, "first_seen": Time.get_unix_time_from_system()}
	var sector_data: Dictionary = data.atlas.sectors[sector]
	for c in session.view.get("contacts", []):
		if not c.get("identified", false): continue
		sector_data.contacts[c.id] = {"name": c.name, "kind": c.kind, "position": c.position.duplicate()}
		var entry: Dictionary = data.bestiary.get(c.kind, {"sightings": 0, "names": []})
		if c.name not in entry.names:
			entry.names.append(c.name)
			entry.sightings += 1
		data.bestiary[c.kind] = entry
	for event in session.view.get("events", []):
		var seq = int(event.get("seq", 0))
		if seq <= _last_seq: continue
		_last_seq = seq
		_append_chronicle(str(event.get("source", "Sistema")), str(event.get("text", "")))
		_apply_reputation(str(event.get("text", "")))

func _apply_reputation(text: String) -> void:
	var lowered = text.to_lower()
	if "rescat" in lowered:
		data.factions.haize.reputation = clampi(int(data.factions.haize.reputation) + 2, -100, 100)
		data.factions.haize.encounters += 1
	elif "destruid" in lowered or "derrot" in lowered:
		data.factions.itzal.reputation = clampi(int(data.factions.itzal.reputation) - 2, -100, 100)
		data.factions.itzal.encounters += 1
	elif "negocia" in lowered or "tregua" in lowered:
		data.factions.itsasargi.reputation = clampi(int(data.factions.itsasargi.reputation) + 2, -100, 100)

func _append_chronicle(source: String, text: String) -> void:
	if text.is_empty(): return
	data.chronicle.append({"time": Time.get_unix_time_from_system(), "sector": _sector(), "source": source.left(32), "text": text.left(300)})
	if data.chronicle.size() > 300: data.chronicle.pop_front()

func _auto_encounter(session: Node) -> void:
	var hostiles = session.sim.state.contacts.filter(func(c): return c.kind == "hostile" and c.hull > 0 and not c.pacified)
	if hostiles.size() >= 3: return
	var angle = float(posmod(int(session.sim.state.sequence) * 79, 360))
	var offset = Vector2.from_angle(deg_to_rad(angle)) * 1500.0
	_perform("director_spawn", {"kind": "hostile", "name": "Patrulla Itzal", "x": offset.x, "y": offset.y}, "1", "mando")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_F2: return
	if _window != null and is_instance_valid(_window):
		_window.queue_free()
		_window = null
	else:
		_window = ExpeditionConsole.new()
		_window.systems = self
		get_tree().root.add_child(_window)
		_window.close_requested.connect(func(): _window.queue_free(); _window = null)
		_window.popup_centered()
	get_viewport().set_input_as_handled()

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

func _exit_tree() -> void:
	save()
