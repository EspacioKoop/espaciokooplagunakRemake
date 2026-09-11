extends Control

var _content: VBoxContainer
var _footer: Label
var _session_label: Label
var _page = "home"
var _target = ""
var _space: SpaceView
var _deck: WorldDeck
var _radar: Radar
var _editor: MissionEditor
var _campaign_window: CampaignEditor
var _gm_window: GMHotConsole
var _asset_window: AssetLibraryWindow
var _draft: Dictionary = {}
var _refs: Dictionary = {}
var _action_refs: Dictionary = {}
var _roles: Dictionary = {}
var _actions: VBoxContainer
var _action_scroll: ScrollContainer
var _last_role = ""
var _target_menu: OptionButton
var _ambient: AudioStreamPlayer
var _effects: AudioStreamPlayer
var _sound_captions: SoundCaptions
var _preferences = {"volume": 65.0, "motion": false, "text_scale": 1.0, "fullscreen": false}
var _clock = 0.0
var _toast_until = 0.0
var _capture_mode = false
var _new_confirmation: ConfirmationDialog
var _help: AcceptDialog

func _ready() -> void:
	var args = OS.get_cmdline_user_args()
	if "--server" in args:
		_start_server(args)
		return
	_capture_mode = "--capture" in args
	_load_preferences()
	if _capture_mode:
		_preferences.motion = true
		_preferences.volume = 0.0
		_preferences.fullscreen = false
		_preferences.text_scale = 1.0
	ConsoleUI.font_scale = _preferences.text_scale
	theme = ConsoleUI.make_theme()
	get_tree().auto_accept_quit = false
	_make_audio()
	_build_shell()
	_sound_captions = SoundCaptions.new()
	add_child(_sound_captions)
	Session.notice.connect(_notice)
	Session.updated.connect(_refresh)
	Session.joined.connect(func():
		if _page == "sessions": _go("bridge")
		else: _refresh())
	Session.disconnected.connect(func(): _go("sessions"))
	_go("home")
	if _preferences.fullscreen: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if _capture_mode: call_deferred("_capture", args)

func _build_shell() -> void:
	var background = ColorRect.new()
	background.color = ConsoleUI.BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 32)
	for edge in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var root = ConsoleUI.column(margin, 18)
	var header = ConsoleUI.row(root, 10)
	var brand = ConsoleUI.column(header, 0)
	brand.custom_minimum_size.x = 206
	brand.add_child(ConsoleUI.label("ESPACIOKOOP", 11, ConsoleUI.TEAL))
	brand.add_child(ConsoleUI.label("L A G U N A K", 25))
	for item in [["Inicio", "home"], ["Puente", "bridge"], ["Cubierta", "deck"], ["Atlas", "atlas"], ["Campaña", "campaign"], ["Editor", "editor"], ["Sesión", "sessions"]]:
		var button = ConsoleUI.button(item[0], _go.bind(item[1]))
		button.add_theme_font_size_override("font_size", 15)
		header.add_child(button)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_session_label = ConsoleUI.label("● LOCAL", 12, ConsoleUI.TEAL)
	header.add_child(_session_label)
	header.add_child(ConsoleUI.button("?", _show_help))
	header.add_child(ConsoleUI.button("Ajustes", _go.bind("settings")))
	var line = HSeparator.new()
	line.modulate = ConsoleUI.LINE
	root.add_child(line)
	_content = ConsoleUI.column(root, 16)
	ConsoleUI.expand(_content)
	var footer_row = ConsoleUI.row(root)
	_footer = ConsoleUI.label("F1 · Guía     F5 · Guardar     F11 · Pantalla completa", 13, ConsoleUI.MUTED)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.clip_text = true
	footer_row.add_child(_footer)
	footer_row.add_child(ConsoleUI.label("ITSASO  /  " + str(ProjectSettings.get_setting("application/config/version", "")), 12, ConsoleUI.MUTED))
	_new_confirmation = ConfirmationDialog.new()
	_new_confirmation.title = "Comenzar una nueva expedición"
	_new_confirmation.dialog_text = "Se reiniciará el progreso de la campaña local. El guardado anterior se conservará como copia de respaldo."
	_new_confirmation.ok_button_text = "Comenzar"
	_new_confirmation.cancel_button_text = "Cancelar"
	_new_confirmation.confirmed.connect(_new_game)
	add_child(_new_confirmation)
	_help = AcceptDialog.new()
	_help.title = "Guía de la tripulación"
	_help.dialog_text = "JUEGO LOCAL\nControlas los ocho puestos. Cambia con los botones o con las teclas 1–8.\nSelecciona un contacto en la lista o el radar antes de emitir órdenes.\n\nPRIMER VUELO\n1. Navegación: selecciona Argi y activa el piloto automático.\n2. Sensores: analiza el faro a menos de 900 m.\n3. Comunicaciones: abre un canal con Kaia.\n4. Navegación: acércate y atraca por debajo de 35 m/s.\n\nCUBIERTA\nPulsa en la vista para capturar el ratón. WASD para caminar, Mayús para correr.\nE accede a escotillas y consolas. Esc libera el ratón.\n\nCOOPERACIÓN\nEl anfitrión abre una sesión y comparte su dirección y clave. Cada persona\nocupa un puesto diferente. La campaña se guarda en el equipo anfitrión.\n\nF5 guarda. F11 alterna pantalla completa. Foundry es opcional."
	add_child(_help)

