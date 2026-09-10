class_name MemoryGuardians
extends Node
## Installs before the app's normal plaque reader connects to each new deck.
## All state here is local presentation, derived from Session.view; never a save or RPC.

const BUNDLE = preload("res://assets/models/memory_guardians.glb")
const VARIANTS = ["campaña", "alba", "vigilia"]
var deck: WorldDeck
var gallery: Node3D
var memories: Array = []
var visited: Array = []
var variant_mode = 0
var active_variant = "vigilia"
var guide = -1
var actors: Array = []
var lamps: Array = []
var labels: Array = []
var markers: Array = []
var banner: Label3D
var _last_projection: Array = []

func _ready() -> void:
	get_tree().node_added.connect(_node_added)
	var session = get_node_or_null("/root/Session")
	if session != null: session.updated.connect(refresh)
	var args = OS.get_cmdline_user_args()
	if "--test" in args and ("--memory-capture" in args or "--memory-smoke" in args):
		var capture = preload("res://world/memory_capture.gd").new()
		add_child(capture)
		capture.call_deferred("run", get_parent(), self)

func _node_added(node: Node) -> void:
	if node is WorldDeck and get_parent().is_ancestor_of(node):
		node.ready.connect(_attach.bind(node), CONNECT_ONE_SHOT)

func _attach(new_deck: WorldDeck) -> void:
	deck = new_deck
	actors.clear()
	lamps.clear()
	labels.clear()
	markers.clear()
	_last_projection.clear()
	gallery = Node3D.new()
	gallery.name = "MemoryGallery"
	deck._zone_models[MemoryCatalog.ZONE].add_child(gallery)
	var bundle = BUNDLE.instantiate()
	_spawn(bundle, "memory_keeper", Vector3(-3.5, 0, 28.5), -1)
	for i in MemoryCatalog.MISSIONS.size():
		var point = MemoryCatalog.reading_point(i)
		_spawn(bundle, "memory_sentinel", Vector3(-3.1, 0, point.z), i)
		var prism = _copy_model(bundle, "memory_prism")
		prism.position = Vector3(4.4, 0, point.z)
		gallery.add_child(prism)
		_collision(prism, Vector3(0.75, 1.9, 0.75))
		var light = OmniLight3D.new()
		light.position = point + Vector3(0.4, 2.6, 0)
		light.omni_range = 7
		gallery.add_child(light)
		lamps.append(light)
		var label = _label(point + Vector3(0, 2.9, 0), 28)
		labels.append(label)
	for i in 12:
		var marker = _label(Vector3(0, 0.35, 27.0 - i * 5.0), 38)
		markers.append(marker)
	banner = _label(Vector3(0, 4.0, 26.5), 38)
	bundle.free()
	deck.interaction_requested.connect(_interact)
	deck.zone_changed.connect(func(_zone): _refresh_markers())
	refresh()

func _copy_model(bundle: Node, model_name: String) -> Node3D:
	return bundle.find_child(model_name, true, false).duplicate() as Node3D

func _spawn(bundle: Node, model_name: String, at: Vector3, index: int) -> void:
	var actor = _copy_model(bundle, model_name)
	actor.position = at
	actor.rotation.y = PI / 2.0
	gallery.add_child(actor)
	_collision(actor, Vector3(1.1, 3.25 if index < 0 else 2.25, 1.1))
	actors.append({"model": actor, "gaze": actor.find_child("Gaze*", true, false), "index": index})

func _collision(model: Node3D, size: Vector3) -> void:
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	body.add_child(shape)
	model.add_child(body)

func _label(at: Vector3, font_size: int) -> Label3D:
	var label = Label3D.new()
	label.position = at
	label.font_size = font_size
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	gallery.add_child(label)
	return label

func refresh() -> void:
	if not is_instance_valid(deck) or not is_instance_valid(gallery): return
	var session = get_node_or_null("/root/Session")
	memories = MemoryCatalog.memories(session.view if session != null else {})
	if memories == _last_projection: return
	_last_projection = memories.duplicate(true)
	visited = visited.filter(func(index): return memories[index].unlocked)
	if guide < 0 or not memories[guide].unlocked: guide = MemoryCatalog.guide_index(memories, visited)
	for entry in deck._interactions:
		if entry.zone == MemoryCatalog.ZONE and entry.kind == "memory":
			entry.text = memories[entry.index].text
	_apply_variant()

