class_name ArmamentConsole
extends Window
## Native control surface for independent ship mounts and turrets.

var armaments: Node
var root_box: VBoxContainer
var status: Label
var target_select: OptionButton
var _refresh_clock = 0.0

func _ready() -> void:
 title = "Armamento modular · F7"
 size = Vector2i(1050, 760)
 min_size = Vector2i(760, 540)
 transient = true
 theme = ConsoleUI.make_theme()
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 18)
 add_child(margin)
 var outer = ConsoleUI.column(margin, 12)
 var heading = ConsoleUI.row(outer)
 var label = ConsoleUI.label("MONTajes Y TORRETAS", 25, ConsoleUI.TEAL)
 label.text = "MONTAJES Y TORRETAS"
 label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 heading.add_child(label)
 heading.add_child(ConsoleUI.label("F7 · cerrar", 13, ConsoleUI.MUTED))
 var target_card = ConsoleUI.card(outer, "BLANCO COMPARTIDO")
 target_select = OptionButton.new()
 target_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 target_card.add_child(target_select)
 var scroll = ScrollContainer.new()
 ConsoleUI.expand(scroll)
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 outer.add_child(scroll)
 root_box = ConsoleUI.column(scroll, 12)
 root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 status = ConsoleUI.label("Cada montaje conserva su arco, alcance y recarga.", 13, ConsoleUI.MUTED)
 outer.add_child(status)
 if armaments != null:
  armaments.updated.connect(_rebuild)
  armaments.notice.connect(_notice)
 _rebuild()

func _process(delta: float) -> void:
 _refresh_clock += delta
 if _refresh_clock >= 0.35:
  _refresh_clock = 0.0
  _rebuild(false)

func _session() -> Node:
 return get_tree().root.get_node_or_null("Session")

func _target_id() -> String:
 return str(target_select.get_item_metadata(target_select.selected)) if target_select != null and target_select.item_count > 0 else ""

func _rebuild(rebuild_targets: bool = true) -> void:
 if root_box == null or armaments == null: return
 var session = _session()
 if session == null or session.view.is_empty():
  ConsoleUI.clear(root_box)
  root_box.add_child(ConsoleUI.paragraph("Inicia una misión para gestionar los montajes.", 16))
  return
 if rebuild_targets or target_select.item_count == 0:
  var selected = _target_id()
  target_select.clear()
  for contact in session.view.get("contacts", []):
   if contact.get("identified", false) and contact.get("kind") == "hostile" and float(contact.get("hull", 0)) > 0:
    target_select.add_item("%s · %d%%" % [contact.name, int(contact.hull)])
    target_select.set_item_metadata(target_select.item_count - 1, contact.id)
  if target_select.item_count == 0:
   target_select.add_item("Sin hostiles identificados")
   target_select.set_item_metadata(0, "")
  else:
   for i in target_select.item_count:
    if target_select.get_item_metadata(i) == selected: target_select.select(i)
 ConsoleUI.clear(root_box)
 var ship: Dictionary = session.view.get("ship", {})
 var loadout: Dictionary = ship.get("loadout", {})
 if loadout.is_empty():
  armaments.ensure()
  loadout = session.sim.state.ship.get("loadout", {}) if session.mode != "client" else {}
 root_box.add_child(ConsoleUI.label("Configuración · " + str(loadout.get("template", "personalizada")).capitalize(), 21))
 var templates = ConsoleUI.card(root_box, "PLANTILLAS · antes de zarpar o atracado")
 var template_row = ConsoleUI.row(templates)
 for template_id in ShipArmaments.TEMPLATES:
  var definition: Dictionary = ShipArmaments.TEMPLATES[template_id]
  var button = ConsoleUI.button(definition.name, func(id = template_id): armaments.command("template", {"template": id}))
  button.disabled = session.role not in ["mando", "armas"]
  template_row.add_child(button)
 for mount in loadout.get("mounts", []):
  var card = ConsoleUI.card(root_box, str(mount.name).to_upper())
  var header = ConsoleUI.row(card)
  var kind = ConsoleUI.label("%s · arco %.0f° · %.0f m" % [str(mount.kind).to_upper(), float(mount.arc), float(mount.range)], 14, ConsoleUI.MUTED)
  kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  header.add_child(kind)
  var remaining = maxf(0.0, float(mount.get("ready_at", 0.0)) - float(session.view.get("time", 0.0)))
  header.add_child(ConsoleUI.label("LISTO" if remaining <= 0 else "%.1f s" % remaining, 14, ConsoleUI.TEAL if remaining <= 0 else ConsoleUI.AMBER))
  card.add_child(ConsoleUI.paragraph("Daño %.0f · ciclo %.2f s · energía %.0f · orientación %+d°" % [float(mount.damage), float(mount.cycle), float(mount.energy), int(mount.arc_center)], 14))
  var actions = ConsoleUI.row(card)
  var fire = ConsoleUI.button("Disparar", func(id = mount.id): armaments.command("fire", {"mount": id, "target": _target_id()}), true)
  fire.disabled = session.role != "armas" or _target_id().is_empty()
  actions.add_child(fire)
  var active_auto = not str(mount.get("auto_target", "")).is_empty()
  var auto = ConsoleUI.button("Quitar auto" if active_auto else "Fijar auto", func(id = mount.id, was_active = active_auto): armaments.command("auto_target", {"mount": id, "target": "" if was_active else _target_id()}))
  auto.disabled = session.role != "armas" or (not active_auto and _target_id().is_empty())
  actions.add_child(auto)
  if active_auto: actions.add_child(ConsoleUI.label("AUTO → " + str(mount.auto_target), 13, ConsoleUI.AMBER))

func _notice(text: String, ok: bool) -> void:
 if status == null: return
 status.text = text
 status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
 call_deferred("_rebuild")
