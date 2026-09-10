class_name TableRounds
extends RefCounted
## Rules only. The table coordinator supplies authenticated identities and randomness.

static func create(kind: String, seats: Array, config: Dictionary, seed_value: int) -> Dictionary:
 var rng = RandomNumberGenerator.new()
 rng.seed = seed_value
 var state = {"kind": kind, "stage": "playing", "players": [], "turn": -1, "deck": [], "board": [], "dealer": [], "bid": {}, "result": "", "pots": [], "button": int(config.get("button", 0)), "bet": int(config.get("bet", 5)), "small": int(config.get("small", 1)), "big": int(config.get("big", 2)), "wild": bool(config.get("wild", true)), "street": 0, "current": 0, "minimum": 2, "showdown": false}
 for seat in seats:
  var player = seat.duplicate(true)
  player.merge({"cards": [], "shown": [], "round_bet": 0, "total_bet": 0, "folded": false, "acted": false, "done": false, "outcome": "", "gain": 0}, true)
  state.players.append(player)
 if kind == "dados":
  for player in state.players:
   for i in int(player.dice): player.cards.append(rng.randi_range(1, 6))
  state.turn = state.button % state.players.size()
  return state
 state.deck = TableCards.shuffled(rng)
 for player in state.players:
  player.cards = [state.deck.pop_back(), state.deck.pop_back()]
 if kind == "blackjack":
  state.dealer = [state.deck.pop_back(), state.deck.pop_back()]
  for player in state.players:
   player.total_bet = state.bet
   player.chips -= state.bet
   player.done = TableCards.natural(player.cards)
  if TableCards.natural(state.dealer): _blackjack_finish(state)
  else: _blackjack_next(state)
 else:
  state.minimum = state.big
  var small_index = state.button if state.players.size() == 2 else (state.button + 1) % state.players.size()
  var big_index = (small_index + 1) % state.players.size()
  _pay(state.players[small_index], state.small)
  _pay(state.players[big_index], state.big)
  state.current = state.big
  state.turn = big_index
  _poker_advance(state)
 return state

static func actions(state: Dictionary, actor: String) -> Array:
 if state.is_empty() or state.stage != "playing": return []
 var index = _index(state, actor)
 if index < 0: return []
 var player: Dictionary = state.players[index]
 var choices: Array = []
 if state.kind == "poker" and not player.folded and player.shown.size() < 2: choices.append("show")
 if state.turn != index: return choices
 match state.kind:
  "poker":
   choices.append("fold")
   choices.append("check" if player.round_bet == state.current else "call")
   if player.chips + player.round_bet > state.current: choices.append("raise")
   if player.chips > 0: choices.append("all_in")
  "blackjack":
   choices.append_array(["hit", "stand"])
   if player.cards.size() == 2 and player.chips >= player.total_bet: choices.append("double")
  "dados":
   choices.append("bid")
   if not state.bid.is_empty(): choices.append("doubt")
 return choices

static func apply(state: Dictionary, actor: String, action: String, args: Dictionary = {}) -> Dictionary:
 if action not in actions(state, actor): return {"ok": false, "message": "La acción no está disponible para tu turno."}
 if action == "all_in":
  var seat: Dictionary = state.players[_index(state, actor)]
  var maximum = seat.chips + seat.round_bet
  return apply(state, actor, "raise" if maximum > state.current else "call", {"amount":maximum})
 var next = state.duplicate(true)
 var player: Dictionary = next.players[_index(next, actor)]
 match action:
  "show":
   var index = args.get("card", -1)
   if not _integer(index, 0, 1) or int(index) in player.shown: return _invalid()
   player.shown.append(int(index))
  "fold", "check", "call", "raise":
   if action == "fold": player.folded = true
   elif action == "call": _pay(player, next.current - player.round_bet)
   elif action == "raise":
    var target = args.get("amount", -1)
    var maximum = int(player.chips + player.round_bet)
    if not _integer(target, next.current + 1, maximum): return _invalid()
    if target < next.current + next.minimum and target != maximum: return _invalid()
    var increment = int(target) - next.current
    _pay(player, int(target) - player.round_bet)
    next.minimum = maxi(next.minimum, increment)
    next.current = int(target)
    for other in next.players: other.acted = false
   player.acted = true
   _poker_advance(next)
  "hit", "stand", "double":
   if action == "double":
    player.chips -= player.total_bet
    player.total_bet *= 2
   if action != "stand": player.cards.append(next.deck.pop_back())
   player.done = action != "hit" or TableCards.blackjack(player.cards) >= 21
   if player.done: _blackjack_next(next)
  "bid":
   var amount = args.get("amount", 0)
   var face = args.get("face", 0)
   var total = 0
   for p in next.players: total += int(p.dice)
   if not _integer(amount, 1, total) or not _integer(face, 1, 6): return _invalid()
   if not next.bid.is_empty() and (amount < next.bid.amount or (amount == next.bid.amount and face <= next.bid.face)): return _invalid()
   next.bid = {"amount": int(amount), "face": int(face), "actor": actor}
   next.turn = (next.turn + 1) % next.players.size()
  "doubt":
   var actual = 0
   for p in next.players:
    for die in p.cards:
     if die == next.bid.face or (next.wild and next.bid.face != 1 and die == 1): actual += 1
   var loser = actor if actual >= next.bid.amount else str(next.bid.actor)
   next.players[_index(next, loser)].dice -= 1
   next.loser = loser
   next.result = "Había %d dados válidos. %s pierde un dado." % [actual, next.players[_index(next, loser)].name]
   next.stage = "done"
   next.turn = -1
 return {"ok": true, "round": next, "message": "Jugada aceptada."}

