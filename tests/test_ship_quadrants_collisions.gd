extends SceneTree
var checks = 0
var failures = 0
var sim: Simulation

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error("QUADRANT_COLLISION_FAIL " + label)

func fresh() -> void:
 sim = Simulation.new()
 sim.start(Catalog.missions()[0])

func dynamic_contact(id: String, kind: String, position: Array, radius: float = 28.0) -> Dictionary:
 var c = {
  "id": id, "name": id.capitalize(), "kind": kind, "position": position,
  "identified": true, "jammed": false, "known": true, "hull": 100.0,
  "hailed": false, "negotiated": false, "rescued": false, "salvaged": false,
  "probed": false, "pacified": false, "attack_at": 9999.0, "survivors": 0,
  "frequency": 0, "radius": radius
 }
 sim.state.contacts.append(c)
 return c

func run() -> void:
 fresh()
 var ship: Dictionary = sim.state.ship
 check(ship.shield_quadrants.size() == 4, "new ships expose four shield quadrants")
 check(ship.shield_quadrants.front_left == 30 and ship.shield_quadrants.front_right == 30, "front capacity is split between port and starboard")
 check(ship.shield_quadrants.rear_left == 20 and ship.shield_quadrants.rear_right == 20, "rear capacity is split between port and starboard")
 ShipModel.damage(ship, 10, [100.0, 30.0])
 check(ship.shield_quadrants.front_right == 20 and ship.shield_quadrants.front_left == 30, "small starboard-front hit drains only its quadrant")
 check(ship.hull == 100 and ship.shield_segments.front == 50, "quadrant hit keeps aggregate compatibility")
 ShipModel.damage(ship, 25, [100.0, 30.0])
 check(ship.shield_quadrants.front_right == 0 and ship.shield_quadrants.front_left == 25, "overflow continues into sibling front quadrant")
 check(ship.hull == 100, "same-hemisphere overflow protects hull while charge remains")
 ShipModel.damage(ship, 30, [100.0, 30.0])
 check(ship.shield_segments.front == 0 and ship.hull == 95, "hull receives only damage beyond both front quadrants")
 check(ShipModel.quadrant_for_source(ship, [100.0, -100.0]) == "front_left", "bearing selects front-left quadrant")
 check(ShipModel.quadrant_for_source(ship, [-100.0, 100.0]) == "rear_right", "bearing selects rear-right quadrant")
 fresh()
 ship = sim.state.ship
 var aggregate_front = ship.shield_segments.front
 var aggregate_rear = ship.shield_segments.rear
 ship.erase("shield_quadrants")
 ShipModel.initialize(sim.state)
 check(ship.shield_quadrants.size() == 4, "two-segment save migrates to four quadrants")
 check(ship.shield_segments.front == aggregate_front and ship.shield_segments.rear == aggregate_rear, "migration preserves aggregate shield charge")
 check(ShipModel.validate_ship(ship).is_empty(), "migrated quadrant state validates")
 fresh()
 ship = sim.state.ship
 var station = dynamic_contact("collision_station", "station", [220.0, 0.0], 82.0)
 SpacePhysics.move(sim, 0.1, Vector2(500.0, 0.0))
 check(ship.position[0] < 117 and ship.speed == 0, "swept station collision blocks high-speed tunnelling")
 check(ship.shield < 100 and station.hull == 100, "station impact damages Itsaso protection without damaging station")
 check(sim.state.events.back().text.contains("estación"), "station collision is recorded in flight log")
 fresh()
 ship = sim.state.ship
 var ally = dynamic_contact("collision_ally", "friendly", [180.0, 0.0], 28.0)
 SpacePhysics.move(sim, 0.1, Vector2(500.0, 0.0))
 check(ship.position[0] < 131 and ship.speed == 0, "ship-to-ship collision resolves at combined radii")
 check(ship.shield < 100 and ally.hull < 100, "ship-to-ship impact damages both participants")
 check(sim.state.events.back().text.contains("otra nave"), "ship collision is described distinctly in flight log")
 print("SHIP_QUADRANT_COLLISION_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)
