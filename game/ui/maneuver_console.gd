class_name ManeuverConsole
extends Window
## Continuous lateral-thruster control for Navigation.

var thrusters: Node
var body: VBoxContainer
var status: Label
var speed_label: Label
var resource_label: Label
var _clock = 0.0

func _ready() -> void:
 title = "Maniobra lateral continua · F8"
 size = Vector2i(760, 520)
 min_size = Vector2i(620, 430)
 transient = true
 theme = ConsoleUI.make_theme()
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
 add_child(margin)
 body = ConsoleUI.column(margin, 14)
 if thrusters != null:
  thrusters.updated.connect(_refresh)
  thrusters.notice.connect(_notice)
 _build()

func _build() -> void:
 if body == null: return
 ConsoleUI.clear(body)
 var top = ConsoleUI.row(body)
 var heading = ConsoleUI.label("PROPULSORES DE MANIOBRA", 25, ConsoleUI.TEAL)
 heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 top.add_child(heading)
 top.add_child(ConsoleUI.label("F8 · cerrar", 13, ConsoleUI.MUTED))
 body.add_child(ConsoleUI.paragraph("El empuje se mantiene hasta centrarlo. La nave gana velocidad lateral de forma progresiva; al soltar, los estabilizadores cancelan sólo la componente lateral.", 15))
 var meter = ConsoleUI.card(body, "ESTADO")
 speed_label = ConsoleUI.label("Velocidad lateral 0.0 m/s", 22, ConsoleUI.TEAL)
 meter.add_child(speed_label)
 resource_label = ConsoleUI.label("Carga de maniobra — · energía —", 14, ConsoleUI.MUTED)
 meter.add_child(resource_label)
 var controls = ConsoleUI.card(body, "EMPUJE SOSTENIDO")
 var strong = ConsoleUI.row(controls)
 strong.add_child(_button("Babor 100%", -1.0, true))
 strong.add_child(_button("Babor 50%", -0.5))
 strong.add_child(_button("CENTRAR", 0.0, true))
 strong.add_child(_button("Estribor 50%", 0.5))
 strong.add_child(_button("Estribor 100%", 1.0, true))
 var fine = ConsoleUI.row(controls)
 for value in [-0.25, 0.25]:
  fine.add_child(_button(("Babor" if value < 0 else "Estribor") + " 25%", value))
 controls.add_child(ConsoleUI.paragraph("El antiguo impulso lateral instantáneo sigue disponible en Operaciones por compatibilidad. F8 es el modo físico continuo.", 13, ConsoleUI.MUTED))
 status = ConsoleUI.label("Control exclusivo del puesto de Navegación.", 13, ConsoleUI.MUTED)
 body.add_child(status)
 _refresh()

func _button(text: String, value: float, primary: bool = false) -> Button:
 var button = ConsoleUI.button(text, func(): thrusters.command(value), primary)
 var session = get_tree().root.get_node_or_null("Session")
 button.disabled = session == null or session.role != "navegacion"
 return button

func _process(delta: float) -> void:
 _clock += delta
 if _clock >= 0.15:
  _clock = 0.0
  _refresh()

func _refresh() -> void:
 if thrusters == null or speed_label == null: return
 var session = get_tree().root.get_node_or_null("Session")
 if session == null or session.view.is_empty():
  speed_label.text = "Velocidad lateral —"
  resource_label.text = "Inicia una misión para maniobrar."
  return
 var ship: Dictionary = session.view.get("ship", {})
 var drift = ship.get("drift", [0.0, 0.0])
 var side = Vector2.from_angle(deg_to_rad(float(ship.get("heading", 0.0))) + PI * 0.5)
 var lateral = Vector2(float(drift[0]), float(drift[1])).dot(side)
 var direction = "CENTRADO" if absf(thrusters.axis) < 0.001 else ("ESTRIBOR" if thrusters.axis > 0 else "BABOR")
 speed_label.text = "%s %d%% · velocidad lateral %+.1f m/s" % [direction, int(absf(thrusters.axis) * 100.0), lateral]
 resource_label.text = "Carga de maniobra %.0f%% · energía %.0f%%" % [float(session.view.get("operations", {}).get("maneuver", 0.0)), float(ship.get("energy", 0.0))]

func _notice(text: String, ok: bool) -> void:
 if status == null: return
 status.text = text
 status.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else ConsoleUI.RED)