static func public_view(state: Dictionary, actor: String) -> Dictionary:
 if state.is_empty(): return {}
 var result = {}
 for key in ["kind", "stage", "turn", "board", "bid", "result", "pots", "button", "bet", "small", "big", "wild", "street", "current", "minimum", "showdown"]:
  result[key] = state[key].duplicate(true) if state[key] is Array or state[key] is Dictionary else state[key]
 result.players = []
 result.private = []
 result.dealer = state.dealer.duplicate() if state.stage == "done" else state.dealer.slice(0, 1)
 for player in state.players:
  var visible = {}
  for key in ["id", "name", "bot", "chips", "dice", "round_bet", "total_bet", "folded", "done", "outcome", "gain"]: visible[key] = player[key]
  visible.cards = []
  if state.kind == "blackjack" or (state.kind == "dados" and state.stage == "done") or (state.kind == "poker" and state.showdown and not player.folded): visible.cards = player.cards.duplicate()
  elif state.kind == "poker":
   for index in player.shown: visible.cards.append(player.cards[index])
  if player.id == actor: result.private = player.cards.duplicate()
  result.players.append(visible)
 result.actions = actions(state, actor)
 return result

static func bot_action(view: Dictionary) -> Dictionary:
 # The agent receives the same projection as its seat, never a deck or other secrets.
 var choices: Array = view.actions
 if view.kind == "blackjack":
  var total = TableCards.blackjack(view.private)
  if total == 11 and "double" in choices: return {"action": "double"}
  return {"action": "hit" if total < 17 else "stand"}
 if view.kind == "poker":
  return {"action": "check" if "check" in choices else "call"}
 var total = 0
 for p in view.players: total += int(p.dice)
 var next_bid = {"amount": 1, "face": 2}
 if not view.bid.is_empty():
  var known = 0
  for die in view.private:
   if die == view.bid.face or (view.wild and view.bid.face != 1 and die == 1): known += 1
  var probability = (2.0 if view.wild and view.bid.face != 1 else 1.0) / 6.0
  if view.bid.amount > known + (total - view.private.size()) * probability + 0.75: return {"action": "doubt"}
  next_bid = {"amount": view.bid.amount, "face": view.bid.face + 1}
  if next_bid.face > 6: next_bid.face = 1; next_bid.amount += 1
 if next_bid.amount > total: return {"action": "doubt"}
 next_bid.action = "bid"
 return next_bid

static func _integer(value: Variant, lower: int, upper: int) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= lower and value <= upper

static func _invalid() -> Dictionary: return {"ok": false, "message": "Importe, cara o carta fuera de los límites de la mesa."}

static func _index(state: Dictionary, actor: String) -> int:
 for i in state.players.size():
  if state.players[i].id == actor: return i
 return -1

static func _pay(player: Dictionary, amount: int) -> void:
 var paid = mini(maxi(amount, 0), player.chips)
 player.chips -= paid
 player.round_bet += paid
 player.total_bet += paid

