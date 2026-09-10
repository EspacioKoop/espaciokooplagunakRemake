class_name ReactiveScore
extends Node
signal changed
const PREFERENCES_PATH = "user://reactive_music.json"
const CROSSFADE_SECONDS = 2.0
var preferences = ScoreComposer.validate_preferences({})
var current_theme = "bridge"
var player: AudioStreamPlayer
var panel: ScorePanel
var settings_button: Button
var _playback: AudioStreamGeneratorPlayback
var _composer = ScoreComposer.new()
var _previous: ScoreComposer
var _blend = 1.0
var _poll = 0.0
var _pending_theme = "bridge"
var _pending_seconds = 0.0
var _gain = 0.0
var _audio_enabled = false
var _app: Node

func _ready() -> void:
	_app = get_parent()
	if "--server" in OS.get_cmdline_user_args():
		set_process(false)
		set_process_input(false)
		return
	if "--test" not in OS.get_cmdline_user_args(): load_preferences()
	player = AudioStreamPlayer.new()
	player.name = "ProceduralMusic"
	player.bus = "Master"
	player.volume_db = -10.0
	add_child(player)
	_audio_enabled = DisplayServer.get_name() != "headless" and "--test" not in OS.get_cmdline_user_args() and "--capture" not in OS.get_cmdline_user_args()
	if not InputMap.has_action("music_settings"):
		InputMap.add_action("music_settings")
		var key = InputEventKey.new()
		key.physical_keycode = KEY_F12
		InputMap.action_add_event("music_settings", key)
	if _audio_enabled and preferences.enabled: _start_audio()

func _start_audio() -> void:
	if player == null or player.playing: return
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = ScoreComposer.RATE
	stream.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	stream.buffer_length = 0.25
	player.stream = stream
	player.play()
	_playback = player.get_stream_playback()
	_gain = 0.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("music_settings") and not event.is_echo():
		open_panel()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.25:
		_poll = 0.0
		_attach_settings_button()
		var view: Dictionary = {}
		var session = get_tree().root.get_node_or_null("Session")
		if session != null: view = session.view
		var zone = -1
		if is_instance_valid(_app) and is_instance_valid(_app.get("_deck")):
			var deck = _app.get("_deck")
			if deck.is_visible_in_tree(): zone = int(deck.zone)
		var desired = ScoreComposer.select_theme(view, zone) if preferences.mode == "auto" else str(preferences.mode)
		if desired != _pending_theme:
			_pending_theme = desired
			_pending_seconds = 0.0
		else: _pending_seconds += 0.25
		if desired != current_theme and (desired == "tension" or _pending_seconds >= 1.0): set_theme(desired)
	if not _audio_enabled or _playback == null: return
	var target_gain = float(preferences.volume) / 100.0 if preferences.enabled else 0.0
	var frames = mini(_playback.get_frames_available(), 4096)
	for i in frames:
		_gain = move_toward(_gain, target_gain, 1.0 / (ScoreComposer.RATE * 0.08))
		var sample = _composer.next_frame()
		if _previous != null:
			_blend = minf(1.0, _blend + 1.0 / (ScoreComposer.RATE * CROSSFADE_SECONDS))
			var smooth = _blend * _blend * (3.0 - 2.0 * _blend)
			sample = _previous.next_frame().lerp(sample, smooth)
			if _blend >= 1.0: _previous = null
		_playback.push_frame(sample * _gain)
	if not preferences.enabled and _gain <= 0.0:
		player.stop()
		_playback = null
		_previous = null

func set_theme(value: String) -> void:
	if value not in ScoreComposer.THEMES or value == current_theme: return
	# One crossfade at a time; _process retries the most recent view afterward.
	if _previous != null and _audio_enabled and is_instance_valid(player) and player.playing: return
	_previous = _composer if _audio_enabled and is_instance_valid(player) and player.playing else null
	_composer = ScoreComposer.new(value)
	_blend = 0.0
	current_theme = value
	changed.emit()

func update_preferences(value: Dictionary, persist: bool = true) -> String:
	preferences = ScoreComposer.validate_preferences(value)
	if preferences.mode != "auto": set_theme(preferences.mode)
	if _audio_enabled and preferences.enabled: _start_audio()
	changed.emit()
	return save_preferences() if persist else ""

func load_preferences(path: String = PREFERENCES_PATH) -> void:
	if not FileAccess.file_exists(path): return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 2048: return
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		preferences = ScoreComposer.validate_preferences(json.data)

func save_preferences(path: String = PREFERENCES_PATH) -> String:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return "No se pudo guardar el ajuste de música."
	file.store_string(JSON.stringify(preferences))
	file.close()
	return ""

func _attach_settings_button() -> void:
	if not is_instance_valid(_app) or _app.get("_page") != "settings": return
	if is_instance_valid(settings_button) and not settings_button.is_queued_for_deletion(): return
	var content = _app.get("_content")
	if not is_instance_valid(content): return
	settings_button = ConsoleUI.button("Música de a bordo · F12", open_panel)
	settings_button.name = "MusicSettings"
	content.add_child(settings_button)

func open_panel() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not is_instance_valid(panel):
		panel = ScorePanel.new()
		panel.score = self
		add_child(panel)
	panel.sync()
	panel.popup_centered(Vector2i(520, 320))

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null
	_playback = null
