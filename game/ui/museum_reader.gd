class_name MuseumReader
extends Window
const TrophyCatalog = preload("res://core/campaign_trophy_catalog.gd")
signal page_changed(page: int)
var page = 0
var heading: Label
var body_text: Label
var previous: Button
var next: Button
var trophy_button: Button
var _trophy_window: Window

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
 trophy_button = ConsoleUI.button("Vitrinas de campaña", _open_trophy_gallery)
 trophy_button.name = "CampaignTrophyGallery"
 navigation.add_child(previous)
 navigation.add_child(next)
 navigation.add_child(trophy_button)
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

func _public_campaign() -> Dictionary:
 var session = get_node_or_null("/root/Session")
 if session == null:
  return {}
 var public_view: Variant = session.get("view")
 if not public_view is Dictionary:
  return {}
 var campaign: Variant = public_view.get("campaign", {})
 return campaign.duplicate(true) if campaign is Dictionary else {}

func _open_trophy_gallery() -> void:
 if is_instance_valid(_trophy_window):
  _trophy_window.popup_centered()
  return
 _trophy_window = Window.new()
 _trophy_window.name = "CampaignTrophyGalleryWindow"
 _trophy_window.title = "Vitrinas de campaña"
 _trophy_window.size = Vector2i(680, 560)
 _trophy_window.min_size = Vector2i(520, 400)
 _trophy_window.close_requested.connect(_trophy_window.queue_free)
 _trophy_window.tree_exiting.connect(_clear_trophy_window)
 add_child(_trophy_window)
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left", "top", "right", "bottom"]:
  margin.add_theme_constant_override("margin_" + edge, 24)
 _trophy_window.add_child(margin)
 var content = ConsoleUI.column(margin, 14)
 content.add_child(ConsoleUI.label("Vitrinas de campaña", 26, ConsoleUI.TEAL))
 var projection: Dictionary = TrophyCatalog.project(_public_campaign())
 if not projection.has("trophies"):
  content.add_child(ConsoleUI.paragraph("No se puede exponer el progreso de campaña recibido.", 18, ConsoleUI.TEXT))
 else:
  var trophies: Array = projection.trophies
  var unlocked := 0
  for trophy in trophies:
   if trophy.unlocked:
    unlocked += 1
  var summary = ConsoleUI.paragraph("%d / %d trofeos expuestos · progreso público de esta campaña" % [unlocked, trophies.size()], 18, ConsoleUI.MUTED)
  summary.name = "UnlockedTrophyCount"
  content.add_child(summary)
  var scroll = ScrollContainer.new()
  ConsoleUI.expand(scroll)
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  content.add_child(scroll)
  var cards = ConsoleUI.column(scroll, 12)
  for trophy in trophies:
   var status := "EXPUESTO" if trophy.unlocked else "PENDIENTE"
   var card = ConsoleUI.card(cards, "%s · %s" % [status, trophy.title])
   var title_label = card.get_child(0) if card.get_child_count() > 0 else null
   if title_label is Label:
    title_label.add_theme_font_size_override("font_size", 20)
    title_label.add_theme_color_override("font_color", ConsoleUI.TEAL if trophy.unlocked else ConsoleUI.MUTED)
   var placard = ConsoleUI.paragraph(trophy.placard, 17, ConsoleUI.TEXT)
   placard.name = "TrophyPlacard-%s" % trophy.id
   card.add_child(placard)
   card.add_child(ConsoleUI.paragraph("Progreso público: %s" % trophy.progress, 15, ConsoleUI.MUTED))
 _trophy_window.popup_centered()

func _clear_trophy_window() -> void:
 _trophy_window = null
