class_name FleetConsole
extends Window
## Strategic fleet command surface for allied and hostile contact AI.

var fleet: Node
var body: VBoxContainer
var status: Label
var selected = ""

func _ready() -> void:
	title = "Flotas y facciones · F7"
	size = Vector2i(1040, 720)
	transient = true
	theme = ConsoleUI.make_theme()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	body = ConsoleUI.column(margin, 12)
	if fleet != null:
		fleet.updated.connect(_rebuild)
		fleet.notice.connect(_notice)
	_rebuild()

func _rebuild() -> void:
	if body == null or fleet == null: return
	ConsoleUI.clear(body)
	var session = get_tree().root.get_node_or_null("Session")
	var expedition = get_tree().root.get_node_or_null("Expedition")
	var top = ConsoleUI.row(body)
	var heading = ConsoleUI.label("CONTROL ESTRATÉGICO DE FLOTA", 25, ConsoleUI.TEAL)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	top.add_child(ConsoleUI.label("F7 · cerrar", 13, ConsoleUI.MUTED))
	if session == null or session.view.is_empty():
		body.add_child(ConsoleUI.paragraph("Inicia una misión para ver las flotas del sector.", 16))
		return
	var can_order = session.role in ["mando", "comunicaciones"]
	var relations = ConsoleUI.row(body, 10)
	if expedition != null:
		for faction_id in ExpeditionSystems.FACTIONS:
			var definition = ExpeditionSystems.FACTIONS[faction_id]
			var value = int(expedition.data.factions[faction_id].reputation)
			var card = ConsoleUI.card(relations, definition.name.to_upper())
			card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.add_child(ConsoleUI.label("%+d" % value, 20, ConsoleUI.TEAL if value >= 0 else ConsoleUI.RED))
	var content = ConsoleUI.row(body, 12)
	ConsoleUI.expand(content)
	var list_card = ConsoleUI.card(content, "CONTACTOS DE FLOTA")
	list_card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows = fleet.report()
	if rows.is_empty(): list_card.add_child(ConsoleUI.paragraph("No hay naves de facción activas en este sector.", 14))
	for row in rows:
		var line = ConsoleUI.row(list_card)
		var text = ConsoleUI.label("%s · %s · %s · casco %d · moral %d · %s" % [row.name, row.faction, row.kind, int(row.hull), int(row.morale), row.order], 13, ConsoleUI.MUTED)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var choose = ConsoleUI.button("Seleccionar", _select.bind(str(row.id)))
		line.add_child(choose)
	var side = ConsoleUI.card(content, "ÓRDENES")
	side.get_parent().custom_minimum_size.x = 360
	var current: Dictionary = {}
	for row in rows:
		if str(row.id) == selected: current = row
	if current.is_empty():
		side.add_child(ConsoleUI.paragraph("Selecciona una nave aliada para transmitir órdenes. Las hostiles muestran su intención y moral, pero no obedecen.", 14))
	else:
		side.add_child(ConsoleUI.label(current.name, 20, ConsoleUI.TEAL if current.kind == "friendly" else ConsoleUI.RED))
		side.add_child(ConsoleUI.label("Facción %s · orden %s · moral %d" % [current.faction, current.order, int(current.morale)], 13, ConsoleUI.MUTED))
		var target_menu = OptionButton.new()
		for c in session.view.contacts:
			if c.kind == "hostile":
				target_menu.add_item(c.name)
				target_menu.set_item_metadata(target_menu.item_count - 1, c.id)
		side.add_child(ConsoleUI.label("Objetivo para intercepción", 13, ConsoleUI.MUTED))
		side.add_child(target_menu)
		for order in FleetAI.ORDERS:
			var button = ConsoleUI.button(order.capitalize(), _order.bind(order, target_menu), order == "escort")
			button.disabled = not can_order or current.kind != "friendly" or (order == "intercept" and target_menu.item_count == 0)
			side.add_child(button)
	var convoy = ConsoleUI.card(side, "CONVOY")
	convoy.add_child(ConsoleUI.paragraph("Mando puede agrupar todas las naves aliadas visibles en un convoy de escolta; después puede disolverlo desde su identificador.", 13))
	var allied: Array = []
	var fleet_id = ""
	for row in rows:
		if row.kind == "friendly":
			allied.append(row.id)
			if fleet_id.is_empty() and not str(row.fleet).is_empty(): fleet_id = str(row.fleet)
	var form = ConsoleUI.button("Formar convoy con aliadas", func(): fleet.command("form_convoy", {"members": allied}), true)
	form.disabled = session.role != "mando" or allied.size() < 2
	convoy.add_child(form)
	var release = ConsoleUI.button("Disolver convoy", func(): fleet.command("release_convoy", {"fleet": fleet_id}))
	release.disabled = session.role != "mando" or fleet_id.is_empty()
	convoy.add_child(release)
	status = ConsoleUI.label(fleet.last_report if not fleet.last_report.is_empty() else "La IA estratégica se ejecuta en el anfitrión.", 13, ConsoleUI.MUTED)
	body.add_child(status)

func _select(id: String) -> void:
	selected = id
	_rebuild()

func _order(order: String, target_menu: OptionButton) -> void:
	var objective = ""
	if order == "intercept" and target_menu.item_count > 0: objective = str(target_menu.get_item_metadata(target_menu.selected))
	fleet.command("order", {"target": selected, "order": order, "objective": objective})

func _notice(text: String, ok: bool) -> void:
	if status != null:
		status.text = text
		status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
	call_deferred("_rebuild")
