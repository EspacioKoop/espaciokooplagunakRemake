extends SceneTree
## Real ENet identities exercise the existing profile_set authority, never a mock.

var session: Node
var expedition: Node
var crew: Node
var checks = 0
var failures = 0
var responses: Array = []
var accepted = false
const PROGRESS = {"xp": 7, "level": 3, "condition": 63, "focus": 1,
	"traits": ["jakinmina"], "milestones": ["Guardia verificada"]}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CHARACTER_NETWORK_FAIL " + label)

func wait_until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return predicate.call()

func progress_matches(profile: Dictionary) -> bool:
	for key in PROGRESS:
		if profile.get(key) != PROGRESS[key]: return false
	return true

func own() -> Dictionary:
	return expedition.data.profiles.get(str(session.multiplayer.get_unique_id()), {})

func run() -> void:
	session = root.get_node("Session")
	expedition = root.get_node("Expedition")
	crew = root.get_node("Crew")
	expedition.data = expedition._default_data()
	var args = OS.get_cmdline_user_args()
	var mode = args[args.find("--case") + 1]
	var port = int(args[args.find("--port") + 1])
	expedition.notice.connect(func(message, ok): responses.append({"message": message, "ok": ok}))
	session.joined.connect(func(): accepted = true)
	if mode == "host":
		await host_case(port)
	else:
		await client_case(mode, port)
	session.close_session()
	# Expedition._exit_tree saves even under --test; the Python runner isolates XDG.
	print("CHARACTER_NETWORK_RESULT ", mode, " checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func host_case(port: int) -> void:
	check(session.host_session(port, "character-editor-ephemeral-fixture").ok, "host binds exclusive test port")
	var host_profile: Dictionary = expedition.profile("1")
	host_profile.name = "Capitana intacta"
	for key in PROGRESS: host_profile[key] = PROGRESS[key].duplicate(true) if PROGRESS[key] is Array else PROGRESS[key]
	var expected_host = host_profile.duplicate(true)
	var seeded: Array = ["1"]
	print("CHARACTER_HOST_READY")
	var deadline = Time.get_ticks_msec() + 22000
	var finished = false
	while Time.get_ticks_msec() < deadline:
		for peer in session.roster:
			var actor = str(peer)
			if actor in seeded: continue
			var profile: Dictionary = expedition.profile(actor)
			for key in PROGRESS: profile[key] = PROGRESS[key].duplicate(true) if PROGRESS[key] is Array else PROGRESS[key]
			seeded.append(actor)
		var completed = 0
		for actor in seeded:
			if expedition.data.profiles[actor].name in ["Ane lista", "Beñat listo"]: completed += 1
		if completed == 2:
			finished = true
			break
		await create_timer(0.05).timeout
	check(finished and seeded.size() == 3, "both real clients finish their character edits")
	check(expedition.profile("1") == expected_host, "injected actor=1 never edits the host profile")
	for actor in seeded:
		check(progress_matches(expedition.profile(actor)), "host preserves every progression field for " + actor)
		if actor != "1":
			check(expedition.profile(actor).skills == {"pilotaje": 4, "ciencia": 3, "ingenieria": 2, "negociacion": 2, "combate": 1}, "validated authored skills persist on authority")
	expedition.save()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(ExpeditionSystems.PATH))
	var expected_persisted = JSON.parse_string(JSON.stringify(expedition.data.profiles))
	check(saved is Dictionary and saved.get("profiles") == expected_persisted, "host persists the authoritative profiles through JSON numeric conversion")
	await create_timer(2.0).timeout

func client_case(mode: String, port: int) -> void:
	var role = "navegacion" if mode == "nav" else "ingenieria"
	var authored_name = "Ane" if mode == "nav" else "Beñat"
	var final_name = "Ane lista" if mode == "nav" else "Beñat listo"
	check(session.join_session("127.0.0.1", port, "character-editor-ephemeral-fixture", authored_name, role).ok, "client starts real handshake")
	var ready = await wait_until(func(): return accepted and progress_matches(own()))
	check(ready, "authenticated client receives its seeded host-owned profile")
	if not ready: return
	var before = own().duplicate(true)
	var fields = CharacterDocument.editable_from_profile(own())
	fields.name = authored_name
	fields.approach = "tecnica"
	fields.skills = {"pilotaje": 4, "ciencia": 3, "ingenieria": 2, "negociacion": 2, "combate": 1}
	var payload = CharacterDocument.command_args(fields)
	check(payload.size() == 7 and not payload.has("actor") and not payload.has("xp"), "portable document emits only seven editable command fields")
	var console = CrewConsole.new()
	console.crew = crew
	root.gui_embed_subwindows = true
	root.add_child(console)
	console.popup_centered()
	var editor = console._open_character_editor()
	editor.fields.name.text = fields.name
	editor.fields.approach.select(ExpeditionSystems.APPROACHES.find(fields.approach))
	for skill in ExpeditionSystems.SKILLS: editor.fields[skill].value = fields.skills[skill]
	editor._draft_changed()
	var draft = editor.read_document()
	await create_timer(0.65).timeout
	check(editor.read_document() == draft, "periodic host snapshots preserve the open UI draft")
	editor.apply_button.pressed.emit()
	check(editor.pending and editor.last_apply_state == "pending", "UI does not treat a queued RPC as confirmation")
	check(await wait_until(func(): return editor.last_apply_state == "confirmed"), "UI waits for the concordant authoritative profile")
	check(own().get("name") == authored_name, "authoritative snapshot acknowledges authored name")
	check(not editor.pending and not editor.is_dirty(), "confirmed client draft becomes clean")
	editor.request_close()
	console.queue_free()
	await process_frame
	check(CharacterDocument.editable_from_profile(own()) == fields, "host echoes the exact validated edit")
	check(progress_matches(own()), "editing cannot replace existing progression")
	var exported = CharacterDocument.document(CharacterDocument.editable_from_profile(own()))
	check(exported.character.keys().size() == 3 and not JSON.stringify(exported).contains("Guardia verificada"), "export contains no runtime progression or other profile")
	# Invalid values must also be rejected at the host, bypassing the UI validator.
	for bad_value in [4, 1.5, "4"]:
		var invalid = payload.duplicate(true)
		if bad_value is int:
			for skill in ExpeditionSystems.SKILLS: invalid[skill] = 4
		else: invalid.pilotaje = bad_value
		var count = responses.size()
		expedition.command("profile_set", invalid)
		check(await wait_until(func(): return responses.size() > count), "invalid RPC receives a host response")
		check(not responses.back().ok, "host rejects over-budget, fractional or nonnumeric skills")
		check(CharacterDocument.editable_from_profile(own()) == fields, "invalid RPC leaves profile unchanged")
	# Even raw clients cannot select a different principal or inject progression.
	var injected = payload.duplicate(true)
	injected.name = final_name
	injected.actor = "1"
	injected.xp = 99999
	injected.condition = 100
	expedition.command("profile_set", injected)
	check(await wait_until(func(): return own().get("name") == final_name), "sender principal overrides any actor argument")
	check(progress_matches(own()) and own().xp == before.xp, "untrusted progression parameters are ignored by authority")
	check(expedition.data.profiles.get("1", {}).get("name") == "Capitana intacta", "client observes unchanged host character")
	check(session.role == role, "character editing cannot reassign the operational station")
