class_name ShipModel
extends RefCounted
## Structural ship capabilities, independent engineering systems and directional damage.

const LEGACY_SYSTEMS = ["motores", "escudos", "armas", "sensores"]
const POWER_BUDGET = 20
const QUADRANTS = ["front_left", "front_right", "rear_left", "rear_right"]
const DESIGN_LIMITS = {
 "hull": [1, 10000], "front_shield": [0, 5000], "rear_shield": [0, 5000],
 "impulse": [0, 1000], "reverse": [0, 1], "turn": [0, 180], "acceleration": [1, 500],
 "warp_speed": [0, 3000], "jump_range": [0, 10000], "radius": [5, 200],
 "beam_arc": [0, 360], "beam_range": [0, 3000], "beam_damage": [0, 300], "beam_cycle": [0.1, 30], "missile_range": [0, 6000]
}

static func standard_design() -> Dictionary:
 return {"id": "itsaso", "name": "Itsaso · exploración", "hull": 100.0, "front_shield": 60.0, "rear_shield": 40.0,
  "impulse": 160.0, "reverse": 0.5, "turn": 60.0, "acceleration": 85.0, "warp_speed": 480.0, "jump_range": 3000.0, "radius": 22.0,
  "beam_arc": 120.0, "beam_range": 600.0, "beam_damage": 18.0, "beam_cycle": 1.0, "missile_range": 1600.0,
  "ammo": {"homing": 8, "nuke": 2, "mine": 4, "emp": 4, "hvli": 12}}

static func validate_design(value: Variant) -> String:
 if not value is Dictionary: return "El diseño de nave debe ser un objeto."
 if not value.get("id") is String or value.id.is_empty() or value.id.length() > 64 or not value.get("name") is String or value.name.is_empty() or value.name.length() > 80: return "Nombre de diseño inválido."
 for key in DESIGN_LIMITS:
  var limits: Array = DESIGN_LIMITS[key]
  if not ShipOperations.number(value, key, limits[0], limits[1]): return "Capacidad de nave inválida: " + key
 if not value.get("ammo") is Dictionary: return "Falta la capacidad de munición."
 for ammo in ShipOperations.AMMO:
  if not ShipOperations.number(value.ammo, ammo, 0, 1000, true): return "Capacidad de munición inválida: " + ammo
 return ""

static func initialize(state: Dictionary) -> void:
 var ship: Dictionary = state.ship
 for key in Catalog.SYSTEMS:
  if not ship.systems.has(key): ship.systems[key] = {"power": 2, "heat": 10.0, "health": 100.0}
 if not ship.has("design"):
  ship.design = state.mission.get("ship_design", standard_design()).duplicate(true)
 if not ship.has("shield_segments"):
  var fraction = clampf(float(ship.shield) / 100.0, 0, 1)
  ship.shield_segments = {"front": ship.design.front_shield * fraction, "rear": ship.design.rear_shield * fraction}
 if not ship.has("target_heading"): ship.target_heading = ship.heading
 if not ship.has("drift"): ship.drift = [0.0, 0.0]
 if not ship.has("gate_cooldown"): ship.gate_cooldown = 0.0
 if state.has("operations"):
  for key in Catalog.SYSTEMS:
   if not state.operations.coolant.has(key): state.operations.coolant[key] = 0.0
 ensure_quadrants(ship)
 sync_shield(ship)

static func efficiency(ship: Dictionary, system: String) -> float:
 var s: Dictionary = ship.systems[system]
 return float(s.power) * 0.5 * float(s.health) / 100.0

static func quadrant_capacity(ship: Dictionary, quadrant: String) -> float:
 return float(ship.design.front_shield if quadrant.begins_with("front") else ship.design.rear_shield) * 0.5

static func ensure_quadrants(ship: Dictionary) -> void:
 if not ship.has("shield_quadrants") or not ship.shield_quadrants is Dictionary:
  ship.shield_quadrants = {
   "front_left": float(ship.shield_segments.front) * 0.5,
   "front_right": float(ship.shield_segments.front) * 0.5,
   "rear_left": float(ship.shield_segments.rear) * 0.5,
   "rear_right": float(ship.shield_segments.rear) * 0.5
  }
 for quadrant in QUADRANTS:
  if not ship.shield_quadrants.has(quadrant):
   var aggregate = float(ship.shield_segments.front if quadrant.begins_with("front") else ship.shield_segments.rear)
   ship.shield_quadrants[quadrant] = aggregate * 0.5
  ship.shield_quadrants[quadrant] = clampf(float(ship.shield_quadrants[quadrant]), 0.0, quadrant_capacity(ship, quadrant))

static func sync_shield(ship: Dictionary) -> void:
 if ship.has("shield_quadrants") and ship.shield_quadrants is Dictionary:
  ensure_quadrants(ship)
  ship.shield_segments.front = float(ship.shield_quadrants.front_left) + float(ship.shield_quadrants.front_right)
  ship.shield_segments.rear = float(ship.shield_quadrants.rear_left) + float(ship.shield_quadrants.rear_right)
 var maximum = float(ship.design.front_shield) + float(ship.design.rear_shield)
 ship.shield = 100.0 * (ship.shield_segments.front + ship.shield_segments.rear) / maximum if maximum > 0 else 0.0

