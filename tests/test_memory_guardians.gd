extends SceneTree
var checks = 0
var failures = 0
var app: Control
var gallery: MemoryGuardians
var deck: WorldDeck
var session: Node

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("MEMORY_FAIL " + message)

func settle(frames: int = 8) -> void:
	for i in frames: await physics_frame

func place(at: Vector3) -> void:
	deck.body.position = WorldDeck.ZONES[12].at + at + Vector3(0, 0.2, 0)
	deck.body.velocity = Vector3.ZERO
	await settle()

func close_readers() -> void:
	for child in app.get_children():
		if child is Window and not child is AcceptDialog: child.queue_free()
	await settle(2)

func run() -> void:
	var blank = MemoryCatalog.memories({})
	check(blank.size() == 6 and blank.all(func(m): return not m.unlocked), "empty campaign never grants memories")
	check(MemoryCatalog.guide_index(blank, []) == -1, "unknown campaign has no invented goal")
	check(MemoryCatalog.campaign_variant(blank) == "vigilia", "new campaign starts in vigil")
	for malformed in [{"campaign": null}, {"campaign": {"completed": "itsasoratu"}}, {"campaign": {"completed": [true, {}, "unknown"]}, "mission": 7}]:
		check(MemoryCatalog.memories(malformed).all(func(m): return not m.unlocked), "malformed progress cannot unlock a story")
	var view = {"campaign": {"completed": ["itsasoratu", "itsasoratu", "aterpe", "custom_story"], "survivors": 6}, "mission": {"id": "zaindari"}}
	var before = view.duplicate(true)
	var records = MemoryCatalog.memories(view)
	check(view == before, "projection never mutates source campaign")
	check(records.filter(func(m): return m.unlocked).size() == 2, "IDs unlock individually, duplicates/custom IDs do not fabricate progress")
	check(records[3].current and not records[3].unlocked, "current mission is distinguished from completed")
	check(not records[1].text.contains(MemoryCatalog.STORIES[1]), "future story is withheld")
	check(records[2].text.contains("6 (total acumulado)"), "rescue record uses public cumulative survivors")
	check(MemoryCatalog.guide_index(records, []) == 0 and MemoryCatalog.guide_index(records, [0]) == 2, "guide selects unread completed records")
	check(MemoryCatalog.guide_index(records, [0, 2]) == 3, "guide returns to current mission after reading")
	check(MemoryCatalog.campaign_variant(records) == "travesia", "completed progress changes automatic environment")
	check(MemoryCatalog.campaign_variant(MemoryCatalog.memories({"campaign": {"completed": MemoryCatalog.MISSIONS}})) == "alba", "six completed missions reach dawn variant")
	root.size = Vector2i(1600, 900)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle(3)
	session = root.get_node("Session")
	app._new_game()
	app._go("deck")
	await settle()
	session.paused = true
	deck = app._deck
	gallery = app.get_node("MemoryGuardians")
	check(gallery.deck == deck and gallery.actors.size() == 7, "main executable installs keeper plus six sentinels on the actual deck")
	check(gallery.gallery.get_parent() == deck._zone_models[12], "guardians share existing zone visibility/lifetime")
	check(gallery.actors.all(func(actor): return actor.gaze != null), "Blender gaze pivots remain editable runtime parts")
	deck.teleport_zone(12)
	await settle(20)
	check(deck.body.is_on_floor() and deck._near_door == -1, "arrival remains walkable and clear of return trigger")
	for entry in MemoryCatalog.interactions():
		await place(entry.position)
		check(deck.body.is_on_floor(), "floor at " + entry.id)
		check(deck._near_interaction.get("id") == entry.id, "physical E interaction selects " + entry.id)
	await place(Vector3(0, 0, 27))
	check(not deck.body.test_move(deck.body.global_transform, Vector3(0, 0, -56)), "full central corridor is unobstructed")
	await place(Vector3(-1.6, 0, 15))
	check(deck.body.test_move(deck.body.global_transform, Vector3(-3, 0, 0)), "sentinel has solid collision")
	await place(Vector3(3.1, 0, 15))
	check(deck.body.test_move(deck.body.global_transform, Vector3(2, 0, 0)), "memory prism has solid collision")
	var original_campaign: Dictionary = session.sim.state.campaign.duplicate(true)
	var keeper = MemoryCatalog.interactions()[0]
	await place(keeper.position)
	deck.interact()
	await settle(2)
	check(gallery.variant_mode == 1 and gallery.guide == 0, "keeper E changes real variant and guides current mission")
	var readers: Array = app.get_children().filter(func(child): return child is Window and not child is AcceptDialog)
	check(readers.size() == 1, "existing app reader opens exactly once")
	if readers.size() == 1:
		var text = ""
		for label in readers[0].find_children("*", "Label", true, false): text += label.text
		check(text.contains("Sigue las señales ámbar") and text.contains("Alba"), "reader receives interaction result in the correct signal order")
	await close_readers()
	deck.interact()
	await settle(2)
	check(gallery.active_variant == "vigilia", "second keeper interaction selects vigil")
	await close_readers()
	check(session.sim.state.campaign == original_campaign, "guardian visits grant no campaign rewards or saved progress")
	await place(Vector3(0, 0, 0))
	var mode_before = gallery.variant_mode
	check(not gallery.interact(keeper.duplicate()), "distant interaction rejected")
	check(not gallery.interact({"id": "memory_sentinel_999", "index": 999}), "unknown identifiers rejected")
	check(gallery.variant_mode == mode_before, "rejected input leaves view state unchanged")
	# Use only the client's public projection to prove no dependency on host sim internals.
	var saved_view: Dictionary = session.view.duplicate(true)
	session.set_physics_process(false)
	session.view = saved_view.duplicate(true)
	session.view.campaign = view.campaign.duplicate(true)
	session.view.mission.id = view.mission.id
	session.updated.emit()
	check(gallery.memories[2].unlocked and not gallery.memories[1].unlocked, "public update refreshes in-world records")
	await place(MemoryCatalog.reading_point(2))
	var memory_entry = {"id": "memory_2", "index": 999}
	check(gallery.interact(memory_entry) and 2 in gallery.visited, "canonical ID controls reading, caller-supplied index is ignored")
	check(memory_entry.text.contains("total acumulado"), "reader receives current campaign facts")
	check(session.sim.state.campaign == original_campaign, "client presentation does not write host campaign")
	await place(Vector3(-1.6, 0, -5))
	check(gallery.interact({"id": "memory_sentinel_3"}) and gallery.guide == 3, "sentinel selects its paired waypoint")
	await settle(10)
	check(gallery.markers.any(func(marker): return marker.visible), "guidance is visible in the 3D corridor")
	deck.reduced_motion = true
	var gaze = gallery.actors[4].gaze as Node3D
	var previous = gaze.transform
	await place(Vector3(0, 0, -7))
	check(gaze.transform == previous, "reduced motion freezes gaze while interactions remain usable")
	deck.reduced_motion = false
	await settle(12)
	check(gaze.transform != previous, "gaze reacts in normal motion mode")
	session.view = saved_view
	session.updated.emit()
	session.set_physics_process(true)
	check(gallery.visited.is_empty() and not gallery.memories[2].unlocked, "campaign reset removes unavailable local reading state")
	await place(Vector3(0, 0, 31.3))
	deck.interact()
	check(deck.zone == 7, "existing return to cantina is always accessible")
	check(not gallery.interact(keeper.duplicate()), "guardian interaction rejected outside its zone")
	app._go("bridge")
	await settle()
	app._go("deck")
	await settle()
	deck = app._deck
	check(gallery.deck == deck and gallery.actors.size() == 7, "returning to deck creates one functional replacement gallery")
	if "--memory-test-capture" in OS.get_cmdline_user_args():
		deck.teleport_zone(12)
		await place(Vector3(0.8, 0, 29))
		deck.body.look_at(WorldDeck.ZONES[12].at + Vector3(-2.5, 1.0, 21))
		deck.camera.rotation.x = -.015
		await settle(30)
		await process_frame
		await RenderingServer.frame_post_draw
		var path = OS.get_environment("MEMORY_CAPTURE_PATH")
		if path.is_empty(): path = "user://memory-guardians.png"
		check(root.get_texture().get_image().save_png(path) == OK, "real executable screenshot saved")
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle(2)
	print("MEMORY_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
