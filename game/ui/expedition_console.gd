class_name ExpeditionConsole
extends Window
## Standalone console for campaign-wide systems that do not belong to a single ship station.

var systems: Node
var tabs: TabContainer
var status: Label

func _ready() -> void:
	title = "Sistemas de expedición · F2"
	size = Vector2i(1180, 760)
	transient = true
	theme = ConsoleUI.make_theme()
	_build()
	if systems != null:
		systems.updated.connect(_rebuild)
		systems.notice.connect(_notice)

func _build() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var root = ConsoleUI.column(margin, 12)
	var heading = ConsoleUI.row(root)
	var title_label = ConsoleUI.label("CENTRO DE EXPEDICIÓN", 25, ConsoleUI.TEAL)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	heading.add_child(ConsoleUI.label("F2 · cerrar", 13, ConsoleUI.MUTED))
	tabs = TabContainer.new()
	ConsoleUI.expand(tabs)
	root.add_child(tabs)
	status = ConsoleUI.label("Atlas, tripulación y dirección viven en el ejecutable standalone.", 13, ConsoleUI.MUTED)
	root.add_child(status)
	_rebuild()

func _rebuild() -> void:
	if tabs == null or systems == null:
		return
	var selected = tabs.current_tab
	ConsoleUI.clear(tabs)
	_make_atlas()
	_make_factions()
	_make_crew()
	_make_chronicle()
	_make_director()
	tabs.current_tab = clampi(selected, 0, tabs.get_tab_count() - 1)

