class_name CrewConsole
extends Window
## Character-facing console for probability checks, traits, focus and abilities.

var crew: Node
var body: VBoxContainer
var status: Label

func _ready() -> void:
	title = "Tripulación y capacidades · F4"
	size = Vector2i(1040, 740)
	transient = true
	theme = ConsoleUI.make_theme()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
	add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	body = ConsoleUI.column(scroll, 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if crew != null:
		crew.updated.connect(_rebuild)
		crew.notice.connect(_notice)
	var expedition = get_tree().root.get_node_or_null("Expedition")
	if expedition != null: expedition.updated.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	if body == null or crew == null: return
	ConsoleUI.clear(body)
	var profile: Dictionary = crew.profile()
	if profile.is_empty():
		body.add_child(ConsoleUI.paragraph("No hay una ficha de tripulación disponible.", 17))
		return
	var top = ConsoleUI.row(body)
	var heading = ConsoleUI.label(profile.name.to_upper(), 27, ConsoleUI.TEAL)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.clip_text = true
	heading.custom_minimum_size.x = 140
	top.add_child(heading)
	top.add_child(ConsoleUI.button("Editar ficha", _open_character_editor, true))
	top.add_child(ConsoleUI.label("NIVEL %d · %d/%d XP · F4 cerrar" % [profile.level, profile.xp, profile.level * 10], 14, ConsoleUI.MUTED))
	var meters = ConsoleUI.row(body, 12)
	for info in [["CONCENTRACIÓN", "%d / %d" % [profile.focus, CrewSystem.MAX_FOCUS]], ["CONDICIÓN", "%d%%" % profile.condition], ["ENFOQUE", profile.approach.capitalize()]]:
		var card = ConsoleUI.card(meters, info[0])
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(ConsoleUI.label(info[1], 22, ConsoleUI.AMBER if info[0] == "CONCENTRACIÓN" else ConsoleUI.TEXT))
	var content = ConsoleUI.row(body, 14)
	ConsoleUI.expand(content)
	var left = ConsoleUI.card(content, "HABILIDADES Y TIRADAS")
	left.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.get_parent().custom_minimum_size.x = 480
	for skill in ExpeditionSystems.SKILLS:
		var value = int(profile.skills.get(skill, 0))
		var bonus = value * 2
		left.add_child(ConsoleUI.label("%-14s %d/4   modificador base %+d" % [skill.capitalize(), value, bonus], 14))
	var check_row = ConsoleUI.row(left)
	var skill_menu = OptionButton.new()
	for skill in ExpeditionSystems.SKILLS:
		skill_menu.add_item(skill.capitalize())
		skill_menu.set_item_metadata(skill_menu.item_count - 1, skill)
	check_row.add_child(skill_menu)
	var difficulty = SpinBox.new()
	difficulty.min_value = 5
	difficulty.max_value = 25
	difficulty.value = 12
	difficulty.step = 1
	check_row.add_child(difficulty)
	var focus = CheckBox.new()
	focus.text = "Gastar concentración (+3)"
	focus.disabled = int(profile.focus) <= 0
	check_row.add_child(focus)
	left.add_child(ConsoleUI.button("Resolver prueba", func(): crew.command("check", {"skill": skill_menu.get_item_metadata(skill_menu.selected), "difficulty": int(difficulty.value), "focus": focus.button_pressed}), true))
	if not crew.last_result.is_empty() and crew.last_result.get("actor", "") == crew.actor_id():
		var result: Dictionary = crew.last_result
		left.add_child(ConsoleUI.label("%s · d20 %d %+d = %d / CD %d" % ["ÉXITO" if result.success else "FALLO", result.roll, result.modifier, result.total, result.difficulty], 18, ConsoleUI.TEAL if result.success else ConsoleUI.RED))
		if result.get("advantage", false): left.add_child(ConsoleUI.label("Ventaja aplicada", 13, ConsoleUI.AMBER))
	var traits = ConsoleUI.card(left, "RASGOS")
	if profile.traits.is_empty(): traits.add_child(ConsoleUI.label("Sin rasgos adquiridos", 14, ConsoleUI.MUTED))
	for trait_id in profile.traits:
		traits.add_child(ConsoleUI.label(CrewSystem.TRAITS[trait_id].name, 15, ConsoleUI.TEAL))
	var trait_row = ConsoleUI.row(traits)
	var trait_menu = OptionButton.new()
	for trait_id in CrewSystem.TRAITS:
		trait_menu.add_item(CrewSystem.TRAITS[trait_id].name)
		trait_menu.set_item_metadata(trait_menu.item_count - 1, trait_id)
	trait_row.add_child(trait_menu)
	trait_row.add_child(ConsoleUI.button("Adquirir", func(): crew.command("trait_add", {"trait": trait_menu.get_item_metadata(trait_menu.selected)})))
	var right = ConsoleUI.card(content, "CAPACIDADES")
	right.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var system_menu = OptionButton.new()
	for system in Catalog.SYSTEMS:
		system_menu.add_item(Catalog.SYSTEM_NAMES[system])
		system_menu.set_item_metadata(system_menu.item_count - 1, system)
	right.add_child(ConsoleUI.label("Sistema objetivo para Overclock", 13, ConsoleUI.MUTED))
	right.add_child(system_menu)
	for id in CrewSystem.ABILITIES:
		var ability: Dictionary = CrewSystem.ABILITIES[id]
		var card = ConsoleUI.card(right, ability.name.to_upper())
		card.add_child(ConsoleUI.paragraph(ability.description + " Coste: %d concentración." % ability.cost, 13))
		var use = ConsoleUI.button("Usar", _use_ability.bind(id, system_menu), true)
		use.disabled = int(profile.focus) < int(ability.cost) or int(profile.skills.get(ability.skill, 0)) <= 0
		card.add_child(use)
	var milestones = ConsoleUI.card(right, "HITOS PERSONALES")
	if profile.milestones.is_empty(): milestones.add_child(ConsoleUI.label("Aún no hay hitos de progresión.", 13, ConsoleUI.MUTED))
	for milestone in profile.milestones:
		milestones.add_child(ConsoleUI.label(str(milestone), 13, ConsoleUI.MUTED))
	status = ConsoleUI.label("Las tiradas y capacidades se resuelven en el anfitrión.", 13, ConsoleUI.MUTED)
	body.add_child(status)

func _open_character_editor() -> CharacterEditor:
	# Root-owned, not a child of the periodically rebuilt body (or this console).
	# Closing F4 cannot destroy a dirty draft; its own close path confirms discard.
	for window in get_tree().get_nodes_in_group(CharacterEditor.EDITOR_GROUP):
		if window is CharacterEditor and not window.is_queued_for_deletion():
			window.grab_focus()
			return window
	var editor = CharacterEditor.new()
	editor.expedition = get_tree().root.get_node_or_null("Expedition")
	get_tree().root.add_child(editor)
	editor.popup_centered(Vector2i(1040, 740))
	return editor

func _use_ability(id: String, system_menu: OptionButton) -> void:
	var args = {"ability": id}
	if id == "overclock": args.system = system_menu.get_item_metadata(system_menu.selected)
	crew.command("ability", args)

func _notice(text: String, ok: bool) -> void:
	if status != null:
		status.text = text
		status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
	call_deferred("_rebuild")
