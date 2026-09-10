class_name LoadoutEditor
extends HBoxContainer
## Edits a detached mission draft; never sends runtime commands.

signal changed

const KIND_NAMES = {"beam": "Haz", "turret": "Torreta", "rail": "Cañón de riel", "emp": "Emisor EMP"}
const PARAMETERS = {
 "arc_center": ["Orientación · °", -180.0, 180.0],
 "arc": ["Arco de tiro · °", 0.0, 360.0],
 "range": ["Alcance · m", 50.0, 3000.0],
 "damage": ["Daño por disparo", 0.0, 100.0],
 "cycle": ["Ciclo · s", 0.1, 30.0],
 "energy": ["Energía por disparo", 0.0, 40.0]
}

var loadout: Dictionary = LoadoutDocument.default_loadout()
var fields: Dictionary = {}
var mounts_list: ItemList
var kind: OptionButton
var templates: OptionButton
var status: Label
var preview: Control
var selected = 0
var _syncing = false
var _pending_numbers: Dictionary = {}
var _add_button: Button
var _copy_button: Button
var _remove_button: Button
var _up_button: Button
var _down_button: Button
var _comparison_window: LoadoutComparisonWindow

func _ready() -> void:
 add_theme_constant_override("separation", 18)
 var left = ConsoleUI.column(self, 8)
 left.custom_minimum_size.x = 230
 left.add_child(ConsoleUI.label("MONTAJES", 14, ConsoleUI.TEAL))
 mounts_list = ItemList.new()
 mounts_list.custom_minimum_size.y = 170
 ConsoleUI.expand(mounts_list)
 left.add_child(mounts_list)
 mounts_list.item_selected.connect(_select)
 var actions = ConsoleUI.row(left, 6)
 _add_button = ConsoleUI.button("Añadir", _add_mount)
 _copy_button = ConsoleUI.button("Duplicar", func(): _add_mount(true))
 actions.add_child(_add_button)
 actions.add_child(_copy_button)
 var ordering = ConsoleUI.row(left, 6)
 _up_button = ConsoleUI.button("↑", func(): _move_mount(-1))
 _up_button.tooltip_text = "Subir montaje"
 _down_button = ConsoleUI.button("↓", func(): _move_mount(1))
 _down_button.tooltip_text = "Bajar montaje"
 _remove_button = ConsoleUI.button("Eliminar", _remove_mount)
 ordering.add_child(_up_button)
 ordering.add_child(_down_button)
 ordering.add_child(_remove_button)
 templates = OptionButton.new()
 for id in ShipArmaments.TEMPLATES:
  templates.add_item(ShipArmaments.TEMPLATES[id].name)
  templates.set_item_metadata(templates.item_count - 1, id)
 left.add_child(templates)
 left.add_child(ConsoleUI.button("Reemplazar por plantilla", _use_template))
 left.add_child(ConsoleUI.button("Comparar montajes…", _open_comparison))
 left.add_child(ConsoleUI.paragraph("Entre 1 y 8 montajes independientes. Cancelar el astillero descarta todos sus cambios.", 13))
 var right = ConsoleUI.column(self, 8)
 ConsoleUI.expand(right)
 var grid = GridContainer.new()
 grid.columns = 2
 grid.add_theme_constant_override("h_separation", 12)
 grid.add_theme_constant_override("v_separation", 6)
 right.add_child(grid)
 for key in ["id", "name"]:
  grid.add_child(ConsoleUI.label("Identificador único" if key == "id" else "Nombre", 14))
  var input = LineEdit.new()
  input.max_length = 32 if key == "id" else 48
  input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  grid.add_child(input)
  fields[key] = input
  input.text_changed.connect(func(value): _change(key, value))
 grid.add_child(ConsoleUI.label("Tipo de montaje", 14))
 kind = OptionButton.new()
 for id in ShipArmaments.MOUNT_KINDS: kind.add_item(KIND_NAMES[id])
 grid.add_child(kind)
 kind.item_selected.connect(func(index): _change("kind", ShipArmaments.MOUNT_KINDS[index]))
 for key in PARAMETERS:
  grid.add_child(ConsoleUI.label(PARAMETERS[key][0], 14))
  var spin = SpinBox.new()
  spin.min_value = PARAMETERS[key][1]
  spin.max_value = PARAMETERS[key][2]
  spin.step = 0.0
  spin.custom_arrow_step = 0.1 if key == "cycle" else 1.0
  spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  grid.add_child(spin)
  fields[key] = spin
  spin.get_line_edit().text_changed.connect(func(_text): _pending_numbers[key] = true)
  spin.value_changed.connect(func(value): _change(key, value))
 right.add_child(ConsoleUI.paragraph("Proa: 0° · babor: −90° · estribor: +90° · popa: ±180°. El tipo determina el efecto; las prestaciones se aplican al iniciar la misión.", 13))
 preview = Control.new()
 preview.custom_minimum_size.y = 180
 preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
 right.add_child(preview)
 preview.draw.connect(_draw_preview)
 status = ConsoleUI.paragraph("", 13)
 right.add_child(status)
 _refresh()

