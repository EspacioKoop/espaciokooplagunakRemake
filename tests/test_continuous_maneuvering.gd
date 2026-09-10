extends SceneTree
var checks = 0
var failures = 0
var session: Node
var thrusters: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error("MANEUVER_FAIL " + label)

func run() -> void:
 session = root.get_node("Session")
 thrusters = root.get_node("Thrusters")
 session.new_campaign()
 session.role = "navegacion"
 var ship: Dictionary = session.sim.state.ship
 ship.heading = 0.0
 ship.target_heading = 0.0
 ship.drift = [0.0, 0.0]
 ship.energy = 100.0
 session.sim.state.operations.maneuver = 100.0
 check(thrusters.command(1.0).ok and is_equal_approx(thrusters.axis, 1.0), "navigation can engage sustained starboard thrust")
 var energy_before = float(ship.energy)
 var maneuver_before = float(session.sim.state.operations.maneuver)
 for i in 10: thrusters._process(0.1)
 var lateral = thrusters.lateral_speed(ship)
 check(lateral > 10.0, "sustained thrust builds lateral velocity over multiple ticks")
 check(float(ship.energy) < energy_before, "continuous thrusters consume ship energy")
 check(float(session.sim.state.operations.maneuver) < maneuver_before, "continuous acceleration consumes maneuver charge")
 var first_speed = lateral
 for i in 10: thrusters._process(0.1)
 check(thrusters.lateral_speed(ship) > first_speed, "lateral velocity continues rising while thrust remains engaged")
 check(thrusters.lateral_speed(ship) <= ContinuousManeuvering.MAX_LATERAL_SPEED * ShipModel.efficiency(ship, "maniobra") + 0.01, "lateral velocity respects maneuver-system speed cap")
 check(thrusters.command(0.0).ok and is_zero_approx(thrusters.axis), "navigation can center lateral controls")
 var before_stabilize = absf(thrusters.lateral_speed(ship))
 for i in 30: thrusters._process(0.1)
 check(absf(thrusters.lateral_speed(ship)) < before_stabilize, "centering activates progressive lateral stabilization")
 for i in 30: thrusters._process(0.1)
 check(absf(thrusters.lateral_speed(ship)) < 0.05, "stabilizers eventually cancel lateral component")
 check(thrusters.command(-0.5).ok, "navigation can engage sustained port thrust")
 for i in 12: thrusters._process(0.1)
 check(thrusters.lateral_speed(ship) < -1.0, "port command creates opposite signed lateral velocity")
 thrusters.command(0.0)
 ship.docked = "station_test"
 check(not thrusters.command(0.5).ok, "docked ship cannot engage lateral thrusters")
 ship.docked = ""
 session.role = "sensores"
 check(not thrusters.command(0.5).ok, "non-navigation station cannot control lateral thrusters")
 session.role = "navegacion"
 ship.systems.maniobra.health = 0.0
 check(thrusters.command(1.0).ok, "navigation command can be requested before system health is evaluated")
 thrusters._process(0.1)
 check(is_zero_approx(thrusters.axis), "inoperative maneuver system automatically drops sustained thrust")
 ship.systems.maniobra.health = 100.0
 print("CONTINUOUS_MANEUVER_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)
