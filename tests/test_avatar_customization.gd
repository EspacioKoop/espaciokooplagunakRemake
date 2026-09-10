extends SceneTree
var checks = 0
var failures = 0
const TEST_PATH = "user://avatar-test.json"

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("AVATAR_FAIL " + label)

func settle() -> void:
	for i in 4: await process_frame

func run() -> void:
	var standard = AvatarProfile.defaults()
	check(AvatarProfile.validate(standard).is_empty(), "default profile valid")
	for invalid in [null, [], "crew", 42, {}, true]:
		check(not AvatarProfile.validate(invalid).is_empty(), "reject wrong profile type or shape")
	for key in standard:
		var missing = standard.duplicate(true)
		missing.erase(key)
		check(not AvatarProfile.validate(missing).is_empty(), "reject missing " + key)
	for entry in [["suit", "res://evil.glb"], ["visor", "unknown"], ["gear", {}], ["version", 2], ["version", true], ["version", INF], ["format", "lagunak-ship"], ["peer_id", 1], ["xp", 9999]]:
		var invalid = standard.duplicate(true)
		invalid[entry[0]] = entry[1]
		check(not AvatarProfile.validate(invalid).is_empty(), "reject invalid field " + entry[0])
	for bytes in [PackedByteArray(), "[{}]".to_utf8_buffer(), "{broken".to_utf8_buffer(), "x".repeat(513).to_utf8_buffer()]:
		check(not AvatarProfile.decode(bytes).ok, "reject malformed or oversized wire format")
	var chosen = standard.duplicate(true)
	chosen.suit = "orchid"
	chosen.visor = "gold"
	chosen.gear = "survey"
	check(AvatarProfile.save_profile(chosen, TEST_PATH).is_empty(), "save valid appearance")
	check(AvatarProfile.read_profile(TEST_PATH).profile == chosen, "read persisted appearance")
	var previous = FileAccess.get_file_as_bytes(TEST_PATH)
	check(not AvatarProfile.save_profile({"peer_id": 1}, TEST_PATH).is_empty(), "invalid write rejected")
	check(FileAccess.get_file_as_bytes(TEST_PATH) == previous, "invalid write preserves bytes")
	check(not FileAccess.file_exists(TEST_PATH + ".tmp"), "atomic write leaves no pending file")
	check(not AvatarProfile.save_profile(chosen, "user://missing-avatar-directory/avatar.json").is_empty(), "filesystem failure returned")
	var file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var corrupted = AvatarProfile.read_profile(TEST_PATH)
	check(not corrupted.ok and corrupted.profile == standard, "corrupt file falls back safely")
	file = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("x".repeat(4096))
	file.close()
	check(not AvatarProfile.read_profile(TEST_PATH).ok, "read caps file length")
	DirAccess.remove_absolute(TEST_PATH)
	check(AvatarProfile.read_profile(TEST_PATH).profile == standard, "missing file defaults")
	var first = SpaceView.model("crew")
	var second = SpaceView.model("crew")
	root.add_child(first)
	root.add_child(second)
	first.position = Vector3(4, 2, 9)
	first.rotation = Vector3(0, 1.4, 0)
	first.scale = Vector3.ONE * 0.7
	var original_transform = first.transform
	var mesh = first.find_children("*", "MeshInstance3D", true, false)[0]
	var other_mesh = second.find_children("*", "MeshInstance3D", true, false)[0]
	var shared_mesh = mesh.mesh
	var original_material = shared_mesh.surface_get_material(0)
	var original_color = original_material.albedo_color
	AvatarAppearance.apply(first, chosen)
	check(mesh.get_surface_override_material(0) != null, "suit changes actual mesh material")
	check(mesh.get_surface_override_material(0).albedo_color == AvatarProfile.SUIT_COLORS.orchid, "suit palette applied")
	check(mesh.get_surface_override_material(1).albedo_color == AvatarProfile.VISOR_COLORS.gold, "visor palette applied")
	check(other_mesh.get_surface_override_material(0) == null, "other instances keep fallback material")
	check(shared_mesh.surface_get_material(0).albedo_color == original_color, "shared asset is not mutated")
	check(first.get_node_or_null("AvatarGear/ScannerLens") != null, "survey equipment exists on crew")
	check(first.transform == original_transform, "appearance preserves physical pose and scale")
	for suit in AvatarProfile.SUITS:
		for visor in AvatarProfile.VISORS:
			for gear in AvatarProfile.GEAR:
				var variant = standard.duplicate(true)
				variant.merge({"suit": suit, "visor": visor, "gear": gear}, true)
				AvatarAppearance.apply(first, variant)
				check(first.get_meta("avatar_profile") == variant, "select every variant")
	AvatarAppearance.apply(first, {"suit": "missing"})
	check(mesh.get_surface_override_material(0) == null and mesh.get_surface_override_material(1) == null, "invalid appearance restores original materials")
	check(first.get_node_or_null("AvatarGear") == null, "fallback removes extra gear")
	check(mesh.mesh == shared_mesh, "fallback keeps original crew mesh")
	first.queue_free()
	second.queue_free()
	await settle()
	var service = root.get_node("Avatars")
	service.storage_path = TEST_PATH
	service.local_profile = standard.duplicate(true)
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle()
	var button = app.find_child("AvatarButton", true, false)
	check(button != null and button.is_visible_in_tree(), "executable offers visible avatar entry")
	button.pressed.emit()
	await settle()
	var editor = service.editor
	check(editor != null and editor.visible, "button opens usable editor")
	check(editor.preview.avatar != null and editor.portrait.avatar != null, "portrait and full preview render crew")
	editor.set_profile(chosen)
	check(service.local_profile == standard, "preview is a draft until saved")
	check(editor.preview.avatar.get_meta("avatar_profile") == chosen, "preview reflects selection")
	check(editor.portrait.avatar.get_meta("avatar_profile") == chosen, "portrait reflects same selection")
	editor.preview.turn(PI / 2)
	check(is_equal_approx(editor.preview.avatar.rotation.y, PI / 2), "preview turn control works")
	editor._save()
	check(service.local_profile == chosen, "editor saves to own local avatar")
	check(AvatarProfile.read_profile(TEST_PATH).profile == chosen, "editor save survives file reload")
	var remote = SpaceView.model("crew")
	root.add_child(remote)
	service.profiles[99] = chosen.duplicate(true)
	service.bind_avatar(remote, 99)
	check(remote.get_meta("avatar_profile") == chosen, "bind applies peer appearance to real crew")
	var changed = chosen.duplicate(true)
	changed.gear = "workpack"
	service.profiles[99] = changed
	service._refresh_bound()
	check(remote.get_node_or_null("AvatarGear/Pack") != null, "bound crew updates when appearance changes")
	editor.set_profile(standard)
	editor.queue_free()
	await settle()
	check(service.local_profile == chosen, "cancel leaves saved appearance intact")
	editor = service.open_editor()
	await settle()
	check(editor.read_profile() == chosen, "reopened editor starts from saved appearance")
	# A real deck remote is bound by the optional integration supplied by seats.
	app._new_game()
	app._go("deck")
	await settle()
	var session = root.get_node("Session")
	session.poses[99] = {"position": [0, 0, -40], "yaw": 0}
	app._deck._update_avatars(session)
	check(app._deck._avatars[99].get_meta("avatar_profile", {}) == changed, "live deck crew receives bound cosmetics")
	if "--capture-avatar" in OS.get_cmdline_user_args():
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		editor.get_texture().get_image().save_png("/tmp/avatar-editor.png")
	editor.queue_free()
	remote.queue_free()
	app.queue_free()
	await settle()
	DirAccess.remove_absolute(TEST_PATH)
	print("AVATAR_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