static func bearing(ship: Dictionary, position: Array) -> float:
 return rad_to_deg(Vector2(position[0] - ship.position[0], position[1] - ship.position[1]).angle())

static func angle_error(ship: Dictionary, target: float) -> float:
 var error = wrapf(target - float(ship.heading), -180.0, 180.0)
 return 180.0 if is_equal_approx(error, -180.0) else error

static func in_beam_arc(ship: Dictionary, position: Array) -> bool:
 return absf(angle_error(ship, bearing(ship, position))) <= float(ship.design.beam_arc) * 0.5

static func quadrant_for_source(ship: Dictionary, position: Array) -> String:
 var error = angle_error(ship, bearing(ship, position))
 var front = absf(error) <= 90.0
 var left = error < 0.0
 if front: return "front_left" if left else "front_right"
 return "rear_left" if left else "rear_right"

static func protects(ship: Dictionary, position: Array) -> bool:
 ensure_quadrants(ship)
 var quadrant = quadrant_for_source(ship, position)
 var system = "escudos" if quadrant.begins_with("front") else "escudos_popa"
 return ship.shields_enabled and float(ship.shield_quadrants[quadrant]) > 0 and efficiency(ship, system) > 0

static func turn(ship: Dictionary, delta: float) -> void:
 var error = angle_error(ship, ship.target_heading)
 var maximum = ship.design.turn * efficiency(ship, "maniobra") * delta
 ship.heading = fposmod(ship.heading + clampf(error, -maximum, maximum), 360.0)

static func maintain(ship: Dictionary, delta: float) -> void:
 ship.energy = clampf(ship.energy + (5.0 * efficiency(ship, "reactor") - 2.0) * delta, 0, 100)
 if ship.energy <= 0: ship.shields_enabled = false
 ensure_quadrants(ship)
 for quadrant in QUADRANTS:
  var system = "escudos" if quadrant.begins_with("front") else "escudos_popa"
  var rate = 0.4 * efficiency(ship, system) * (4 if not ship.docked.is_empty() else 1)
  if ship.energy > 0: ship.shield_quadrants[quadrant] = minf(quadrant_capacity(ship, quadrant), float(ship.shield_quadrants[quadrant]) + rate * delta)
 sync_shield(ship)

static func damage(ship: Dictionary, amount: float, source: Array) -> float:
 ensure_quadrants(ship)
 var quadrant = quadrant_for_source(ship, source)
 var front = quadrant.begins_with("front")
 var system = "escudos" if front else "escudos_popa"
 if ship.shields_enabled and efficiency(ship, system) > 0:
  var absorbed = minf(float(ship.shield_quadrants[quadrant]), amount)
  ship.shield_quadrants[quadrant] -= absorbed
  amount -= absorbed
 ship.hull = maxf(0, ship.hull - amount)
 if amount > 0:
  var damaged = "armas" if front else "motores"
  ship.systems[damaged].health = maxf(0, ship.systems[damaged].health - amount * 0.15)
 sync_shield(ship)
 return amount

static func validate_ship(ship: Dictionary) -> String:
 var error = validate_design(ship.get("design"))
 if not error.is_empty(): return error
 if not ship.get("shield_segments") is Dictionary: return "Escudos segmentados incompletos."
 if not ShipOperations.number(ship.shield_segments, "front", 0, ship.design.front_shield) or not ShipOperations.number(ship.shield_segments, "rear", 0, ship.design.rear_shield): return "Escudo segmentado fuera de rango."
 ensure_quadrants(ship)
 for quadrant in QUADRANTS:
  if not ShipOperations.number(ship.shield_quadrants, quadrant, 0, quadrant_capacity(ship, quadrant)): return "Cuadrante de escudo fuera de rango: " + quadrant
 var expected_front = float(ship.shield_quadrants.front_left) + float(ship.shield_quadrants.front_right)
 var expected_rear = float(ship.shield_quadrants.rear_left) + float(ship.shield_quadrants.rear_right)
 if absf(float(ship.shield_segments.front) - expected_front) > 0.001 or absf(float(ship.shield_segments.rear) - expected_rear) > 0.001: return "Escudos agregados incoherentes con sus cuadrantes."
 var capacity = ship.design.front_shield + ship.design.rear_shield
 var expected = 100.0 * (ship.shield_segments.front + ship.shield_segments.rear) / capacity if capacity > 0 else 0.0
 if absf(ship.shield - expected) > 0.001: return "Escudo total incoherente."
 if not ShipOperations.number(ship, "target_heading", 0, 360) or not ShipOperations.number(ship, "gate_cooldown", 0, 3): return "Maniobra guardada inválida."
 if not ship.get("drift") is Array or ship.drift.size() != 2: return "Deriva inválida."
 for component in ship.drift:
  if not Catalog.finite_number(component) or absf(component) > 5000: return "Deriva fuera de rango."
 return ""
