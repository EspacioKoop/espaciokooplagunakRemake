extends SceneTree
var checks = 0
var failures = 0
var session: Node
var expedition: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("EXPEDITION_FAIL " + label)
func settle(frames: int = 4) -> void:
	for i in frames: await process_frame

func run() -> void:
	session = root.get_node("Session")
	expedition = root.get_node("Expedition")
	expedition.data = expedition._default_data()
	session.new_campaign()
	await settle()
	check(expedition.data.format == "lagunak-expedition", "extension state is standalone versioned data")
	var profile = expedition.command("profile_set", {"name":"Ane", "approach":"tecnica", "pilotaje":3, "ciencia":3, "ingenieria":2, "negociacion":2, "combate":2})
	check(profile.ok and expedition.profile().name == "Ane", "crew profile persists approach and skills")
	check(not expedition.command("profile_set", {"name":"Ane", "approach":"tecnica", "pilotaje":4, "ciencia":4, "ingenieria":4, "negociacion":4, "combate":4}).ok, "crew sheet enforces point budget")
	check(expedition.command("marker_add", {"label":"Deriva", "x":120, "y":-90}).ok and expedition.data.atlas.markers.size() == 1, "atlas accepts persistent marker")
	var marker_id = expedition.data.atlas.markers[0].id
	check(expedition.command("marker_remove", {"id":marker_id}).ok and expedition.data.atlas.markers.is_empty(), "marker owner can remove marker")
	var before_contacts = session.sim.state.contacts.size()
	var spawn = expedition.command("director_spawn", {"kind":"hostile", "name":"Patrulla de prueba", "x":800, "y":0})
	check(spawn.ok and session.sim.state.contacts.size() == before_contacts + 1, "Mando spawns encounter directly into authoritative simulation")
	var spawned = session.sim.state.contacts.back()
	check(spawned.kind == "hostile" and spawned.id.begins_with("dir_"), "director contact uses validated native contact model")
	var old_role = session.role
	session.role = "sensores"
	check(not expedition.command("director_spawn", {"kind":"hostile", "name":"No", "x":800, "y":0}).ok, "non-command station cannot direct encounters")
	session.role = old_role
	var station: Dictionary = {}
	for c in session.sim.state.contacts:
		if c.kind == "station": station = c; break
	if station.is_empty():
		station = {"id":"market_test", "name":"Merkatu", "kind":"station", "position":session.sim.state.ship.position.duplicate(), "identified":true, "jammed":false, "known":true, "hull":100.0, "hailed":false, "negotiated":false, "rescued":false, "salvaged":false, "probed":false, "pacified":false, "attack_at":0.0, "survivors":0, "frequency":2}
		session.sim.state.contacts.append(station)
	session.sim.state.ship.docked = station.id
	session.sim.state.campaign.credits = 200
	var credits = session.sim.state.campaign.credits
	check(expedition.command("trade_buy", {"item":"hornidurak", "amount":2}).ok, "docked crew can buy cargo")
	check(expedition.inventory().hornidurak == 2 and session.sim.state.campaign.credits == credits - 36, "trade spends campaign credits and adds inventory")
	check(expedition.command("trade_sell", {"item":"hornidurak", "amount":1}).ok and expedition.inventory().hornidurak == 1, "cargo can be sold back at station")
	var identified = session.sim.state.contacts[0]
	identified.identified = true
	session._refresh_view()
	expedition._consume_session(session)
	check(expedition.data.atlas.sectors.has(session.view.mission.sector), "current mission sector enters hierarchical atlas root")
	check(not expedition.data.bestiary.is_empty(), "identified contacts feed native bestiary")
	session.sim.log_event("Prueba", "Rescate completado")
	session._refresh_view()
	expedition._consume_session(session)
	check(not expedition.data.chronicle.is_empty(), "simulation events feed persistent chronicle")
	check(expedition.data.factions.haize.reputation > 0, "meaningful events change faction reputation")
	check(expedition.command("director_tempo", {"value":1.5}).ok and is_equal_approx(expedition.data.director.tempo, 1.5), "Mando controls encounter tempo")
	var old_parts = session.sim.state.ship.parts
	session.sim.state.campaign.credits = 100
	check(expedition.command("director_supply", {}).ok and session.sim.state.ship.parts >= old_parts, "director emergency supply affects shared ship resources")
	expedition.save()
	check(FileAccess.file_exists("user://expedition-systems.json"), "extension state persists locally without Foundry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://expedition-systems.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://expedition-systems.json.bak"))
	print("EXPEDITION_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
