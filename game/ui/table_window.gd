class_name LoungeWindow
extends Window
var selected = "poker"
var _root: VBoxContainer
var _table_area: VBoxContainer
var _status: Label
var _amount: SpinBox
var _face: SpinBox
var _actions: Dictionary = {}
var _management: Dictionary = {}
var _last_revision = -1
var _last_kind = ""
var _notice: Label
var _seat_status: Label
var _config_amount: SpinBox
var _config_option: OptionButton

const WORDS = {"join": "Sentarse / volver", "watch": "Observar", "leave": "Levantarse", "bot": "+ NPC", "remove_bot": "− NPC", "start": "Repartir", "cancel": "Cancelar mano", "fold": "Retirarse", "check": "Pasar", "call": "Igualar", "raise": "Subir hasta", "all_in": "Todo dentro", "show": "Mostrar carta", "hit": "Pedir", "stand": "Plantarse", "double": "Doblar", "bid": "Apostar dados", "doubt": "Dudar"}

func _ready() -> void:
 title = "Mesas de la cantina"
 size = Vector2i(1160, 760)
 min_size = Vector2i(1000, 670)
 var margin = MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 20)
 add_child(margin)
 _root = ConsoleUI.column(margin, 12)
 var choices = ConsoleUI.row(_root)
 for kind in ["poker", "blackjack", "dados"]:
  choices.add_child(ConsoleUI.button({"poker": "Póker", "blackjack": "Blackjack", "dados": "Dados de faroleo"}[kind], func(): selected = kind; _last_revision = -1; refresh()))
 _status = ConsoleUI.label("", 22, ConsoleUI.TEAL)
 _root.add_child(_status)
 var toolbar = ConsoleUI.row(_root, 8)
 for action in ["join", "watch", "leave", "bot", "remove_bot", "start", "cancel"]:
  var button = ConsoleUI.button(WORDS[action], send.bind(action))
  toolbar.add_child(button)
  _management[action] = button
 var scroll = ScrollContainer.new()
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 ConsoleUI.expand(scroll)
 _root.add_child(scroll)
 _table_area = ConsoleUI.column(scroll, 10)
 _table_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _seat_status = ConsoleUI.label("", 16, ConsoleUI.TEAL)
 _root.add_child(_seat_status)
 _notice = ConsoleUI.label("", 16)
 _root.add_child(_notice)
 Session.notice.connect(_notice_received)
 var inputs = ConsoleUI.row(_root, 10)
 inputs.add_child(ConsoleUI.label("Cantidad", 16))
 _amount = SpinBox.new()
 _amount.min_value = 1
 _amount.max_value = 100000
 _amount.value = 5
 inputs.add_child(_amount)
 inputs.add_child(ConsoleUI.label("Cara / carta", 16))
 _face = SpinBox.new()
 _face.min_value = 1
 _face.max_value = 6
 _face.value = 2
 inputs.add_child(_face)
 var buttons = HFlowContainer.new()
 _root.add_child(buttons)
 for action in ["fold", "check", "call", "raise", "all_in", "show", "hit", "stand", "double", "bid", "doubt"]:
  var button = ConsoleUI.button(WORDS[action], send.bind(action))
  buttons.add_child(button)
  _actions[action] = button
 var config = ConsoleUI.row(_root, 8)
 _config_option = OptionButton.new()
 for option in ["Apuesta blackjack", "Ciega pequeña", "Ciega grande", "Fichas iniciales (antes de jugar)"]: _config_option.add_item(option)
 config.add_child(_config_option)
 _config_amount = SpinBox.new()
 _config_amount.min_value = 1
 _config_amount.max_value = 10000
 _config_amount.value = 5
 config.add_child(_config_amount)
 var apply_config = ConsoleUI.button("Aplicar entre manos", func(): Session.order("table_configure", {"table": selected, "option": str(_config_option.get_selected_metadata()), "value": int(_config_amount.value)}))
 config.add_child(apply_config)
 _management.config = apply_config
 var wild = ConsoleUI.button("Alternar unos comodín", func():
  var table: Dictionary = Session.view.get("lounge", {}).get("tables", {}).get(selected, {})
  if not table.is_empty(): Session.order("table_configure", {"table": selected, "option": "wild", "value": not table.config.wild}))
 config.add_child(wild)
 _management.wild = wild
 config.add_child(ConsoleUI.button("Cerrar ventana", queue_free))
 close_requested.connect(queue_free)
 Session.updated.connect(refresh)
 refresh()