func set_loadout(value: Dictionary) -> bool:
 var error = LoadoutDocument.validate_loadout(value)
 if not error.is_empty():
  if is_node_ready(): status.text = error
  return false
 loadout = LoadoutDocument.authored_loadout(value)
 selected = 0
 if is_node_ready(): _refresh()
 return true

func read_loadout() -> Dictionary:
 # Commit a value typed into a SpinBox even if the user clicks Apply directly.
 _flush_pending()
 return loadout.duplicate(true)

func _open_comparison() -> void:
 if is_instance_valid(_comparison_window) and not _comparison_window.is_queued_for_deletion():
  _comparison_window.grab_focus()
  return
 _comparison_window = LoadoutComparisonWindow.new()
 _comparison_window.configure(read_loadout())
 _comparison_window.theme = ConsoleUI.make_theme()
 add_child(_comparison_window)
 _comparison_window.popup_centered_clamped(Vector2i(800, 640))

func _flush_pending() -> void:
 # Godot redraws numeric text later; applying untouched controls can read stale
 # text after a template/import. Flush only text actually typed by the user.
 for key in _pending_numbers.keys():
  fields[key].apply()
  _pending_numbers.erase(key)

func _select(index: int) -> void:
 if index < 0 or index >= loadout.mounts.size(): return
 _flush_pending()
 selected = index
 _refresh()

func _change(key: String, value: Variant) -> void:
 if _syncing: return
 _pending_numbers.erase(key)
 if loadout.mounts[selected][key] == value: return
 loadout.mounts[selected][key] = value
 loadout.template = "custom"
 _refresh_list()
 _validate()
 changed.emit()

func _new_id() -> String:
 var ids: Array = []
 for mount in loadout.mounts: ids.append(mount.id)
 var number = 1
 while "montaje_%d" % number in ids: number += 1
 return "montaje_%d" % number

func _add_mount(copy_selected: bool = false) -> void:
 if loadout.mounts.size() >= ShipArmaments.MAX_MOUNTS: return
 _flush_pending()
 var mount: Dictionary = loadout.mounts[selected].duplicate(true) if copy_selected else LoadoutDocument.default_loadout().mounts[0]
 mount.id = _new_id()
 mount.name = (mount.name.left(40) + " · copia") if copy_selected else "Nuevo montaje"
 loadout.mounts.append(mount)
 selected = loadout.mounts.size() - 1
 loadout.template = "custom"
 _refresh()
 changed.emit()

func _remove_mount() -> void:
 if loadout.mounts.size() <= 1: return
 _flush_pending()
 loadout.mounts.remove_at(selected)
 selected = mini(selected, loadout.mounts.size() - 1)
 loadout.template = "custom"
 _refresh()
 changed.emit()

