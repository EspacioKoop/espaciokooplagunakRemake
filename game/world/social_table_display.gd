class_name SocialTableDisplay
extends Node3D
## Recipient-specific 3D projection of a native ShipLounge table.
## It consumes only the injected recipient view, so hidden cards never cross the privacy boundary.

var table_id = "poker"
var session: Node
var _dynamic: Node3D
var _signature = ""

func _ready() -> void:
	_dynamic = Node3D.new()
	_dynamic.name = "Projection"
	add_child(_dynamic)
	_refresh(true)

func _process(_delta: float) -> void:
	_refresh(false)

func _refresh(force: bool) -> void:
	if session == null or not is_instance_valid(session): return
	var lounge: Dictionary = session.view.get("lounge", {})
	var table: Dictionary = lounge.get("tables", {}).get(table_id, {})
	var signature = "empty" if table.is_empty() else "%s:%s:%s" % [table.get("revision", -1), table.get("hands", 0), table.get("round", {}).get("stage", "")]
	if not force and signature == _signature: return
	_signature = signature
	for child in _dynamic.get_children(): child.queue_free()
	if table.is_empty():
		_title(_table_name(), Vector3(0, 1.25, 0), 30, ConsoleUI.MUTED)
		return
	_title(table.get("title", _table_name()), Vector3(0, 1.25, 0), 29, ConsoleUI.TEAL)
	var seats: Array = table.get("seats", [])
	for i in seats.size():
		var seat: Dictionary = seats[i]
		var angle = TAU * float(i) / maxf(1.0, seats.size()) - PI * 0.5
		var position = Vector3(cos(angle) * 2.25, 0.0, sin(angle) * 1.9)
		_avatar(seat, position, angle)
		var status = "NPC" if seat.get("bot", false) else ("AUSENTE" if seat.get("away", false) else "TRIPULANTE")
		var resource = "%d dados" % int(seat.get("dice", 0)) if table_id == "dados" else "%d fichas" % int(seat.get("chips", 0))
		_title("%s\n%s · %s" % [seat.get("name", "—"), status, resource], position + Vector3(0, 1.35, 0), 18, ConsoleUI.MUTED if seat.get("away", false) else ConsoleUI.TEXT)
	var round: Dictionary = table.get("round", {})
	if round.is_empty():
		_title("Mesa preparada\nE · jugar", Vector3(0, 0.62, 0), 22, ConsoleUI.AMBER)
		return
	match table_id:
		"poker": _render_poker(round)
		"blackjack": _render_blackjack(round)
		"dados": _render_dice(round)
	if not str(round.get("result", "")).is_empty(): _title(round.result, Vector3(0, 0.34, 1.55), 18, ConsoleUI.AMBER)

func _avatar(seat: Dictionary, position: Vector3, angle: float) -> void:
	var avatar = SpaceView.model("crew")
	avatar.position = position + Vector3(0, 0.04, 0)
	avatar.rotation.y = -angle - PI * 0.5
	avatar.scale = Vector3(0.62, 0.46, 0.62) if not seat.get("away", false) else Vector3.ONE * 0.5
	_dynamic.add_child(avatar)
	var personality = posmod(str(seat.get("name", "crew")).hash(), 3)
	avatar.rotation.z = [-0.035, 0.0, 0.035][personality]
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		if seat.get("away", false): mesh.transparency = 0.65
		elif seat.get("bot", false):
			var material = StandardMaterial3D.new()
			material.albedo_color = [Color("4e9a91"), Color("a88752"), Color("7a718f")][personality]
			material.roughness = 0.78
			mesh.material_override = material

func _render_poker(round: Dictionary) -> void:
	var board: Array = round.get("board", [])
	for i in board.size(): _card(int(board[i]), Vector3((i - (board.size() - 1) * 0.5) * 0.68, 0.18, 0))
	var private_cards: Array = round.get("private", [])
	for i in private_cards.size(): _card(int(private_cards[i]), Vector3((i - 0.5) * 0.72, 0.22, 1.05), true)
	if not private_cards.is_empty(): _title("TU MANO", Vector3(0, 0.46, 1.05), 16, ConsoleUI.TEAL)
	var street = ["Preflop", "Flop", "Turn", "River"][clampi(int(round.get("street", 0)), 0, 3)]
	_title("%s · apuesta %d" % [street, int(round.get("current", 0))], Vector3(0, 0.55, -1.12), 17, ConsoleUI.MUTED)
	_render_public_hands(round)

