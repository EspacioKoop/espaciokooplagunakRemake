extends SceneTree
var checks = 0
var failures = 0
var app: Control
var session: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("GM_LIVE_UI_FAIL " + label)
func frames(count: int = 3) -> void:
	for i in count: await process_frame
func capture(filename: String) -> void:
	var folder = OS.get_environment("GM_LIVE_CAPTURE_DIR")
	if folder.is_empty(): return
	check(DisplayServer.get_name() != "headless", "capture requires a graphical display")
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(filename)) == OK, "current run screenshot saved")

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1600, 900)
	if "--require-display" in OS.get_cmdline_user_args():
		check(DisplayServer.get_name() != "headless", "real display required")
	session = root.get_node("Session")
	session.suppress_saves = true
	for child in root.get_children():
		child.set_process(false)
		child.set_physics_process(false)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app._new_game()
	session.paused = true
	await frames()
	var launcher = app.find_child("GMConsoleLauncher", true, false)
	check(launcher != null and not launcher.disabled, "real bridge exposes host GM launcher")
	launcher.grab_focus()
	launcher.pressed.emit()
	await frames()
	var window = app._gm_window
	check(is_instance_valid(window) and window.visible, "launcher opens actual GM modal")
	check(window.exclusive and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "modal releases pointer and owns input")
	app._open_gm_console()
	check(app._gm_window == window, "GM window is a singleton")
	window.contact_id.text = "gm_ui_contact"
	window.contact_name.text = "Nave de apoyo"
	window.identified.button_pressed = true
	for index in window.visual.item_count:
		if window.visual.get_item_metadata(index) == "frontier/haizea_scout": window.visual.select(index)
	window.find_child("GMSpawn", true, false).pressed.emit()
	check(not session.sim.contact("gm_ui_contact").is_empty(), "actual create button authors contact: " + window.notice.text)
	if session.sim.contact("gm_ui_contact").is_empty():
		print("GM_LIVE_UI_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	check(session.sim.contact("gm_ui_contact").visual_model == "frontier/haizea_scout", "UI preserves selected model ID")
	app._space._process(0.0)
	check(app._space.contacts["gm_ui_contact"].visual_model == "frontier/haizea_scout", "space renderer uses library skin")
	check(LocalStorage.validate_state(session.sim.state).is_empty(), "UI-authored state is saveable")
	var index = window._ids.find("gm_ui_contact")
	window.listing.select(index)
	window._select(index)
	session.sim.contact("gm_ui_contact").position = [2000.0, 50.0]
	session.sim.contact("gm_ui_contact").hull = 90.0
	window.contact_name.text = "Apoyo renombrado"
	window.find_child("GMModify", true, false).pressed.emit()
	check(session.sim.contact("gm_ui_contact").name == "Apoyo renombrado", "actual modify button renames")
	check(session.sim.contact("gm_ui_contact").position == [2000.0, 50.0] and session.sim.contact("gm_ui_contact").hull == 90.0, "unmodified fields do not overwrite live changes")
	window.event_kind.select(0)
	window.event_value.text = "ambar"
	window._trigger_event()
	check(session.view.ship.alert == "ambar", "UI event updates authoritative snapshot")
	var before = var_to_bytes(session.sim.state)
	window.event_kind.select(4)
	window.event_value.text = "1.5"
	window._trigger_event()
	check(var_to_bytes(session.sim.state) == before, "fractional reinforcement UI input rejected")
	window.find_child("GMRemove", true, false).pressed.emit()
	check(window._confirmation.visible, "removal requires confirmation")
	window._confirmation.canceled.emit()
	window._confirmation.hide()
	check(not session.sim.contact("gm_ui_contact").is_empty(), "cancel leaves contact intact")
	window.size = Vector2i(760, 540)
	await frames()
	window.contact_name.grab_focus()
	check(window.contact_name.has_focus(), "small window supports keyboard editing")
	window.size = Vector2i(1060, 740)
	await frames()
	window.notice.text = "Modelo seleccionado y cambios guardables en la misión activa."
	window._select(window._ids.find("gm_ui_contact"))
	await frames()
	await capture("gm-live.png")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	window.push_input(escape)
	await frames()
	check(not is_instance_valid(window), "Escape closes GM window")
	check(launcher.has_focus(), "modal focus returns to launcher")
	app._open_gm_console()
	await frames()
	window = app._gm_window
	var previous_run = window.run_id
	session.new_campaign()
	before = var_to_bytes(session.sim.state)
	check(not GMLiveActions.dispatch(session, "message", {"text":"stale"}, previous_run).ok, "stale run rejected")
	check(var_to_bytes(session.sim.state) == before, "stale request does not mutate new mission")
	await frames()
	check(not is_instance_valid(window), "mission change closes stale modal")
	session.mode = "client"
	before = var_to_bytes(session.sim.state)
	app._open_gm_console()
	check(not is_instance_valid(app._gm_window), "client cannot open GM")
	check(not GMLiveActions.dispatch(session, "spawn", {"id":"spoofed"}).ok, "client cannot dispatch GM actions")
	check(var_to_bytes(session.sim.state) == before, "client rejection has no effects")
	session.mode = "offline"
	app._go("editor")
	var library_button = app.find_child("AssetLibraryLauncher", true, false)
	check(library_button != null, "native editor exposes library")
	library_button.grab_focus()
	before = var_to_bytes(session.sim.state)
	library_button.pressed.emit()
	await frames()
	var library = app._asset_window
	check(is_instance_valid(library) and library.visible, "real library modal opens")
	check(library.listing.item_count == 78, "complete registered library shown")
	library.search.text = "haizea"
	library.search.text_changed.emit(library.search.text)
	await frames()
	check(library.listing.item_count == 1, "library search filters by title")
	check(library.preview.model_id == "frontier/haizea_scout", "search renders the real matching GLB")
	await capture("runtime-asset-library.png")
	library.search.text = "not-a-real-model"
	library.search.text_changed.emit(library.search.text)
	check(library.listing.item_count == 0, "no-match search does not fabricate assets")
	library.search.text = "soros"
	library.search.text_changed.emit(library.search.text)
	await frames()
	check(library.preview.model_id == "fieldkit/soros_medkit", "equipment can be inspected independently")
	library.preview.set_animation(true)
	await frames()
	library.preview.set_animation(false)
	check(var_to_bytes(session.sim.state) == before, "library inspection never mutates campaign")
	library.push_input(escape)
	await frames()
	check(not is_instance_valid(library) and library_button.has_focus(), "library closes and restores focus")
	app.queue_free()
	await frames(4)
	print("GM_LIVE_UI_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