func _go(page: String) -> void:
	if page in ["bridge", "deck", "atlas"] and Session.view.is_empty():
		_notice("Comienza o continúa una expedición para acceder a la nave.", false)
		page = "home"
	if _editor != null and is_instance_valid(_editor): _draft = _editor.mission.duplicate(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_space = null
	_deck = null
	_radar = null
	_editor = null
	_target_menu = null
	_actions = null
	_refs.clear()
	_action_refs.clear()
	_roles.clear()
	ConsoleUI.clear(_content)
	_page = page
	if Session.mode == "offline": Session.paused = page not in ["bridge", "deck", "atlas"]
	match page:
		"home": _home()
		"bridge": _bridge()
		"deck": _interior()
		"atlas": _atlas()
		"campaign": _campaign()
		"editor": _mission_editor()
		"sessions": _sessions()
		"settings": _settings()
	_refresh()

func _home() -> void:
	var body = ConsoleUI.row(_content, 30)
	ConsoleUI.expand(body)
	var left = ConsoleUI.column(body, 22)
	left.custom_minimum_size.x = 570
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(ConsoleUI.label("LA RUTA COMPARTIDA  /  ITSASO", 13, ConsoleUI.TEAL))
	left.add_child(ConsoleUI.label("Una nave.\nOcho puestos.\nUn mismo destino.", 54))
	left.add_child(ConsoleUI.paragraph("Explora un universo con nombres en euskera. Traza rutas, cuida el reactor y lleva a tu tripulación a puerto. Cada decisión se toma desde un puesto; cada resultado pertenece a todos.", 19))
	var controls = ConsoleUI.row(left)
	controls.add_child(ConsoleUI.button("Comenzar expedición  ↗", _confirm_new, true))
	var resume = ConsoleUI.button("Continuar", _resume)
	resume.disabled = not FileAccess.file_exists("user://campaign.json") and not FileAccess.file_exists("user://campaign.json.bak")
	controls.add_child(resume)
	left.add_child(ConsoleUI.label("Juego local · Cooperación en red · Guardado en tu equipo", 14, ConsoleUI.MUTED))
	var right = ConsoleUI.card(body)
	ConsoleUI.expand(right.get_parent())
	var top = ConsoleUI.row(right)
	top.add_child(ConsoleUI.label("ITSASO", 19))
	var tag = ConsoleUI.label("EXPLORADOR DE LARGO ALCANCE", 12, ConsoleUI.TEAL)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(tag)
	_space = SpaceView.new()
	_space.showcase = true
	_space.reduced_motion = _preferences.motion
	ConsoleUI.expand(_space)
	right.add_child(_space)
	right.add_child(ConsoleUI.label("SECTOR ITSASARGI       43° N / CORREDOR INTERIOR", 12, ConsoleUI.MUTED))
	var features = ConsoleUI.row(_content, 16)
	for feature in [["01", "Tu nave, tus decisiones", "Ocho puestos conectados por una simulación común."], ["02", "Una campaña completa", "Seis misiones de exploración, rescate, combate y diplomacia."], ["03", "Un universo que puedes ampliar", "Editor de misiones y modelos de Blender editables."]]:
		var card = ConsoleUI.card(features)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var heading = ConsoleUI.row(card)
		heading.add_child(ConsoleUI.label(feature[0], 25, ConsoleUI.TEAL))
		heading.add_child(ConsoleUI.label(feature[1], 19))
		card.add_child(ConsoleUI.paragraph(feature[2], 15))

func _confirm_new() -> void:
	if Session.mode == "client": _notice("El anfitrión gestiona la campaña.", false); return
	if not Session.sim.state.is_empty() or FileAccess.file_exists("user://campaign.json"):
		_new_confirmation.popup_centered(Vector2i(660, 180))
	else: _new_game()

func _new_game() -> void:
	Session.new_campaign()
	_target = "argi"
	Session.select_role("navegacion")
	_go("bridge")

func _resume() -> void:
	var result = Session.resume_game()
	_notice(result.message, result.ok)
	if result.ok: _go("bridge")

func _bridge() -> void:
	var headline = ConsoleUI.row(_content)
	_refs.mission_title = ConsoleUI.label("", 26)
	_refs.mission_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.add_child(_refs.mission_title)
	_refs.flight_clock = ConsoleUI.label("", 14, ConsoleUI.MUTED)
	headline.add_child(_refs.flight_clock)
	var pause = ConsoleUI.button("Pausa local", func(): Session.paused = not Session.paused)
	pause.disabled = Session.mode != "offline"
	headline.add_child(pause)
	var gm_button = ConsoleUI.button("Dirección en vivo", _open_gm_console)
	gm_button.name = "GMConsoleLauncher"
	gm_button.disabled = not GMLiveActions.can_direct(Session)
	_refs.gm_button = gm_button
	headline.add_child(gm_button)
	var body = ConsoleUI.row(_content, 16)
	ConsoleUI.expand(body)
	var stations = ConsoleUI.card(body, "PUESTOS DE LA TRIPULACIÓN")
	stations.add_theme_constant_override("separation", 8)
	stations.get_parent().custom_minimum_size.x = 222
	stations.add_child(ConsoleUI.label("Una sola nave", 22))
	for i in Catalog.ROLES.size():
		var role: String = Catalog.ROLES[i]
		var button = ConsoleUI.button("%02d   %s" % [i + 1, Catalog.ROLE_NAMES[i]], _choose_role.bind(role))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)
		button.custom_minimum_size.y = 36
		stations.add_child(button)
		_roles[role] = button
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stations.add_child(spacer)
	stations.add_child(ConsoleUI.paragraph("En local puedes ocupar cualquier puesto. En red, cada persona controla el suyo.", 14))
	stations.add_child(ConsoleUI.button("Recorrer la cubierta", _go.bind("deck")))
	var center = ConsoleUI.column(body, 12)
	ConsoleUI.expand(center)
	var objective = ConsoleUI.card(center)
	_refs.objective = ConsoleUI.paragraph("", 17, ConsoleUI.TEAL)
	objective.add_child(_refs.objective)
	var viewport_panel = PanelContainer.new()
	ConsoleUI.expand(viewport_panel)
	center.add_child(viewport_panel)
	_space = SpaceView.new()
	_space.custom_minimum_size.y = 225
	_space.reduced_motion = _preferences.motion
	viewport_panel.add_child(_space)
	_action_scroll = ScrollContainer.new()
	_action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(_action_scroll)
	_actions = ConsoleUI.card(_action_scroll)
	_actions.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_actions()
	var right = ConsoleUI.column(body, 12)
	right.custom_minimum_size.x = 288
	var health = ConsoleUI.card(right, "ESTADO DE LA ITSASO")
	health.add_theme_constant_override("separation", 5)
	for info in [["hull", "Integridad"], ["shield", "Escudos"], ["energy", "Energía"], ["fuel", "Combustible"]]:
		var line = ConsoleUI.row(health)
		line.add_child(ConsoleUI.label(info[1], 14, ConsoleUI.MUTED))
		var value = ConsoleUI.label("", 14)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		var bar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 7
		health.add_child(bar)
		_refs[info[0]] = [value, bar]
	var radar_card = ConsoleUI.card(right, "RADAR TÁCTICO")
	_radar = Radar.new()
	_radar.custom_minimum_size = Vector2(245, 168)
	_radar.reduced_motion = _preferences.motion
	_radar.contact_selected.connect(_select_target)
	radar_card.add_child(_radar)
	var details = ConsoleUI.card(right, "CONTACTO SELECCIONADO")
	details.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_refs.contact_info = ConsoleUI.paragraph("", 15)
	details.add_child(_refs.contact_info)
	details.add_child(ConsoleUI.button("Abrir atlas", _go.bind("atlas")))
	right.add_child(ConsoleUI.button("Campaña y mejoras", _go.bind("campaign")))

func _choose_role(role: String) -> void:
	Session.select_role(role)
	if _page == "bridge" and _last_role != Session.role: _build_actions()

func _select_target(id: String) -> void:
	_target = id
	_refresh()

