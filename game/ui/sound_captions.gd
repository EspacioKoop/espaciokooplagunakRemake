class_name SoundCaptions
extends CanvasLayer
## Non-interactive local captions emitted from the same call as the audio cue.

var profile = SoundCaptionProfile.DEFAULTS.duplicate()
var profile_path = SoundCaptionProfile.PATH
var queue = SoundCaptionQueue.new()
var panel: PanelContainer
var caption_label: Label
var settings: AcceptDialog
var enabled_control: CheckBox
var duration_control: SpinBox
var preview_label: Label
var status_label: Label
var _layout: Control
var _locale = ""

func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		set_process(false)
		return
	layer = 6
	profile = SoundCaptionProfile.read_profile(profile_path)
	_layout = Control.new()
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layout)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background = StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.035, 0.05, 1.0)
	background.set_corner_radius_all(6)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: background.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", background)
	_layout.add_child(panel)
	caption_label = Label.new()
	caption_label.name = "SoundCaptionText"
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_label.add_theme_color_override("font_color", Color.WHITE)
	caption_label.add_theme_font_size_override("font_size", 20)
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(caption_label)
	panel.hide()
	_layout.resized.connect(_place_panel)
	panel.minimum_size_changed.connect(_place_panel)
	_place_panel()

func _place_panel() -> void:
	if panel == null: return
	var bounds = get_viewport().get_visible_rect().size
	var width = minf(640.0, maxf(120.0, bounds.x - 48.0))
	panel.size.x = width
	panel.size.y = panel.get_combined_minimum_size().y
	panel.position = Vector2((bounds.x - width) * 0.5, maxf(0.0, bounds.y - panel.size.y - 62.0))

func present(cue: String) -> void:
	if panel == null or not profile.enabled: return
	if queue.push(cue, Time.get_ticks_msec() / 1000.0, profile.duration): _refresh()

func clear() -> void:
	queue.clear()
	_refresh()

func _process(_delta: float) -> void:
	if panel == null: return
	var locale = TranslationServer.get_locale()
	if queue.expire(Time.get_ticks_msec() / 1000.0) or locale != _locale: _refresh()

func _refresh() -> void:
	if panel == null: return
	_locale = TranslationServer.get_locale()
	caption_label.text = "\n".join(queue.lines(_locale))
	panel.visible = profile.enabled and not caption_label.text.is_empty()
	_place_panel()

func _text(spanish: String, english: String) -> String:
	return english if TranslationServer.get_locale().begins_with("en") else spanish

func open_settings() -> void:
	if settings != null and is_instance_valid(settings):
		settings.popup_centered()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings = AcceptDialog.new()
	settings.name = "SoundCaptionSettings"
	settings.theme = ConsoleUI.make_theme()
	settings.title = _text("Subtítulos de avisos sonoros", "Sound captions")
	settings.ok_button_text = _text("Cerrar", "Close")
	settings.min_size = Vector2i(400, 330)
	settings.size = Vector2i(590, 420)
	settings.transient = true
	settings.exclusive = true
	add_child(settings)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_right = -16
	scroll.offset_top = 16
	scroll.offset_bottom = -56
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	enabled_control = CheckBox.new()
	enabled_control.text = _text("Mostrar subtítulos de sonidos", "Show sound captions")
	enabled_control.button_pressed = profile.enabled
	column.add_child(enabled_control)
	var explanation = Label.new()
	explanation.text = _text("Avisos de consola, pulso, torpedo, sensores y atraque. Funcionan con el volumen a cero. No transcriben voz ni conversaciones.", "Console, pulse, torpedo, sensor and docking cues. Works when muted. Does not transcribe speech or conversations.")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)
	var duration_label = Label.new()
	duration_label.text = _text("Duración en segundos (2–12)", "Duration in seconds (2–12)")
	column.add_child(duration_label)
	duration_control = SpinBox.new()
	duration_control.min_value = 2
	duration_control.max_value = 12
	duration_control.step = 1
	duration_control.value = profile.duration
	column.add_child(duration_control)
	preview_label = Label.new()
	preview_label.text = _text("Vista previa: [Sonido] Barrido de sensores", "Preview: [Sound] Sensor sweep")
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(preview_label)
	var reset = Button.new()
	reset.text = _text("Restablecer valores", "Restore defaults")
	column.add_child(reset)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	enabled_control.toggled.connect(func(value):
		profile.enabled = value
		clear()
		_save())
	duration_control.value_changed.connect(func(value):
		profile.duration = value
		_save())
	reset.pressed.connect(func():
		profile = SoundCaptionProfile.DEFAULTS.duplicate()
		enabled_control.set_pressed_no_signal(profile.enabled)
		duration_control.set_value_no_signal(profile.duration)
		clear()
		_save())
	settings.popup_centered()
	enabled_control.grab_focus()

func _save() -> void:
	var error = SoundCaptionProfile.write_profile(profile, profile_path)
	status_label.text = _text("Guardado sólo en este equipo.", "Saved on this device only.") if error == OK else _text("No se pudo guardar. El cambio sólo se aplica a esta ejecución.", "Could not save. The change applies to this run only.")
