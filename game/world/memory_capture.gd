extends Node
## Reproducible exported-game QA, enabled only by the explicit --test flag.
## Release templates ignore external --script; exercise the real app instead.
var failures = 0
var checks = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("MEMORY_CAPTURE_FAIL " + message)

func settle(frames: int = 20) -> void:
	for i in frames: await get_tree().physics_frame

func run(app: Control, director: Node) -> void:
	app._new_game()
	app._go("deck")
	await settle()
	var deck: WorldDeck = app._deck
	var session = get_node("/root/Session")
	session.paused = true
	check(session.suppress_saves, "capture must never write campaign saves")
	check(director.deck == deck and director.actors.size() == 7, "export contains seven interactive guardians")
	deck.teleport_zone(12)
	await settle()
	check(deck.body.is_on_floor(), "exported gallery has a floor")
	deck.body.position = WorldDeck.ZONES[12].at + Vector3(-2.3, .2, 28)
	await settle()
	check(deck._near_interaction.get("id") == "memory_keeper", "keeper is reachable in exported game")
	deck.interact()
	await settle(4)
	check(director.active_variant == "alba" and director.guide == 0, "E selects dawn and first mission guidance")
	var readers = app.get_children().filter(func(child): return child is Window and not child is AcceptDialog)
	check(readers.size() == 1, "one readable interaction window opens")
	for reader in readers: reader.queue_free()
	await settle(4)
	deck.body.position = WorldDeck.ZONES[12].at + Vector3(0, .2, 31.3)
	await settle()
	deck.interact()
	check(deck.zone == 7, "return cabin is accessible in exported game")
	deck.teleport_zone(12)
	deck.body.position = WorldDeck.ZONES[12].at + Vector3(0, .2, 31)
	deck.body.look_at(WorldDeck.ZONES[12].at + Vector3(-2, .2, 25))
	deck.camera.rotation.x = -.04
	await settle(30)
	if "--memory-capture" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			check(false, "capture requires a real display renderer")
		else:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path = OS.get_environment("MEMORY_CAPTURE_PATH")
			check(not path.is_empty(), "capture output path is provided")
			if not path.is_empty(): check(get_tree().root.get_texture().get_image().save_png(path) == OK, "PNG saved from exported game")
	print("MEMORY_EXPORT_TESTS ", checks, " checks; ", failures, " failures")
	get_tree().quit(1 if failures else 0)