func _build_actions() -> void:
	if _actions == null: return
	ConsoleUI.clear(_actions)
	_action_refs.clear()
	_last_role = Session.role
	_action_scroll.custom_minimum_size.y = 335 if Session.role == "ingenieria" else 250
	var top = ConsoleUI.row(_actions)
	var name = ConsoleUI.label(Catalog.role_name(Session.role), 24)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	top.add_child(ConsoleUI.button("Operaciones", _open_operations))
	if Session.role == "ingenieria": top.add_child(ConsoleUI.button("Asistencia", _open_assistance))
	_target_menu = OptionButton.new()
	_target_menu.custom_minimum_size.x = 295
	_target_menu.add_theme_font_size_override("font_size", 15)
	top.add_child(_target_menu)
	_target_menu.item_selected.connect(func(index): _target = _target_menu.get_item_metadata(index); _refresh())
	_actions.add_child(ConsoleUI.paragraph(Catalog.DESCRIPTIONS[Session.role], 14))
	var buttons = ConsoleUI.row(_actions, 8)
	match Session.role:
		"mando":
			for level in ["verde", "ambar", "roja"]: buttons.add_child(ConsoleUI.button("Alerta " + level, _send.bind("alert", {"level": level})))
			var choices = ConsoleUI.row(_actions)
			choices.add_child(ConsoleUI.button("Compartir cartas", _send.bind("mission_choice", {"choice": "compartir"}), true))
			choices.add_child(ConsoleUI.button("Reservar cartas", _send.bind("mission_choice", {"choice": "reservar"})))
		"navegacion":
			var heading = HSlider.new()
			heading.max_value = 359
			heading.step = 1
			heading.custom_minimum_size.x = 180
			heading.value = Session.view.ship.heading
			buttons.add_child(ConsoleUI.label("Rumbo", 14))
			buttons.add_child(heading)
			var heading_label = ConsoleUI.label("%03d°" % heading.value, 15, ConsoleUI.TEAL)
			buttons.add_child(heading_label)
			heading.value_changed.connect(func(value): heading_label.text = "%03d°" % value)
			var throttle = HSlider.new()
			throttle.min_value = -100
			throttle.max_value = 100
			throttle.step = 5
			throttle.value = Session.view.ship.throttle * 100
			throttle.custom_minimum_size.x = 135
			buttons.add_child(ConsoleUI.label("Impulso", 14))
			buttons.add_child(throttle)
			buttons.add_child(ConsoleUI.button("Aplicar", func(): _send("helm", {"heading": heading.value, "throttle": throttle.value / 100.0})))
			var orders = ConsoleUI.row(_actions, 8)
			orders.add_child(ConsoleUI.button("Piloto automático", func(): _send("autopilot", {"target": _target}), true))
			orders.add_child(ConsoleUI.button("Atracar", func(): _send("dock", {"target": _target})))
			orders.add_child(ConsoleUI.button("Desatracar", _send.bind("undock", {})))
			orders.add_child(ConsoleUI.button("Impulso +", _send.bind("boost", {})))
			orders.add_child(ConsoleUI.button("Frenar", func(): _send("helm", {"heading": Session.view.ship.heading, "throttle": 0.0})))
		"ingenieria":
			var circuits = GridContainer.new()
			circuits.columns = 5
			circuits.add_theme_constant_override("h_separation", 16)
			circuits.add_theme_constant_override("v_separation", 12)
			circuits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			buttons.add_child(circuits)
			for system in Catalog.SYSTEMS:
				var column = ConsoleUI.column(circuits, 4)
				column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				column.add_child(ConsoleUI.label(Catalog.SYSTEM_NAMES[system], 16))
				var values = ConsoleUI.label("", 13, ConsoleUI.MUTED)
				column.add_child(values)
				_action_refs[system] = values
				var controls = ConsoleUI.row(column, 5)
				controls.add_child(ConsoleUI.button("−", func(): _send("power", {"system": system, "value": int(Session.view.ship.systems[system].power) - 1})))
				controls.add_child(ConsoleUI.button("+", func(): _send("power", {"system": system, "value": int(Session.view.ship.systems[system].power) + 1})))
				var cool = ConsoleUI.button("Frío", _send.bind("coolant", {"system": system}))
				cool.tooltip_text = "Dirigir refrigeración a " + Catalog.SYSTEM_NAMES[system]
				cool.add_theme_font_size_override("font_size", 13)
				controls.add_child(cool)
				for control in controls.get_children(): control.custom_minimum_size.y = 32
			var shields = ConsoleUI.row(_actions)
			shields.add_child(ConsoleUI.button("Subir escudos", _send.bind("shields", {"enabled": true})))
			shields.add_child(ConsoleUI.button("Bajar escudos", _send.bind("shields", {"enabled": false})))
			_action_refs.shield_segments = ConsoleUI.label("", 14, ConsoleUI.TEAL)
			shields.add_child(_action_refs.shield_segments)
		"armas":
			buttons.add_child(ConsoleUI.button("Disparar pulso · %d m" % Session.view.ship.design.beam_range, func(): _send("fire", {"target": _target}), true))
			buttons.add_child(ConsoleUI.button("Lanzar torpedo · %d m" % minf(900, Session.view.ship.design.missile_range), func(): _send("missile", {"target": _target})))
			_action_refs.resources = ConsoleUI.label("", 17, ConsoleUI.AMBER)
			_actions.add_child(_action_refs.resources)
		"sensores":
			buttons.add_child(ConsoleUI.button("Analizar contacto · 900 m", func(): _send("scan", {"target": _target}), true))
			_action_refs.scan = ConsoleUI.label("", 16, ConsoleUI.TEAL)
			buttons.add_child(_action_refs.scan)
			_actions.add_child(ConsoleUI.paragraph("Si hay interferencias, Comunicaciones debe abrir primero un canal con este contacto. Una sonda reduce a la mitad el tiempo de análisis.", 15))
		"comunicaciones":
			buttons.add_child(ConsoleUI.button("Abrir canal · 900 m", func(): _send("hail", {"target": _target}), true))
			buttons.add_child(ConsoleUI.button("Negociar paso", func(): _send("negotiate", {"target": _target})))
			_actions.add_child(ConsoleUI.paragraph("Para negociar necesitas un aliado u hostil identificado, un canal abierto y los escudos bajos. Acércate a menos de 900 m.", 15))
		"enlace":
			buttons.add_child(ConsoleUI.button("Desplegar sonda", func(): _send("probe", {"target": _target})))
			buttons.add_child(ConsoleUI.button("Rescatar tripulación", func(): _send("rescue", {"target": _target}), true))
			buttons.add_child(ConsoleUI.button("Recuperar materiales", func(): _send("salvage", {"target": _target})))
			_actions.add_child(ConsoleUI.paragraph("Sondas: 2500 m. Rescate y recuperación: contacto identificado a menos de 300 m. Los supervivientes se registran al completar la misión.", 15))
		"reparaciones":
			var system = OptionButton.new()
			for system_name in Catalog.SYSTEMS: system.add_item(Catalog.SYSTEM_NAMES[system_name])
			buttons.add_child(system)
			buttons.add_child(ConsoleUI.button("Enviar drones · 2 repuestos", func(): _send("repair", {"system": Catalog.SYSTEMS[system.selected]}), true))
			buttons.add_child(ConsoleUI.button("Reparar estación", func(): _send("repair_target", {"target": _target})))
			_actions.add_child(ConsoleUI.paragraph("Los drones reparan 35 puntos de un sistema en 5 segundos. Reparar una estación consume 5 repuestos y requiere estar a menos de 300 m.", 15))
	if Session.role != "ingenieria":
		var support = ConsoleUI.row(_actions)
		var assist = ConsoleUI.button("Asistencia entre puestos", _open_assistance)
		assist.add_theme_font_size_override("font_size", 13)
		support.add_child(assist)
		_action_refs.summary = ConsoleUI.label("", 13, ConsoleUI.MUTED)
		support.add_child(_action_refs.summary)

func _open_assistance() -> Window:
	var window = Window.new()
	window.title = "Asistencia entre puestos"
	window.size = Vector2i(1020, 840)
	window.transient = true
	window.exclusive = true
	add_child(window)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window.add_child(scroll)
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	scroll.add_child(margin)
	margin.add_child(AssistanceConsole.new())
	window.close_requested.connect(window.queue_free)
	window.popup_centered()
	return window

func _open_operations() -> Window:
	var window = Window.new()
	window.title = "Operaciones de la Itsaso"
	window.size = Vector2i(1080, 710)
	window.transient = true
	window.exclusive = true
	add_child(window)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
	window.add_child(margin)
	var console = OperationsConsole.new()
	console.role = Session.role
	console.selected_target = _target
	margin.add_child(console)
	window.close_requested.connect(window.queue_free)
	window.popup_centered()
	return window

func _send(operation: String, args: Dictionary) -> void:
	var result = Session.order(operation, args)
	if result.ok:
		var effect = {"fire": "pulse", "missile": "torpedo", "scan": "scan", "dock": "arrival"}.get(operation, "confirm")
		_play_effect(effect)
	_refresh()

