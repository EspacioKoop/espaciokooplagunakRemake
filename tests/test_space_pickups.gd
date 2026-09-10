extends SceneTree
var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("PICKUP_FAIL " + label)

static func mission() -> Dictionary:
	return {"id": "pickup_test", "title": "Recogibles", "sector": "Prueba", "briefing": "Recuperar suministros y tocar el artefacto.", "reward": 25,
		"contacts": [{"id": "box", "name": "Suministro", "kind": "supplydrop", "position": [350, 0], "radius": 30, "known": true, "supply_energy": 25, "supply_ammo": {"homing": 8}},
		{"id": "relic", "name": "Artefacto", "kind": "artifact", "position": [650, 0], "radius": 30, "allow_pickup": false}],
		"objectives": [{"type": "pickup", "target": "box", "text": "Recoge el suministro."}, {"type": "touch", "target": "relic", "text": "Toca el artefacto."}]}

func fresh(document: Dictionary = {}) -> Simulation:
	var sim = Simulation.new()
	sim.start(mission() if document.is_empty() else document)
	sim.state.ship.energy = 10.0
	sim.state.operations.ammo.homing = 0
	sim.state.ship.torpedoes = 0
	return sim

func run() -> void:
	var sim = fresh()
	check(LocalStorage.validate_state(sim.state).is_empty(), "uncollected save remains valid")
	SpacePhysics.move(sim, 0.1, Vector2(500, 0))
	check(sim.contact("box").hull == 0 and sim.state.facts.has("pickup:box"), "swept crossing consumes supply")
	check(sim.state.ship.energy == 35 and sim.state.operations.ammo.homing == 8, "actual energy and ammunition restored")
	check(sim.state.ship.torpedoes == 8, "legacy ammunition display synchronized")
	check(sim.contact("relic").hull > 0 and not sim.state.facts.has("touch:relic"), "distant artifact untouched")
	SpacePhysics.move(sim, 0.1, Vector2(-500, 0))
	check(sim.state.ship.energy == 35 and sim.state.operations.ammo.homing == 8, "crossing consumed supply again grants nothing")
	check(not sim.command("enlace", "pickup", {"target": "relic"}).ok, "client-style pickup command cannot bypass collision")
	var path = "user://pickups-" + str(OS.get_process_id()) + ".json"
	check(LocalStorage.save_state(sim.state, path).is_empty(), "consumed contact saved")
	var loaded = LocalStorage.read_state(path)
	check(loaded.has("state"), "consumed contact restored")
	if loaded.has("state"):
		sim.state = loaded.state
		SpacePhysics.move(sim, 0.1, Vector2(500, 0))
		check(sim.state.ship.energy == 35 and sim.state.operations.ammo.homing == 8, "resume does not award consumed payload")
		SpacePhysics.move(sim, 0.1, Vector2(200, 0))
		check(sim.state.facts.has("touch:relic") and sim.contact("relic").hull > 0, "noncollectible artifact records collision and remains")
		sim.advance_objectives()
		check(sim.state.status == "won" and sim.state.campaign.credits == 25, "collision facts advance existing mission and reward")
		sim.advance_objectives()
		check(sim.state.campaign.credits == 25, "mission reward is not duplicated")
	var damaged = sim.state.duplicate(true)
	damaged.contacts[0].hull = 100
	check(not LocalStorage.validate_state(damaged).is_empty(), "revived consumed pickup rejected by save validation")
	damaged = sim.state.duplicate(true)
	damaged.contacts[0].supply_energy = 100
	check(not LocalStorage.validate_state(damaged).is_empty(), "altered saved payload rejected")
	sim = fresh()
	sim.state.ship.energy = 95
	sim.state.operations.ammo.homing = 7
	sim.state.operations.tubes[0].ammo = "homing"
	SpacePhysics.move(sim, 0.1, Vector2(350, 0))
	check(sim.state.ship.energy == 100 and sim.state.operations.ammo.homing == 7, "caps include ammunition already in tubes")
	var doc = mission()
	doc.contacts[1].allow_pickup = true
	doc.objectives[1].type = "pickup"
	sim = fresh(doc)
	SpacePhysics.move(sim, 0.1, Vector2(800, 0))
	check(sim.contact("relic").hull == 0 and sim.state.facts.has("pickup:relic"), "collectible artifact is removed on contact")
	check(not sim.snapshot("navegacion").contacts[0].has("supply_ammo"), "authored payload stays out of public snapshot")
	doc = mission()
	doc.contacts.append({"id": "wall", "name": "Roca", "kind": "asteroid", "position": [180, 0], "radius": 40})
	sim = fresh(doc)
	SpacePhysics.move(sim, 0.1, Vector2(800, 0))
	check(not sim.state.facts.has("pickup:box"), "blocking collision prevents collecting through obstacle")
	doc = mission()
	doc.contacts.append({"id": "gate", "name": "Portal", "kind": "wormhole", "position": [180, 0], "radius": 40, "destination": [650, 0]})
	sim = fresh(doc)
	SpacePhysics.move(sim, 0.1, Vector2(800, 0))
	check(not sim.state.facts.has("pickup:box") and sim.state.facts.has("touch:relic"), "portal checks arrival only, not teleport line")
	for invalid in [-1, 101, "25", true, INF]:
		doc = mission(); doc.contacts[0].supply_energy = invalid
		check(not Catalog.validate_mission(doc).is_empty(), "invalid supply energy rejected")
	for invalid in [{"homing": -1}, {"homing": 1.5}, {"homing": 1001}, {"homing": true}, {"unknown": 1}, []]:
		doc = mission(); doc.contacts[0].supply_ammo = invalid
		check(not Catalog.validate_mission(doc).is_empty(), "invalid supply ammunition rejected")
	doc = mission(); doc.contacts[1].allow_pickup = "yes"
	check(not Catalog.validate_mission(doc).is_empty(), "artifact flag is boolean")
	doc = mission(); doc.objectives[1].type = "pickup"
	check(not Catalog.validate_mission(doc).is_empty(), "noncollectible artifact cannot require pickup")
	var editor = MissionEditor.new()
	root.add_child(editor)
	editor.set_mission(mission())
	editor._kind.select(Catalog.CONTACT_KINDS.find("supplydrop"))
	editor._add_contact(Vector2(1000, 0))
	check(editor.mission.contacts.back().supply_energy == 25, "map editor creates usable supplies")
	editor._kind.select(Catalog.CONTACT_KINDS.find("artifact"))
	editor._add_contact(Vector2(1100, 0))
	check(editor.mission.contacts.back().allow_pickup, "map editor creates collectible artifacts")
	check("pickup" in MissionEditor.GOALS and "touch" in MissionEditor.GOALS, "collision goals exposed in editor")
	editor.free()
	for kind in SpacePickups.KINDS:
		var model = PickupModel.create(kind)
		check(model.get_child_count() > 0, "pickup has native 3D geometry")
		model.free()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("SPACE_PICKUPS_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
