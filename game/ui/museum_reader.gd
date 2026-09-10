class_name MuseumReader
extends Window
signal page_changed(page: int)
var page = 0
var heading: Label
var body_text: Label
var previous: Button
var next: Button

func _ready() -> void:
 title = "Libro del museo"
 size = Vector2i(760, 530)
 min_size = Vector2i(600, 420)
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 28)
 add_child(margin)
 var root = ConsoleUI.column(margin, 22)
 heading = ConsoleUI.label("", 26, ConsoleUI.TEAL)
 root.add_child(heading)
 var scroll = ScrollContainer.new()
 ConsoleUI.expand(scroll)
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 root.add_child(scroll)
 body_text = ConsoleUI.paragraph("", 20, ConsoleUI.TEXT)
 scroll.add_child(body_text)
 var navigation = ConsoleUI.row(root)
 previous = ConsoleUI.button("← Anterior", turn.bind(-1))
 next = ConsoleUI.button("Siguiente →", turn.bind(1))
 navigation.add_child(previous)
 navigation.add_child(next)
 navigation.add_child(ConsoleUI.button("Cerrar libro", queue_free))
 close_requested.connect(queue_free)
 turn(0)

func turn(direction: int) -> void:
 page = clampi(page + direction, 0, LeisurePlaces.BOOK_PAGES.size() - 1)
 var content: Dictionary = LeisurePlaces.BOOK_PAGES[page]
 heading.text = "%02d / %02d · %s" % [page + 1, LeisurePlaces.BOOK_PAGES.size(), content.title]
 body_text.text = content.text
 previous.disabled = page == 0
 next.disabled = page == LeisurePlaces.BOOK_PAGES.size() - 1
 page_changed.emit(page)