func _apply_variant() -> void:
	active_variant = MemoryCatalog.campaign_variant(memories) if variant_mode == 0 else VARIANTS[variant_mode]
	var color = {"vigilia": Color("87bfff"), "travesia": Color("75ead5"), "alba": Color("ffcb83")}[active_variant]
	for i in lamps.size():
		lamps[i].light_color = color if memories[i].unlocked else color.darkened(0.28)
		lamps[i].light_energy = 2.2 if memories[i].unlocked else 0.55
		labels[i].text = "%02d · %s" % [i + 1, memories[i].state]
		labels[i].modulate = color if memories[i].unlocked else Color("9faec1")
	banner.text = "MEMORIAS DE LA ITSASO\n" + active_variant.to_upper()
	banner.modulate = color
	_refresh_markers()

func _refresh_markers() -> void:
	if not is_instance_valid(deck) or markers.is_empty(): return
	var guided = guide >= 0
	var target_z = MemoryCatalog.reading_point(guide).z if guided else 0.0
	var body_z = deck.body.position.z - WorldDeck.ZONES[MemoryCatalog.ZONE].at.z
	for marker in markers:
		marker.visible = guided and marker.position.z >= minf(body_z, target_z) - 2.0 and marker.position.z <= maxf(body_z, target_z) + 2.0
		marker.text = ("↑" if target_z < body_z else "↓") + "  %02d" % (guide + 1)
		marker.modulate = Color("ffcb83")
	for i in labels.size():
		labels[i].text = ("→ " if guide == i else "") + "%02d · %s" % [i + 1, memories[i].state]

func _interact(entry: Dictionary) -> void:
	interact(entry)

func interact(entry: Dictionary) -> bool:
	if not is_instance_valid(deck) or deck.zone != MemoryCatalog.ZONE or not deck.is_visible_in_tree(): return false
	var source: Dictionary = {}
	for candidate in deck._interactions:
		if candidate.zone == MemoryCatalog.ZONE and candidate.id == entry.get("id", ""):
			source = candidate
			break
	if source.is_empty(): return false
	var offset: Vector3 = deck.body.position - source.position
	if not offset.is_finite() or Vector2(offset.x, offset.z).length() >= 2.2 or absf(offset.y) > 2.0: return false
	refresh()
	var reply = ""
	match source.kind:
		"memory_keeper":
			variant_mode = (variant_mode + 1) % VARIANTS.size()
			guide = MemoryCatalog.guide_index(memories, visited)
			_apply_variant()
			reply = "Ambiente: %s.\n\n" % active_variant.capitalize()
			reply += ("Sigue las señales ámbar hacia %02d · %s (%s)." % [guide + 1, memories[guide].title, memories[guide].state]) if guide >= 0 else "Esta campaña aún no tiene recuerdos de la ruta Itsaso. La salida permanece abierta."
			reply += "\n\nVuelve a interactuar conmigo para alternar Alba, Vigilia y el ambiente de campaña. Los centinelas señalan cada relato; los hitos se abren al completar misiones."
		"memory_sentinel":
			guide = source.index
			reply = "El centinela gira su mirada hacia %02d · %s, al otro lado del pasillo.\n\n%s. Acércate a su prisma y pulsa E para leer." % [guide + 1, memories[guide].title, memories[guide].state]
		"memory":
			var index: int = source.index
			reply = memories[index].text
			if memories[index].unlocked and index not in visited: visited.append(index)
			guide = MemoryCatalog.guide_index(memories, visited)
		_:
			return false
	# The existing app reader receives this same dictionary after this handler.
	entry.text = reply
	entry.title = source.title
	_refresh_markers()
	return true

func _process(delta: float) -> void:
	if not is_instance_valid(deck) or not is_instance_valid(gallery) or deck.zone != MemoryCatalog.ZONE: return
	_refresh_markers()
	if deck.reduced_motion: return
	for actor in actors:
		var gaze = actor.gaze as Node3D
		if gaze == null: continue
		var target: Vector3 = deck.body.global_position + Vector3(0, 1.6, 0)
		if actor.index >= 0 and actor.index == guide:
			target = gallery.global_position + MemoryCatalog.reading_point(guide) + Vector3(0, 1.6, 0)
		elif target.distance_to(gaze.global_position) > 7.0: continue
		var previous = gaze.quaternion
		gaze.look_at(target, Vector3.UP, true)
		gaze.quaternion = previous.slerp(gaze.quaternion, minf(delta * 3.0, 1.0))