func send(action: String) -> Dictionary:
 var parameters = {"table": selected}
 if action in ["raise", "bid"]: parameters.amount = int(_amount.value)
 if action == "bid": parameters.face = int(_face.value)
 if action == "show": parameters.card = int(_face.value) - 1
 var response = Session.order("table_" + action, parameters)
 if not response.ok: _notice_received(response.message, false)
 return response

func refresh() -> void:
 if _root == null: return
 var lounge: Dictionary = Session.view.get("lounge", {})
 var table: Dictionary = lounge.get("tables", {}).get(selected, {})
 if table.is_empty(): _status.text = "Esperando la mesa del anfitrión…"; return
 var round_state: Dictionary = table.round
 var playing = not round_state.is_empty() and round_state.stage == "playing"
 var own: Dictionary = {}
 for seat in table.seats:
  if seat.id == lounge.identity: own = seat
 var turn_name = "Entre manos"
 if playing and round_state.turn >= 0: turn_name = "Tu turno" if round_state.players[round_state.turn].id == lounge.identity else "Turno de " + str(round_state.players[round_state.turn].name)
 _status.text = "%s  ·  %s%s" % [table.title, turn_name, " · %ds" % table.remaining if playing else ""]
 _seat_status.text = "Tu asiento está reservado; pulsa Volver." if not own.is_empty() and own.away else ("Estás sentado. Cerrar la ventana no abandona la mesa." if not own.is_empty() else "Puedes observar o sentarte cuando termine la mano.")
 _management.join.disabled = (not own.is_empty() and not own.away) or (own.is_empty() and (playing or table.seats.size() >= 6))
 _management.watch.disabled = not own.is_empty()
 _management.leave.disabled = false
 for action in ["bot", "remove_bot", "start", "config"]: _management[action].disabled = not table.can_manage or playing
 _management.cancel.disabled = not table.can_manage or round_state.is_empty()
 _management.wild.visible = selected == "dados"
 _management.wild.disabled = not table.can_manage or playing
 if selected != _last_kind:
  _config_option.clear()
  for option in (["small", "big", "initial"] if selected == "poker" else ["bet", "initial"]):
   _config_option.add_item({"small":"Ciega pequeña", "big":"Ciega grande", "bet":"Apuesta", "initial":"Fichas iniciales"}[option])
   _config_option.set_item_metadata(_config_option.item_count - 1, option)
 _config_option.visible = selected != "dados"
 _config_amount.visible = selected != "dados"
 _management.config.visible = selected != "dados"
 _face.max_value = 2 if selected == "poker" else 6
 for action in _actions:
  var relevant = action in {"poker": ["fold", "check", "call", "raise", "all_in", "show"], "blackjack": ["hit", "stand", "double"], "dados": ["bid", "doubt"]}[selected]
  _actions[action].visible = relevant
  _actions[action].disabled = action not in round_state.get("actions", []) or own.is_empty() or own.away
 if table.revision == _last_revision and selected == _last_kind: return
 _last_revision = table.revision
 _last_kind = selected
 for child in _table_area.get_children(): _table_area.remove_child(child); child.queue_free()
 var rules = "Ciegas %d / %d. La subida corta all-in reabre las apuestas. Fichas de mesa; sin recompras." % [table.config.small, table.config.big]
 if selected == "blackjack": rules = "Apuesta %d. Blackjack 3:2 (redondeo inferior). Banca en 17 blando. Doblar solo con dos cartas." % table.config.bet
 elif selected == "dados": rules = "Sube la cantidad o, con igual cantidad, la cara. Los unos %s. Quien pierde resta un dado." % ("son comodín" if table.config.wild else "no son comodín")
 _table_area.add_child(ConsoleUI.paragraph(rules, 16))
 if not round_state.is_empty():
  if selected == "poker":
   _table_area.add_child(ConsoleUI.label("MESA", 22, ConsoleUI.TEAL))
   _cards(_table_area, round_state.board, 5 - round_state.board.size())
   var pot = 0
   for player in round_state.players: pot += int(player.total_bet)
   _table_area.add_child(ConsoleUI.label("Bote %d · Apuesta %d · Subida mínima %d" % [pot, round_state.current, round_state.minimum], 18))
  elif selected == "blackjack":
   _table_area.add_child(ConsoleUI.label("BANCA", 22, ConsoleUI.TEAL))
   _cards(_table_area, round_state.dealer, 1 if playing else 0)
  elif not round_state.bid.is_empty(): _table_area.add_child(ConsoleUI.label("Apuesta: %d dados de cara %d" % [round_state.bid.amount, round_state.bid.face], 25, ConsoleUI.TEAL))
  if selected != "blackjack" and not round_state.private.is_empty():
   var private_text = TableCards.labels(round_state.private) if selected == "poker" else "  ".join(round_state.private.map(func(v): return str(v)))
   if selected == "poker":
    var row = ConsoleUI.row(_table_area)
    row.add_child(ConsoleUI.label("TUS CARTAS", 20, ConsoleUI.TEAL))
    _cards(row, round_state.private)
   else: _table_area.add_child(ConsoleUI.label("TU CUBILETE  " + private_text, 26, ConsoleUI.TEAL))
 var seats = ConsoleUI.card(_table_area, "%d ASIENTOS · %d ESPECTADORES" % [table.seats.size(), table.watchers])
 for seat in table.seats:
  var shown: Dictionary = seat
  for player in round_state.get("players", []):
   if player.id == seat.id: shown = player
  var line = "%s%s%s · %d %s" % [seat.name, " · NPC" if seat.bot else "", " · ausente" if seat.away else "", shown.dice if selected == "dados" else shown.chips, "dados" if selected == "dados" else "fichas"]
  if shown.get("folded", false): line += " · retirado"
  if not shown.get("cards", []).is_empty(): line += "  |  " + ("  ".join(shown.cards.map(func(v): return str(v))) if selected == "dados" else TableCards.labels(shown.cards))
  if not str(shown.get("outcome", "")).is_empty(): line += " · " + shown.outcome
  seats.add_child(ConsoleUI.paragraph(line, 18))
 if not round_state.get("result", "").is_empty(): _table_area.add_child(ConsoleUI.paragraph(round_state.result, 19, ConsoleUI.TEAL))

func _notice_received(message: String, ok: bool) -> void:
 _notice.text = message
 _notice.add_theme_color_override("font_color", ConsoleUI.TEAL if ok else Color("f1bf73"))

func _cards(parent: Node, cards: Array, hidden: int = 0) -> void:
 var row = ConsoleUI.row(parent, 9)
 for i in cards.size() + hidden:
  var card = PanelContainer.new()
  card.custom_minimum_size = Vector2(58, 74)
  var secret = i >= cards.size()
  card.add_theme_stylebox_override("panel", ConsoleUI.style(Color("123943") if secret else Color("f0eadc"), Color("527d80"), 6))
  row.add_child(card)
  var text = "▧" if secret else TableCards.label(int(cards[i]))
  var color = ConsoleUI.TEAL if secret else (Color("b53d47") if int(cards[i]) / 13 in [1,2] else Color("183139"))
  var face = ConsoleUI.label(text, 22, color)
  face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
  card.add_child(face)
