extends SceneTree
## Real imported GLBs and native combat UI. All fixtures and profiles are synthetic.
var checks = 0
var failures = 0
var board: TacticalBoard3D
var combat: Node
var window: TacticalCombatWindow
var capture = ""

func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TACTICAL_MODELS_FAIL " + message)

func wait_frames(count: int = 3) -> void:
	for i in count: await process_frame

func sample(id: String, team: String, weapon: String, cell: Array) -> Dictionary:
	return {"id": id, "name": id, "team": team, "weapon": weapon, "position": cell, "hp": 30, "max_hp": 30, "down": false}

func screen_point(view: TacticalBoard3D, point: Vector3) -> Vector2:
	return view.camera.unproject_position(point) * view.size / Vector2(view.viewport_3d.size)

func click(view: TacticalBoard3D, point: Vector3) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_point(view, point)
	view.gui_input.emit(event)

func geometry_tests() -> void:
	for pair in [["crew", "pistola"], ["crew", "carabina"], ["crew", "escopeta"], ["enemy", "pistola"], ["enemy", "carabina"]]:
		var unit = sample("enemy_0_centinela" if pair[0] == "enemy" and pair[1] == "carabina" else "test", pair[0], pair[1], [1, 3])
		var before = var_to_bytes(unit)
		var pawn = TacticalModels.create_unit(unit)
		root.add_child(pawn)
		await wait_frames()
		check(var_to_bytes(unit) == before, "model creation does not mutate combat")
		check(pawn.scale.is_equal_approx(Vector3.ONE), "pawn preserves metre scale")
		var body: Node3D = pawn.get_node("Body")
		check(body.scale.is_equal_approx(Vector3.ONE), "body preserves source scale")
		check(TacticalModels.geometry_bounds(body).size.length() > 1, "real body contains imported geometry")
		var hand = TacticalModels.find_socket(body, "Socket_Hand_R")
		check(hand != null, "registered humanoid has hand socket")
		if hand != null:
			var weapon: Node3D = hand.get_node_or_null("Equipment")
			check(weapon != null, "native weapon has attached collection model")
			if weapon != null:
				var grip = TacticalModels.find_socket(weapon, "socket_grip")
				check(grip != null, "weapon has authored grip")
				if grip != null:
					check(grip.global_transform.is_equal_approx(hand.global_transform), "grip frame aligns with bone socket")
					pawn.rotation.y = 1.7
					pawn.position = Vector3(10, 2, -7)
					check(grip.global_transform.is_equal_approx(hand.global_transform), "attachment survives world translation/rotation")
					check(weapon.basis.get_scale().is_equal_approx(Vector3.ONE), "equipment remains 1:1")
				check(pawn.get_meta("weapon_resource") == TacticalModels.WEAPONS[unit.weapon], "correct compatible weapon bound")
		pawn.free()
	var drone = TacticalModels.create_unit(sample("enemy_0_enjambre", "enemy", "escopeta", [8, 1]))
	check(drone.get_meta("body_resource") == TacticalModels.DRONE, "swarm uses existing Orbita drone")
	check(not drone.has_meta("weapon_resource"), "no humanoid weapon attached to a drone")
	drone.free()
	var forged = sample("forged", "crew", "res://private.gd", [0, 0])
	forged.model = "user://secret.tscn"
	var safe = TacticalModels.create_unit(forged)
	check(safe.get_meta("body_resource") == TacticalModels.NAVIGATOR and not safe.has_meta("weapon_resource"), "untrusted model/weapon paths ignored")
	safe.free()
	for kind in SpacePickups.KINDS:
		var pickup = PickupModel.create(kind)
		check(pickup != null, "pickup is instantiated")
		var bounds = TacticalModels.geometry_bounds(pickup)
		check(bounds.get_center().length() < 0.001, "pickup geometry centered at simulation origin")
		check(is_equal_approx(maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)), 2.0 if kind == "supplydrop" else 2.5), "pickup visual footprint kept bounded")
		check(pickup.get_meta("asset_resource") == (PickupModel.SUPPLY if kind == "supplydrop" else PickupModel.ARTIFACT), "pickup uses correct library resource")
		check(pickup.find_children("*", "CollisionObject3D", true, false).is_empty(), "render asset does not add simulation collisions")
		pickup.free()
	for bad in ["", "planet", "../secret", "user://secret.tscn"]:
		check(PickupModel.create(bad) == null, "unsupported pickup kind rejected")