func _interior() -> void:
	var title = ConsoleUI.row(_content)
	title.add_child(ConsoleUI.label("A bordo de la Itsaso", 28))
	_refs.deck_zone = ConsoleUI.label("Puente", 18, ConsoleUI.TEAL)
	_refs.deck_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refs.deck_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.add_child(_refs.deck_zone)
	var body = ConsoleUI.row(_content, 18)
	ConsoleUI.expand(body)
	var viewport_panel = PanelContainer.new()
	ConsoleUI.expand(viewport_panel)
	body.add_child(viewport_panel)
	_deck = WorldDeck.new()
	_deck.reduced_motion = _preferences.motion
	viewport_panel.add_child(_deck)
	# Keep the emitting deck alive until its input callback has returned.
	_deck.station_requested.connect(_open_deck_station.bind(_deck.get_instance_id()), CONNECT_DEFERRED)
	_deck.interaction_requested.connect(_open_leisure_interaction)
	_deck.zone_changed.connect(func(name):
		if _refs.has("deck_zone"): _refs.deck_zone.text = name
		if _refs.has("deck_station"): _refs.deck_station.disabled = WorldDeck.ZONES[_deck.zone].role.is_empty())
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.x = 290
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var side = ConsoleUI.card(scroll, "RECORRIDO DE LA CUBIERTA")
	side.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	for i in WorldDeck.ZONES.size():
		side.add_child(ConsoleUI.button("%02d  %s" % [i + 1, WorldDeck.ZONES[i].name], func(): _deck.teleport_zone(i)))
	side.add_child(ConsoleUI.paragraph("Recorre cada sala en primera persona. Las escotillas del pasillo comunican los compartimentos; acércate y pulsa E. También puedes usar el traslado rápido de esta lista.", 15))
	_refs.deck_station = ConsoleUI.button("Operar puesto de esta sala", func(): Session.select_role(WorldDeck.ZONES[_deck.zone].role); _go("bridge"), true)
	side.add_child(_refs.deck_station)
	side.add_child(ConsoleUI.button("Mesas de la cantina", func(): _open_leisure_interaction({"kind": "table", "table": "poker"})))
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	side.add_child(ConsoleUI.paragraph("WASD · caminar\nMayús · correr\nRatón · mirar\nE · escotilla / consola\nEsc · liberar ratón", 15))
	_refs.deck_prompt = ConsoleUI.label("", 15, ConsoleUI.TEAL)
	_content.add_child(_refs.deck_prompt)

func _open_deck_station(role: String, source_id: int) -> void:
	# A queued request may outlive a page change, disconnect or another request.
	# Bind an ID, not a Node reference that may already have been freed.
	if not is_inside_tree() or is_queued_for_deletion(): return
	if _page != "deck" or not is_instance_valid(_deck): return
	if _deck.get_instance_id() != source_id: return
	if not _deck.is_inside_tree() or _deck.is_queued_for_deletion(): return
	if role not in Catalog.ROLES: return
	Session.select_role(role)
	_go("bridge")

func _open_leisure_interaction(entry: Dictionary) -> Window:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var window: Window
	if entry.kind == "table":
		window = LoungeWindow.new()
		window.selected = entry.table
	elif entry.kind == "book":
		window = MuseumReader.new()
		window.page = int(Session.get_meta("museum_page", 0))
		var deck = _deck
		deck.book_open = true
		window.page_changed.connect(func(page):
			Session.set_meta("museum_page", page)
			if is_instance_valid(deck): deck.turn_book(page))
		window.tree_exiting.connect(func():
			if is_instance_valid(deck): deck.book_open = false)
	else:
		window = Window.new()
		window.title = entry.title
		window.size = Vector2i(730, 420)
		var margin = MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 28)
		window.add_child(margin)
		var root = ConsoleUI.column(margin, 22)
		root.add_child(ConsoleUI.paragraph(entry.title, 26, ConsoleUI.TEAL))
		var scroll = ScrollContainer.new()
		ConsoleUI.expand(scroll)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		root.add_child(scroll)
		scroll.add_child(ConsoleUI.paragraph(entry.text, 19, ConsoleUI.TEXT))
		root.add_child(ConsoleUI.button("Volver al recorrido", window.queue_free, true))
		window.close_requested.connect(window.queue_free)
	window.transient = true
	window.exclusive = true
	add_child(window)
	window.popup_centered()
	return window

func _atlas() -> void:
	_content.add_child(ConsoleUI.label("Atlas del sector", 28))
	var body = ConsoleUI.row(_content, 18)
	ConsoleUI.expand(body)
	var map_panel = PanelContainer.new()
	ConsoleUI.expand(map_panel)
	body.add_child(map_panel)
	_radar = Radar.new()
	_radar.range_m = 2600
	_radar.show_labels = true
	_radar.reduced_motion = _preferences.motion
	_radar.contact_selected.connect(_select_target)
	map_panel.add_child(_radar)
	var side = ConsoleUI.card(body, "CONTACTOS Y RUTAS")
	side.get_parent().custom_minimum_size.x = 340
	_refs.atlas_contacts = ItemList.new()
	_refs.atlas_contacts.custom_minimum_size.y = 245
	side.add_child(_refs.atlas_contacts)
	_refs.atlas_contacts.item_selected.connect(func(index): _select_target(_refs.atlas_contacts.get_item_metadata(index)))
	_refs.contact_info = ConsoleUI.paragraph("", 18)
	side.add_child(_refs.contact_info)
	side.add_child(ConsoleUI.button("Puesto de navegación  ↗", func(): Session.select_role("navegacion"); _go("bridge"), true))
	side.add_child(ConsoleUI.paragraph("Los contactos sin identificar aparecen como ecos. Sus posiciones son visibles, pero su identidad se resuelve desde Sensores. La rueda del ratón cambia la escala del atlas.", 16))
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	side.add_child(ConsoleUI.label("◆ ITSASO   □ ESTACIÓN   ● CONTACTO", 13, ConsoleUI.MUTED))

