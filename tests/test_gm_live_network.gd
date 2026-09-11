extends SceneTree
var checks = 0
var failures = 0
var session: Node
var role = ""
var folder = ""
const KEY = "synthetic-gm-network-key"
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("GM_NETWORK_FAIL " + label)
func delay() -> void: await create_timer(0.05).timeout
func wait_until(predicate: Callable, label: String) -> void:
	var deadline = Time.get_ticks_msec() + 10000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await delay()
	check(predicate.call(), label)
func flag(name: String) -> void:
	var file = FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	check(file != null, "synthetic synchronization file")
	if file != null:
		file.store_string("complete")
		file.close()
func run() -> void:
	var args = OS.get_cmdline_user_args()
	role = args[args.find("--gm-case") + 1]
	var port = int(args[args.find("--gm-port") + 1])
	folder = args[args.find("--gm-sync") + 1]
	session = root.get_node("Session")
	if role == "host":
		check(session.host_session(port, KEY).ok, "host starts")
		var result = GMLiveActions.dispatch(session, "spawn", {"id":"gm_visible", "name":"Visible spacecraft", "kind":"friendly", "x":1200.0, "y":900.0, "identified":true, "visual_model":"frontier/haizea_scout"})
		check(result.ok, "host authors library skin")
		result = GMLiveActions.dispatch(session, "spawn", {"id":"gm_secret", "name":"SYNTHETIC_GM_SECRET", "kind":"hostile", "x":9000.0, "y":9000.0, "identified":false, "visual_model":"orbita/karramarro_tug"})
		check(result.ok, "host authors hidden contact")
		print("GM_NETWORK_HOST_READY")
		await wait_until(func(): return FileAccess.file_exists(folder.path_join("phase-one")), "client inspected initial view")
		check(session.sim.contact("spoofed").is_empty(), "remote commands cannot author contacts")
		check(not JSON.stringify(session.sim.state.events).contains("SPOOFED_MESSAGE"), "remote commands cannot publish GM messages")
		check(LocalStorage.validate_state(session.sim.state).is_empty(), "live network state remains saveable")
		check(GMLiveActions.dispatch(session, "remove", {"id":"gm_visible"}).ok, "host removes dynamic contact")
		await wait_until(func(): return FileAccess.file_exists(folder.path_join("finished")), "client observes removal")
	else:
		var responses: Array = []
		session.notice.connect(func(message, ok): responses.append({"message":message, "ok":ok}))
		check(session.join_session("127.0.0.1", port, KEY, "Synthetic client", "navegacion").ok, "client starts")
		await wait_until(func(): return session.view.get("contacts", []).any(func(c): return c.id == "gm_visible"), "client receives current host snapshot")
		if not session.view.is_empty():
			check(not session.view.has("gm_live"), "private GM delta absent in actual RPC")
			check(not session.view.mission.has("contacts"), "mission source absent in actual RPC")
			check(not JSON.stringify(session.view).contains("SYNTHETIC_GM_SECRET"), "hidden name absent in actual RPC")
			var visible: Dictionary = {}
			var hidden: Dictionary = {}
			for c in session.view.contacts:
				if c.id == "gm_visible": visible = c
				if c.id == "gm_secret": hidden = c
			check(visible.get("visual_model") == "frontier/haizea_scout", "public model ID replicated")
			check(not hidden.has("visual_model") and hidden.get("kind") == "unknown", "hidden model identity not replicated")
			var visual = RuntimeAssetLibrary.contact_model(str(visible.get("visual_model", "")), str(visible.get("kind", "")), 28.0)
			check(visual != null, "client can instantiate replicated visual")
			if visual != null: visual.free()
		check(not GMLiveActions.dispatch(session, "spawn", {}).ok, "client local entry point denied")
		session.order("spawn", {"id":"spoofed"})
		session.order("gm_message", {"text":"SPOOFED_MESSAGE"})
		await wait_until(func(): return responses.filter(func(item): return not item.ok).size() >= 2, "remote authoring attempts rejected by existing authority")
		flag("phase-one")
		await wait_until(func(): return not session.view.get("contacts", []).any(func(c): return c.id == "gm_visible"), "removal replicated")
		flag("finished")
	session.close_session()
	print("GM_NETWORK_RESULT case=%s checks=%d failures=%d" % [role, checks, failures])
	quit(1 if failures else 0)
