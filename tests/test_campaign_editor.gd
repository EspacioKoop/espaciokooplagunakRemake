extends SceneTree
var failures = 0
var checks = 0

func _initialize() -> void:
	call_deferred("run_peer" if "--campaign-peer" in OS.get_cmdline_user_args() else "run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CAMPAIGN_FAIL " + label)

func settle() -> void:
	for i in 5: await process_frame

func equivalent(a: Variant, b: Variant) -> bool:
	# JSON numbers deserialize as floats, unlike authored GDScript integers.
	return JSON.parse_string(JSON.stringify(a, "", true, true)) == JSON.parse_string(JSON.stringify(b, "", true, true))

func fixture() -> Dictionary:
	var document = CampaignDocument.create()
	document.id = "test_voyage"
	document.title = "Los faros del mar compartido"
	document.description = "Tres etapas de exploración cooperativa."
	document.missions = []
	for i in 3:
		var mission = CampaignDocument.new_mission()
		mission.id = "stage_" + str(i)
		mission.title = "Faro " + str(i + 1)
		mission.contacts[0].position = [100, 0]
		document.missions.append(mission)
	return document

func run() -> void:
	root.size = Vector2i(1600, 900)
	var document = fixture()
	check(CampaignDocument.validate(document).is_empty(), "valid authored campaign")
	check(equivalent(CampaignDocument.decode(JSON.stringify(document, "", true, true)).document, document), "JSON round trip")
	check(CampaignDocument.validate(CampaignDocument.create()).is_empty(), "new campaign is playable")
	for bad in [null, [], {}, {"format": "unknown"}]: check(not CampaignDocument.validate(bad).is_empty(), "reject malformed root")
	for field in ["id", "title", "description", "missions", "version", "format"]:
		var bad = document.duplicate(true)
		bad[field] = null
		check(not CampaignDocument.validate(bad).is_empty(), "reject null " + field)
	for bad_id in ["../escape", "", "a".repeat(65), "with space"]:
		var bad = document.duplicate(true)
		bad.id = bad_id
		check(not CampaignDocument.validate(bad).is_empty(), "reject unsafe campaign ID")
	var bad = document.duplicate(true)
	bad.missions[1].id = bad.missions[0].id
	check(not CampaignDocument.validate(bad).is_empty(), "duplicate mission IDs")
	bad = document.duplicate(true)
	bad.missions[0].objectives[0].target = "missing"
	check(not CampaignDocument.validate(bad).is_empty(), "delegates contact dependencies to Catalog")
	bad = document.duplicate(true)
	bad.missions = []
	check(not CampaignDocument.validate(bad).is_empty(), "no empty campaign")
	for requirements in [["missing"], ["stage_1"], ["stage_2"], ["stage_0", "stage_0"], [42], "stage_0", null]:
		bad = document.duplicate(true)
		bad.missions[1].requires = requirements
		check(not CampaignDocument.validate(bad).is_empty(), "reject malformed cyclic forward duplicate dependencies")
	bad = document.duplicate(true)
	bad.version = true
	check(not CampaignDocument.validate(bad).is_empty(), "boolean is not version 1")
	check(CampaignDocument.decode(" ".repeat(CampaignDocument.MAX_BYTES + 1)).has("error"), "bounded import")
	check(CampaignDocument.decode("{bad").has("error"), "invalid JSON")
	var deep: Dictionary = {"leaf": "metadata"}
	for i in 16: deep = {"child": deep}
	bad = document.duplicate(true)
	bad.extra = deep
	check(LocalStorage.validate_json(bad), "boundary fixture was valid before embedding")
	check(not CampaignDocument.validate(bad).is_empty(), "content reserves save envelope nesting level")
	var explicit = document.duplicate(true)
	explicit.missions[1].requires = ["stage_0"]
	explicit.missions[2].requires = ["stage_0", "stage_1"]
	check(CampaignDocument.validate(explicit).is_empty(), "DAG prerequisites accepted")
	check(not CampaignDocument.unlocked(explicit, 2, [CampaignDocument.runtime_id(document, "stage_0")]), "all prerequisites required")
	check(CampaignDocument.move_mission(explicit, 0, 1).has("error"), "reorder cannot break references")
	check(CampaignDocument.remove_mission(explicit, 0).has("error"), "cannot delete referenced mission")
	var renamed = explicit.missions[0].duplicate(true)
	renamed.id = "renamed"
	var changed = CampaignDocument.replace_mission(explicit, 0, renamed)
	check(changed.document.missions[1].requires == ["renamed"] and changed.document.missions[2].requires[0] == "renamed", "renames update dependants atomically")
	check(explicit.missions[0].id == "stage_0", "editing never aliases input")
	check(CampaignDocument.move_mission(document, 0, 1).document.missions[1].id == "stage_0", "reorder linear campaign")
	check(CampaignDocument.remove_mission(document, 1).document.missions.size() == 2, "delete independent mission")
	check(CampaignDocument.remove_mission(CampaignDocument.create(), 0).has("error"), "cannot delete last mission")
	explicit.missions[1].requires = []
	check(CampaignDocument.unlocked(explicit, 1, []), "explicit root can start without previous mission")
	var long_ids = document.duplicate(true)
	long_ids.missions[0].id = "a".repeat(63) + "x"
	long_ids.missions[1].id = "a".repeat(63) + "y"
	check(CampaignDocument.playable_missions(long_ids)[0].id != CampaignDocument.playable_missions(long_ids)[1].id, "no prefix truncation collision")
	var other = document.duplicate(true)
	other.id = "different_campaign"
	check(CampaignDocument.runtime_id(other, "stage_0") != CampaignDocument.runtime_id(document, "stage_0"), "campaign namespace isolation")
	var path = "user://campaign-test-content.json"
	check(CampaignDocument.write_document(document, path).is_empty(), "writes document")
	check(equivalent(CampaignDocument.read_document(path).document, document), "file import round trip")
	check(CampaignDocument.write_document(other, path).is_empty(), "updates document atomically")
	check(equivalent(CampaignDocument.read_document(path + ".bak").document, document), "preserves previous document")
	check(not CampaignDocument.write_document(bad, path).is_empty(), "reject invalid document before write")
	check(equivalent(CampaignDocument.read_document(path).document, other), "failed write preserves prior valid file")
	var session = root.get_node("Session")
	session.suppress_saves = true
	check(session.start_campaign(document).ok, "starts real custom campaign")
	session.paused = true
	check(session.sim.state.campaign.completed.is_empty(), "new campaign has fresh progress")
	check(not session.start_mission(1).ok, "host enforces stage unlock")
	check(not session.start_mission(-1).ok and not session.start_mission(30).ok, "index bounds")
	var first_id: String = session.sim.state.mission.id
	for i in 3:
		if i > 0: check(session.start_mission(i).ok, "start unlocked next stage")
		for tick in 3: session.sim.tick(1.0 / 30)
		check(session.sim.state.status == "won", "complete actual authored mission")
		check(session.sim.state.campaign.completed.size() == i + 1, "progress carries between stages")
		check(session.sim.state.campaign_document == document, "host retains authored content")
	var credits = session.sim.state.campaign.credits
	check(session.start_mission(0).ok, "replay authored stage")
	for tick in 3: session.sim.tick(1.0 / 30)
	check(session.sim.state.campaign.credits == credits, "replay cannot duplicate rewards")
	for role in Catalog.ROLES + [""]:
		var snapshot = session.sim.snapshot(role, "recipient")
		check(not snapshot.has("campaign_document"), "document redacted for " + role)
		check(not JSON.stringify(snapshot).contains("stage_2"), "future authored identifier not leaked")
	session._refresh_view()
	check(not session._telemetry_view().has("campaign_document"), "HTTP projection redacted")
	check(LocalStorage.save_state(session.sim.state, "user://campaign-test-save.json").is_empty(), "save authored campaign")
	var restored = LocalStorage.read_state("user://campaign-test-save.json")
	check(restored.has("state") and equivalent(restored.state.campaign_document, document), "restore self-contained campaign")
	session.sim.state = restored.state
	check(session.start_mission(2).ok and session.sim.state.campaign.credits == credits, "continue saved campaign without importing external content")
	var corrupt = session.sim.state.duplicate(true)
	corrupt.campaign_document.missions[2].title = "different mission"
	check(not LocalStorage.validate_state(corrupt).is_empty(), "reject mismatched embedded mission")
	var prior = session.sim.state.duplicate(true)
	check(not session.start_campaign({}).ok and session.sim.state == prior, "invalid start is atomic")
	session.mode = "client"
	check(not session.start_campaign(document).ok and not session.start_mission(0).ok, "client cannot start campaigns or missions")
	check(session.sim.state == prior, "client rejection does not mutate host state")
	check(session.campaign_missions().size() == 1 and not session.campaign_missions()[0].has("contacts"), "client campaign list contains only safe active mission")
	session.mode = "offline"
	check(session.start_mission(0, document.missions[0]).ok, "preview uses existing mission entry point")
	check(not session.sim.state.has("campaign_document") and session.sim.state.campaign.completed.is_empty(), "preview cannot advance authored campaign")
	session.new_campaign()
	check(not session.sim.state.has("campaign_document") and not session.sim.state.mission.id.begins_with("custom_"), "built-in campaign reset remains compatible")
	check(LocalStorage.validate_state(session.sim.state).is_empty(), "old save without authored content valid")
	session.paused = true
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle()
	app._go("campaign")
	await settle()
	var editor: CampaignEditor
	for button in app.find_children("*", "Button", true, false):
		if button.text == "Taller de campañas":
			button.pressed.emit()
			for child in app.get_children():
				if child is CampaignEditor: editor = child
	await settle()
	check(editor != null, "real application opens campaign editor")
	editor.fields.title.text = "Una ruta editada"
	editor._add_mission()
	check(editor.document.missions.size() == 2 and editor.document.title == "Una ruta editada", "UI creates mission and commits metadata")
	editor._move(-1)
	check(editor.selected == 0, "UI reorders selected mission")
	editor._undo()
	check(editor.document.missions.size() == 2, "UI undo retains campaign")
	editor.selected = 1
	editor._refresh()
	editor.linear.button_pressed = false
	editor.dependency_fields.values()[0].button_pressed = true
	editor._apply_dependencies()
	check(editor.document.missions[1].requires == [editor.document.missions[0].id], "UI chooses prerequisite without typing IDs")
	editor._delete()
	for child in editor.get_children():
		if child is ConfirmationDialog: child.confirmed.emit()
	await settle()
	check(editor.document.missions.size() == 1, "UI confirms deletion")
	editor._undo()
	check(editor.document.missions.size() == 2, "UI restores deleted stage")
	editor._edit_mission()
	await settle()
	editor.mission_editor._set_text("Etapa editada", "title")
	editor._apply_mission()
	await settle()
	check(editor.document.missions[editor.selected].title == "Etapa editada", "existing mission editor applies to campaign")
	editor._save_local()
	var local_path = "user://campaigns/" + editor.document.id + ".json"
	check(equivalent(CampaignDocument.read_document(local_path).document, editor.document), "UI local save can reopen")
	editor._file_action = "export"
	editor._file_selected(path)
	check(equivalent(CampaignDocument.read_document(path).document, editor.document), "UI JSON export matches editor")
	editor._file_action = "open"
	editor._file_selected(path)
	check(editor.document.title == "Una ruta editada", "UI imports exported campaign")
	if "--campaign-capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		editor.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../docs/images/campaign-editor.png"))
	for size in [Vector2i(1000, 650), Vector2i(1280, 800)]:
		editor.size = size
		await settle()
		for button in editor.find_children("*", "Button", true, false):
			if button.text == "Cerrar taller": check(button.get_global_rect().end.y <= size.y, "editor close stays in compact viewport")
	# Preview retains the same draft, including unapplied mission edits.
	editor._edit_mission()
	await settle()
	editor.mission_editor._set_text("Borrador para probar", "title")
	editor.mission_editor._play()
	await settle()
	for child in editor.mission_window.get_children():
		if child is ConfirmationDialog: child.confirmed.emit()
	await settle()
	check(not editor.visible and not editor.mission_window.visible, "preview exposes the playable bridge")
	app._go("campaign")
	check(app._open_campaign_editor() == editor, "return reuses draft after page navigation")
	await settle()
	check(editor.mission_editor.mission.title == "Borrador para probar", "preview preserves unapplied edits")
	editor._apply_mission()
	await settle()
	editor._play_campaign()
	await settle()
	var confirmation: ConfirmationDialog
	for child in editor.get_children():
		if child is ConfirmationDialog: confirmation = child
	check(confirmation != null, "playing asks before replacing campaign")
	confirmation.confirmed.emit()
	await settle()
	check(session.sim.state.has("campaign_document") and session.sim.state.campaign_document.title == "Una ruta editada", "UI starts real authored campaign")
	app._go("campaign")
	await settle()
	check(app._content.get_global_rect().end.x <= root.size.x + 1, "campaign list stays within viewport")
	var wide = fixture()
	wide.missions[0].title = "Exploración y encuentro con los navegantes del faro occidental"
	for mission in wide.missions: mission.requires = []
	check(session.start_campaign(wide).ok, "valid long-title campaign starts")
	app._go("campaign")
	await settle()
	check(app._content.get_global_rect().end.x <= root.size.x + 1, "long mission title cannot widen campaign list")
	var embark_buttons = 0
	for button in app.find_children("*", "Button", true, false):
		if button.text == "Embarcar":
			embark_buttons += 1
			check(button.get_global_rect().end.x <= root.size.x, "all three embark actions stay visible")
	check(embark_buttons == 3, "three independent authored stages remain reachable")
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle()
	for target in [path, path + ".bak", local_path, "user://campaign-test-save.json", "user://campaign-test-save.json.bak"]:
		if FileAccess.file_exists(target): DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	print("CAMPAIGN_OK ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)

func run_peer() -> void:
	var args = OS.get_cmdline_user_args()
	var peer_case: String = args[args.find("--campaign-peer") + 1]
	var port = int(args[args.find("--port") + 1])
	var session = root.get_node("Session")
	var document = fixture()
	document.missions[0].contacts.append({"id": "hidden", "name": "ACTIVE_SECRET_CONTACT", "kind": "beacon", "position": [1500, 1500], "known": false})
	document.missions[2].contacts[0].name = "FUTURE_SECRET_CONTACT"
	if peer_case == "host":
		check(session.start_campaign(document).ok, "network host selects custom campaign")
		check(session.host_session(port, "campaign-integration-test-key").ok, "real ENet host starts")
		print("CAMPAIGN_HOST_READY")
		for i in 80:
			if session.roster.size() == 2: break
			await create_timer(0.05).timeout
		check(session.roster.size() == 2, "real authenticated campaign participant")
		await create_timer(0.8).timeout
		check(session.sim.state.campaign_document == document, "network activity cannot replace document")
		check(session.start_mission(1).ok, "host starts unlocked second mission over ENet")
		await create_timer(1.2).timeout
	else:
		check(session.join_session("127.0.0.1", port, "campaign-integration-test-key", "Campaign QA", "navegacion").ok, "real client starts")
		for i in 80:
			if not session.view.is_empty(): break
			await create_timer(0.05).timeout
		check(not session.view.is_empty(), "client receives authored mission")
		if not session.view.is_empty():
			check(session.view.mission.id == CampaignDocument.runtime_id(document, "stage_0"), "client sees active stage only")
			check(not session.start_campaign(document).ok and not session.start_mission(2).ok, "connected client cannot select host campaign")
			check(not session.view.has("campaign_document"), "ENet never sends authoring document")
			var serialized = JSON.stringify(session.view)
			check(not serialized.contains("ACTIVE_SECRET_CONTACT") and not serialized.contains("FUTURE_SECRET_CONTACT"), "ENet redacts active and future hidden contacts")
			check(session.campaign_missions().size() == 1, "client lists no future stage")
			for i in 60:
				if session.view.get("mission", {}).get("id") == CampaignDocument.runtime_id(document, "stage_1"): break
				await create_timer(0.05).timeout
			check(session.view.mission.id == CampaignDocument.runtime_id(document, "stage_1"), "host transition reaches actual client")
			check(not session.view.has("campaign_document"), "transition keeps document private")
	session.close_session()
	print("CAMPAIGN_PEER_OK ", peer_case, " checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