func _campaign() -> void:
	if Session.sim.state.is_empty() and Session.mode != "client":
		var saved = LocalStorage.read_state()
		if saved.has("state"):
			Session.sim.state = saved.state
			Session._refresh_view()
	var data = Session.view.get("campaign", {"completed": [], "credits": 0, "reputation": 0, "survivors": 0, "upgrades": 0, "decisions": {}})
	var missions = Session.campaign_missions()
	var authored: Dictionary = Session.sim.state.get("campaign_document", {}) if Session.mode != "client" else {}
	var completed_count = missions.filter(func(mission): return mission.id in data.completed).size()
	var header = ConsoleUI.row(_content)
	var heading = ConsoleUI.column(header, 4)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var campaign_title = ConsoleUI.paragraph(authored.get("title", "La ruta compartida"), 32, ConsoleUI.TEXT)
	campaign_title.max_lines_visible = 2
	campaign_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	campaign_title.tooltip_text = campaign_title.text
	heading.add_child(campaign_title)
	heading.add_child(ConsoleUI.label("EL ANFITRIÓN SELECCIONA LA SIGUIENTE MISIÓN." if Session.mode == "client" else "%d TRAVESÍAS. UNA TRIPULACIÓN." % missions.size(), 13, ConsoleUI.TEAL))
	if Session.mode != "client":
		header.add_child(ConsoleUI.button("Taller de campañas", _open_campaign_editor))
		header.add_child(ConsoleUI.label("%d / %d\nmisiones cumplidas" % [completed_count, missions.size()], 20, ConsoleUI.TEAL))
	var stats = ConsoleUI.row(_content, 16)
	for stat in [["CRÉDITOS", str(data.credits)], ["SUPERVIVIENTES", str(data.survivors)], ["REPUTACIÓN", str(data.reputation)], ["REFUERZOS DE CASCO", "%d / 4" % data.upgrades]]:
		var panel = ConsoleUI.card(stats)
		panel.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(ConsoleUI.label(stat[0], 12, ConsoleUI.MUTED))
		panel.add_child(ConsoleUI.label(stat[1], 27, ConsoleUI.TEAL))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ConsoleUI.expand(scroll)
	_content.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	for i in missions.size():
		var mission: Dictionary = missions[i]
		var unlocked = Session.mission_unlocked(i)
		var won = mission.id in data.completed
		var card = ConsoleUI.card(grid)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.get_parent().custom_minimum_size = Vector2(430, 225)
		card.add_child(ConsoleUI.label("COMPLETADA" if won else ("DISPONIBLE" if unlocked else "RUTA BLOQUEADA"), 12, ConsoleUI.TEAL if unlocked else ConsoleUI.MUTED))
		var mission_title = ConsoleUI.paragraph(mission.title, 25, ConsoleUI.TEXT)
		mission_title.max_lines_visible = 2
		mission_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mission_title.tooltip_text = mission.title
		card.add_child(mission_title)
		var briefing = ConsoleUI.paragraph(mission.briefing, 15)
		briefing.max_lines_visible = 3
		briefing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		briefing.tooltip_text = mission.briefing
		card.add_child(briefing)
		var row = ConsoleUI.row(card)
		var reward = ConsoleUI.label("%d créditos · %d objetivos" % [mission.get("reward", 0), mission.objectives.size()], 13, ConsoleUI.MUTED)
		reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(reward)
		var start = ConsoleUI.button("Repetir" if won else "Embarcar", _begin_mission.bind(i), unlocked and not won)
		start.disabled = not unlocked or Session.mode == "client"
		row.add_child(start)
	var bottom = ConsoleUI.row(_content)
	bottom.add_child(ConsoleUI.button("Reforzar casco · 120 créditos", _upgrade))
	bottom.add_child(ConsoleUI.paragraph("Las mejoras se instalan tras completar una misión y atracar. Cada refuerzo añade 15 puntos de integridad máxima. Repetir una misión no duplica sus recompensas.", 15))
	if data.decisions.has("haize"):
		_content.add_child(ConsoleUI.paragraph("Epílogo · Compartiste las cartas con Haize. La ruta hacia Egunsenti queda en manos de una comunidad de navegantes." if data.decisions.haize == "compartir" else "Epílogo · Conservaste las cartas. Haize respeta el acuerdo de paso, aunque la responsabilidad del próximo viaje sigue siendo vuestra.", 16, ConsoleUI.AMBER))

func _open_campaign_editor() -> CampaignEditor:
	if Session.mode == "client":
		_notice("El anfitrión edita y selecciona las campañas.", false)
		return null
	if is_instance_valid(_campaign_window):
		_campaign_window.popup_centered()
		if is_instance_valid(_campaign_window.mission_window): _campaign_window.mission_window.popup_centered()
		return _campaign_window
	var editor = CampaignEditor.new()
	_campaign_window = editor
	editor.document = Session.sim.state.get("campaign_document", {}).duplicate(true)
	editor.campaign_requested.connect(func(document):
		var confirm = ConfirmationDialog.new()
		confirm.title = "Comenzar campaña"
		confirm.dialog_text = "Se iniciará una expedición nueva y sustituirá la partida actual. Guarda o exporta los cambios del taller antes de continuar."
		confirm.confirmed.connect(func():
			var result = Session.start_campaign(document)
			_notice(result.message, result.ok)
			if result.ok:
				editor.queue_free()
				_target = ""
				Session.select_role("navegacion")
				_go("bridge")
			else: confirm.queue_free())
		confirm.canceled.connect(confirm.queue_free)
		editor.add_child(confirm)
		confirm.popup_centered(Vector2i(590, 190)))
	editor.mission_preview_requested.connect(func(mission):
		# Preview goes through the same host gate and never unlocks campaign stages.
		var confirm = ConfirmationDialog.new()
		confirm.dialog_text = "¿Probar esta misión como partida independiente? Sustituirá la partida actual; el taller seguirá abierto para conservar tus cambios."
		confirm.confirmed.connect(func():
			var result = Session.start_mission(0, mission)
			_notice(result.message, result.ok)
			if result.ok:
				editor.mission_window.hide()
				editor.hide()
				_target = ""
				_go("bridge")
				# Closing the preview returns to the still-live authored draft.
				var return_button = ConsoleUI.button("Volver al taller de campañas", _open_campaign_editor)
				_content.add_child(return_button)
			confirm.queue_free())
		confirm.canceled.connect(confirm.queue_free)
		editor.mission_window.add_child(confirm)
		confirm.popup_centered(Vector2i(590, 190)))
	add_child(editor)
	editor.popup_centered()
	return editor

func _begin_mission(index: int) -> void:
	var result = Session.start_mission(index)
	_notice(result.message, result.ok)
	if result.ok:
		_target = ""
		_go("bridge")

func _upgrade() -> void:
	if Session.mode == "client": _notice("El anfitrión gestiona las mejoras.", false); return
	var result = Session.sim.purchase_upgrade()
	if result.ok:
		Session.save_game()
		Session._refresh_view()
		_go("campaign")
	_notice(result.message, result.ok)

func _mission_editor() -> void:
	var library_button = ConsoleUI.button("Biblioteca 3D · inspeccionar recursos", _open_asset_library)
	library_button.name = "AssetLibraryLauncher"
	_content.add_child(library_button)
	_editor = MissionEditor.new()
	_editor.mission = _draft.duplicate(true)
	ConsoleUI.expand(_editor)
	_content.add_child(_editor)
	_editor.play_requested.connect(func(mission):
		var result = Session.start_mission(0, mission)
		_notice(result.message, result.ok)
		if result.ok:
			_target = ""
			_go("bridge"))

func _field(parent: Node, caption: String, text: String = "", secret: bool = false) -> LineEdit:
	parent.add_child(ConsoleUI.label(caption, 14, ConsoleUI.MUTED))
	var edit = LineEdit.new()
	edit.text = text
	edit.secret = secret
	edit.custom_minimum_size.y = 42
	parent.add_child(edit)
	return edit

