class_name ShipModel
extends RefCounted
## Structural ship capabilities, independent engineering systems and directional damage.

const LEGACY_SYSTEMS = ["motores", "escudos", "armas", "sensores"]
const POWER_BUDGET = 20
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
 sync_shield(ship)

static func efficiency(ship: Dictionary, system: String) -> float:
 var s: Dictionary = ship.systems[system]
 return float(s.power) * 0.5 * float(s.health) / 100.0

static func sync_shield(ship: Dictionary) -> void:
 var maximum = float(ship.design.front_shield) + float(ship.design.rear_shield)
 ship.shield = 100.0 * (ship.shield_segments.front + ship.shield_segments.rear) / maximum if maximum > 0 else 0.0

static func bearing(ship: Dictionary, position: Array) -> float:
 return rad_to_deg(Vector2(position[0] - ship.position[0], position[1] - ship.position[1]).angle())

static func angle_error(ship: Dictionary, target: float) -> float:
 var error = wrapf(target - float(ship.heading), -180.0, 180.0)
 return 180.0 if is_equal_approx(error, -180.0) else error

static func in_beam_arc(ship: Dictionary, position: Array) -> bool:
 return absf(angle_error(ship, bearing(ship, position))) <= float(ship.design.beam_arc) * 0.5

static func protects(ship: Dictionary, position: Array) -> bool:
 var front = absf(angle_error(ship, bearing(ship, position))) <= 90
 return ship.shields_enabled and ship.shield_segments["front" if front else "rear"] > 0 and efficiency(ship, "escudos" if front else "escudos_popa") > 0

static func turn(ship: Dictionary, delta: float) -> void:
 var error = angle_error(ship, ship.target_heading)
 var maximum = ship.design.turn * efficiency(ship, "maniobra") * delta
 ship.heading = fposmod(ship.heading + clampf(error, -maximum, maximum), 360.0)

static func maintain(ship: Dictionary, delta: float) -> void:
 ship.energy = clampf(ship.energy + (5.0 * efficiency(ship, "reactor") - 2.0) * delta, 0, 100)
 if ship.energy <= 0: ship.shields_enabled = false
 for segment in ["front", "rear"]:
  var system = "escudos" if segment == "front" else "escudos_popa"
  var capacity = ship.design.front_shield if segment == "front" else ship.design.rear_shield
  var rate = 0.8 * efficiency(ship, system) * (4 if not ship.docked.is_empty() else 1)
  if ship.energy > 0: ship.shield_segments[segment] = minf(capacity, ship.shield_segments[segment] + rate * delta)
 sync_shield(ship)

static func damage(ship: Dictionary, amount: float, source: Array) -> float:
 var front = absf(angle_error(ship, bearing(ship, source))) <= 90.0
 var segment = "front" if front else "rear"
 var system = "escudos" if front else "escudos_popa"
 if ship.shields_enabled and efficiency(ship, system) > 0:
  var absorbed = minf(ship.shield_segments[segment], amount)
  ship.shield_segments[segment] -= absorbed
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
 var capacity = ship.design.front_shield + ship.design.rear_shield
 var expected = 100.0 * (ship.shield_segments.front + ship.shield_segments.rear) / capacity if capacity > 0 else 0.0
 if absf(ship.shield - expected) > 0.001: return "Escudo total incoherente."
 if not ShipOperations.number(ship, "target_heading", 0, 360) or not ShipOperations.number(ship, "gate_cooldown", 0, 3): return "Maniobra guardada inválida."
 if not ship.get("drift") is Array or ship.drift.size() != 2: return "Deriva inválida."
 for component in ship.drift:
  if not Catalog.finite_number(component) or absf(component) > 5000: return "Deriva fuera de rango."
 return ""
