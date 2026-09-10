extends Node
## Cosmetic channel, gated by Session's authenticated roster. It never reads
## campaign profiles, cards, dice, credentials or lounge identities.
signal changed

var local_profile = AvatarProfile.defaults()
var storage_path = AvatarProfile.PATH
var load_message = ""
var profiles: Dictionary = {}
var editor: Window
var _bound: Dictionary = {}
var _subscribers: Dictionary = {}
var _rates: Dictionary = {}
var _mode = ""
var _pending = true
var _clock = 0.0
var _session: Node

func _ready() -> void:
	var loaded = AvatarProfile.read_profile(storage_path)
	local_profile = loaded.profile
	if not loaded.ok: load_message = loaded.message + " Se usa el avatar Itsaso."
	_session = get_node_or_null("/root/Session")
	if _session != null:
		_session.updated.connect(_sync_session)
		_session.joined.connect(func(): _pending = true)
	if not InputMap.has_action("avatar_editor"):
		InputMap.add_action("avatar_editor")
		var key = InputEventKey.new()
		key.physical_keycode = KEY_A
		key.alt_pressed = true
		InputMap.action_add_event("avatar_editor", key)
	_sync_session()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("avatar_editor") and not event.is_echo():
		open_editor()
		get_viewport().set_input_as_handled()

func open_editor() -> Window:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(editor):
		editor.popup_centered()
		return editor
	editor = AvatarEditor.new()
	editor.service = self
	add_child(editor)
	editor.popup_centered()
	return editor

func save_local(value: Variant) -> Dictionary:
	var error = AvatarProfile.save_profile(value, storage_path)
	if not error.is_empty(): return {"ok": false, "message": error}
	local_profile = value.duplicate(true)
	_pending = true
	_sync_session()
	_refresh_bound()
	changed.emit()
	return {"ok": true, "message": "Avatar guardado."}

func profile_for(peer_id: int) -> Dictionary:
	if peer_id == multiplayer.get_unique_id(): return local_profile.duplicate(true)
	return profiles.get(peer_id, AvatarProfile.defaults()).duplicate(true)

func bind_avatar(avatar: Node3D, peer_id: int) -> void:
	_bound[avatar.get_instance_id()] = {"node": weakref(avatar), "peer": peer_id}
	AvatarAppearance.apply(avatar, profile_for(peer_id))

func _refresh_bound() -> void:
	for key in _bound.keys():
		var avatar = _bound[key].node.get_ref()
		if avatar == null: _bound.erase(key)
		else: AvatarAppearance.apply(avatar, profile_for(_bound[key].peer))

func _sync_session() -> void:
	if _session == null: return
	if _mode != _session.mode:
		_mode = _session.mode
		profiles.clear()
		_subscribers.clear()
		_rates.clear()
		_pending = true
		_refresh_bound()
	if _mode != "host": return
	var dirty = profiles.get(1, {}) != local_profile
	profiles[1] = local_profile.duplicate(true)
	for peer_id in profiles.keys():
		if not _session.roster.has(peer_id):
			profiles.erase(peer_id)
			_subscribers.erase(peer_id)
			_rates.erase(peer_id)
			dirty = true
	if dirty: _publish()

func _process(delta: float) -> void:
	_sync_session()
	_clock += delta
	if _clock < 0.5: return
	_clock = 0
	_refresh_bound()
	if _mode == "client" and _pending and _session.connection_status.begins_with("Conectado"):
		_submit.rpc_id(1, JSON.stringify(local_profile).to_utf8_buffer())

@rpc("any_peer", "call_remote", "reliable", 0)
func _submit(data: PackedByteArray) -> void:
	if _session == null or _session.mode != "host": return
	var peer_id = multiplayer.get_remote_sender_id()
	# The RPC has no target/user parameter: only its transport sender may change.
	if not _session.roster.has(peer_id): return
	var now = Time.get_ticks_msec()
	if now - int(_rates.get(peer_id, -1000)) < 250: return
	_rates[peer_id] = now
	var decoded = AvatarProfile.decode(data)
	if not decoded.ok: return
	profiles[peer_id] = decoded.profile.duplicate(true)
	_subscribers[peer_id] = true
	_publish()

func _publish() -> void:
	_refresh_bound()
	changed.emit()
	if _mode != "host": return
	var packet = JSON.stringify({"version": 1, "profiles": profiles}).to_utf8_buffer()
	for peer_id in _subscribers:
		if _session.roster.has(peer_id) and peer_id in multiplayer.get_peers():
			_receive.rpc_id(peer_id, packet)

@rpc("authority", "call_remote", "reliable", 0)
func _receive(data: PackedByteArray) -> void:
	if _session == null or _session.mode != "client" or multiplayer.get_remote_sender_id() != 1: return
	if data.is_empty() or data.size() > 8192: return
	var json = JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK: return
	var value = json.data
	if not value is Dictionary or value.size() != 2 or value.get("version") != 1: return
	if not value.get("profiles") is Dictionary or value.profiles.size() > 9: return
	var accepted: Dictionary = {}
	for key in value.profiles:
		if not key is String or not key.is_valid_int(): return
		var peer_id = int(key)
		if peer_id < 1 or peer_id > 2147483647 or str(peer_id) != key: return
		if not AvatarProfile.validate(value.profiles[key]).is_empty(): return
		var decoded = AvatarProfile.decode(JSON.stringify(value.profiles[key]).to_utf8_buffer())
		if not decoded.ok: return
		accepted[peer_id] = decoded.profile
	profiles = accepted
	_pending = profiles.get(multiplayer.get_unique_id(), {}) != local_profile
	_refresh_bound()
	changed.emit()