func view_tests() -> void:
	board = TacticalBoard3D.new()
	board.size = Vector2(800, 620)
	root.add_child(board)
	await wait_frames()
	board.present({"units": [], "obstacles": []})
	await wait_frames()
	for y in GroundCombat.HEIGHT:
		for x in GroundCombat.WIDTH:
			var cell = Vector2i(x, y)
			var position = TacticalBoard3D.cell_position(cell)
			check(TacticalBoard3D.position_cell(position) == cell, "world/grid round trip")
			var screen = screen_point(board, position)
			check(Rect2(Vector2.ZERO, board.size).has_point(screen), "tactical framing contains every cell")
			check(board.pick(screen).get("cell") == cell, "actual camera ray selects correct cell")
	for invalid in [null, {}, [], [0], [0, 0, 0], [NAN, 1], [INF, 1], [-1, 0], [10, 0], [0, 7], [0.1, 1], ["1", 1], [true, 1]]:
		check(not TacticalBoard3D.valid_cell(invalid), "invalid grid position rejected")
	for point in [Vector2(-1, 0), Vector2(9999, 9999), Vector2(NAN, 1), Vector2(INF, 1)]:
		check(board.pick(point).is_empty(), "invalid/offscreen picking rejected")
	check(TacticalBoard3D.position_cell(Vector3(INF, 0, 0)) == Vector2i(-1, -1), "nonfinite world coordinates rejected")
	var original_camera = board.camera.transform
	var wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	board.gui_input.emit(wheel)
	check(board._zoom < 1.0, "wheel zoom is local presentation")
	var right = InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	board.gui_input.emit(right)
	var motion = InputEventMouseMotion.new()
	motion.relative = Vector2(50, 0)
	motion.position = Vector2(400, 300)
	board.gui_input.emit(motion)
	check(not board.camera.transform.is_equal_approx(original_camera), "right drag orbits the real camera")
	board._reset_camera()
	check(board.camera.transform.is_equal_approx(original_camera) and is_equal_approx(board._zoom, 1.0), "recenter restores full tactical framing")
	var units = [sample("self", "crew", "pistola", [1, 3]), sample("enemy_0_centinela", "enemy", "carabina", [8, 1]), sample("enemy_1_enjambre", "enemy", "escopeta", [8, 5])]
	var state = {"status": "active", "turn": 0, "camera": "tactical", "selected": "enemy_0_centinela", "units": units, "obstacles": [[4, 2], [4, 4]]}
	var before = var_to_bytes(state)
	board.present(state)
	await wait_frames()
	check(var_to_bytes(state) == before, "rendering leaves entire input snapshot unchanged")
	check(board.pawns.size() == 3 and board.covers.size() == 2, "native units and obstacles have models")
	check(board.pawns.enemy_0_centinela.selection.visible, "selection marker follows existing selected id")
	var instance = board.pawns.self.node.get_instance_id()
	var cover_instance = board.covers[Vector2i(4, 2)].get_instance_id()
	for i in 20: board.present(state)
	check(board.pawns.self.node.get_instance_id() == instance, "stable snapshots reuse pawn nodes")
	check(board.covers[Vector2i(4, 2)].get_instance_id() == cover_instance, "stable snapshots reuse cover nodes")
	for id in board.pawns:
		var point: Vector3 = board.pawns[id].node.position + Vector3.UP * 1.2
		check(board.pick(screen_point(board, point)).get("unit") == id, "real camera ray targets visible model")
	state.camera = "third"
	board.present(state)
	check(board.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and board.camera.position.distance_to(board.pawns.self.node.position) > 5, "third person is a real offset perspective camera")
	state.camera = "pov"
	board.present(state)
	check(not board.pawns.self.node.visible and not board.pawns.enemy_0_centinela.node.visible, "POV hides own shell and out-of-range enemies")
	check(is_equal_approx(board.camera.position.y, 1.65), "POV uses eye height")
	check(board.pick(Vector2(400, 310)).get("unit", "") != "enemy_0_centinela", "hidden model cannot be selected by ray")
	state.units[1].position = [3, 3]
	board.present(state)
	check(board.pawns.enemy_0_centinela.node.visible, "POV reveals an in-range enemy")
	state.units[1].down = true
	board.present(state)
	check(not board.pawns.enemy_0_centinela.node.visible, "downed unit is not interactive")
	state.camera = "tactical"
	state.units[0].weapon = "carabina"
	board.present(state)
	check(board.pawns.self.node.get_instance_id() != instance, "loadout changes rebuild only affected model")
	var excessive: Array = []
	for i in 100: excessive.append(sample("u%d" % i, "crew", "pistola", [i % 10, (i / 10) % 7]))
	board.present({"units": excessive, "obstacles": [], "turn": INF})
	check(board.pawns.size() <= TacticalBoard3D.MAX_UNITS, "render work bounded for oversized input")
	board.present({"units": [{}, {"id": "bad", "team": "crew", "position": [NAN, 0]}], "obstacles": [[-1, 4], "bad"]})
	check(board.pawns.is_empty() and board.covers.is_empty(), "malformed replacement clears previous visuals")
	board.present({"units": "bad", "obstacles": null})
	check(board.pawns.is_empty(), "malformed containers are handled")
	await wait_frames()
	board.free()
	board = null

