extends SceneTree
var checks = 0
var failures = 0
var serial = 0
var lounge

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
 checks += 1
 if not value: failures += 1; push_error("TABLE_FAIL " + message)
func card(rank_value: int, suit: int = 0) -> int: return suit * 13 + rank_value - 2
func player(id: String, chips: int = 100, dice: int = 5) -> Dictionary: return {"id": id, "name": id, "chips": chips, "dice": dice, "bot": false}
func request(actor: String, kind: String, action: String, parameters: Dictionary = {}) -> Dictionary:
 serial += 1
 var args = parameters.duplicate()
 args.merge({"table": kind, "epoch": lounge.epoch, "revision": lounge.tables[kind].revision, "nonce": "test_nonce_%d" % serial}, true)
 return lounge.command(actor, actor, actor == "host", "table_" + action, args)
func total_chips(state: Dictionary) -> int:
 var total = 0
 for p in state.players: total += int(p.chips + p.total_bet)
 return total

func run() -> void:
 check(TableCards.blackjack([card(14), card(14), card(9)]) == 21, "soft aces become one independently")
 check(TableCards.blackjack([card(14), card(6)]) == 17, "soft seventeen")
 check(TableCards.natural([card(14), card(13)]), "natural blackjack")
 check(not TableCards.natural([card(7), card(7), card(7)]), "three-card 21 is not a natural")
 var hands = [
  [card(14), card(11,1), card(9,2), card(5,3), card(2)],
  [card(14), card(14,1), card(9,2), card(5,3), card(2)],
  [card(14), card(14,1), card(9,2), card(9,3), card(2)],
  [card(14), card(14,1), card(14,2), card(9,3), card(2)],
  [card(14), card(2,1), card(3,2), card(4,3), card(5)],
  [card(14), card(11), card(9), card(5), card(2)],
  [card(14), card(14,1), card(14,2), card(9,3), card(9)],
  [card(14), card(14,1), card(14,2), card(14,3), card(2)],
  [card(10), card(11), card(12), card(13), card(14)]]
 var previous = -1
 for i in hands.size():
  var score = TableCards.score(hands[i])
  check(score > previous and TableCards.category(score) == TableCards.CATEGORIES[i], "poker category %d and ordering" % i)
  previous = score
 check(TableCards.score(hands[8] + [card(2,1), card(3,2)]) == previous, "best five selected from seven")
 check(TableCards.score([card(2),card(3),card(4),card(5),card(6)]) > TableCards.score([card(14),card(2),card(3),card(4),card(5)]), "ace-low straight remains below six-high")
 for kind in ["poker", "blackjack", "dados"]:
  for seed_value in range(1, 25):
   var participants = [player("a", 11), player("b", 37), player("c", 100)]
   var state = TableRounds.create(kind, participants, {}, seed_value)
   check(state == TableRounds.create(kind, participants, {}, seed_value), "reproducible deal %s %d" % [kind, seed_value])
   var initial = JSON.stringify(state)
   check(not TableRounds.apply(state, "outsider", "fold").ok and initial == JSON.stringify(state), "spectator action rejected without mutation")
   var public_view = TableRounds.public_view(state, "")
   check(not public_view.has("deck") and public_view.private.is_empty(), "spectator has no deck or private hand")
   if kind != "blackjack" and state.stage == "playing":
    check(public_view.players.all(func(p): return p.cards.is_empty()), "live hands and cups remain private")
    check(TableRounds.public_view(state, "a").private == state.players[0].cards, "seat gets exactly its own hand")
   var steps = 0
   while state.stage == "playing" and steps < 100:
    var actor = state.players[state.turn].id
    var view = TableRounds.public_view(state, actor)
    var move = TableRounds.bot_action(view)
    if kind == "poker" and steps == 0 and "raise" in view.actions:
     move = {"action": "raise", "amount": state.players[state.turn].chips + state.players[state.turn].round_bet}
    var response = TableRounds.apply(state, actor, move.action, move)
    if not response.ok: break
    state = response.round
    if kind == "poker" and total_chips(state) != 148: break
    steps += 1
   check(state.stage == "done", "%s completes through real actions (seed %d)" % [kind, seed_value])
   if kind == "poker": check(total_chips(state) == 148, "all-in side pots conserve every chip")
   if kind == "dados":
    check(state.players.reduce(func(sum, p): return sum + p.dice, 0) == 14, "one lost die per challenge")
    check(TableRounds.public_view(state, "").players.all(func(p): return not p.cards.is_empty()), "dice revealed after challenge")
 var game = TableRounds.create("poker", [player("a"),player("b")], {}, 100)
 check(game.turn == 0 and game.players[0].round_bet == 1 and game.players[1].round_bet == 2, "heads-up dealer posts small blind and acts first")
 var shown = TableRounds.apply(game, "b", "show", {"card": 0})
 check(shown.ok and shown.round.turn == game.turn and TableRounds.public_view(shown.round, "").players[1].cards.size() == 1, "voluntary card reveal does not consume another player's turn")
 check(not TableRounds.apply(shown.round, "b", "show", {"card": 0}).ok, "already revealed card rejected")
 check(not TableRounds.apply(game, "a", "raise", {"amount": 3}).ok, "raise below minimum rejected unless all-in")
 check(TableRounds.apply(game, "a", "all_in").round.players[0].chips == 0, "all-in action commits the remaining stack")
 check(TableRounds.apply(game, "a", "fold").round.players[1].chips == 101, "uncontested pot is paid once")
 var all_in = TableRounds.create("poker", [player("a",1),player("b",1)], {}, 40)
 check(all_in.stage == "done" and total_chips(all_in) == 2, "blinds can resolve an immediate all-in")
 # Rigged test fixtures check payouts and side-pot eligibility independently of the shuffle.
 game = TableRounds.create("blackjack", [player("a")], {}, 7)
 game.players[0].cards = [card(14),card(13)]
 game.dealer = [card(10),card(7)]
 TableRounds._blackjack_finish(game)
 check(game.players[0].chips == 107, "natural pays floor of 3:2 on a five-chip stake")
 game = TableRounds.create("blackjack", [player("a")], {}, 7)
 game.players[0].cards = [card(9),card(7)]
 game.dealer = [card(14),card(6)]
 var deck_size = game.deck.size()
 TableRounds._blackjack_finish(game)
 check(game.deck.size() == deck_size, "dealer stands on soft 17")
 game = TableRounds.create("poker", [player("a",10),player("b",30),player("c",100)], {}, 11)
 game.board = [card(2),card(4,1),card(6,2),card(8,3),card(10)]
 for i in 3:
  game.players[i].chips = 0
  game.players[i].total_bet = [10,30,100][i]
  game.players[i].cards = [card(14-i,1),card(14-i,2)]
 TableRounds._poker_finish(game)
 check(game.players.map(func(p): return p.chips) == [30,40,70], "short stack wins main pot, next stack side pot, uncalled excess returned")
 game = TableRounds.create("dados", [player("a"),player("b")], {}, 4)
 game.players[0].cards = [1,1,3,4,5]
 game.players[1].cards = [2,2,3,4,5]
 game.turn = 0
 var bid = TableRounds.apply(game,"a","bid",{"amount":4,"face":2})
 var doubt = TableRounds.apply(bid.round,"b","doubt")
 check(doubt.ok and doubt.round.loser == "b", "ones wild count once toward a valid claim")
 game.wild = false
 bid = TableRounds.apply(game,"a","bid",{"amount":4,"face":2})
 doubt = TableRounds.apply(bid.round,"b","doubt")
 check(doubt.round.loser == "a", "wild rule disabled changes actual outcome")
 check(not TableRounds.apply(game,"a","bid",{"amount":11,"face":2}).ok, "impossible count rejected")
 lounge = ShipLounge.new()
 check(request("a","poker","join").ok and request("b","poker","join").ok, "two seats join")
 var arrival = {"table":"poker", "epoch":lounge.epoch, "revision":0, "nonce":"concurrent_arrival_1"}
 check(lounge.command("passerby","passerby",false,"table_watch",arrival).ok, "concurrent spectator arrivals merge without consuming a turn")
 check(not request("b","poker","bot").ok, "non-owner cannot add a bot")
 check(request("observer","poker","watch").ok, "spectator joins without a hand")
 check(request("a","poker","bot").ok, "owner adds an NPC")
 check(request("a","poker","configure",{"option":"initial","value":140}).ok and lounge.tables.poker.ledger.b.chips == 140, "initial stack configured before first hand")
 check(request("a","poker","configure",{"option":"initial","value":100}).ok, "initial table amount restored explicitly")
 check(request("a","poker","start").ok, "owner starts a full round")
 check(not request("a","poker","configure",{"option":"initial","value":900}).ok, "configuration cannot refill an active table")
 check(not request("late","poker","join").ok, "seat cannot be inserted mid-hand")
 var view = lounge.snapshot("observer")
 check(view.tables.poker.round.private.is_empty(), "lounge projects spectator without secrets")
 check(not request("observer","poker","fold").ok, "spectator cannot play")
 check(request("a","poker","leave").ok and lounge._seat(lounge.tables.poker,"a").away, "leave reserves identity mid-hand")
 check(request("a","poker","join").ok and not lounge._seat(lounge.tables.poker,"a").away, "return restores reserved seat")
 lounge.presence("a",false)
 check(lounge._seat(lounge.tables.poker,"a").away, "disconnect marks seat absent")
 lounge.presence("a",true)
 check(not lounge._seat(lounge.tables.poker,"a").away, "authenticated reconnect restores presence")
 check(request("a","poker","cancel").ok and lounge.tables.poker.ledger.a.chips == 100, "cancel refunds checkpoint and deletes live round")
 check(not request("a","poker","configure",{"option":"initial","value":900}).ok, "initial stacks cannot change after a cancelled hand")
 var table = lounge.tables.poker
 var args = {"table":"poker","epoch":lounge.epoch,"revision":table.revision,"nonce":"repeat_nonce_123"}
 var first = lounge.command("a","a",false,"table_start",args)
 var revision = table.revision
 check(first.ok and lounge.command("a","a",false,"table_start",args).ok and table.revision == revision, "duplicate request is idempotent")
 check(not lounge.command("a","a",false,"table_cancel",args).ok, "same nonce cannot carry another command")
 args.nonce = "stale_revision_123"
 check(not lounge.command("a","a",false,"table_cancel",args).ok, "stale revision rejected")
 request("a","poker","cancel")
 table.ledger.a.chips = 0
 request("a","poker","leave")
 request("a","poker","join")
 check(table.ledger.a.chips == 0, "leaving and returning never refills chips")
 request("a","poker","start")
 check(table.round.players.all(func(p): return p.id != "a"), "busted player remains seated but sits out")
 lounge.cancel_all()
 check(table.round.is_empty(), "coordinator cancellation clears secret cards")
 for kind in ["blackjack","dados"]:
  request("host",kind,"join")
  request("host",kind,"bot")
  request("host",kind,"start")
 for step in 220: lounge.tick(1.0)
 check(lounge.tables.blackjack.round.stage == "done" and lounge.tables.dados.round.stage == "done", "NPC and absent/idle turns resolve without freezing the room")
 await test_ui()
 print("TABLE_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)

func test_ui() -> void:
 var session = root.get_node("Session")
 session.new_campaign()
 var app = load("res://ui/app.gd").new()
 root.add_child(app)
 await process_frame
 app._go("deck")
 await process_frame
 var window = app._open_leisure_interaction({"kind":"table","table":"blackjack"})
 await process_frame
 check(is_instance_valid(window) and window.title == "Mesas de la cantina", "native game window opens from deck")
 var joined = window.send("join")
 check(joined.ok, "native join parameters pass the actual command boundary")
 await process_frame
 check(session.view.lounge.tables.blackjack.seats.size() == 1, "native join button reserves an authoritative seat")
 window.send("start")
 await process_frame
 check(not session.view.lounge.tables.blackjack.round.is_empty(), "native deal starts an actual blackjack round")
 window.queue_free()
 app.queue_free()
 await process_frame