func _move_mount(direction: int) -> void:
 var destination = selected + direction
 if destination < 0 or destination >= loadout.mounts.size(): return
 _flush_pending()
 var mount = loadout.mounts.pop_at(selected)
 loadout.mounts.insert(destination, mount)
 selected = destination
 loadout.template = "custom"
 _refresh()
 changed.emit()

func _use_template() -> void:
 set_loadout(ShipArmaments.template(templates.get_item_metadata(templates.selected)))
 changed.emit()

func _refresh() -> void:
 _syncing = true
 _pending_numbers.clear()
 var mount: Dictionary = loadout.mounts[selected]
 for key in ["id", "name"]: fields[key].text = mount[key]
 for key in PARAMETERS: fields[key].set_value_no_signal(mount[key])
 kind.select(ShipArmaments.MOUNT_KINDS.find(mount.kind))
 _refresh_list()
 _syncing = false
 _validate()

func _refresh_list() -> void:
 mounts_list.clear()
 for mount in loadout.mounts:
  mounts_list.add_item(str(mount.name))
  mounts_list.set_item_tooltip(mounts_list.item_count - 1, "%s · %s" % [mount.id, KIND_NAMES[mount.kind]])
 mounts_list.select(selected)
 _add_button.disabled = loadout.mounts.size() >= ShipArmaments.MAX_MOUNTS
 _copy_button.disabled = _add_button.disabled
 _remove_button.disabled = loadout.mounts.size() <= 1
 _up_button.disabled = selected == 0
 _down_button.disabled = selected == loadout.mounts.size() - 1

func _validate() -> void:
 var error = LoadoutDocument.validate_loadout(loadout)
 status.text = error if not error.is_empty() else "%d / %d montajes · configuración válida" % [loadout.mounts.size(), ShipArmaments.MAX_MOUNTS]
 status.add_theme_color_override("font_color", ConsoleUI.AMBER if not error.is_empty() else ConsoleUI.TEAL)
 preview.queue_redraw()

func _draw_preview() -> void:
 var center = preview.size * 0.5
 var radius = maxf(1.0, minf(preview.size.x - 80.0, preview.size.y - 36.0) * 0.5)
 var longest = 50.0
 for mount in loadout.mounts: longest = maxf(longest, float(mount.range))
 preview.draw_circle(center, radius, ConsoleUI.LINE, false, 1.0, true)
 preview.draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), ConsoleUI.LINE)
 preview.draw_line(center - Vector2(0, radius), center + Vector2(0, radius), ConsoleUI.LINE)
 # Draw selected last, so the editable arc stays visible over the other mounts.
 var order = range(loadout.mounts.size())
 order.erase(selected)
 order.append(selected)
 for index in order:
  var mount: Dictionary = loadout.mounts[index]
  var start = deg_to_rad(float(mount.arc_center) - float(mount.arc) * 0.5) - PI * 0.5
  var end = start + deg_to_rad(float(mount.arc))
  var reach = radius * float(mount.range) / longest
  var color = ConsoleUI.TEAL if index == selected else ConsoleUI.MUTED * Color(1, 1, 1, 0.4)
  preview.draw_arc(center, reach, start, end, 80, color, 2.0 if index == selected else 1.0, true)
  if float(mount.arc) < 360:
   preview.draw_line(center, center + Vector2.from_angle(start) * reach, color, 1.0, true)
   preview.draw_line(center, center + Vector2.from_angle(end) * reach, color, 1.0, true)
 preview.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -9), center + Vector2(-5, 6), center + Vector2(5, 6)]), ConsoleUI.TEXT)
 var font = ThemeDB.fallback_font
 preview.draw_string(font, Vector2(center.x - 16, 14), "PROA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ConsoleUI.TEXT)
 preview.draw_string(font, Vector2(4, preview.size.y - 2), "Radio exterior: %.2f m" % longest, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ConsoleUI.MUTED)