func _sessions() -> void:
	_content.add_child(ConsoleUI.label("Una tripulación, desde varios equipos", 30))
	_content.add_child(ConsoleUI.paragraph("Abre una sesión en tu red y comparte la dirección y la clave con tu tripulación. No hace falta crear una cuenta. El anfitrión conserva el guardado y decide la siguiente misión.", 18))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ConsoleUI.expand(scroll)
	_content.add_child(scroll)
	var body = ConsoleUI.row(scroll, 18)
	ConsoleUI.expand(body)
	var host = ConsoleUI.card(body, "01 / ANFITRIÓN")
	host.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.get_parent().custom_minimum_size.x = 380
	host.add_child(ConsoleUI.label("Abrir la nave", 26))
	var host_port = SpinBox.new()
	host_port.min_value = 1024
	host_port.max_value = 65535
	host_port.value = 27840
	host.add_child(ConsoleUI.label("Puerto UDP", 14, ConsoleUI.MUTED))
	host.add_child(host_port)
	var address = "127.0.0.1"
	for candidate in IP.get_local_addresses():
		if not ":" in candidate and not candidate.begins_with("127."):
			address = candidate
			break
	var ip = _field(host, "Dirección de este equipo", address)
	ip.editable = false
	var host_key = _field(host, "Clave de acceso", Session.access_key if Session.mode == "host" else "", true)
	host_key.editable = false
	host.add_child(ConsoleUI.button("Crear sesión", func():
		var result = Session.host_session(int(host_port.value))
		_notice(result.message, result.ok)
		if result.ok: host_key.text = result.key, true))
	host.add_child(ConsoleUI.button("Copiar clave", func():
		if not host_key.text.is_empty(): DisplayServer.clipboard_set(host_key.text); _notice("Clave copiada al portapapeles.", true)))
	host.add_child(ConsoleUI.paragraph("Comparte la clave por un canal privado. La sesión usa UDP; fuera de tu red necesitas una VPN o configurar el acceso. La clave se renueva al crear otra sesión.", 15))
	host.add_child(ConsoleUI.button("Cerrar sesión de red", func(): Session.close_session(); _go("sessions")))
	var join_card = ConsoleUI.card(body, "02 / TRIPULANTE")
	join_card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_card.get_parent().custom_minimum_size.x = 390
	join_card.add_child(ConsoleUI.label("Ocupar un puesto", 26))
	var player_name = _field(join_card, "Nombre en la sesión", "Tripulante")
	var host_address = _field(join_card, "Dirección del anfitrión", "127.0.0.1")
	var join_port = SpinBox.new()
	join_port.min_value = 1024
	join_port.max_value = 65535
	join_port.value = 27840
	join_card.add_child(ConsoleUI.label("Puerto UDP", 14, ConsoleUI.MUTED))
	join_card.add_child(join_port)
	var join_key = _field(join_card, "Clave de acceso", "", true)
	var station = OptionButton.new()
	for role in Catalog.ROLE_NAMES: station.add_item(role)
	station.select(1)
	join_card.add_child(station)
	join_card.add_child(ConsoleUI.button("Conectar", func():
		var result = Session.join_session(host_address.text, int(join_port.value), join_key.text, player_name.text, Catalog.ROLES[station.selected])
		_notice(result.message, result.ok)
		if result.ok: join_key.clear(), true))
	join_card.add_child(ConsoleUI.paragraph("Cada puesto admite una persona. Si está ocupado, elige otro. Al desconectarte, el puesto vuelve a quedar libre.", 15))
	var foundry = ConsoleUI.card(body, "03 / COMPLEMENTO OPCIONAL")
	foundry.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foundry.get_parent().custom_minimum_size.x = 390
	foundry.add_child(ConsoleUI.label("Enlace con Foundry", 26))
	foundry.add_child(ConsoleUI.paragraph("Foundry puede mostrar el estado de la nave e importar la bitácora. La partida y sus controles siguen dentro de Lagunak.", 16))
	var origin = _field(foundry, "Origen exacto de Foundry", Session.telemetry.origin)
	var token = _field(foundry, "Token de consulta", Session.telemetry.token, true)
	token.editable = false
	foundry.add_child(ConsoleUI.button("Activar consulta local", func():
		var error = Session.telemetry.start(origin.text.strip_edges())
		_notice("Consulta local activada en 127.0.0.1:27841." if error.is_empty() else error, error.is_empty())
		token.text = Session.telemetry.token))
	foundry.add_child(ConsoleUI.button("Copiar token", func():
		if not token.text.is_empty(): DisplayServer.clipboard_set(token.text); _notice("Token copiado al portapapeles.", true)))
	foundry.add_child(ConsoleUI.button("Desactivar consulta", func(): Session.telemetry.stop(); token.clear(); _notice("Consulta local desactivada.", true)))
	foundry.add_child(ConsoleUI.paragraph("Abre Foundry en un navegador del mismo equipo que Lagunak. Instala el módulo de integrations/foundry y pega allí el token. Este acceso solo permite consultas y está desactivado al iniciar.", 15))
	_refs.connection = ConsoleUI.paragraph(Session.connection_status, 16, ConsoleUI.TEAL)
	_content.add_child(_refs.connection)

func _settings() -> void:
	_content.add_child(ConsoleUI.label("Ajusta tu puesto", 32))
	var body = ConsoleUI.row(_content, 20)
	var options = ConsoleUI.card(body, "PREFERENCIAS LOCALES")
	options.get_parent().custom_minimum_size.x = 580
	options.add_child(ConsoleUI.label("Volumen general", 20))
	var volume = HSlider.new()
	volume.max_value = 100
	volume.step = 1
	volume.value = _preferences.volume
	volume.custom_minimum_size.y = 40
	options.add_child(volume)
	volume.value_changed.connect(func(value): _preferences.volume = value; _apply_audio(); _save_preferences())
	var motion = CheckBox.new()
	motion.text = "Reducir movimiento decorativo"
	motion.button_pressed = _preferences.motion
	options.add_child(motion)
	motion.toggled.connect(func(value): _preferences.motion = value; _save_preferences())
	var fullscreen = CheckBox.new()
	fullscreen.text = "Pantalla completa"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	options.add_child(fullscreen)
	fullscreen.toggled.connect(func(value):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		_preferences.fullscreen = value
		_save_preferences())
	options.add_child(ConsoleUI.label("Tamaño del texto", 20))
	var scale = OptionButton.new()
	for caption in ["Compacto · 90 %", "Normal · 100 %", "Grande · 110 %"]: scale.add_item(caption)
	scale.select(clampi(roundi((_preferences.text_scale - 0.9) * 10), 0, 2))
	options.add_child(scale)
	scale.item_selected.connect(func(index):
		_preferences.text_scale = [0.9, 1.0, 1.1][index]
		ConsoleUI.font_scale = _preferences.text_scale
		theme = ConsoleUI.make_theme()
		_save_preferences()
		_go("settings"))
	options.add_child(ConsoleUI.button("Subtítulos de avisos sonoros…", _sound_captions.open_settings))
	options.add_child(ConsoleUI.button("Guardar partida ahora", _manual_save, true))
	options.add_child(ConsoleUI.button("Salir del juego", _quit))
	var help_card = ConsoleUI.card(body, "CONTROL Y ACCESIBILIDAD")
	help_card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_card.add_child(ConsoleUI.label("Todo a mano", 26))
	help_card.add_child(ConsoleUI.paragraph("1–8 · Cambiar de puesto\nF1 · Abrir la guía de tripulación\nF5 · Guardar la campaña\nF11 · Alternar pantalla completa\nEsc · Liberar el ratón o volver a inicio\n\nEn cubierta: WASD, ratón, Mayús y E.\nEn el radar: pulsa para seleccionar; rueda para acercar o alejar.\nEn la vista exterior: botón derecho y ratón para orbitar.\n\nLa campaña se guarda automáticamente cada 30 segundos, al terminar una misión y al salir. Se conserva una copia anterior para recuperar un guardado dañado.", 18))
	help_card.add_child(ConsoleUI.button("Abrir guía", _show_help))

