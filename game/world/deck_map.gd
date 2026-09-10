class_name DeckMap
extends Control
## Live ship map rendered from the same world coordinates used by WorldDeck.
## It never owns navigation state; it only visualises the already-loaded deck.

var deck: Node
const SHIP_LINKS = [[1, 0], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6]]
const MIN_X = -34.0
const MAX_X = 34.0
const MIN_Z = -56.0
const MAX_Z = 56.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(270, 190)

func _process(_delta: float) -> void:
	queue_redraw()

func _point(position: Vector3) -> Vector2:
	var usable = size - Vector2(24, 42)
	var x = remap(clampf(position.x, MIN_X, MAX_X), MIN_X, MAX_X, 0.0, usable.x)
	var y = remap(clampf(position.z, MIN_Z, MAX_Z), MIN_Z, MAX_Z, 0.0, usable.y)
	return Vector2(12 + x, 30 + y)

func _draw() -> void:
	if deck == null or not is_instance_valid(deck): return
	draw_rect(Rect2(Vector2.ZERO, size), Color("101c28e8"), true)
	draw_rect(Rect2(Vector2.ZERO, size), ConsoleUI.LINE, false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(12, 19), "PLANO · ITSASO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ConsoleUI.TEAL)
	for link in SHIP_LINKS:
		var a = _point(WorldDeck.ZONES[link[0]].at)
		var b = _point(WorldDeck.ZONES[link[1]].at)
		draw_line(a, b, Color("41616d"), 4.0, true)
	for i in range(7):
		var point = _point(WorldDeck.ZONES[i].at)
		var active = i == deck.zone
		draw_circle(point, 5.5 if active else 4.0, ConsoleUI.AMBER if active else ConsoleUI.TEAL)
		var short_name = ["Puente", "Pasillo", "Ing.", "Camar.", "Bodega", "Comedor", "Enferm."][i]
		draw_string(ThemeDB.fallback_font, point + Vector2(7, 4), short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ConsoleUI.TEXT if active else ConsoleUI.MUTED)
	if deck.body != null:
		var player = _point(deck.body.position)
		draw_circle(player, 3.2, Color.WHITE)
		var facing = Vector2(-sin(deck.body.rotation.y), -cos(deck.body.rotation.y))
		draw_line(player, player + facing * 10.0, Color.WHITE, 1.5, true)
	var session = get_tree().root.get_node_or_null("Session")
	if session == null: return
	for key in session.poses:
		if int(key) == multiplayer.get_unique_id(): continue
		var pose: Dictionary = session.poses[key]
		var coordinates: Array = pose.get("position", [])
		if coordinates.size() != 3: continue
		var remote = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
		if remote.x < MIN_X or remote.x > MAX_X or remote.z < MIN_Z or remote.z > MAX_Z: continue
		draw_circle(_point(remote), 2.8, ConsoleUI.RED)
