class_name ShipDesignEditor
extends Window
signal design_changed(design: Dictionary)
signal configuration_changed(design: Dictionary, loadout: Dictionary)

const LABELS = {"hull": "Casco máximo", "front_shield": "Escudo de proa", "rear_shield": "Escudo de popa", "impulse": "Velocidad de impulso · m/s", "reverse": "Factor de marcha atrás", "turn": "Viraje · grados/s", "acceleration": "Aceleración · m/s²", "warp_speed": "Velocidad por nivel warp", "jump_range": "Salto máximo · m", "radius": "Radio de colisión · m", "beam_arc": "Arco frontal de haces · grados", "beam_range": "Alcance de haces · m", "beam_damage": "Daño por pulso", "beam_cycle": "Recarga del haz · s", "missile_range": "Alcance de misiles · m"}
const AMMO_NAMES = {"homing": "Guiados", "nuke": "Nucleares", "mine": "Minas", "emp": "EMP", "hvli": "HVLI"}
var design: Dictionary = {}
var loadout: Dictionary = LoadoutDocument.default_loadout()
var loadout_editor: LoadoutEditor
var tabs: TabContainer
var fields: Dictionary = {}
var status: Label
var dialog: FileDialog
var template_picker: OptionButton
var _exporting = false
var _pending_numbers: Dictionary = {}

func _ready() -> void:
 title = "Astillero · diseño de nave"
 size = Vector2i(920, 720)
 min_size = Vector2i(780, 560)
 if design.is_empty(): design = ShipModel.standard_design()
 close_requested.connect(queue_free)
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 22)
 add_child(margin)
 var root = ConsoleUI.column(margin, 14)
 root.add_child(ConsoleUI.label("Diseño de la nave", 26))
 root.add_child(ConsoleUI.paragraph("Estas capacidades se aplican al comenzar la misión. La potencia, las averías y el pilotaje determinan el rendimiento durante la partida.", 15))
 var tools_row = ConsoleUI.row(root)
 tools_row.add_child(ConsoleUI.button("Diseño Itsaso", _reset_design))
 tools_row.add_child(ConsoleUI.button("Importar nave", func(): _choose_file(false)))
 tools_row.add_child(ConsoleUI.button("Exportar nave", func(): _choose_file(true)))
 var templates_row = ConsoleUI.row(root)
 template_picker = OptionButton.new()
 template_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 for entry in ShipTemplateCatalog.entries():
  template_picker.add_item(entry.name)
  template_picker.set_item_metadata(template_picker.item_count - 1, entry.id)
 templates_row.add_child(template_picker)
 templates_row.add_child(ConsoleUI.button("Cargar variante", func():
  if template_picker.selected >= 0: select_template(str(template_picker.get_selected_metadata()))))
 root.add_child(ConsoleUI.paragraph(ShipTemplateCatalog.NOTICE, 13))
 tabs = TabContainer.new()
 ConsoleUI.expand(tabs)
 root.add_child(tabs)
 var scroll = ScrollContainer.new()
 scroll.name = "Estructura"
 ConsoleUI.expand(scroll)
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 tabs.add_child(scroll)
 var grid = GridContainer.new()
 grid.columns = 4
 grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 grid.add_theme_constant_override("h_separation", 20)
 grid.add_theme_constant_override("v_separation", 10)
 scroll.add_child(grid)
 for key in ["id", "name"]:
  grid.add_child(ConsoleUI.label("Identificador" if key == "id" else "Nombre", 15))
  var input = LineEdit.new()
  input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  input.max_length = 64 if key == "id" else 80
  grid.add_child(input)
  fields[key] = input
 for key in ShipModel.DESIGN_LIMITS:
  grid.add_child(ConsoleUI.label(LABELS[key], 14))
  var spin = SpinBox.new()
  spin.min_value = ShipModel.DESIGN_LIMITS[key][0]
  spin.max_value = ShipModel.DESIGN_LIMITS[key][1]
  spin.step = 0.0
  spin.custom_arrow_step = 0.05 if key in ["reverse", "beam_cycle"] else 1.0
  spin.custom_minimum_size.x = 115
  grid.add_child(spin)
  fields[key] = spin
  spin.get_line_edit().text_changed.connect(func(_text): _pending_numbers[key] = true)
  spin.value_changed.connect(func(_value): _pending_numbers.erase(key))
 for ammo in ShipOperations.AMMO:
  grid.add_child(ConsoleUI.label("Almacén · " + AMMO_NAMES[ammo], 14))
  var spin = SpinBox.new()
  spin.max_value = 1000
  grid.add_child(spin)
  fields["ammo_" + ammo] = spin
  var field = "ammo_" + ammo
  spin.get_line_edit().text_changed.connect(func(_text): _pending_numbers[field] = true)
  spin.value_changed.connect(func(_value): _pending_numbers.erase(field))
 var mounts_scroll = ScrollContainer.new()
 mounts_scroll.name = "Montajes"
 mounts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 tabs.add_child(mounts_scroll)
 loadout_editor = LoadoutEditor.new()
 ConsoleUI.expand(loadout_editor)
 mounts_scroll.add_child(loadout_editor)
 loadout_editor.set_loadout(loadout)
 status = ConsoleUI.paragraph("", 14)
 root.add_child(status)
 var footer = ConsoleUI.row(root)
 footer.add_child(ConsoleUI.button("Aplicar diseño a la misión", _apply_design, true))
 footer.add_child(ConsoleUI.button("Cancelar", queue_free))
 dialog = FileDialog.new()
 dialog.access = FileDialog.ACCESS_FILESYSTEM
 dialog.filters = PackedStringArray(["*.json ; Diseño de nave"])
 dialog.file_selected.connect(_file_selected)
 add_child(dialog)
 set_design(design)

