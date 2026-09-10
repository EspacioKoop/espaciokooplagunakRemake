extends SceneTree
var checks = 0
var failures = 0
var app: Control
var deck
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
 app._new_game()
 app._go("deck")
 await settle()
 deck = app._deck
 zones = deck.get_script().get_script_constant_map().ZONES
 check(zones.size() == 13, "ship and six social spaces are real destinations")
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
 app._ambient.stop()
 app._effects.stop()
 app._ambient.stream = null
 app._effects.stream = null
 app.queue_free()
 await settle(2)
 print("LEISURE_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)
