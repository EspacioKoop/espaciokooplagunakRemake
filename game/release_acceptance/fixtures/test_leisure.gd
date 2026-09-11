extends SceneTree
var checks = 0
var failures = 0
var app: Control
var deck
var session
var zones: Array = []

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
 checks += 1
 if not value: failures += 1; push_error("LEISURE_FAIL " + label)
func settle(frames: int = 15) -> void:
 for i in frames: await physics_frame
func place(zone: int, position: Vector3) -> void:
 deck.teleport_zone(zone)
 deck.body.position = zones[zone].at + position + Vector3(0, 0.4, 0)
 deck.body.velocity = Vector3.ZERO
 await settle()

func run() -> void:
 root.size = Vector2i(1600, 900)
 app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await settle(3)
 session = root.get_node("Session")
 app._new_game()
 app._go("deck")
 await settle()
 deck = app._deck
 zones = deck.get_script().get_script_constant_map().ZONES
 check(zones.size() == 13, "ship and six social spaces are real destinations")
 check(deck._corridors != null and deck._corridors.links.size() == 6, "seven ship compartments have six physical no-load corridor links")
 check(deck._map != null and deck._map.visible, "live deck map exists while walking aboard ship")
 var first_gate: Dictionary = deck._corridors.doors[0]
 check(not first_gate.open and not first_gate.collider.disabled, "physical hatch begins closed with collision")
 deck._corridors.toggle(0)
 await settle(3)
 check(deck._corridors.doors[0].open and deck._corridors.doors[0].collider.disabled, "hatch opens physically without changing zone or teleporting")
 deck._corridors.toggle(0)
 await settle(3)
 check(not deck._corridors.doors[0].open, "hatch can be closed again")
 await preload("res://release_acceptance/fixtures/test_ship_corridors.gd").run(self)
 await preload("res://release_acceptance/fixtures/test_ship_deck_layout.gd").run(self)
 for zone in range(7, 13):
  deck.teleport_zone(zone)
  await settle()
  check(deck.body.is_on_floor(), "walkable arrival at " + zones[zone].name)
  check(deck._near_door == -1, "arrival does not trigger exit in " + zones[zone].name)
  check(app._refs.deck_station.disabled, "social room has no misleading ship console")
 check(LeisurePlaces.exhibits().size() == 18, "all eighteen sculpture identities have native entries")
 for entry in LeisurePlaces.interactions(8):
  await place(8, entry.position)
  check(deck.body.is_on_floor(), "museum reading point has reachable floor: " + entry.id)
  check(deck._near_interaction.get("id") == entry.id, "museum interaction resolves its own plaque: " + entry.id)
 await place(8, Vector3(5, 0, 25.6))
 deck.interact()
 await settle(3)
 var reader: MuseumReader
 for child in app.get_children():
  if child is MuseumReader: reader = child
 check(reader != null and deck.book_open, "walking to lectern and E opens native book")
 if reader != null:
  for i in 4: reader.next.pressed.emit()
  check(reader.page == 4 and reader.next.disabled, "book turns through five actual readable pages")
  check(deck._book_page == 4 and deck._page_turn > 0, "page controls drive in-world book animation")
  reader.previous.pressed.emit()
  check(reader.page == 3, "book can turn backwards")
  reader.queue_free()
  await settle(2)
  check(not deck.book_open, "closing reader closes physical book")
 await place(8, Vector3(0, 0, 28.3))
 deck.interact()
 check(deck.zone == 7, "museum exit returns to cantina")
 await place(9, Vector3(0, 0, 50))
 check(not deck.body.test_move(deck.body.global_transform, Vector3(0, 0, -100)), "beach has a continuous walkable route")
 await place(9, Vector3(0, 0, 0))
 check(deck.body.test_move(deck.body.global_transform, Vector3(30, 0, 0)), "shoreline prevents walking into sea")
 await place(9, Vector3(2, 0, -29.5))
 check(deck._near_interaction.get("id") == "beach_lion", "beach lion plaque is reachable")
 var hand = deck._zone_models[9].find_child("second_hand", true, false)
 check(hand != null, "clock has an actual animated hand")
 var before: float = hand.rotation.z
 deck.reduced_motion = false
 await settle(5)
 check(hand.rotation.z != before, "clock advances with scene time")
 deck.reduced_motion = true
 before = hand.rotation.z
 await settle(5)
 check(hand.rotation.z == before, "reduced motion freezes decorative animation")
 await place(9, Vector3(-7, 0, 49.2))
 deck.interact()
 check(deck.zone == 7, "beach phone booth returns to cantina")
 var seat: Dictionary = LeisurePlaces.interactions(10)[0]
 await place(10, seat.position)
 var standing = deck.body.position
 check(deck._near_interaction.get("id") == seat.id, "terrace seat interaction is reachable before sitting")
 deck.interact()
 check(deck.seated and is_equal_approx(deck.camera.position.y, 1.15), "terrace seating changes real viewpoint")
 deck.interact()
 check(not deck.seated and deck.body.position == standing and deck.body.collision_mask == 1, "standing restores reachable pose and collisions")
 await place(11, Vector3(0, 0, -1))
 deck.interact()
 check(deck._studio_lights.filter(func(light): return light.visible).size() == 1, "studio interaction selects a real spotlight")
 for zone in [10, 11, 12]:
  await place(zone, Vector3(0, 0, zones[zone].depth * 0.5 - 0.7))
  deck.interact()
  check(deck.zone == 7, "social room return remains accessible: " + str(zone))
 deck.teleport_zone(7)
 await settle(3)
 var displays: Array = []
 for child in deck._zone_models[7].get_children():
  if child is SocialTableDisplay: displays.append(child)
 check(displays.size() == 3, "cantina has native 3D displays for poker blackjack and liar dice")
 var poker: SocialTableDisplay
 for display in displays:
  if display.table_id == "poker": poker = display
 check(poker != null, "poker table projection is attached to its physical table")
 var joined = session.table_order("table_join", {"table": "poker"})
 check(joined.ok, "local player can sit from the native lounge state")
 check(session.table_order("table_bot", {"table": "poker"}).ok, "native poker can add first table NPC")
 check(session.table_order("table_bot", {"table": "poker"}).ok, "native poker can add second table NPC")
 check(session.table_order("table_start", {"table": "poker"}).ok, "native poker starts while physical table is visible")
 await settle(5)
 if poker != null:
  check(poker._dynamic.get_child_count() > 4, "physical table projects live cards seats and round state")
 var projected: Dictionary = session.view.get("lounge", {}).get("tables", {}).get("poker", {}).get("round", {})
 check(projected.get("private", []).size() == 2, "3D table source contains own private poker hand")
 var foreign_visible = false
 for player in projected.get("players", []):
  if player.get("id", "") != "self" and player.get("cards", []).size() >= 2 and not projected.get("showdown", false): foreign_visible = true
 check(not foreign_visible, "3D projection never receives another hidden poker hand")
 app._ambient.stop()
 app._effects.stop()
 app._ambient.stream = null
 app._effects.stream = null
 app.queue_free()
 await settle(2)
 print("LEISURE_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)
