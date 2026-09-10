class_name ConsoleUI
extends RefCounted

const BG = Color("08131f")
const PANEL = Color("101f2c")
const LINE = Color("28404d")
const TEXT = Color("e2efed")
const MUTED = Color("8ba6ad")
const TEAL = Color("65dfca")
const AMBER = Color("f6bf70")
const RED = Color("fa8285")
static var font_scale = 1.0

static func style(color: Color, border: Color = LINE, radius: int = 12) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

static func make_theme() -> Theme:
	var t = Theme.new()
	t.default_font_size = int(18 * font_scale)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEAL)
	t.set_color("font_pressed_color", "Button", BG)
	t.set_color("font_disabled_color", "Button", Color("596b73"))
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, button_style(PANEL))
		t.set_stylebox("hover", type, button_style(Color("183039"), TEAL))
		t.set_stylebox("pressed", type, button_style(TEAL, TEAL))
		t.set_stylebox("disabled", type, button_style(Color("101a24"), Color("1c2d39")))
		var focus = style(Color(0, 0, 0, 0), AMBER)
		focus.set_border_width_all(2)
		t.set_stylebox("focus", type, focus)
	t.set_stylebox("panel", "PanelContainer", style(PANEL))
	t.set_stylebox("panel", "PopupMenu", style(PANEL))
	t.set_stylebox("panel", "Window", style(PANEL))
	for type in ["LineEdit", "TextEdit", "CodeEdit"]:
		t.set_stylebox("normal", type, style(BG))
		t.set_stylebox("focus", type, style(BG, TEAL))
		t.set_color("font_color", type, TEXT)
		t.set_color("caret_color", type, TEAL)
		t.set_color("selection_color", type, Color("2a6663"))
	t.set_stylebox("panel", "ItemList", style(BG))
	t.set_stylebox("selected", "ItemList", style(Color("21514f")))
	t.set_stylebox("selected_focus", "ItemList", style(Color("21514f"), TEAL))
	t.set_color("font_color", "ItemList", TEXT)
	for element in ["background", "fill"]:
		var color = TEAL if element == "fill" else Color("1d3441")
		var bar_style = style(color, color, 4)
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: bar_style.set_content_margin(side, 0)
		t.set_stylebox(element, "ProgressBar", bar_style)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	return t

static func button_style(color: Color, border: Color = LINE) -> StyleBoxFlat:
	var box = style(color, border, 10)
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.content_margin_left = 12
	box.content_margin_right = 12
	return box

static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var n = Label.new()
	n.text = text
	n.add_theme_font_size_override("font_size", int(size * font_scale))
	n.add_theme_color_override("font_color", color)
	return n

static func paragraph(text: String, size: int = 17, color: Color = MUTED) -> Label:
	var n = label(text, size, color)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return n

static func button(text: String, action: Callable, primary: bool = false) -> Button:
	var n = Button.new()
	n.text = text
	n.custom_minimum_size.y = 44
	n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	n.pressed.connect(action)
	if primary:
		n.add_theme_stylebox_override("normal", button_style(TEAL, TEAL))
		n.add_theme_color_override("font_color", BG)
	return n

static func column(parent: Node, separation: int = 12) -> VBoxContainer:
	var n = VBoxContainer.new()
	n.add_theme_constant_override("separation", separation)
	parent.add_child(n)
	return n

static func row(parent: Node, separation: int = 12) -> HBoxContainer:
	var n = HBoxContainer.new()
	n.add_theme_constant_override("separation", separation)
	parent.add_child(n)
	return n

static func card(parent: Node, title: String = "") -> VBoxContainer:
	var p = PanelContainer.new()
	parent.add_child(p)
	var box = column(p)
	if not title.is_empty(): box.add_child(label(title, 13, MUTED))
	return box

static func expand(control: Control) -> void:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
