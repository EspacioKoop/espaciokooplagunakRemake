extends SceneTree
var checks = 0
var failures = 0
var sim: Simulation

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
 checks += 1
 if not value: failures += 1; push_error("SHIP_PHYSICS_FAIL " + label)
func fresh() -> void:
 sim = Simulation.new()
 sim.start(Catalog.missions()[0])
func ticks(seconds: float) -> void:
 for i in ceili(seconds * 30): sim.tick(1.0 / 30)
func enemy(position: Array) -> Dictionary:
 var c: Dictionary = sim.state.contacts.back()
 c.kind = "hostile"
 c.identified = true
 c.position = position
 return c
func object(kind: String, position: Array) -> Dictionary:
 var c = {"id": "physics_object", "name": "Objeto de prueba", "kind": kind, "position": position, "hull": 100.0}
 sim.state.contacts.append(c)
 return c

func run() -> void:
 fresh()
 check(sim.state.ship.systems.size() == 10, "nine source subsystems plus native sensors")
 check(LocalStorage.validate_state(sim.state).is_empty(), "new ship state validates")
 check(sim.command("navegacion", "helm", {"heading": 180.0, "throttle": 0.0}).ok, "helm accepts target course")
 check(sim.state.ship.heading == 0, "course command cannot rotate ship instantly")
 ticks(1)
 check(absf(sim.state.ship.heading - 60) < 0.01, "heading changes at structural turn rate")
 sim.state.ship.systems.maniobra.health = 0
 var heading: float = sim.state.ship.heading
 ticks(1)
 check(sim.state.ship.heading == heading, "failed maneuver system stops turning")
 fresh()
 check(sim.command("navegacion", "helm", {"heading": 0.0, "throttle": -1.0}).ok, "reverse is an actual helm command")
 ticks(3)
 check(sim.state.ship.position[0] < -100 and is_equal_approx(sim.state.ship.speed, -80), "reverse respects half-speed design limit")
 check(not sim.command("navegacion", "warp", {"level": 1}).ok, "warp disallows reverse")
 check(LocalStorage.validate_state(sim.state).is_empty(), "negative speed can be saved")
 check(LocalStorage.save_state(sim.state, "user://physics-save.json").is_empty(), "reverse state saved")
 var round_trip = LocalStorage.read_state("user://physics-save.json").state
 check(round_trip == JSON.parse_string(JSON.stringify(sim.state, "", true, true)), "reverse and independent systems survive JSON save round trip")
 fresh()
 sim.state.ship.systems.motores.power = 0
 sim.command("navegacion", "helm", {"heading": 0.0, "throttle": 1.0})
 ticks(2)
 check(sim.state.ship.speed == 0, "unpowered impulse cannot propel ship")
 sim.state.ship.systems.warp.health = 0
 check(not sim.command("navegacion", "warp", {"level": 1}).ok, "damaged warp cannot engage")
 sim.state.ship.systems.salto.health = 0
 check(not sim.command("navegacion", "jump", {"distance": 1000}).ok, "damaged jump drive cannot charge")
 fresh()
 sim.state.ship.energy = 40
 ticks(2)
 check(sim.state.ship.energy > 45, "healthy reactor replenishes battery")
 sim.state.ship.systems.reactor.health = 0
 var energy: float = sim.state.ship.energy
 ticks(2)
 check(sim.state.ship.energy < energy - 3, "reactor failure depletes battery")
 fresh()
 ShipModel.damage(sim.state.ship, 70, [100.0, 0.0])
 check(sim.state.ship.shield_segments.front == 0 and sim.state.ship.shield_segments.rear == 40, "front strike only drains forward shield")
 check(sim.state.ship.hull == 90 and sim.state.ship.systems.armas.health < 100, "shield overflow damages hull and forward equipment")
 fresh()
 ShipModel.damage(sim.state.ship, 50, [-100.0, 0.0])
 check(sim.state.ship.shield_segments.front == 60 and sim.state.ship.shield_segments.rear == 0 and sim.state.ship.hull == 90, "rear strike cannot consume intact front shield")
 sim.state.ship.systems.escudos_popa.health = 0
 ShipModel.maintain(sim.state.ship, 1)
 check(sim.state.ship.shield_segments.rear == 0, "failed rear shield cannot regenerate")
 sim.state.ship.systems.escudos.power = 0
 ShipModel.damage(sim.state.ship, 10, [100.0, 0.0])
 check(sim.state.ship.hull == 80, "unpowered front generator cannot absorb despite stored charge")
 fresh()
 var attacker = enemy([400.0, 0.0])
 sim.state.operations.shield_frequency = attacker.frequency
 sim.state.ship.systems.escudos.power = 0
 sim.tick(0.1)
 check(sim.state.ship.hull == 91, "frequency matching cannot protect hull through a disabled shield generator")
 fresh()
 var c = enemy([-400.0, 0.0])
 var before: Dictionary = sim.state.duplicate(true)
 check(not sim.command("armas", "fire", {"target": c.id}).ok, "beam cannot shoot behind its firing arc")
 check(sim.state == before, "out-of-arc refusal consumes nothing")
 check(sim.command("armas", "missile", {"target": c.id}).ok, "guided missile can engage outside beam arc")
 check(sim.state.operations.ammo.homing == 7 and sim.state.ship.torpedoes == 7, "quick launch shares inventory with launch tubes")
 fresh()
 c = enemy([400.0, 0.0])
 sim.state.ship.systems.armas.health = 0
 check(not sim.command("armas", "fire", {"target": c.id}).ok, "beam failure disables beam")
 check(sim.command("armas", "tube_load", {"tube": 0, "ammo": "homing"}).ok, "independent missiles can load with failed beam system")
 sim.state.ship.systems.misiles.power = 0
 ticks(5)
 check(sim.state.operations.tubes[0].remaining == 4, "missile loading pauses without its own power")
 check(not sim.command("armas", "tube_fire", {"tube": 0, "target": c.id}).ok, "unpowered tube cannot launch")
 fresh()
 var mission: Dictionary = Catalog.missions()[0].duplicate(true)
 mission.ship_design = ShipModel.standard_design()
 mission.ship_design.hull = 180
 mission.ship_design.impulse = 80
 mission.ship_design.front_shield = 120
 mission.ship_design.ammo.homing = 0
 sim.start(mission)
 check(sim.state.ship.max_hull == 180 and sim.state.ship.shield_segments.front == 120, "mission design sets structural capabilities")
 c = enemy([400.0, 0.0])
 check(not sim.command("armas", "missile", {"target": c.id}).ok, "zero-capacity design cannot use quick-launch bypass")
 check(not sim.command("armas", "tube_load", {"tube": 0, "ammo": "homing"}).ok, "zero-capacity design has no hidden tube inventory")
 check(LocalStorage.validate_state(sim.state).is_empty(), "custom design saves validate")
 mission.ship_design.turn = -1
 check(not Catalog.validate_mission(mission).is_empty(), "invalid structural capabilities rejected at mission boundary")
 fresh()
 var legacy = sim.state.duplicate(true)
 for key in ["design", "target_heading", "shield_segments", "drift", "gate_cooldown"]: legacy.ship.erase(key)
 for key in Catalog.SYSTEMS:
  if key not in ShipModel.LEGACY_SYSTEMS: legacy.ship.systems.erase(key); legacy.operations.coolant.erase(key)
 check(LocalStorage.save_state(legacy, "user://physics-legacy.json").is_empty(), "old four-system save remains accepted")
 var loaded = LocalStorage.read_state("user://physics-legacy.json")
 check(loaded.has("state") and loaded.state.ship.systems.size() == 10, "old save migrates independent systems")
 check(LocalStorage.validate_state(loaded.state).is_empty(), "migrated save satisfies new invariants")
 fresh()
 object("asteroid", [300.0, 0.0])
 SpacePhysics.move(sim, 0.1, Vector2(1000, 0))
 check(sim.state.ship.position[0] < 224 and sim.state.ship.speed == 0, "swept collision blocks high-speed tunneling")
 fresh()
 object("planet", [800.0, 0.0])
 SpacePhysics.move(sim, 0.1, Vector2.ZERO)
 check(sim.state.ship.position[0] > 0 and sim.state.ship.drift[0] > 0, "planetary gravity produces acceleration and drift")
 fresh()
 var gate = object("wormhole", [200.0, 0.0])
 gate.destination = [1200.0, 50.0]
 SpacePhysics.move(sim, 0.1, Vector2(500, 0))
 check(sim.state.ship.position == [1200.0, 50.0] and sim.state.ship.gate_cooldown == 3, "gate traverses to its authored destination")
 check(sim.state.facts.has("navigate:physics_object"), "gate transit records navigation objective")
 fresh()
 object("blackhole", [50.0, 0.0])
 sim.tick(0.1)
 check(sim.state.status == "lost", "crossing event horizon loses ship")
 fresh()
 object("nebula", [350.0, 0.0])
 c = sim.state.contacts[0]
 c.position = [700.0, 0.0]
 check(not sim.command("sensores", "scan", {"target": c.id}).ok, "nebula blocks distant scanner path")
 sim.state.ship.position = [450.0, 0.0]
 check(sim.command("sensores", "scan", {"target": c.id}).ok, "short-range scan works inside nebula")
 for path in ["physics-save.json", "physics-save.json.bak", "physics-legacy.json", "physics-legacy.json.bak"]:
  DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + path))
 print("SHIP_PHYSICS_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)