func _render_blackjack(round: Dictionary) -> void:
	var dealer: Array = round.get("dealer", [])
	for i in dealer.size(): _card(int(dealer[i]), Vector3((i - (dealer.size() - 1) * 0.5) * 0.68, 0.2, -0.65))
	_title("BANCA", Vector3(0, 0.5, -0.65), 16, ConsoleUI.MUTED)
	var private_cards: Array = round.get("private", [])
	for i in private_cards.size(): _card(int(private_cards[i]), Vector3((i - (private_cards.size() - 1) * 0.5) * 0.68, 0.22, 0.75), true)
	if not private_cards.is_empty(): _title("TU MANO · %d" % TableCards.blackjack(private_cards), Vector3(0, 0.5, 0.75), 16, ConsoleUI.TEAL)
	_render_public_hands(round)

func _render_dice(round: Dictionary) -> void:
	var private_dice: Array = round.get("private", [])
	for i in private_dice.size():
		var x = (i - (private_dice.size() - 1) * 0.5) * 0.48
		_die(int(private_dice[i]), Vector3(x, 0.28, 0.85))
	if not private_dice.is_empty(): _title("TUS DADOS", Vector3(0, 0.68, 0.85), 16, ConsoleUI.TEAL)
	var bid: Dictionary = round.get("bid", {})
	if bid.is_empty(): _title("Sin apuesta", Vector3(0, 0.55, -0.35), 18, ConsoleUI.MUTED)
	else:
		_die(int(bid.face), Vector3(0.55, 0.28, -0.35))
		_title("%d ×" % int(bid.amount), Vector3(-0.35, 0.52, -0.35), 22, ConsoleUI.AMBER)
	if round.get("stage", "") == "done":
		var players: Array = round.get("players", [])
		var offset = -float(players.size() - 1) * 0.42
		for player in players:
			for die in player.get("cards", []):
				_die(int(die), Vector3(offset, 0.22, -1.0))
				offset += 0.36

func _render_public_hands(round: Dictionary) -> void:
	var players: Array = round.get("players", [])
	var shown_index = 0
	for player in players:
		var cards: Array = player.get("cards", [])
		if cards.is_empty(): continue
		var base_x = -1.35 + shown_index * 1.35
		for i in cards.size(): _card(int(cards[i]), Vector3(base_x + i * 0.38, 0.16, -1.55))
		shown_index += 1

func _card(card: int, position: Vector3, private_card: bool = false) -> void:
	var root = Node3D.new()
	root.position = position
	_dynamic.add_child(root)
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.56, 0.035, 0.78)
	mesh.mesh = box
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("e6e0ce")
	material.roughness = 0.82
	mesh.material_override = material
	root.add_child(mesh)
	var label = Label3D.new()
	label.text = TableCards.label(card)
	label.position = Vector3(0, 0.045, 0)
	label.rotation.x = -PI * 0.5
	label.font_size = 32
	label.pixel_size = 0.006
	label.modulate = ConsoleUI.RED if int(card) / 13 in [1, 2] else Color("15202b")
	label.no_depth_test = true
	root.add_child(label)
	if private_card:
		var glow = OmniLight3D.new()
		glow.position.y = 0.22
		glow.omni_range = 1.2
		glow.light_energy = 0.25
		glow.light_color = ConsoleUI.TEAL
		root.add_child(glow)

func _die(value: int, position: Vector3) -> void:
	var root = Node3D.new()
	root.position = position
	_dynamic.add_child(root)
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3.ONE * 0.34
	mesh.mesh = box
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("d9d5c8")
	material.roughness = 0.75
	mesh.material_override = material
	root.add_child(mesh)
	_title(str(clampi(value, 1, 6)), position + Vector3(0, 0.26, 0), 22, Color("14212a"))

func _title(text: String, position: Vector3, font_size: int, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	label.position = position
	label.font_size = font_size
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.no_depth_test = true
	_dynamic.add_child(label)

func _table_name() -> String:
	return {"poker": "Póker", "blackjack": "Blackjack", "dados": "Dados de faroleo"}.get(table_id, table_id)
