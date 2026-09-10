class_name TacticalCombatWindow
extends Window
## Native tactical combat surface. Click units to target and free cells to move.

var combat: Node
var selected = ""
var root_box: VBoxContainer
var board: TacticalBoard
var status: Label

func _ready() -> void:
	title = "Expedición táctica · F6"
	size = Vector2i(1240, 790)
	transient = true
	theme = ConsoleUI.make_theme()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	root_box = ConsoleUI.column(margin, 10)
	if combat != null:
		combat.updated.connect(_rebuild)
		combat.notice.connect(_notice)
	_rebuild()

func _rebuild() -> void:
	if root_box == null or combat == null: return
	ConsoleUI.clear(root_box)
	var header = ConsoleUI.row(root_box)
	var heading = ConsoleUI.label("EXPEDICIÓN TÁCTICA", 25, ConsoleUI.TEAL)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	for mode in [["Táctica", "tactical"], ["3ª persona", "third"], ["POV", "pov"]]:
		var button = ConsoleUI.button(mode[0], combat.set_camera.bind(mode[1]))
		button.disabled = combat.state.is_empty()
		header.add_child(button)
	header.add_child(ConsoleUI.label("F6 · cerrar", 12, ConsoleUI.MUTED))
	if combat.state.is_empty():
		var empty = ConsoleUI.card(root_box, "PREPARAR INCURSIÓN")
		empty.add_child(ConsoleUI.paragraph("Combate por cuadrícula integrado con las fichas de tripulación. La condición, experiencia y recompensas vuelven al estado persistente de la expedición.", 17))
		var row = ConsoleUI.row(empty)
		var kind = OptionButton.new()
		for id in GroundCombat.ENEMIES:
			kind.add_item(GroundCombat.ENEMIES[id].name)
			kind.set_item_metadata(kind.item_count - 1, id)
		row.add_child(kind)
		var count = SpinBox.new()
		count.min_value = 1
		count.max_value = 6
		count.value = 2
		row.add_child(count)
		row.add_child(ConsoleUI.button("Iniciar encuentro", func(): combat.start_encounter(kind.get_item_metadata(kind.selected), int(count.value)), true))
		status = ConsoleUI.label("Mando inicia el encuentro; después cada tripulante actúa en su turno.", 14, ConsoleUI.MUTED)
		root_box.add_child(status)
		return
	var state: Dictionary = combat.state
	var summary = ConsoleUI.row(root_box, 12)
	for info in [["RONDA", str(state.round)], ["ESTADO", str(state.status).to_upper()], ["CÁMARA", str(state.camera).to_upper()]]:
		var card = ConsoleUI.card(summary, info[0])
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(ConsoleUI.label(info[1], 19, ConsoleUI.AMBER if info[0] == "ESTADO" else ConsoleUI.TEXT))
	var content = ConsoleUI.row(root_box, 12)
	ConsoleUI.expand(content)
	var board_panel = PanelContainer.new()
	ConsoleUI.expand(board_panel)
	content.add_child(board_panel)
	board = TacticalBoard.new()
	board.combat = combat
	board.cell_pressed.connect(_cell)
	board.unit_pressed.connect(_select_unit)
	board_panel.add_child(board)
	var side_scroll = ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 390
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(side_scroll)
	var side = ConsoleUI.column(side_scroll, 10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var turn: Dictionary = combat._turn_unit()
	var turn_card = ConsoleUI.card(side, "TURNO ACTUAL")
	if not turn.is_empty():
		turn_card.add_child(ConsoleUI.label(turn.name, 22, ConsoleUI.AMBER))
		turn_card.add_child(ConsoleUI.label("%s · %d/%d salud · armadura %d · movimiento %d" % [turn.team.to_upper(), turn.hp, turn.max_hp, turn.armor, turn.move], 13, ConsoleUI.MUTED))
		turn_card.add_child(ConsoleUI.label("Arma: " + GroundCombat.WEAPONS[turn.weapon].name, 14))
	var actor = combat.actor_id()
	var my_turn = not turn.is_empty() and turn.team == "crew" and str(turn.id) == actor and state.status == "active"
	var selection: Dictionary = combat._unit(selected)
	var selection_card = ConsoleUI.card(side, "OBJETIVO")
	if selection.is_empty():
		selection_card.add_child(ConsoleUI.paragraph("Pulsa sobre una unidad para seleccionarla. Pulsa una casilla libre para moverte durante tu turno.", 14))
	else:
		selection_card.add_child(ConsoleUI.label(selection.name, 19, ConsoleUI.TEAL if selection.team == "crew" else ConsoleUI.RED))
		selection_card.add_child(ConsoleUI.label("Salud %d/%d · defensa %d · %s" % [selection.hp, selection.max_hp, selection.armor, "FUERA DE COMBATE" if selection.down else "ACTIVA"], 13, ConsoleUI.MUTED))
	var actions = ConsoleUI.card(side, "ACCIONES")
	var attack = ConsoleUI.button("Atacar objetivo", func(): combat.command("attack", {"target": selected}), true)
	attack.disabled = not my_turn or selection.is_empty() or selection.team == "crew" or selection.down or turn.acted
	actions.add_child(attack)
	var guard = ConsoleUI.button("Ponerse en guardia", func(): combat.command("guard", {}))
	guard.disabled = not my_turn or turn.acted
	actions.add_child(guard)
	var help = ConsoleUI.button("Asistir aliado", func(): combat.command("help", {"target": selected}))
	help.disabled = not my_turn or selection.is_empty() or selection.team != "crew" or turn.acted
	actions.add_child(help)
	var medicine = ConsoleUI.button("Usar medicina", func(): combat.command("medkit", {"target": selected if not selected.is_empty() else actor}))
	medicine.disabled = not my_turn or turn.acted
	actions.add_child(medicine)
	var end = ConsoleUI.button("Finalizar turno", func(): combat.command("end", {}), true)
	end.disabled = not my_turn
	actions.add_child(end)
	var flee = ConsoleUI.button("Extraerse por el borde", func(): combat.command("flee", {}))
	flee.disabled = not my_turn
	actions.add_child(flee)
	if state.status != "active":
		var outcome = ConsoleUI.card(side, "RESULTADO")
		outcome.add_child(ConsoleUI.label("VICTORIA" if state.winner == "crew" else ("RETIRADA" if state.status == "fled" else "DERROTA"), 28, ConsoleUI.TEAL if state.winner == "crew" else ConsoleUI.RED))
		var session = get_tree().root.get_node_or_null("Session")
		var can_close = session == null or session.role == "mando"
		var close = ConsoleUI.button("Cerrar encuentro", func(): combat.command("close", {}), true)
		close.disabled = not can_close
		outcome.add_child(close)
	var log = ConsoleUI.card(side, "REGISTRO TÁCTICO")
	var entries: Array = state.log
	for i in range(maxi(0, entries.size() - 12), entries.size()):
		log.add_child(ConsoleUI.paragraph(str(entries[i]), 12, ConsoleUI.MUTED))
	status = ConsoleUI.label("Tu turno" if my_turn else ("Turno de " + turn.name if not turn.is_empty() and state.status == "active" else "Encuentro resuelto"), 14, ConsoleUI.TEAL if my_turn else ConsoleUI.MUTED)
	root_box.add_child(status)

func _select_unit(id: String) -> void:
	selected = id
	if not combat.state.is_empty(): combat.state.selected = id
	_rebuild()

func _cell(x: int, y: int) -> void:
	if combat.state.is_empty(): return
	var turn = combat._turn_unit()
	if turn.is_empty() or turn.team != "crew" or str(turn.id) != combat.actor_id(): return
	combat.command("move", {"x": x, "y": y})

func _notice(text: String, ok: bool) -> void:
	if status != null:
		status.text = text
		status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
	call_deferred("_rebuild")
