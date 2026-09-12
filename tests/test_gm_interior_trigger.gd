extends SceneTree
## Production-chain regression: main shell -> WorldDeck -> zone trigger -> GM event.

var checks := 0
var failures := 0
var app: Control
var session: Node
const GM_INTERIOR_TRIGGER = preload("res://world/gm_interior_trigger.gd")

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("GM_INTERIOR_TRIGGER_FAIL " + label)

func frames(count: int = 3) -> void:
	for _i in count: await process_frame

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1600, 900)
	session = root.get_node("Session")
	session.suppress_saves = true
	for child in root.get_children():
		child.set_process(false)
		child.set_physics_process(false)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(5)
	app._new_game()
	session.paused = true
	app._go("deck")
	await frames(12)
	var deck = app._deck
	check(deck != null and deck._gm_interior_trigger != null, "shell creates the production trigger")
	if deck == null or deck._gm_interior_trigger == null:
		_finish()
		return
	var before_events: int = session.sim.state.events.size()
	deck.teleport_zone(7)
	await frames(3)
	check(session.sim.state.events.size() == before_events + 1, "entering Cantina emits one public GM event")
	if session.sim.state.events.size() > before_events:
		var event: Dictionary = session.sim.state.events.back()
		check(event.source == "Dirección", "trigger event keeps the public GM source")
		check(event.text == GM_INTERIOR_TRIGGER.PUBLIC_MESSAGE, "trigger event uses the bounded public message")
		check(session.view.events.back().text == GM_INTERIOR_TRIGGER.PUBLIC_MESSAGE, "event reaches the session snapshot")
		check(app._footer.text == GM_INTERIOR_TRIGGER.PUBLIC_MESSAGE, "event is visible in the main shell footer")
	var duplicate: Dictionary = deck._gm_interior_trigger.enter_zone("Cantina")
	check(duplicate.ok and duplicate.duplicate and not duplicate.triggered, "re-entering the same run is idempotent")
	check(session.sim.state.events.size() == before_events + 1, "duplicate entry does not append another event")
	var ignored: Dictionary = deck._gm_interior_trigger.enter_zone("Museo")
	check(ignored.ok and not ignored.triggered, "unbound interior zones are ignored")
	check(session.sim.state.events.size() == before_events + 1, "unbound zone does not mutate the mission")
	var before_client = var_to_bytes(session.sim.state)
	session.mode = "client"
	var denied: Dictionary = deck._gm_interior_trigger.enter_zone("Cantina")
	check(not denied.ok and not denied.triggered, "clients cannot execute the interior trigger")
	check(var_to_bytes(session.sim.state) == before_client, "client rejection leaves authoritative state unchanged")
	session.mode = "offline"
	_finish()

func _finish() -> void:
	print("GM_INTERIOR_TRIGGER_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