func _tab(tab_name: String) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	scroll.add_child(margin)
	var column = ConsoleUI.column(margin, 12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return column

func _make_atlas() -> void:
	var root = _tab("Atlas")
	root.add_child(ConsoleUI.label("Atlas persistente", 27))
	root.add_child(ConsoleUI.paragraph("Los contactos identificados se conservan por sector aunque cambies de misión. Los marcadores son parte del núcleo local y se sincronizan con la sesión.", 16))
	var current = systems._sector()
	var sector_data: Dictionary = systems.data.atlas.sectors.get(current, {"contacts": {}})
	var summary = ConsoleUI.card(root, "SECTOR ACTUAL")
	summary.add_child(ConsoleUI.label(current, 22, ConsoleUI.TEAL))
	summary.add_child(ConsoleUI.paragraph("%d contactos cartografiados · %d marcadores globales" % [sector_data.get("contacts", {}).size(), systems.data.atlas.markers.size()], 15))
	var sectors = ConsoleUI.card(root, "SECTORES CONOCIDOS")
	if systems.data.atlas.sectors.is_empty():
		sectors.add_child(ConsoleUI.paragraph("Todavía no hay sectores registrados.", 15))
	for id in systems.data.atlas.sectors:
		var entry: Dictionary = systems.data.atlas.sectors[id]
		sectors.add_child(ConsoleUI.label("%s  ·  %d contactos" % [id, entry.get("contacts", {}).size()], 16, ConsoleUI.TEXT))
	var marker = ConsoleUI.card(root, "AÑADIR MARCADOR")
	var row = ConsoleUI.row(marker)
	var label = LineEdit.new()
	label.placeholder_text = "Nombre del marcador"
	label.text = "Punto de interés"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var x = SpinBox.new()
	x.min_value = -12000
	x.max_value = 12000
	x.step = 10
	row.add_child(x)
	var y = SpinBox.new()
	y.min_value = -12000
	y.max_value = 12000
	y.step = 10
	row.add_child(y)
	row.add_child(ConsoleUI.button("Marcar", func(): systems.command("marker_add", {"label": label.text, "x": x.value, "y": y.value})))
	for item in systems.data.atlas.markers:
		var line = ConsoleUI.row(marker)
		var text = ConsoleUI.label("%s · %s · %.0f, %.0f" % [item.label, item.sector, item.position[0], item.position[1]], 14, ConsoleUI.MUTED)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		if item.author == systems.actor_id():
			line.add_child(ConsoleUI.button("Quitar", _remove_marker.bind(str(item.id))))

func _remove_marker(id: String) -> void:
	systems.command("marker_remove", {"id": id})

func _make_factions() -> void:
	var root = _tab("Facciones y comercio")
	root.add_child(ConsoleUI.label("Relaciones y comercio", 27))
	var faction_row = ConsoleUI.row(root, 12)
	for id in ExpeditionSystems.FACTIONS:
		var definition: Dictionary = ExpeditionSystems.FACTIONS[id]
		var state: Dictionary = systems.data.factions[id]
		var card = ConsoleUI.card(faction_row, definition.name.to_upper())
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(ConsoleUI.label("%+d" % int(state.reputation), 25, ConsoleUI.TEAL if state.reputation >= 0 else ConsoleUI.RED))
		card.add_child(ConsoleUI.paragraph(definition.description, 13))
		card.add_child(ConsoleUI.label("Encuentros %d · tratos %d" % [state.encounters, state.trades], 12, ConsoleUI.MUTED))
	var session = get_tree().root.get_node_or_null("Session")
	var docked = session != null and not session.view.is_empty() and not str(session.view.ship.get("docked", "")).is_empty()
	var trade = ConsoleUI.card(root, "MERCADO DE ESTACIÓN" if docked else "MERCADO · ATRACA PARA OPERAR")
	var credits = int(session.view.get("campaign", {}).get("credits", 0)) if session != null else 0
	trade.add_child(ConsoleUI.label("Créditos de campaña: %d" % credits, 18, ConsoleUI.AMBER))
	var stock: Dictionary = systems.inventory()
	for id in ExpeditionSystems.COMMODITIES:
		var commodity: Dictionary = ExpeditionSystems.COMMODITIES[id]
		var line = ConsoleUI.row(trade)
		var label = ConsoleUI.label("%s · llevas %d · compra %d / venta %d" % [commodity.name, int(stock[id]), commodity.buy, commodity.sell], 15)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var buy = ConsoleUI.button("Comprar 1", _trade.bind("trade_buy", id))
		buy.disabled = not docked
		line.add_child(buy)
		var sell = ConsoleUI.button("Vender 1", _trade.bind("trade_sell", id))
		sell.disabled = not docked or int(stock[id]) < 1
		line.add_child(sell)

func _trade(operation: String, item: String) -> void:
	systems.command(operation, {"item": item, "amount": 1})

func _make_crew() -> void:
	var root = _tab("Tripulación")
	root.add_child(ConsoleUI.label("Ficha de tripulación", 27))
	root.add_child(ConsoleUI.paragraph("Cada tripulante conserva un enfoque y cinco habilidades. La ficha viaja con la sesión y queda guardada por el anfitrión.", 16))
	var profile: Dictionary = systems.profile()
	var card = ConsoleUI.card(root, "PERFIL")
	var name = LineEdit.new()
	name.text = profile.name
	name.max_length = 32
	card.add_child(name)
	var approach = OptionButton.new()
	for approach_name in ExpeditionSystems.APPROACHES:
		approach.add_item(approach_name.capitalize())
		approach.set_item_metadata(approach.item_count - 1, approach_name)
	for i in approach.item_count:
		if approach.get_item_metadata(i) == profile.approach:
			approach.select(i)
	card.add_child(approach)
	var skill_values = {}
	for skill in ExpeditionSystems.SKILLS:
		var row = ConsoleUI.row(card)
		var label = ConsoleUI.label(skill.capitalize(), 15)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var value = SpinBox.new()
		value.min_value = 0
		value.max_value = 4
		value.step = 1
		value.value = int(profile.skills.get(skill, 1))
		row.add_child(value)
		skill_values[skill] = value
	var save = ConsoleUI.button("Guardar ficha", func():
		var args = {"name": name.text, "approach": approach.get_item_metadata(approach.selected)}
		for skill in ExpeditionSystems.SKILLS:
			args[skill] = int(skill_values[skill].value)
		systems.command("profile_set", args), true)
	card.add_child(save)
	card.add_child(ConsoleUI.label("Concentración: %d / 3" % int(profile.focus), 16, ConsoleUI.TEAL))
	var roster = ConsoleUI.card(root, "TRIPULACIÓN CONOCIDA")
	for id in systems.data.profiles:
		var other: Dictionary = systems.data.profiles[id]
		roster.add_child(ConsoleUI.label("%s · %s · %d puntos" % [other.name, other.approach.capitalize(), _skill_total(other.skills)], 15))

func _skill_total(skills: Dictionary) -> int:
	var total = 0
	for value in skills.values():
		total += int(value)
	return total

func _make_chronicle() -> void:
	var root = _tab("Crónica y bestiario")
	root.add_child(ConsoleUI.label("Crónica de la expedición", 27))
	var export_button = ConsoleUI.button("Exportar sesión…", _open_session_report)
	export_button.name = "ExportSessionReport"
	var session = get_tree().root.get_node_or_null("Session")
	export_button.disabled = session == null or session.view.is_empty()
	root.add_child(export_button)
	var bestiary = ConsoleUI.card(root, "BESTIARIO / CATÁLOGO")
	if systems.data.bestiary.is_empty():
		bestiary.add_child(ConsoleUI.paragraph("Identifica contactos para alimentar el catálogo.", 15))
	for kind in systems.data.bestiary:
		var entry: Dictionary = systems.data.bestiary[kind]
		bestiary.add_child(ConsoleUI.label("%s · %d avistamientos · %s" % [kind.capitalize(), entry.sightings, ", ".join(entry.names)], 14))
	var chronicle = ConsoleUI.card(root, "ÚLTIMOS REGISTROS")
	var entries: Array = systems.data.chronicle
	for i in range(maxi(0, entries.size() - 60), entries.size()):
		var entry: Dictionary = entries[i]
		chronicle.add_child(ConsoleUI.paragraph("[%s] %s · %s" % [entry.sector, entry.source, entry.text], 13, ConsoleUI.MUTED))

func _open_session_report() -> void:
	var session = get_tree().root.get_node_or_null("Session")
	if session == null or systems == null or session.view.is_empty():
		return
	for child in get_children():
		if child is SessionReportDialog and not child.is_queued_for_deletion():
			child.popup_centered()
			return
	var dialog = SessionReportDialog.new()
	dialog.name = "SessionReportDialog"
	dialog.configure(session.view, systems.data)
	add_child(dialog)
	dialog.popup_centered()

func _make_director() -> void:
	var root = _tab("Dirección")
	root.add_child(ConsoleUI.label("Dirección de juego", 27))
	var session = get_tree().root.get_node_or_null("Session")
	var can_direct = session == null or session.role == "mando"
	root.add_child(ConsoleUI.paragraph("Mando puede variar el tempo, convocar encuentros dentro del sector y autorizar reposición. Todo se resuelve en el anfitrión y aparece inmediatamente en la simulación compartida.", 16))
	var tempo_card = ConsoleUI.card(root, "TEMPO Y ENCUENTROS")
	var tempo = HSlider.new()
	tempo.min_value = 0.25
	tempo.max_value = 3.0
	tempo.step = 0.05
	tempo.value = float(systems.data.director.tempo)
	tempo.custom_minimum_size.y = 38
	tempo_card.add_child(tempo)
	var tempo_label = ConsoleUI.label("Tempo %.2f" % tempo.value, 15, ConsoleUI.TEAL)
	tempo_card.add_child(tempo_label)
	tempo.value_changed.connect(func(value): tempo_label.text = "Tempo %.2f" % value)
	var apply_tempo = ConsoleUI.button("Aplicar tempo", func(): systems.command("director_tempo", {"value": tempo.value}))
	apply_tempo.disabled = not can_direct
	tempo_card.add_child(apply_tempo)
	var automatic = CheckBox.new()
	automatic.text = "Encuentros automáticos cada ciclo de amenaza"
	automatic.button_pressed = bool(systems.data.director.auto_events)
	automatic.disabled = not can_direct
	automatic.toggled.connect(func(value): systems.command("director_auto", {"enabled": value}))
	tempo_card.add_child(automatic)
	var threat = ProgressBar.new()
	threat.max_value = 90
	threat.value = float(systems.data.director.threat)
	threat.custom_minimum_size.y = 12
	tempo_card.add_child(threat)
	var spawn = ConsoleUI.card(root, "CONVOCAR ENCUENTRO")
	var row = ConsoleUI.row(spawn)
	var kind = OptionButton.new()
	for kind_name in ExpeditionSystems.DIRECTOR_KINDS:
		kind.add_item(kind_name.capitalize())
		kind.set_item_metadata(kind.item_count - 1, kind_name)
	row.add_child(kind)
	var name = LineEdit.new()
	name.text = "Patrulla Itzal"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var x = SpinBox.new()
	x.min_value = -3500
	x.max_value = 3500
	x.value = 900
	x.step = 50
	row.add_child(x)
	var y = SpinBox.new()
	y.min_value = -3500
	y.max_value = 3500
	y.step = 50
	row.add_child(y)
	var create = ConsoleUI.button("Convocar", func(): systems.command("director_spawn", {"kind": kind.get_item_metadata(kind.selected), "name": name.text, "x": x.value, "y": y.value}), true)
	create.disabled = not can_direct
	row.add_child(create)
	var supply = ConsoleUI.button("Reposición de emergencia · 25 créditos", func(): systems.command("director_supply", {}))
	supply.disabled = not can_direct
	spawn.add_child(supply)
	spawn.add_child(ConsoleUI.label("Encuentros convocados: %d" % int(systems.data.director.spawned), 14, ConsoleUI.MUTED))

func _notice(text: String, ok: bool) -> void:
	if status == null:
		return
	status.text = text
	status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
	call_deferred("_rebuild")
