extends SceneTree
## Synthetic states: no player saves, keys or external services.
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("GM_LIVE_FAIL " + label)

func fresh() -> Simulation:
	var sim = Simulation.new()
	sim.start(Catalog.missions()[0])
	return sim

func contact_args() -> Dictionary:
	return {"id": "gm_contact", "name": "Synthetic contact", "kind": "hostile", "x": 1000.0, "y": 200.0, "identified": true}

func run() -> void:
	var sim = fresh()
	check(LocalStorage.validate_state(sim.state).is_empty(), "baseline save is valid")
	check(GMLiveActions.spawn_contact(sim, contact_args()).ok, "spawn succeeds")
	check(LocalStorage.validate_state(sim.state).is_empty(), "spawn preserves save validity")
	var before = var_to_bytes(sim.state)
	check(not GMLiveActions.modify_contact(sim, "gm_contact", {"name": "MUST_NOT_COMMIT", "x": INF}).ok, "invalid position is rejected")
	check(var_to_bytes(sim.state) == before, "failed multi-field modification is atomic")
	for field in ["hull", "frequency", "survivors", "identified"]:
		for invalid in [null, "7", [], {}, INF]:
			var candidate = contact_args()
			candidate[field] = invalid
			var other = fresh()
			var original = var_to_bytes(other.state)
			check(not GMLiveActions.spawn_contact(other, candidate).ok, "invalid spawn type rejected: " + field)
			check(var_to_bytes(other.state) == original, "failed spawn does not mutate: " + field)
	for field in ["x", "y"]:
		var candidate = contact_args()
		candidate[field] = 14001
		var other = fresh()
		check(not GMLiveActions.spawn_contact(other, candidate).ok, "coordinates obey persistence limits")
	for count in [0, -1, 1.5, "3", true, 13]:
		var other = fresh()
		var original = var_to_bytes(other.state)
		check(not GMLiveActions.trigger_event(other, "reinforcements", {"count": count}).ok, "invalid reinforcement count rejected")
		check(var_to_bytes(other.state) == original, "invalid reinforcement batch is atomic")
	var other = fresh()
	check(GMLiveActions.trigger_event(other, "alert", {"level": "ambar"}).ok, "canonical amber alert accepted")
	check(other.state.ship.alert == "ambar", "canonical alert stored")
	var hidden = fresh()
	var secret = contact_args()
	secret.name = "SYNTHETIC_HIDDEN_CONTACT"
	secret.identified = false
	check(GMLiveActions.spawn_contact(hidden, secret).ok, "hidden contact can be authored")
	check(not JSON.stringify(hidden.snapshot("navegacion", "test")).contains(secret.name), "public event log does not reveal hidden contact")
	print("GM_LIVE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
