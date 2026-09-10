class_name ShipLounge
extends RefCounted
## Ephemeral table economy, independent of the ship campaign and Foundry.
var tables: Dictionary = {}
var epoch = Crypto.new().generate_random_bytes(12).hex_encode()
var _nonces: Dictionary = {}
var _bot_number = 0

func _init() -> void:
 for kind in ["poker", "blackjack", "dados"]:
  tables[kind] = {"kind": kind, "title": {"poker": "Póker · Texas Hold’em", "blackjack": "Blackjack", "dados": "Dados de faroleo"}[kind], "owner": "", "revision": 0, "seats": [], "watchers": [], "ledger": {}, "round": {}, "hands": 0, "button_id": "", "clock": 0.0, "config": {"initial": 100, "bet": 5, "small": 1, "big": 2, "wild": true}, "checkpoint": {}}

func command(actor: String, name: String, privileged: bool, operation: String, args: Dictionary) -> Dictionary:
 if actor.is_empty() or args.size() > 10: return _no("Petición inválida.")
 for key in args:
  if not (key is String or key is StringName) or not (args[key] is String or args[key] is StringName or args[key] is bool or Catalog.finite_number(args[key])): return _no("Parámetro inválido.")
  if (args[key] is String or args[key] is StringName) and str(args[key]).length() > 80: return _no("Parámetro demasiado largo.")
 var id = str(args.get("table", ""))
 if not tables.has(id): return _no("Mesa inexistente.")
 if args.get("epoch", "") != epoch: return _no("La sesión de la mesa ha cambiado.")
 var nonce = str(args.get("nonce", ""))
 if nonce.length() < 8 or nonce.length() > 64: return _no("Identificador de petición inválido.")
 var token = actor + ":" + nonce
 var signature = operation + JSON.stringify(args, "", true)
 if _nonces.has(token):
  return _nonces[token].response.duplicate() if _nonces[token].signature == signature else _no("Una petición anterior usa ya ese identificador.")
 var table: Dictionary = tables[id]
 var revision = args.get("revision", -1)
 var membership = operation in ["table_join", "table_watch", "table_leave"]
 # Joining or observing does not spend a betting turn. Concurrent arrivals can
 # merge after invariant checks; wagers and management still require exact revision.
 if not TableRounds._integer(revision, 0, table.revision) or (not membership and revision != table.revision): return _no("La mesa ha cambiado. Comprueba el turno e inténtalo de nuevo.")
 var response = _dispatch(table, actor, name.left(32), privileged, operation.trim_prefix("table_"), args)
 if response.ok:
  table.revision += 1
  _nonces[token] = {"signature": signature, "response": response.duplicate()}
  if _nonces.size() > 256: _nonces.erase(_nonces.keys()[0])
 return response

func _dispatch(table: Dictionary, actor: String, name: String, privileged: bool, action: String, args: Dictionary) -> Dictionary:
 var seat = _seat(table, actor)
 var owner = table.owner == actor or privileged
 var playing = not table.round.is_empty() and table.round.stage == "playing"
 match action:
  "join":
   if not seat.is_empty():
    if seat.away: seat.away = false; return _yes("Has vuelto a tu asiento.")
    return _no("Ya estás en esta mesa.")
   if playing or table.seats.size() >= 6: return _no("Espera al final de la mano o a que quede un asiento.")
   if table.owner.is_empty(): table.owner = actor
   _add_seat(table, actor, name, false)
   table.watchers.erase(actor)
   return _yes("Asiento reservado. Las fichas pertenecen solo a esta mesa.")
  "watch":
   if not seat.is_empty() or actor in table.watchers: return _no("Ya participas en esta mesa.")
   if table.watchers.size() >= 16: return _no("No quedan plazas de espectador.")
   table.watchers.append(actor)
   return _yes("Observas la mesa sin recibir información privada.")
  "leave":
   if actor in table.watchers: table.watchers.erase(actor); return _yes("Has dejado de observar.")
   if seat.is_empty(): return _no("No ocupas un asiento.")
   if playing: seat.away = true
   else: table.seats.erase(seat)
   return _yes("Asiento reservado durante esta mano; puedes volver." if playing else "Te has levantado de la mesa.")
  "bot":
   if not owner or playing or table.seats.size() >= 6: return _no("El responsable añade NPC entre manos, hasta seis asientos.")
   _bot_number += 1
   _add_seat(table, "npc_%d" % _bot_number, ["Lur", "Itsas", "Amai", "Unai", "Eki", "Nora"][_bot_number % 6], true)
   return _yes("NPC sentado. Decide con la información visible desde su asiento.")
  "remove_bot":
   if not owner or playing: return _no("Solo el responsable puede retirar NPC entre manos.")
   for i in range(table.seats.size() - 1, -1, -1):
    if table.seats[i].bot: table.seats.remove_at(i); return _yes("NPC retirado.")
   return _no("No hay NPC en la mesa.")
  "configure":
   if not owner or playing: return _no("El responsable configura la mesa entre manos.")
   var option = str(args.get("option", ""))
   var value = args.get("value")
   if option == "initial" and TableRounds._integer(value, 1, 10000) and table.hands == 0:
    table.config.initial = int(value)
    for balance in table.ledger.values(): balance.chips = int(value)
   elif option == "wild" and value is bool: table.config.wild = value
   elif option in ["bet", "small", "big"] and TableRounds._integer(value, 1, 10000):
    var config = table.config.duplicate()
    config[option] = int(value)
    if config.big < config.small: return _no("La ciega grande debe alcanzar la pequeña.")
    table.config = config
   else: return _no("Opción de mesa inválida.")
   return _yes("Regla actualizada para el siguiente reparto.")
  "start":
   if not owner or playing: return _no("El responsable reparte cuando termina la mano anterior.")
   var participants: Array = []
   for candidate in table.seats:
    var balance: Dictionary = table.ledger[candidate.id]
    if candidate.away or (balance.dice <= 0 if table.kind == "dados" else balance.chips < (table.config.bet if table.kind == "blackjack" else 1)): continue
    participants.append({"id": candidate.id, "name": candidate.name, "bot": candidate.bot, "chips": balance.chips, "dice": balance.dice})
   if participants.size() < (1 if table.kind == "blackjack" else 2): return _no("No hay suficientes jugadores con fichas o dados. Puedes añadir NPC.")
   var button = 0
   for i in participants.size():
    if participants[i].id == table.button_id: button = (i + 1) % participants.size()
   table.button_id = participants[button].id
   var config = table.config.duplicate()
   config.button = button
   table.checkpoint = table.ledger.duplicate(true)
   table.round = TableRounds.create(table.kind, participants, config, Crypto.new().generate_random_bytes(8).decode_s64(0))
   table.hands += 1
   table.clock = 0.0
   _settle(table)
   return _yes("Reparto iniciado.")
  "cancel":
   if not owner: return _no("Solo el responsable o Mando puede cancelar la mano.")
   if playing: table.ledger = table.checkpoint.duplicate(true)
   table.round = {}
   table.clock = 0.0
   return _yes("Mano cancelada. Se conservan las fichas anteriores al reparto.")
  _:
   if seat.is_empty() or seat.away: return _no("Vuelve a tu asiento antes de jugar.")
   var response = TableRounds.apply(table.round, actor, action, args)
   if not response.ok: return response
   var old_turn = table.round.turn
   table.round = response.round
   if old_turn != table.round.turn or action != "show": table.clock = 0.0
   _settle(table)
   return _yes(response.message)

