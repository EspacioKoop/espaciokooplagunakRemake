class_name ShipDesignEditor
extends Window
signal design_changed(design: Dictionary)

const LABELS = {"hull": "Casco máximo", "front_shield": "Escudo de proa", "rear_shield": "Escudo de popa", "impulse": "Velocidad de impulso · m/s", "reverse": "Factor de marcha atrás", "turn": "Viraje · grados/s", "acceleration": "Aceleración · m/s²", "warp_speed": "Velocidad por nivel warp", "jump_range": "Salto máximo · m", "radius": "Radio de colisión · m", "beam_arc": "Arco frontal de haces · grados", "beam_range": "Alcance de haces · m", "beam_damage": "Daño por pulso", "beam_cycle": "Recarga del haz · s", "missile_range": "Alcance de misiles · m"}
const AMMO_NAMES = {"homing": "Guiados", "nuke": "Nucleares", "mine": "Minas", "emp": "EMP", "hvli": "HVLI"}
var design: Dictionary = {}
var fields: Dictionary = {}
var status: Label
var dialog: FileDialog
var _exporting = false

func _ready() -> void:
 title = "Astillero · diseño de nave"
 size = Vector2i(920, 720)
 min_size = Vector2i(680, 520)
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
 tools_row.add_child(ConsoleUI.button("Diseño Itsaso", func(): set_design(ShipModel.standard_design())))
 tools_row.add_child(ConsoleUI.button("Importar nave", func(): _choose_file(false)))
 tools_row.add_child(ConsoleUI.button("Exportar nave", func(): _choose_file(true)))
 var scroll = ScrollContainer.new()
 ConsoleUI.expand(scroll)
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 root.add_child(scroll)
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
  spin.step = 0.05 if key in ["reverse", "beam_cycle"] else 1.0
  spin.custom_minimum_size.x = 115
  grid.add_child(spin)
  fields[key] = spin
 for ammo in ShipOperations.AMMO:
  grid.add_child(ConsoleUI.label("Almacén · " + AMMO_NAMES[ammo], 14))
  var spin = SpinBox.new()
  spin.max_value = 1000
  grid.add_child(spin)
  fields["ammo_" + ammo] = spin
 status = ConsoleUI.paragraph("", 14)
 root.add_child(status)
 root.add_child(ConsoleUI.button("Aplicar diseño a la misión", _apply_design, true))
 dialog = FileDialog.new()
 dialog.access = FileDialog.ACCESS_FILESYSTEM
 dialog.filters = PackedStringArray(["*.json ; Diseño de nave"])
 dialog.file_selected.connect(_file_selected)
 add_child(dialog)
 set_design(design)

func set_design(value: Dictionary) -> void:
 design = value.duplicate(true)
 if fields.is_empty(): return
 for key in ["id", "name"]: fields[key].text = design[key]
 for key in ShipModel.DESIGN_LIMITS: fields[key].value = design[key]
 for ammo in ShipOperations.AMMO: fields["ammo_" + ammo].value = design.ammo[ammo]
 status.text = "Diseño cargado."

func read_design() -> Dictionary:
 var value = ShipModel.standard_design()
 for key in ["id", "name"]: value[key] = fields[key].text.strip_edges()
 for key in ShipModel.DESIGN_LIMITS: value[key] = fields[key].value
 for ammo in ShipOperations.AMMO: value.ammo[ammo] = int(fields["ammo_" + ammo].value)
 return value

func _apply_design() -> void:
 var value = read_design()
 status.text = ShipModel.validate_design(value)
 if not status.text.is_empty(): return
 design_changed.emit(value)
 queue_free()

func _choose_file(exporting: bool) -> void:
 _exporting = exporting
 dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
 if exporting: dialog.current_file = "nave-lagunak.json"
 dialog.popup_centered(Vector2i(800, 580))

func _file_selected(path: String) -> void:
 if _exporting:
  var value = read_design()
  status.text = ShipModel.validate_design(value)
  if not status.text.is_empty(): return
  var file = FileAccess.open(path, FileAccess.WRITE)
  if file == null: status.text = "No se pudo abrir el archivo."; return
  file.store_string(JSON.stringify({"format": "lagunak-ship", "version": 1, "design": value}, "  "))
  file.flush()
  status.text = "Diseño exportado." if file.get_error() == OK else "No se pudo escribir el diseño."
  file.close()
 else:
  var file = FileAccess.open(path, FileAccess.READ)
  if file == null: status.text = "No se pudo abrir el archivo."; return
  if file.get_length() > 65536: file.close(); status.text = "El diseño supera 64 KiB."; return
  var value = JSON.parse_string(file.get_as_text())
  file.close()
  if not value is Dictionary or value.get("format") != "lagunak-ship" or value.get("version") != 1: status.text = "Formato de nave no reconocido."; return
  var error = ShipModel.validate_design(value.get("design"))
  if not error.is_empty(): status.text = error; return
  set_design(value.design)
