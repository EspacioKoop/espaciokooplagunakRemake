extends SceneTree
var checks = 0
var failures = 0
var session: Node
var expedition: Node
var fleet: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FLEET_FAIL " + label)

func contact(id: String, name: String, kind: String, position: Array) -> Dictionary:
	var value = {"id":id,"name":name,"kind":kind,"position":position,"identified":true,"jammed":false,"known":true,"hull":100.0,"hailed":false,"negotiated":false,"rescued":false,"salvaged":false,"probed":false,"pacified":false,"attack_at":9999.0,"survivors":0,"frequency":3}
	session.sim.state.contacts.append(value)
	return value

func run() -> void:
	session = root.get_node("Session")
	expedition = root.get_node("Expedition")
	fleet = root.get_node("Fleet")
	expedition.data = expedition._default_data()
	session.new_campaign()
	session.sim.state.contacts.clear()
	var ally_a = contact("ally_a", "Haize A", "friendly", [900.0, 300.0])
	var ally_b = contact("ally_b", "Haize B", "friendly", [950.0, 350.0])
	var enemy = contact("enemy_a", "Itzal A", "hostile", [1500.0, 300.0])
	fleet._bootstrap(session.sim.state.contacts)
	ally_a.faction = "haize"
	ally_b.faction = "haize"
	enemy.faction = "itzal"
	expedition.data.factions.haize.reputation = 10
	expedition.data.factions.itzal.reputation = -20
	check(ally_a.has("ai_order") and ally_a.has("morale") and ally_a.has("anchor"), "fleet bootstrap adds strategic AI state to contacts")
	session.role = "comunicaciones"
	check(fleet.command("order", {"target":"ally_a","order":"escort","objective":""}).ok and ally_a.ai_order == "escort", "communications can order allied escort")
	var before = Vector2(ally_a.position[0], ally_a.position[1])
	fleet._update_contact(ally_a, session.sim.state.ship, session.sim.state.contacts, 1.0)
	var after = Vector2(ally_a.position[0], ally_a.position[1])
	check(after != before, "escort order moves allied contact strategically")
	check(fleet.command("order", {"target":"ally_a","order":"intercept","objective":"enemy_a"}).ok and ally_a.ai_objective == "enemy_a", "allied fleet accepts valid interception target")
	ally_a.position = [1250.0, 300.0]
	enemy.position = [1400.0, 300.0]
	var hostile_hull = float(enemy.hull)
	fleet._update_contact(ally_a, session.sim.state.ship, session.sim.state.contacts, 1.0)
	check(enemy.hull < hostile_hull, "interception inflicts strategic attrition at close range")
	session.role = "sensores"
	check(not fleet.command("order", {"target":"ally_b","order":"hold"}).ok, "unrelated station cannot command fleets")
	session.role = "mando"
	var convoy = fleet.command("form_convoy", {"members":["ally_a","ally_b"]})
	check(convoy.ok and not str(ally_a.fleet_id).is_empty() and ally_a.fleet_id == ally_b.fleet_id, "command forms allied convoy with shared fleet id")
	var convoy_id = str(ally_a.fleet_id)
	check(fleet.command("release_convoy", {"fleet":convoy_id}).ok and ally_a.fleet_id.is_empty() and ally_a.ai_order == "patrol", "command can release convoy back to patrol")
	enemy.morale = 10.0
	enemy.ai_order = "patrol"
	fleet._process(0.1)
	check(enemy.ai_order == "retreat", "low-morale hostile switches to retreat")
	enemy.pacified = false
	enemy.ai_order = "patrol"
	enemy.morale = 100.0
	expedition.data.factions.itzal.reputation = 25
	fleet._process(0.1)
	check(enemy.pacified, "positive faction relationship can suspend hostility")
	var report = fleet.report()
	check(report.size() >= 3, "fleet console receives live strategic report")
	var named = false
	for row in report:
		if row.id == "ally_a" and row.faction == "haize": named = true
	check(named, "strategic report exposes faction and order state for identified fleet")
	print("FLEET_AI_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
