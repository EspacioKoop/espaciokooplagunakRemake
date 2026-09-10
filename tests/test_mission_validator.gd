extends SceneTree
## Real Catalog/Simulation contract tests; no game-rule copy in the CLI.
var checks := 0
var failed := 0
var sim: Simulation

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		push_error("FAIL: " + label)

func repo(path: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../" + path).simplify_path()

func rejected(value: Variant, label: String) -> void:
	check(not Catalog.validate_mission(value).is_empty(), label)

func approach(id: String, distance: float) -> void:
	check(sim.command("navegacion", "autopilot", {"target": id}).ok, "autopilot " + id)
	for _i in range(15000):
		sim.tick(1.0 / 30.0)
		if sim.distance_to(sim.contact(id)) < distance:
			break
	check(sim.distance_to(sim.contact(id)) < distance, "arrival " + id)
	check(sim.command("navegacion", "helm", {"heading": sim.state.ship.heading, "throttle": 0.0}).ok, "stop " + id)
	for _i in range(90):
		sim.tick(1.0 / 30.0)

func run() -> void:
	var example = JSON.parse_string(FileAccess.get_file_as_string(repo("examples/missions/first-contact.json")))
	var schema = JSON.parse_string(FileAccess.get_file_as_string(repo("schemas/mission-v1.schema.json")))
	check(example is Dictionary and schema is Dictionary, "authored JSON documents load")
	if not example is Dictionary or not schema is Dictionary:
		quit(1)
		return
	check(Catalog.validate_mission(example).is_empty(), "example accepted by production Catalog")
	var before := JSON.stringify(example)
	Catalog.validate_mission(example)
	check(JSON.stringify(example) == before, "validation does not rewrite example")
	var missions := Catalog.missions()
	check(not missions.is_empty(), "bundled campaign is present")
	for mission in missions:
		check(Catalog.validate_mission(mission).is_empty(), "bundled mission " + str(mission.id))
	var contact_kinds: Array = schema["$defs"]["contact"]["properties"]["kind"]["enum"]
	check(contact_kinds == Catalog.CONTACT_KINDS, "schema contact enum follows production")
	for kind in contact_kinds:
		var value: Dictionary = example.duplicate(true)
		value.contacts = [{"id": "one", "name": "Objeto", "kind": kind, "position": [100, 0]}]
		value.objectives = [{"type": "navigate", "target": "one", "text": "Acércate."}]
		check(Catalog.validate_mission(value).is_empty(), "schema contact kind " + str(kind))
	var targets := {"dock": "station", "repair_target": "station", "rescue": "derelict",
		"salvage": "anomaly", "defeat": "hostile", "choice": "friendly", "touch": "supplydrop", "pickup": "supplydrop"}
	for action in schema["$defs"]["objective"]["properties"]["type"]["enum"]:
		var value: Dictionary = example.duplicate(true)
		value.contacts = [{"id": "one", "name": "Objeto", "kind": targets.get(action, "beacon"), "position": [100, 0]}]
		value.objectives = [{"type": action, "target": "one", "text": "Objetivo de contrato."}]
		check(Catalog.validate_mission(value).is_empty(), "schema objective " + str(action))
	for key in schema.required:
		var value: Dictionary = example.duplicate(true)
		value.erase(key)
		rejected(value, "required " + str(key))
	rejected([], "non-object mission")
	var bad: Dictionary = example.duplicate(true)
	bad.objectives[0].target = "missing"
	rejected(bad, "semantic missing target not decidable by schema")
	bad = example.duplicate(true)
	bad.objectives = [{"type": "dock", "target": "izar", "text": "Atraca."}]
	rejected(bad, "cannot dock at beacon")
	bad = example.duplicate(true)
	bad.contacts[1].id = "izar"
	rejected(bad, "duplicate contact ids")
	bad = example.duplicate(true)
	bad.contacts[0].position = [12001, 0]
	rejected(bad, "sector coordinate bounds")
	bad = example.duplicate(true)
	bad.contacts[0].known = "true"
	rejected(bad, "boolean contact flag")
	bad = example.duplicate(true)
	bad.contacts[0].frequency = 1.5
	rejected(bad, "integer frequency")
	bad = example.duplicate(true)
	bad.reward = -1
	rejected(bad, "negative reward")
	bad = example.duplicate(true)
	bad.ship_design = []
	rejected(bad, "invalid ship design delegated")
	bad = example.duplicate(true)
	bad.ship_loadout = []
	rejected(bad, "invalid loadout delegated")
	bad = example.duplicate(true)
	for index in range(46):
		bad.contacts.append({"id": "extra_" + str(index), "name": "Baliza", "kind": "beacon", "position": [0, 0]})
	check(Catalog.validate_mission(bad).is_empty(), "48 contacts accepted")
	bad.contacts.append({"id": "overflow", "name": "Baliza", "kind": "beacon", "position": [0, 0]})
	rejected(bad, "49 contacts rejected")
	bad = example.duplicate(true)
	bad.objectives = []
	rejected(bad, "at least one objective")
	for _index in range(24):
		bad.objectives.append(example.objectives[0].duplicate(true))
	check(Catalog.validate_mission(bad).is_empty(), "24 objectives accepted")
	bad.objectives.append(example.objectives[0].duplicate(true))
	rejected(bad, "25 objectives rejected")
	# Play the published example using actual ship orders, not fabricated facts.
	sim = Simulation.new()
	sim.start(example)
	check(sim.state.status == "active", "example starts standalone")
	approach("izar", 220)
	check(sim.command("sensores", "scan", {"target": "izar"}).ok, "example scan")
	for _index in range(210):
		sim.tick(1.0 / 30.0)
	approach("kaia", 145)
	check(sim.command("navegacion", "dock", {"target": "kaia"}).ok, "example docking")
	check(sim.state.status == "won", "example completed with real orders")
	print("MISSION_CONTRACT_TESTS ", checks, " checks; ", failed, " failures")
	quit(1 if failed else 0)