func _reset_design() -> void:
 set_design(ShipModel.standard_design())
 loadout_editor.set_loadout(LoadoutDocument.default_loadout())

func select_template(id: String) -> bool:
 var result = ShipTemplateCatalog.configuration(id)
 if result.has("error"):
  status.text = result.error
  return false
 set_design(result.design)
 loadout = result.loadout.duplicate(true)
 loadout_editor.set_loadout(loadout)
 status.text = "%s · %d montajes cargados. Puedes editar y exportar la configuración." % [design.name, loadout.mounts.size()]
 return true

func set_design(value: Dictionary) -> void:
 design = value.duplicate(true)
 if fields.is_empty(): return
 _pending_numbers.clear()
 for key in ["id", "name"]: fields[key].text = design[key]
 for key in ShipModel.DESIGN_LIMITS: fields[key].value = design[key]
 for ammo in ShipOperations.AMMO: fields["ammo_" + ammo].value = design.ammo[ammo]
 status.text = "Diseño cargado."

func read_design() -> Dictionary:
 for key in _pending_numbers.keys():
  fields[key].apply()
  _pending_numbers.erase(key)
 var value = design.duplicate(true)
 for key in ["id", "name"]: value[key] = fields[key].text.strip_edges()
 for key in ShipModel.DESIGN_LIMITS:
  value[key] = fields[key].value
 for ammo in ShipOperations.AMMO:
  value.ammo[ammo] = int(fields["ammo_" + ammo].value)
 return value

func _apply_design() -> void:
 var value = read_design()
 var mounts = loadout_editor.read_loadout()
 status.text = ShipModel.validate_design(value)
 if status.text.is_empty(): status.text = LoadoutDocument.validate_loadout(mounts)
 if not status.text.is_empty(): return
 configuration_changed.emit(value, mounts)
 design_changed.emit(value)
 queue_free()

func _choose_file(exporting: bool) -> void:
 _exporting = exporting
 dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
 if exporting: dialog.current_file = "nave-lagunak.json"
 dialog.popup_centered(Vector2i(800, 580))

func _file_selected(path: String) -> void:
 if _exporting:
  var result = LoadoutDocument.encode(read_design(), loadout_editor.read_loadout())
  if result.has("error"): status.text = result.error; return
  var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
  if file == null: status.text = "No se pudo abrir el archivo."; return
  file.store_string(result.text)
  file.flush()
  var error = file.get_error()
  file.close()
  if error == OK: error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
  status.text = "Diseño y montajes exportados." if error == OK else "No se pudo escribir el diseño."
 else:
  var file = FileAccess.open(path, FileAccess.READ)
  if file == null: status.text = "No se pudo abrir el archivo."; return
  if file.get_length() > LoadoutDocument.MAX_BYTES: file.close(); status.text = "El diseño supera 64 KiB."; return
  var result = LoadoutDocument.decode(file.get_as_text())
  file.close()
  if result.has("error"): status.text = result.error; return
  set_design(result.design)
  loadout_editor.set_loadout(result.loadout)
  status.text = "Diseño antiguo cargado con montajes de exploración Itsaso." if result.legacy else "Diseño y montajes cargados."
