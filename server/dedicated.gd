extends SceneTree
## Deployment adapter only. Session remains the simulation/network/save authority.
var session: Node
var runtime = ""
var ready = false
var heartbeat = 0.0

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	# Configuration errors never contain credentials or untrusted file contents.
	printerr("SERVER_ERROR: " + message)
	ready = false
	quit(2)

func run() -> void:
	session = root.get_node("Session")
	runtime = OS.get_environment("LAGUNAK_RUNTIME_DIR")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("LAGUNAK_SETTINGS")))
	if not parsed is Dictionary or parsed.size() != 5 or parsed.get("version") != 1 or not parsed.get("port") is float or parsed.port != floorf(parsed.port) or parsed.port < 1024 or parsed.port > 65535 or parsed.get("load_mode") not in ["auto", "new", "resume"] or not parsed.get("mission_index") is float or parsed.mission_index != floorf(parsed.mission_index) or parsed.mission_index < -1 or parsed.mission_index > 255 or not parsed.get("key_file") is String:
		fail("Invalid deployment settings"); return
	var key_source = FileAccess.open(parsed.key_file, FileAccess.READ)
	if key_source == null or key_source.get_length() > 130: fail("Invalid key file"); return
	var key = key_source.get_as_text().strip_edges()
	key_source.close()
	if key.length() < 16 or key.length() > 128:
		fail("Invalid key file"); return
	for character in key:
		if character.unicode_at(0) < 33 or character.unicode_at(0) > 126: fail("Invalid key file"); return
	# Preserve corrupt saves for recovery instead of silently creating a new campaign.
	var has_save = FileAccess.file_exists("user://campaign.json") or FileAccess.file_exists("user://campaign.json.bak")
	if parsed.load_mode == "new" and has_save: fail("New mode requires an empty campaign volume"); return
	if parsed.load_mode == "resume" and not has_save: fail("Resume requires an existing campaign"); return
	if FileAccess.file_exists(ExpeditionSystems.PATH):
		var expedition = JSON.parse_string(FileAccess.get_file_as_string(ExpeditionSystems.PATH))
		if not expedition is Dictionary or expedition.get("format") != ExpeditionSystems.FORMAT or expedition.get("version") != ExpeditionSystems.VERSION or not LocalStorage.validate_json(expedition): fail("Invalid expedition save; restore the volume backup"); return
	session.role = "" # No native station is reserved for the headless observer.
	if has_save:
		if not session.resume_game().ok: fail("Campaign save and backup could not be resumed"); return
	else:
		session.new_campaign()
	if parsed.mission_index >= 0:
		if not session.mission_unlocked(int(parsed.mission_index)): fail("Requested mission is locked or missing"); return
		var missions: Array = session.campaign_missions()
		if session.sim.state.mission.id != missions[int(parsed.mission_index)].id:
			if not session.start_mission(int(parsed.mission_index)).ok: fail("Cannot start requested mission"); return
	if not session.host_session(int(parsed.port), key).ok: fail("Cannot listen on the ENet port"); return
	key = ""
	session.roster[1].name = "Servidor"
	session._refresh_view()
	if not session.save_game().ok: fail("Campaign persistence is unavailable"); return
	ready = true
	write_heartbeat()
	print("SERVER_READY port=%d" % int(parsed.port))

func _process(delta: float) -> bool:
	if not ready: return false
	if FileAccess.file_exists(runtime.path_join("stop")):
		ready = false
		var saved: Dictionary = session.save_game()
		var expedition = root.get_node("Expedition")
		expedition.save()
		var stored = JSON.parse_string(FileAccess.get_file_as_string(ExpeditionSystems.PATH))
		if not saved.ok: fail("Campaign save failed"); return false
		if stored != JSON.parse_string(JSON.stringify(expedition.data)):
			fail("Expedition save failed"); return false
		print("SERVER_STOPPED saved=true")
		quit(0)
		return false
	heartbeat += delta
	if heartbeat >= 1.0:
		heartbeat = 0.0
		write_heartbeat()
	return false

func write_heartbeat() -> void:
	if session.mode != "host" or session.multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		fail("Native host is no longer connected"); return
	var temporary = runtime.path_join("health.json.tmp")
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: fail("Cannot write health heartbeat"); return
	file.store_string(JSON.stringify({"version": 1, "host": true, "pid": OS.get_process_id()}))
	file.close()
	if DirAccess.rename_absolute(temporary, runtime.path_join("health.json")) != OK: fail("Cannot publish health heartbeat")
