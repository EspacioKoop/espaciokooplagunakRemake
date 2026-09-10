extends SceneTree
var checks = 0
var failures = 0
var session: Node
var expedition: Node
var crew: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CREW_FAIL " + label)

func run() -> void:
	session = root.get_node("Session")
	expedition = root.get_node("Expedition")
	crew = root.get_node("Crew")
	expedition.data = expedition._default_data()
	session.new_campaign()
	var profile: Dictionary = crew.profile()
	profile.name = "Ane"
	profile.approach = "tecnica"
	profile.skills = {"pilotaje": 2, "ciencia": 3, "ingenieria": 3, "negociacion": 2, "combate": 2}
	crew._ensure_fields(profile)
	check(profile.level == 1 and profile.focus == 3 and profile.condition == 100, "crew profile migrates progression fields")
	check(crew.command("trait_add", {"trait": "jakinmina"}).ok, "crew can acquire a valid trait")
	check(not crew.command("trait_add", {"trait": "jakinmina"}).ok, "duplicate trait is rejected")
	var focus_before = int(profile.focus)
	var xp_before = int(profile.xp)
	check(crew.command("check", {"skill": "ciencia", "difficulty": 12, "focus": true}).ok, "host resolves native skill check")
	check(crew.last_result.roll >= 1 and crew.last_result.roll <= 20, "skill check uses bounded d20 result")
	check(crew.last_result.modifier >= 11, "science skill trait and focus contribute to modifier")
	check(profile.focus == focus_before - 1 and profile.xp > xp_before, "skill check consumes focus and advances experience")
	profile.focus = 3
	check(crew.command("ability", {"ability": "azterketa"}).ok, "science ability prepares advantage")
	check(crew.command("check", {"skill": "ciencia", "difficulty": 10, "focus": false}).ok and crew.last_result.advantage, "prepared science ability applies advantage exactly once")
	check(not crew.pending_advantage.has("self:ciencia"), "advantage is consumed after the check")
	profile.focus = 3
	session.role = "ingenieria"
	session.sim.state.ship.energy = 40.0
	session.sim.state.ship.systems.motores.heat = 80.0
	check(crew.command("ability", {"ability": "overclock", "system": "motores"}).ok, "engineering can use overclock")
	check(session.sim.state.ship.energy == 48.0 and session.sim.state.ship.systems.motores.heat == 62.0, "overclock changes authoritative ship energy and heat")
	session.role = "sensores"
	profile.focus = 3
	check(not crew.command("ability", {"ability": "overclock", "system": "motores"}).ok, "wrong station cannot overclock ship systems")
	session.role = "comunicaciones"
	profile.focus = 3
	session.sim.state.ship.alert = "roja"
	var reputation = int(expedition.data.factions.itsasargi.reputation)
	check(crew.command("ability", {"ability": "lasaitasuna"}).ok, "communications can calm the ship")
	check(session.sim.state.ship.alert == "verde" and expedition.data.factions.itsasargi.reputation == reputation + 1, "calm ability changes alert and faction relationship")
	session.role = "navegacion"
	profile.focus = 3
	session.sim.state.ship.speed = 100.0
	session.sim.state.ship.throttle = 1.0
	check(crew.command("ability", {"ability": "maniobra"}).ok, "navigation can perform emergency manoeuvre")
	check(is_equal_approx(session.sim.state.ship.speed, 65.0) and session.sim.state.ship.throttle == 0.0, "manoeuvre stabilizes authoritative ship movement")
	session.role = "armas"
	profile.focus = 3
	check(crew.command("ability", {"ability": "adrenalina"}).ok, "combat ability can prime ground bonus")
	check(crew.consume_combat_bonus("self") == 3 and crew.consume_combat_bonus("self") == 0, "ground combat bonus is consumable exactly once")
	profile.xp = 9
	profile.level = 1
	crew._award_xp(profile, 2, "Prueba")
	check(profile.level == 2 and profile.xp == 1 and profile.focus == 3, "experience levels up and restores focus")
	profile.focus = 0
	profile.condition = 70
	session.role = "sensores"
	check(not crew.command("rest", {}).ok, "non-command station cannot authorize crew rest")
	session.role = "mando"
	check(crew.command("rest", {}).ok and profile.focus == 3 and profile.condition == 90, "command-authorized rest restores focus and condition")
	check(crew.command("condition", {"delta": -35}).ok and profile.condition == 55, "command can record character condition changes")
	expedition.save()
	check(FileAccess.file_exists("user://expedition-systems.json"), "crew progression persists through standalone expedition save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://expedition-systems.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://expedition-systems.json.bak"))
	print("CREW_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
