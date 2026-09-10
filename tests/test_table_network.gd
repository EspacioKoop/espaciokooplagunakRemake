extends SceneTree
var session
var failures = 0
var checks = 0
var joined = false
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
 checks += 1
 if not value: failures += 1; push_error("TABLE_NET_FAIL " + label)
func delay(seconds: float) -> void: await create_timer(seconds).timeout
func table() -> Dictionary: return session.view.get("lounge", {}).get("tables", {}).get("poker", {})
func wait_for(condition: Callable, seconds: float = 5.0) -> bool:
 for i in int(seconds * 10):
  if condition.call(): return true
  await delay(0.1)
 return bool(condition.call())

func run() -> void:
 session = root.get_node("Session")
 var args = OS.get_cmdline_user_args()
 var mode = args[args.find("--case") + 1]
 var port = int(args[args.find("--port") + 1])
 session.joined.connect(func(): joined = true)
 if mode == "host":
  check(session.host_session(port, "table-network-test-key").ok, "host starts")
  check(session.order("table_join", {"table":"poker"}).ok, "host joins")
  print("TABLE_NETWORK_READY")
  check(await wait_for(func(): return table().get("seats", []).size() == 2 and table().get("watchers", 0) == 1), "player and spectator join through RPC")
  check(session.order("table_start", {"table":"poker"}).ok, "host deals to two humans")
  check(table().round.private.size() == 2, "host gets host's own cards")
  check(table().round.players[1].cards.is_empty(), "host UI does not receive the client's private cards")
  var remembered = str(table().seats[1].id)
  check(await wait_for(func():
   for seat in table().get("seats", []):
    if seat.id == remembered and seat.away: return true
   return false), "disconnect marks reserved seat away")
  check(await wait_for(func():
   for seat in table().get("seats", []):
    if seat.id == remembered and not seat.away: return true
   return false), "reconnect restores same reserved identity")
  check(table().seats.size() == 2, "reconnect never creates a duplicate seat")
  check(not session._telemetry_view().has("lounge"), "HTTP projection excludes private table data")
  await delay(3.0)
 else:
  var role = "navegacion" if mode == "player" else "ingenieria"
  check(session.join_session("127.0.0.1",port,"table-network-test-key",mode,role).ok, "client starts")
  check(await wait_for(func(): return joined and not table().is_empty()), "authenticated table snapshot arrives")
  session.order("table_join" if mode == "player" else "table_watch", {"table":"poker"})
  check(await wait_for(func(): return not table().get("round", {}).is_empty()), "dealt snapshot arrives")
  var round_state: Dictionary = table().get("round", {})
  if mode == "player":
   check(round_state.get("private", []).size() == 2, "player receives exactly two private cards")
   check(round_state.players[0].cards.is_empty(), "player cannot read host's cards")
   var identity = str(session.view.lounge.identity)
   var hand = round_state.private.duplicate()
   var ticket = session._resume_lounge_ticket
   check(ticket.length() == 48, "server issues a private reconnect capability")
   session.close_session()
   joined = false
   await delay(0.6)
   check(session.join_session("127.0.0.1",port,"table-network-test-key",mode,role).ok, "same player reconnects")
   check(await wait_for(func(): return joined and not table().get("round", {}).is_empty()), "reconnected snapshot arrives")
   check(session.view.lounge.identity == identity and session._resume_lounge_ticket == ticket, "reconnect capability restores identity")
   check(table().round.private == hand and table().seats.size() == 2, "private cards and seat survive reconnect without redeal")
   session.select_role("sensores")
   check(await wait_for(func(): return session.role == "sensores"), "changing station retains authenticated table identity")
   check(session.view.lounge.identity == identity, "table identity is independent of station")
  else:
   check(round_state.get("private", []).is_empty(), "spectator receives no private hand")
   check(round_state.players.all(func(p): return p.cards.is_empty()), "spectator sees no hole cards")
   check(not JSON.stringify(session.view.lounge).contains("ticket"), "reconnect capabilities never appear in public snapshots")
   var revision = table().revision
   session.order("table_fold", {"table":"poker"})
   await delay(0.3)
   check(table().round.stage == "playing" and table().round.players.all(func(p): return not p.folded), "spectator RPC cannot fold someone else's cards")
  await delay(1.3)
 session.close_session()
 print("TABLE_NETWORK_RESULT ", mode, " checks=", checks, " failures=", failures)
 quit(1 if failures else 0)