static func _blackjack_next(state: Dictionary) -> void:
 for i in range(state.turn + 1, state.players.size()):
  if not state.players[i].done: state.turn = i; return
 _blackjack_finish(state)

static func _blackjack_finish(state: Dictionary) -> void:
 while TableCards.blackjack(state.dealer) < 17: state.dealer.append(state.deck.pop_back())
 var bank = TableCards.blackjack(state.dealer)
 var bank_natural = TableCards.natural(state.dealer)
 for player in state.players:
  var total = TableCards.blackjack(player.cards)
  var natural = TableCards.natural(player.cards)
  var payout = 0
  player.outcome = "Pierde"
  if total <= 21:
   if natural and not bank_natural: payout = player.total_bet + int(floor(player.total_bet * 1.5)); player.outcome = "Blackjack"
   elif (natural and bank_natural) or (not bank_natural and total == bank): payout = player.total_bet; player.outcome = "Empate"
   elif not bank_natural and (bank > 21 or total > bank): payout = player.total_bet * 2; player.outcome = "Gana"
  player.gain = payout - player.total_bet
  player.chips += payout
  player.done = true
 state.stage = "done"
 state.turn = -1
 state.result = "Banca: %d. Blackjack 3:2; la banca se planta en 17, incluido el blando." % bank

static func _poker_advance(state: Dictionary) -> void:
 var alive: Array = state.players.filter(func(p): return not p.folded)
 if alive.size() == 1:
  var pot = 0
  for p in state.players: pot += p.total_bet; p.total_bet = 0; p.round_bet = 0
  alive[0].chips += pot
  state.result = "%s gana %d fichas por retirada." % [alive[0].name, pot]
  state.stage = "done"
  state.turn = -1
  return
 var pending: Array = state.players.filter(func(p): return not p.folded and p.chips > 0 and (not p.acted or p.round_bet < state.current))
 var can_act = alive.filter(func(p): return p.chips > 0)
 if pending.is_empty() or can_act.is_empty():
  if state.street == 3 or can_act.size() <= 1:
   while state.board.size() < 5: state.board.append(state.deck.pop_back())
   _poker_finish(state)
   return
  state.street += 1
  for i in (3 if state.street == 1 else 1): state.board.append(state.deck.pop_back())
  state.current = 0
  state.minimum = state.big
  for p in state.players: p.round_bet = 0; p.acted = false
  state.turn = state.button
 for step in range(1, state.players.size() + 1):
  var index = (state.turn + step) % state.players.size()
  var player: Dictionary = state.players[index]
  if not player.folded and player.chips > 0 and (not player.acted or player.round_bet < state.current): state.turn = index; return

static func _poker_finish(state: Dictionary) -> void:
 var levels: Array = []
 var scores = {}
 for player in state.players:
  if player.total_bet > 0 and player.total_bet not in levels: levels.append(player.total_bet)
  if not player.folded: scores[player.id] = TableCards.score(player.cards + state.board)
 levels.sort()
 var previous = 0
 for level in levels:
  var contributors = state.players.filter(func(p): return p.total_bet >= level)
  var eligible = contributors.filter(func(p): return not p.folded)
  var amount = (int(level) - previous) * contributors.size()
  previous = level
  var winners: Array = []
  if eligible.is_empty():
   # Uncalled layers belong to their contributors, even after an absent seat folds.
   winners = contributors
  else:
   var best = 0
   for p in eligible: best = maxi(best, scores[p.id])
   winners = eligible.filter(func(p): return scores[p.id] == best)
  var share = amount / winners.size()
  var extra = amount % winners.size()
  # Odd chips follow seat order after the button.
  winners.sort_custom(func(a, b): return posmod(_index(state, a.id) - state.button - 1, state.players.size()) < posmod(_index(state, b.id) - state.button - 1, state.players.size()))
  for i in winners.size(): winners[i].chips += share + (1 if i < extra else 0)
  state.pots.append({"amount": amount, "winners": winners.map(func(p): return p.id)})
 for player in state.players:
  player.total_bet = 0
  player.round_bet = 0
  if not player.folded: player.outcome = TableCards.category(scores[player.id])
 state.stage = "done"
 state.showdown = true
 state.turn = -1
 state.result = "Reparto de botes completado. Se muestran las manos que seguían jugando."
