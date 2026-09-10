extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GM_HOT_CONSOLE_FAIL " + label)

func mission() -> Dictionary:
	return {
		"id": "gm-live-test",
		"title": "GM Live Test",
		"briefing": "Prueba de dirección en vivo",
		"contacts": [
			{"id": "base", "name": "Base", "kind": "station", "position": [500.0, 0.0], "known": true}
		],
		"objectives": [{"type": "dock", "target": "base", "text": "Atraca"}],
		"reward": 100
	}

func run() -> void:
	var sim = Simulation.new()
	sim.start(mission())
	var initial_events = sim.state.events.size()

	var created = GMLiveActions.spawn_contact(sim, {"id": "gm-raider", "name": "Incursor GM", "kind": "hostile", "x": 1200.0, "y": -100.0, "identified": true})
	check(created.ok, "GM can spawn a validated live contact")
	check(not sim.contact("gm-raider").is_empty(), "spawned contact exists in live simulation")
	check(sim.state.events.size() > initial_events and sim.state.events.back().source == "Dirección", "spawn is audited")

	check(not GMLiveActions.spawn_contact(sim, {"id": "gm-raider", "name": "Dup", "kind": "hostile", "x": 0, "y": 0}).ok, "duplicate ids are rejected")
	check(not GMLiveActions.spawn_contact(sim, {"id": "bad id", "name": "Bad", "kind": "hostile", "x": 0, "y": 0}).ok, "unsafe ids are rejected")
	check(not GMLiveActions.spawn_contact(sim, {"id": "gm-x", "name": "Bad", "kind": "unsupported", "x": 0, "y": 0}).ok, "unknown contact kinds are rejected")
	check(not GMLiveActions.spawn_contact(sim, {"id": "gm-far", "name": "Far", "kind": "hostile", "x": 9999999, "y": 0}).ok, "out of range positions are rejected")

	var modified = GMLiveActions.modify_contact(sim, "gm-raider", {"x": 700.0, "hull": 55.0, "jammed": true, "name": "Incursor Herido"})
	check(modified.ok, "GM can modify allowed live fields")
	check(sim.contact("gm-raider").position[0] == 700.0 and sim.contact("gm-raider").hull == 55.0 and sim.contact("gm-raider").jammed, "modifications affect live contact")
	check(not GMLiveActions.modify_contact(sim, "gm-raider", {"rescued": true}).ok, "non-whitelisted fields are rejected")
	check(not GMLiveActions.modify_contact(sim, "missing", {"hull": 1}).ok, "missing contact cannot be modified")

	sim.state.ship.autopilot = "gm-raider"
	sim.state.scan = {"target": "gm-raider", "remaining": 2.0}
	var removed = GMLiveActions.remove_contact(sim, "gm-raider")
	check(removed.ok and sim.contact("gm-raider").is_empty(), "GM can remove live contact")
	check(sim.state.ship.autopilot.is_empty() and sim.state.scan.target.is_empty(), "removal clears live references safely")
	check(not GMLiveActions.remove_contact(sim, "gm-raider").ok, "removing absent contact is rejected")

	check(GMLiveActions.trigger_event(sim, "alert", {"level": "roja"}).ok and sim.state.ship.alert == "roja", "GM can change alert level")
	check(not GMLiveActions.trigger_event(sim, "alert", {"level": "magenta"}).ok, "invalid alert level is rejected")
	var hull_before = sim.state.ship.hull
	check(GMLiveActions.trigger_event(sim, "damage", {"amount": 17}).ok and sim.state.ship.hull == hull_before - 17, "GM can apply bounded scene damage")
	check(not GMLiveActions.trigger_event(sim, "damage", {"amount": -1}).ok, "negative damage is rejected")
	check(GMLiveActions.trigger_event(sim, "repair", {"amount": 999}).ok and sim.state.ship.hull <= sim.state.ship.max_hull, "GM repair respects max hull")
	check(GMLiveActions.trigger_event(sim, "message", {"text": "Se apagan las luces del hangar."}).ok, "GM can publish an audited scene message")
	check(not GMLiveActions.trigger_event(sim, "message", {"text": ""}).ok, "empty GM messages are rejected")
	check(not GMLiveActions.trigger_event(sim, "unknown", {}).ok, "unknown GM events are rejected")

	var contacts_before = sim.state.contacts.size()
	check(GMLiveActions.trigger_event(sim, "reinforcements", {"count": 3}).ok, "GM can deploy reinforcements")
	check(sim.state.contacts.size() == contacts_before + 3, "reinforcements create requested hostile contacts")
	for c in sim.state.contacts.slice(contacts_before):
		check(c.kind == "hostile" and c.identified, "reinforcement is an identified hostile")

	sim.state.status = "won"
	check(not GMLiveActions.trigger_event(sim, "message", {"text": "late"}).ok, "GM actions stop after mission ends")
	check(not GMLiveActions.spawn_contact(sim, {"id": "late", "name": "Late", "kind": "hostile", "x": 0, "y": 0}).ok, "spawn stops after mission ends")

	print("GM_HOT_CONSOLE_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