func _refresh() -> void:
	if _session_label == null: return
	_session_label.text = "● " + {"offline": "LOCAL", "host": "ANFITRIÓN", "client": "TRIPULANTE"}.get(Session.mode, "LOCAL")
	if _refs.has("connection"): _refs.connection.text = Session.connection_status
	if _refs.has("deck_prompt") and _deck != null: _refs.deck_prompt.text = _deck.prompt
	if _refs.has("gm_button"): _refs.gm_button.disabled = not GMLiveActions.can_direct(Session)
	var data: Dictionary = Session.view
	if data.is_empty(): return
	var ship: Dictionary = data.ship
	if _target.is_empty() or not data.contacts.any(func(c): return c.id == _target):
		_target = data.contacts[0].id if not data.contacts.is_empty() else ""
	if _space != null: _space.selected = _target
	if _radar != null:
		_radar.data = data
		_radar.selected = _target
	if _refs.has("mission_title"): _refs.mission_title.text = data.mission.title
	if _refs.has("flight_clock"): _refs.flight_clock.text = "%02d:%02d  ·  %d m/s  ·  %03d°%s" % [int(data.time) / 60, int(data.time) % 60, ship.speed, ship.heading, "  /  PAUSA" if Session.paused and Session.mode == "offline" else ""]
	if _refs.has("objective"):
		if data.status == "won": _refs.objective.text = "MISIÓN CUMPLIDA · Abre Campaña para instalar mejoras y elegir el siguiente destino."
		elif data.status == "lost": _refs.objective.text = "NAVE PERDIDA · Vuelve a intentarlo desde Campaña."
		else: _refs.objective.text = "%02d / %02d   %s" % [int(data.objective) + 1, data.mission.objectives.size(), data.mission.objectives[int(data.objective)].text]
	for key in ["hull", "shield", "energy", "fuel"]:
		if _refs.has(key):
			var value = float(ship[key])
			_refs[key][0].text = "%d / %d" % [value, ship.max_hull] if key == "hull" else "%d%%" % value
			_refs[key][1].max_value = ship.max_hull if key == "hull" else 100
			_refs[key][1].value = value
	var chosen: Dictionary = {}
	for c in data.contacts:
		if c.id == _target: chosen = c
	if _target_menu != null and not _target_menu.get_popup().visible:
		_target_menu.clear()
		for i in data.contacts.size():
			var c: Dictionary = data.contacts[i]
			_target_menu.add_item(c.name + " · %d m" % _distance(c, ship))
			_target_menu.set_item_metadata(i, c.id)
			if c.id == _target: _target_menu.select(i)
	if _refs.has("atlas_contacts"):
		_refs.atlas_contacts.clear()
		for i in data.contacts.size():
			var c: Dictionary = data.contacts[i]
			_refs.atlas_contacts.add_item(c.name + " · %d m" % _distance(c, ship))
			_refs.atlas_contacts.set_item_metadata(i, c.id)
			if c.id == _target: _refs.atlas_contacts.select(i)
	if _refs.has("contact_info"):
		_refs.contact_info.text = "Selecciona un contacto." if chosen.is_empty() else "%s\n\n%s · %d m\n%s\n%s" % [chosen.name, (Catalog.CONTACT_NAMES[Catalog.CONTACT_KINDS.find(chosen.kind)] if chosen.kind in Catalog.CONTACT_KINDS else "Sin identificar"), _distance(chosen, ship), "Canal abierto" if chosen.get("hailed", false) else "Canal sin abrir", "Sonda activa" if chosen.get("probed", false) else "Sin sonda"]
		if _page == "bridge" and not chosen.is_empty(): _refs.contact_info.text = "%s · %d m\n%s" % [chosen.name, _distance(chosen, ship), "Identificado" if chosen.identified else "Eco sin identificar"]
	if _page == "bridge":
		if _last_role != Session.role: _build_actions()
		for role in _roles:
			_roles[role].add_theme_color_override("font_color", ConsoleUI.TEAL if role == Session.role else ConsoleUI.TEXT)
			_roles[role].add_theme_stylebox_override("normal", ConsoleUI.button_style(Color("183c40") if role == Session.role else ConsoleUI.PANEL, ConsoleUI.TEAL if role == Session.role else ConsoleUI.LINE))
		for system in Catalog.SYSTEMS:
			if _action_refs.has(system):
				var values: Dictionary = ship.systems[system]
				_action_refs[system].text = "%d/4 · %d°C · %d%%" % [values.power, values.heat, values.health]
				_action_refs[system].add_theme_color_override("font_color", ConsoleUI.RED if values.heat > 95 else (ConsoleUI.TEAL if ship.coolant == system else ConsoleUI.MUTED))
		if _action_refs.has("shield_segments"): _action_refs.shield_segments.text = "Proa %d / %d · Popa %d / %d" % [ship.shield_segments.front, ship.design.front_shield, ship.shield_segments.rear, ship.design.rear_shield]
		if _action_refs.has("resources"): _action_refs.resources.text = "%d torpedos · %d energía · %s" % [ship.torpedoes, ship.energy, "Armas listas" if ship.weapon_ready <= data.time else "Recarga %.1f s" % (ship.weapon_ready - data.time)]
		if _action_refs.has("scan"): _action_refs.scan.text = "Sensores disponibles" if data.scan.target.is_empty() else "Analizando · %.1f s" % maxf(0, data.scan.remaining)
		if _action_refs.has("summary"): _action_refs.summary.text = "%d repuestos · %d sondas · Alerta %s" % [ship.parts, ship.probes, ship.alert]
	if _clock > _toast_until:
		if not data.events.is_empty():
			var event: Dictionary = data.events.back()
			_footer.text = event.source + " · " + event.text
			_footer.add_theme_color_override("font_color", ConsoleUI.MUTED)

func _distance(contact: Dictionary, ship: Dictionary) -> float:
	return Vector2(contact.position[0] - ship.position[0], contact.position[1] - ship.position[1]).length()

func _notice(message: String, ok: bool) -> void:
	if _footer == null: return
	_footer.text = message
	_footer.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
	_toast_until = _clock + 5.0

func _process(delta: float) -> void:
	_clock += delta
	if _deck != null and _refs.has("deck_prompt"): _refs.deck_prompt.text = _deck.prompt

func _show_help() -> void:
	_help.popup_centered(Vector2i(840, 620))

func _manual_save() -> void:
	var result = Session.save_game()
	_notice(result.message, result.ok)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F1: _show_help()
	elif event.keycode == KEY_F5: _manual_save()
	elif event.keycode == KEY_F11:
		_preferences.fullscreen = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _preferences.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		_save_preferences()
	elif event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else: _go("home")
	elif _page in ["bridge", "atlas"] and event.keycode >= KEY_1 and event.keycode <= KEY_8:
		var focus = get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return
		_choose_role(Catalog.ROLES[event.keycode - KEY_1])

func _make_audio() -> void:
	_ambient = AudioStreamPlayer.new()
	var stream = load("res://assets/audio/itsaso_ambient.wav").duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_ambient.stream = stream
	_ambient.volume_db = -20
	add_child(_ambient)
	if "--test" not in OS.get_cmdline_user_args(): _ambient.play()
	_effects = AudioStreamPlayer.new()
	_effects.volume_db = -10
	_effects.max_polyphony = 4
	add_child(_effects)
	_apply_audio()

func _play_effect(name: String) -> void:
	var cue = name if SoundCaptionQueue.CUES.has(name) else "confirm"
	var path = "res://assets/audio/" + cue + ".wav"
	if not ResourceLoader.exists(path):
		cue = "confirm"
		path = "res://assets/audio/confirm.wav"
	if _sound_captions != null: _sound_captions.present(cue)
	if _effects == null or "--test" in OS.get_cmdline_user_args(): return
	_effects.stream = load(path)
	_effects.play()

func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, _preferences.volume / 100.0)))

func _load_preferences() -> void:
	var cfg = ConfigFile.new()
	if cfg.load("user://preferences.cfg") != OK: return
	var volume = cfg.get_value("app", "volume", 65.0)
	if Catalog.finite_number(volume): _preferences.volume = clampf(volume, 0, 100)
	var scale = cfg.get_value("app", "text_scale", 1.0)
	if Catalog.finite_number(scale): _preferences.text_scale = clampf(scale, 0.9, 1.1)
	for key in ["motion", "fullscreen"]:
		var value = cfg.get_value("app", key, false)
		if value is bool: _preferences[key] = value