func crew_turn() -> Dictionary:
	for i in combat.state.units.size():
		if combat.state.units[i].team == "crew":
			combat.state.turn = i
			return combat.state.units[i]
	return {}

func integration_tests() -> void:
	root.get_node("Session").role = "mando"
	root.get_node("Session").new_campaign()
	combat = root.get_node("Combat")
	combat.set_process(false)
	combat.state = {}
	combat._rng.seed = 320052
	check(combat.start_encounter("corsario", 2).ok, "native encounter starts")
	var actor = crew_turn()
	actor.name = "Tripulante"
	actor.position = [1, 3]
	actor.move = 4
	combat.state.camera = "tactical"
	window = TacticalCombatWindow.new()
	window.combat = combat
	root.add_child(window)
	window.popup_centered()
	await wait_frames(8)
	check(window.board is TacticalBoard3D, "F6 combat window uses 3D by default")
	var view: TacticalBoard3D = window.board
	var instance = view.get_instance_id()
	var pawn_instance = view.pawns[str(actor.id)].node.get_instance_id()
	click(view, TacticalBoard3D.cell_position(Vector2i(2, 3)))
	await wait_frames(6)
	check(actor.position == [2, 3] and actor.move == 3, "3D click executes native movement and spends allowance")
	check(window.board.get_instance_id() == instance, "action panel rebuild preserves viewport")
	check(window.board.pawns[str(actor.id)].node.get_instance_id() == pawn_instance, "action panel rebuild preserves imported models")
	var enemy = combat._alive("enemy")[0]
	click(view, view.pawns[str(enemy.id)].node.position + Vector3.UP * 1.2)
	await wait_frames()
	check(window.selected == enemy.id and combat.state.selected == enemy.id, "3D selection reaches native combat target")
	var state_before = var_to_bytes(combat.state)
	window._toggle_renderer()
	await wait_frames()
	check(window.board is TacticalBoard and not window.use_3d, "2D alternative remains usable")
	check(var_to_bytes(combat.state) == state_before, "renderer switch does not change rules or progression")
	window._toggle_renderer()
	await wait_frames(5)
	check(window.board is TacticalBoard3D and window.selected == enemy.id, "3D return preserves target")
	for mode in ["third", "pov", "tactical"]:
		combat.set_camera(mode)
		await wait_frames()
		check(window.board._camera_mode == mode, "existing camera controls drive 3D view")
	for i in 12:
		combat.updated.emit()
		combat.notice.emit("Prueba de transición", true)
		await wait_frames(2)
	check(window.board is TacticalBoard3D and is_instance_valid(window.board.camera), "coalesced repeated updates retain live viewport")
	combat.state = {}
	combat.updated.emit()
	await wait_frames(4)
	check(window.board == null, "closing encounter clears 3D board")
	check(combat.start_encounter("centinela", 2).ok, "encounter can reopen without restarting UI")
	actor = crew_turn()
	actor.name = "Tripulante"
	actor.position = [1, 3]
	actor.weapon = "pistola"
	var engineer = actor.duplicate(true)
	engineer.id = "crew_engineer"
	engineer.name = "Ingeniería"
	engineer.position = [2, 5]
	engineer.weapon = "escopeta"
	var synthetic = actor.duplicate(true)
	synthetic.id = "crew_synthetic"
	synthetic.name = "Especialista"
	synthetic.position = [2, 1]
	synthetic.weapon = "carabina"
	combat.state.units.append_array([engineer, synthetic, combat._enemy_unit("enjambre", 4)])
	combat.state.camera = "tactical"
	combat.updated.emit()
	await wait_frames(10)
	check(window.board.pawns.size() == combat.state.units.size(), "reopened encounter shows all native archetypes")
	if not capture.is_empty():
		check(DisplayServer.get_name() != "headless", "capture requires actual graphics renderer")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(window.get_texture().get_image().save_png(capture) == OK, "real combat screenshot saved")
	window.free()
	window = null
	combat.state = {}
	await wait_frames(4)

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1480, 980)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): capture = argument.trim_prefix("--capture=")
	await geometry_tests()
	await view_tests()
	await integration_tests()
	print("TACTICAL_MODELS_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures == 0, "capture": not capture.is_empty()}))
	quit(1 if failures else 0)
