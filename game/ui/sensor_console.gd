class_name SensorConsole
extends Window
## Native sensor station extension: range selection, probe view, analysis and hacking puzzles.

var sensors: Node
var root_box: VBoxContainer
var target_menu: OptionButton
var status: Label
var selected_target = ""

func _ready() -> void:
	title = "Sensores avanzados · F3"
	size = Vector2i(1020, 720)
	transient = true
	theme = ConsoleUI.make_theme()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	root_box = ConsoleUI.column(margin, 12)
	if sensors != null:
		sensors.updated.connect(_rebuild)
		sensors.notice.connect(_notice)
	_rebuild()

func _session() -> Node:
	return get_tree().root.get_node_or_null("Session")

func _rebuild() -> void:
	if root_box == null or sensors == null: return
	ConsoleUI.clear(root_box)
	var session = _session()
	var top = ConsoleUI.row(root_box)
	var heading = ConsoleUI.label("MATRIZ DE SENSORES", 25, ConsoleUI.TEAL)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	top.add_child(ConsoleUI.label("F3 · cerrar", 13, ConsoleUI.MUTED))
	if session == null or session.view.is_empty():
		root_box.add_child(ConsoleUI.paragraph("Inicia una expedición para operar los sensores.", 17))
		return
	var allowed = session.role == "sensores"
	if not allowed:
		root_box.add_child(ConsoleUI.paragraph("Esta consola pertenece al puesto de Sensores. En local cambia al puesto Sensores; en red debe operarla su tripulante.", 15, ConsoleUI.AMBER))
	var operator: Dictionary = sensors.operator()
	var controls = ConsoleUI.card(root_box, "BANDA Y ORIGEN")
	var band_row = ConsoleUI.row(controls)
	var band_label = ConsoleUI.label("Banda actual: %s" % ("CORTA · %.0f m" % AdvancedSensors.SHORT_RANGE if operator.band == "short" else "LARGA · %.0f m" % AdvancedSensors.LONG_RANGE), 16, ConsoleUI.TEAL)
	band_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	band_row.add_child(band_label)
	var short = ConsoleUI.button("Corta", func(): sensors.command("band", {"band": "short"}))
	short.disabled = not allowed
	band_row.add_child(short)
	var long = ConsoleUI.button("Larga", func(): sensors.command("band", {"band": "long"}))
	long.disabled = not allowed
	band_row.add_child(long)
	var origin_row = ConsoleUI.row(controls)
	var origin_name = "Itsaso"
	if not str(operator.origin).is_empty():
		for c in session.view.contacts:
			if c.id == operator.origin: origin_name = c.name
	var origin_label = ConsoleUI.label("Origen: " + origin_name, 15)
	origin_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	origin_row.add_child(origin_label)
	var probes = OptionButton.new()
	probes.add_item("Seleccionar sonda…")
	probes.set_item_metadata(0, "")
	for c in session.view.contacts:
		if c.get("probed", false):
			probes.add_item(c.name)
			probes.set_item_metadata(probes.item_count - 1, c.id)
	origin_row.add_child(probes)
	var link = ConsoleUI.button("Enlazar", func():
		var target = str(probes.get_item_metadata(probes.selected))
		if not target.is_empty(): sensors.command("probe_origin", {"target": target}))
	link.disabled = not allowed
	origin_row.add_child(link)
	var clear = ConsoleUI.button("Itsaso", func(): sensors.command("probe_clear", {}))
	clear.disabled = not allowed
	origin_row.add_child(clear)
	var body = ConsoleUI.row(root_box, 12)
	ConsoleUI.expand(body)
	var contacts = ConsoleUI.card(body, "CONTACTOS")
	contacts.get_parent().custom_minimum_size.x = 420
	target_menu = OptionButton.new()
	contacts.add_child(target_menu)
	var first = ""
	for c in session.view.contacts:
		var level = sensors.analysis_level(c.id)
		if c.get("identified", false): level = 3
		var level_name = AdvancedSensors.ANALYSIS_LEVELS[level]
		var caption = "%s · %s · %d m" % [c.name, level_name, _distance(c, session.view.ship)]
		target_menu.add_item(caption)
		target_menu.set_item_metadata(target_menu.item_count - 1, c.id)
		if first.is_empty(): first = c.id
		if c.id == selected_target: target_menu.select(target_menu.item_count - 1)
	if selected_target.is_empty() or not session.view.contacts.any(func(c): return c.id == selected_target): selected_target = first
	for i in target_menu.item_count:
		if target_menu.get_item_metadata(i) == selected_target: target_menu.select(i)
	target_menu.item_selected.connect(func(index): selected_target = str(target_menu.get_item_metadata(index)); call_deferred("_rebuild"))
	var analysis_row = ConsoleUI.row(contacts)
	var analyze = ConsoleUI.button("Analizar", func(): sensors.command("analysis_begin", {"target": selected_target}), true)
	analyze.disabled = not allowed or selected_target.is_empty()
	analysis_row.add_child(analyze)
	var hack = ConsoleUI.button("Hackear", func(): sensors.command("hack_begin", {"target": selected_target}))
	hack.disabled = not allowed or selected_target.is_empty()
	analysis_row.add_child(hack)
	contacts.add_child(ConsoleUI.paragraph("Larga distancia permite adquirir firma y clase. La identidad final y el hackeo requieren banda corta. Una sonda puede convertirse en origen remoto de observación.", 14))
	var readout = ConsoleUI.card(contacts, "LECTURAS")
	for c in session.view.contacts:
		var level = sensors.analysis_level(c.id)
		if c.get("identified", false): level = 3
		var line = "%s · nivel %d/%d" % [c.name, level, 3]
		if sensors.state.hacks.has(c.id): line += " · ENLACE INHIBIDO"
		readout.add_child(ConsoleUI.label(line, 13, ConsoleUI.MUTED))
	var puzzle = ConsoleUI.card(body, "ANÁLISIS DE SEÑAL")
	puzzle.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var task: Dictionary = operator.get("task", {})
	if task.is_empty():
		puzzle.add_child(ConsoleUI.label("Sin reto activo", 22))
		puzzle.add_child(ConsoleUI.paragraph("Elige un contacto y comienza un análisis o una intrusión. El anfitrión genera y valida la secuencia.", 15))
	else:
		puzzle.add_child(ConsoleUI.label("ANÁLISIS" if task.mode == "analysis" else "INTRUSIÓN", 22, ConsoleUI.AMBER))
		var sequence = ""
		for i in task.pattern.size():
			sequence += AdvancedSensors.SYMBOLS[int(task.pattern[i])] + ("  " if i < task.pattern.size() - 1 else "")
		puzzle.add_child(ConsoleUI.label(sequence, 32, ConsoleUI.TEXT))
		puzzle.add_child(ConsoleUI.label("Progreso %d/%d · errores %d/3" % [task.progress, task.pattern.size(), task.errors], 15, ConsoleUI.TEAL))
		var buttons = GridContainer.new()
		buttons.columns = 2
		buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		puzzle.add_child(buttons)
		for i in AdvancedSensors.SYMBOLS.size():
			var button = ConsoleUI.button(AdvancedSensors.SYMBOLS[i], _pulse.bind(i), true)
			button.custom_minimum_size.y = 72
			buttons.add_child(button)
		puzzle.add_child(ConsoleUI.button("Cancelar patrón", func(): sensors.command("cancel", {})))
	status = ConsoleUI.label("Los resultados se resuelven en el anfitrión.", 13, ConsoleUI.MUTED)
	root_box.add_child(status)

func _pulse(value: int) -> void:
	sensors.command("input", {"value": value})

func _distance(contact: Dictionary, ship: Dictionary) -> float:
	return Vector2(contact.position[0] - ship.position[0], contact.position[1] - ship.position[1]).length()

func _notice(text: String, ok: bool) -> void:
	if status != null:
		status.text = text
		status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
	call_deferred("_rebuild")
