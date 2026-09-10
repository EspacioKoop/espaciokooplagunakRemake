class_name FleetConsole
extends Window
## Strategic fleet command surface for allied and hostile contact AI.

var fleet: Node
var body: VBoxContainer
var status: Label
var selected = ""

func _ready() -> void:
	title = "Flotas y facciones · F5"
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
	top.add_child(ConsoleUI.label("F5 · cerrar", 13, ConsoleUI.MUTED))
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
	if selected.is_empty():
		side.add_child(ConsoleUI.paragraph("Selecciona una nave identificada. Las aliadas obedecen si la relación con su facción lo permite.", 14))
	else:
		side.add_child(ConsoleUI.label("Objetivo: " + selected, 16, ConsoleUI.TEAL))
		for order in FleetAI.ORDERS:
			if order == "intercept": continue
			var button = ConsoleUI.button(order.capitalize(), func(value = order): fleet.command("order", {"target": selected, "order": value, "objective": ""}))
			button.disabled = not can_order
			side.add_child(button)
		var enemy = OptionButton.new()
		for row in rows:
			if row.kind == "hostile":
				enemy.add_item(row.name)
				enemy.set_item_metadata(enemy.item_count - 1, row.id)
		side.add_child(enemy)
		var intercept = ConsoleUI.button("Interceptar hostil", func(): fleet.command("order", {"target": selected, "order": "intercept", "objective": enemy.get_item_metadata(enemy.selected) if enemy.item_count > 0 else ""}), true)
		intercept.disabled = not can_order or enemy.item_count == 0
		side.add_child(intercept)
	var convoy = ConsoleUI.card(side, "CONVOY")
	convoy.add_child(ConsoleUI.paragraph("Mando puede formar convoyes desde dos hasta seis aliados mediante la API autoritativa; las naves pasan a escolta y comparten identificador de flota.", 13))
	status = ConsoleUI.label("IA estratégica activa: patrulla, escolta, intercepción y retirada por moral.", 13, ConsoleUI.MUTED)
	body.add_child(status)

func _select(id: String) -> void:
	selected = id
	_rebuild()

func _notice(text: String, ok: bool) -> void:
	if status != null:
		status.text = text
		status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
	call_deferred("_rebuild")