func snapshot(actor: String, privileged: bool = false) -> Dictionary:
 var view = {"epoch": epoch, "identity": actor, "tables": {}}
 for id in tables:
  var table: Dictionary = tables[id]
  var data = {"title": table.title, "kind": table.kind, "revision": table.revision, "hands": table.hands, "owner": table.owner, "config": table.config.duplicate(), "seats": [], "watchers": table.watchers.size(), "remaining": maxi(0, 30 - int(table.clock)), "can_manage": table.owner == actor or privileged, "round": TableRounds.public_view(table.round, actor)}
  for seat in table.seats:
   var shown = seat.duplicate()
   shown.merge(table.ledger[seat.id], true)
   data.seats.append(shown)
  view.tables[id] = data
 return view

func presence(actor: String, available: bool) -> void:
 for table in tables.values():
  var seat = _seat(table, actor)
  if not seat.is_empty() and seat.away == available:
   seat.away = not available
   table.revision += 1

func cancel_all() -> void:
 for table in tables.values():
  if not table.round.is_empty() and table.round.stage == "playing": table.ledger = table.checkpoint.duplicate(true)
  table.round = {}
  table.revision += 1
 epoch = Crypto.new().generate_random_bytes(12).hex_encode()
 _nonces.clear()

func tick(delta: float) -> void:
 for table in tables.values():
  if table.round.is_empty() or table.round.stage != "playing" or table.round.turn < 0: continue
  var player: Dictionary = table.round.players[table.round.turn]
  var seat = _seat(table, player.id)
  table.clock += delta
  var absent = seat.is_empty() or seat.away
  if table.clock < (1.1 if player.bot else (3.0 if absent else 30.0)): continue
  var projection = TableRounds.public_view(table.round, player.id)
  var move = TableRounds.bot_action(projection)
  if not player.bot:
   if table.kind == "poker": move = {"action": "check" if "check" in projection.actions else "fold"}
   elif table.kind == "blackjack": move = {"action": "stand"}
   elif "doubt" in projection.actions: move = {"action": "doubt"}
  var response = TableRounds.apply(table.round, player.id, move.action, move)
  table.clock = 0.0
  if response.ok:
   table.round = response.round
   table.revision += 1
   _settle(table)

func _settle(table: Dictionary) -> void:
 if table.round.is_empty() or table.round.stage != "done": return
 for player in table.round.players: table.ledger[player.id] = {"chips": player.chips, "dice": player.dice}

func _add_seat(table: Dictionary, actor: String, name: String, bot: bool) -> void:
 if not table.ledger.has(actor): table.ledger[actor] = {"chips": table.config.initial, "dice": 5}
 table.seats.append({"id": actor, "name": name, "bot": bot, "away": false})

func _seat(table: Dictionary, actor: String) -> Dictionary:
 for seat in table.seats:
  if seat.id == actor: return seat
 return {}

func _yes(message: String) -> Dictionary: return {"ok": true, "message": message}
func _no(message: String) -> Dictionary: return {"ok": false, "message": message}