func _save_preferences() -> void:
	if _capture_mode: return
	var cfg = ConfigFile.new()
	for key in _preferences: cfg.set_value("app", key, _preferences[key])
	if cfg.save("user://preferences.cfg") != OK: _notice("No se pudieron guardar las preferencias.", false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit()

func _quit() -> void:
	Session.save_game()
	for player in [_ambient, _effects]:
		if player != null:
			player.stop()
			player.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func _exit_tree() -> void:
	for player in [_ambient, _effects]:
		if player != null:
			player.stop()
			player.stream = null

func _argument(args: PackedStringArray, name: String, fallback: String) -> String:
	var index = args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _start_server(args: PackedStringArray) -> void:
	var port = int(_argument(args, "--port", "27840"))
	var loaded = Session.resume_game()
	if not loaded.ok: Session.new_campaign()
	var result = Session.host_session(port)
	if not result.ok: push_error(result.message); get_tree().quit(1); return
	var path = "user://server-access.txt"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: push_error("No se pudo escribir la clave local de la sesión."); get_tree().quit(1); return
	file.store_string(Session.access_key)
	file.close()
	if OS.get_name() == "Linux": FileAccess.set_unix_permissions(path, 384)
	print("LAGUNAK_SERVER_READY UDP ", port, " · La clave está en el archivo local server-access.txt del directorio de datos de Godot.")
	set_process(false)

func _capture(args: PackedStringArray) -> void:
	get_tree().root.gui_embed_subwindows = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_window().size = Vector2i(1600, 900)
	var path = _argument(args, "--capture-dir", "user://captures")
	if DirAccess.make_dir_recursive_absolute(path) != OK: push_error("No se pudo crear la carpeta de capturas."); get_tree().quit(1); return
	await _take(path, "01_inicio.png")
	Session.new_campaign()
	Session.role = "navegacion"
	_target = "argi"
	_go("bridge")
	await _take(path, "02_puente.png")
	Session.role = "ingenieria"
	Session.sim.command("ingenieria", "power", {"system": "sensores", "value": 0})
	Session.sim.command("ingenieria", "power", {"system": "armas", "value": 4})
	for i in 1080: Session.sim.tick(1.0 / 30.0)
	Session.sim.command("ingenieria", "coolant", {"system": "armas"})
	Session._refresh_view()
	_go("bridge")
	await _take(path, "03_ingenieria.png")
	_go("deck")
	await _take(path, "04_cubierta.png")
	_deck.teleport_zone(2)
	await _take(path, "05_reactor.png")
	_go("atlas")
	await _take(path, "06_atlas.png")
	_go("campaign")
	await _take(path, "07_campana.png")
	_go("editor")
	_editor.set_mission(Catalog.missions()[1])
	await _take(path, "08_editor.png")
	Session.role = "ingenieria"
	Session._refresh_view()
	_go("bridge")
	var operations = _open_operations()
	operations.size = Vector2i(1500, 790)
	operations.popup_centered()
	await _take(path, "09_operaciones.png")
	operations.queue_free()
	await get_tree().process_frame
	Session.role = "mando"
	Session.order("assist_begin", {"recipient": "ingenieria", "mode": "puzzle"})
	var assistance = _open_assistance()
	assistance.size = Vector2i(1500, 790)
	assistance.popup_centered()
	await _take(path, "10_asistencia.png")
	assistance.queue_free()
	await get_tree().process_frame
	_go("editor")
	_editor._open_ship_design()
	await _take(path, "11_astillero.png")
	for child in _editor.get_children():
		if child is ShipDesignEditor: child.queue_free()
	await get_tree().process_frame
	_go("deck")
	_deck.teleport_zone(8)
	_deck.body.position = WorldDeck.ZONES[8].at + Vector3(14, 0.4, 24)
	_deck.body.look_at(WorldDeck.ZONES[8].at + Vector3(0, 0.4, -5))
	await _take(path, "12_museo.png")
	var book = _open_leisure_interaction({"kind": "book"})
	await _take(path, "13_libro.png")
	book.queue_free()
	await get_tree().process_frame
	for entry in [[9, "14_playa.png"], [7, "15_cantina.png"], [10, "16_terraza.png"], [11, "17_estudio.png"], [12, "18_recuerdos.png"]]:
		_deck.teleport_zone(entry[0])
		if entry[0] == 9:
			_deck.body.position = WorldDeck.ZONES[9].at + Vector3(5, 0.4, 40)
			_deck.body.look_at(WorldDeck.ZONES[9].at + Vector3(20, 0.4, -5))
		await _take(path, entry[1])
	_deck.teleport_zone(7)
	var table_window = _open_leisure_interaction({"kind": "table", "table": "poker"})
	table_window.send("join")
	table_window.send("bot")
	table_window.send("bot")
	table_window.send("start")
	await _take(path, "19_poker.png")
	table_window.queue_free()
	if "--capture-campaign-editor" in args:
		# queue_free is deferred; release the table's exclusive modal first.
		await get_tree().process_frame
		_go("campaign")
		var editor = _open_campaign_editor()
		editor.fields.title.text = "Expedición de los tres faros"
		editor._add_mission()
		editor._add_mission()
		editor.linear.button_pressed = false
		for field in editor.dependency_fields.values(): field.button_pressed = true
		editor._apply_dependencies()
		if editor.document.missions.size() != 3 or not CampaignDocument.validate(editor.document).is_empty():
			push_error("El taller de campañas no produjo contenido válido.")
			get_tree().quit(1)
			return
		await _take(path, "campaign-editor.png")
		editor.queue_free()
		print("LAGUNAK_CAMPAIGN_CAPTURE_OK")
	print("LAGUNAK_CAPTURE_OK 19 screenshots")
	_ambient.stop()
	_effects.stop()
	_ambient.stream = null
	_effects.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)

func _take(path: String, filename: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var texture = get_viewport().get_texture()
	if texture == null or texture.get_image().save_png(path.path_join(filename)) != OK:
		push_error("No se pudo guardar la captura: " + filename)
		get_tree().quit(1)
	else: print("CAPTURE ", filename)


func _open_gm_console() -> void:
	if not GMLiveActions.can_direct(Session): return
	if is_instance_valid(_gm_window):
		_gm_window.grab_focus()
		return
	var old_focus = get_viewport().gui_get_focus_owner()
	var focus_ref = weakref(old_focus) if old_focus != null else null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_gm_window = GMHotConsole.new()
	_gm_window.setup(Session)
	add_child(_gm_window)
	_gm_window.tree_exited.connect(_restore_modal_focus.bind(focus_ref))
	_gm_window.popup_centered_clamped(Vector2i(1060, 740), 0.95)

func _open_asset_library() -> void:
	if is_instance_valid(_asset_window):
		_asset_window.grab_focus()
		return
	var old_focus = get_viewport().gui_get_focus_owner()
	var focus_ref = weakref(old_focus) if old_focus != null else null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_asset_window = AssetLibraryWindow.new()
	add_child(_asset_window)
	_asset_window.tree_exited.connect(_restore_modal_focus.bind(focus_ref))
	_asset_window.popup_centered_clamped(Vector2i(1140, 720), 0.95)

func _restore_modal_focus(reference: WeakRef) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var control = reference.get_ref() if reference != null else null
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.call_deferred("grab_focus")
