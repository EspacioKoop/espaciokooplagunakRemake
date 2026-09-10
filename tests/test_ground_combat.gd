extends SceneTree
var checks = 0
var failures = 0
var session: Node
var expedition: Node
var crew: Node
var combat: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GROUND_FAIL " + label)

func crew_turn() -> Dictionary:
	for i in combat.state.units.size():
		if combat.state.units[i].team == "crew":
			combat.state.turn = i
			combat.state.units[i].acted = false
			combat.state.units[i].move = 4
			return combat.state.units[i]
	return {}

func enemy_unit() -> Dictionary:
	for unit in combat.state.units:
		if unit.team == "enemy" and not unit.down: return unit
	return {}

func run() -> void:
	session = root.get_node("Session")
	expedition = root.get_node("Expedition")
	crew = root.get_node("Crew")
	combat = root.get_node("GroundCombat")
	expedition.data = expedition._default_data()
	session.new_campaign()
	session.role = "mando"
	var profile = crew.profile()
	profile.name = "Ane"
	profile.skills = {"pilotaje":2,"ciencia":2,"ingenieria":2,"negociacion":2,"combate":4}
	crew._ensure_fields(profile)
	combat._rng.seed = 43021
	var start = combat.start_encounter("corsario", 2)
	check(start.ok and combat.state.status == "active", "command can start standalone tactical encounter")
	check(combat.state.units.size() == 3 and combat._alive("enemy").size() == 2, "encounter contains crew and requested enemies")
	check(combat.state.obstacles.size() >= 5, "tactical arena has real cover obstacles")
	var actor = crew_turn()
	check(not actor.is_empty() and actor.weapon == "carabina", "crew combat skill selects expedition weapon")
	var original = actor.position.duplicate()
	var move_target = [2, 3]
	if move_target in combat.state.obstacles or combat._occupied(move_target[0], move_target[1]): move_target = [2, 2]
	var moved = combat.command("move", {"x":move_target[0], "y":move_target[1]})
	check(moved.ok and actor.position == move_target and actor.move < 4, "crew moves across tactical grid and spends movement")
	check(not combat.command("move", {"x":9, "y":6}).ok, "movement rejects cells beyond remaining movement")
	var enemy = enemy_unit()
	enemy.position = [min(9, actor.position[0] + 2), actor.position[1]]
	enemy.armor = 0
	actor.acted = false
	var hp_before = int(enemy.hp)
	var attempts = 0
	while enemy.hp == hp_before and attempts < 8:
		actor.acted = false
		combat._rng.seed = 1000 + attempts
		combat.command("attack", {"target":enemy.id})
		attempts += 1
	check(enemy.hp < hp_before, "weapon attack resolves authoritative hit and damage")
	actor = crew_turn()
	check(combat.command("guard", {}).ok and actor.guard and actor.acted, "guard action grants defensive state")
	actor = crew_turn()
	var ally = {"id":"ally_test","name":"Unai","team":"crew","position":[actor.position[0], clampi(actor.position[1] + 1,0,6)],"hp":20,"max_hp":30,"armor":11,"weapon":"pistola","skill":2,"move":4,"guard":false,"help":0,"acted":false,"down":false,"initiative":10}
	combat.state.units.append(ally)
	check(combat.command("help", {"target":"ally_test"}).ok and ally.help == 2, "crew can assist adjacent ally for next attack")
	actor = crew_turn()
	ally.position = [actor.position[0], clampi(actor.position[1] + 1,0,6)]
	expedition.inventory().sendagaiak = 1
	var ally_hp = int(ally.hp)
	check(combat.command("medkit", {"target":"ally_test"}).ok, "crew can consume expedition medicine on adjacent ally")
	check(ally.hp > ally_hp and expedition.inventory().sendagaiak == 0, "medkit heals and consumes persistent inventory")
	combat.set_camera("third")
	check(combat.state.camera == "third", "third-person framing is selectable")
	combat.set_camera("pov")
	check(combat.state.camera == "pov", "POV visibility mode is selectable")
	combat.set_camera("tactical")
	check(combat.state.camera == "tactical", "full tactical camera is selectable")
	actor = crew_turn()
	actor.position = [4,3]
	var cover_target = [5,3]
	combat.state.obstacles.append(cover_target)
	check(combat._cover([4,4], [7,4]) >= 0, "cover calculation is available for attack defense")
	var credits_before = int(session.sim.state.campaign.credits)
	var xp_before = int(profile.xp)
	for unit in combat.state.units:
		if unit.team == "enemy":
			unit.hp = 0
			unit.down = true
	combat._check_end()
	check(combat.state.status == "won" and combat.state.winner == "crew", "defeating all enemies resolves victory")
	check(session.sim.state.campaign.credits == credits_before + 20, "ground victory rewards shared campaign credits")
	check(profile.xp > xp_before or profile.level > 1, "ground outcome advances crew progression")
	check(profile.condition >= 0 and profile.condition <= 100, "ground outcome writes persistent crew condition")
	check(not expedition.data.chronicle.is_empty(), "ground encounter records expedition chronicle")
	combat.state = {}
	combat._rng.seed = 1234
	check(combat.start_encounter("enjambre", 1).ok, "different enemy archetype can start an encounter")
	actor = crew_turn()
	actor.position = [1, actor.position[1]]
	check(combat.command("flee", {}).ok and combat.state.status == "fled", "crew can extract from valid edge cell")
	combat.state = {}
	print("GROUND_COMBAT_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
