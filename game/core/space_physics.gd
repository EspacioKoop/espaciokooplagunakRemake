class_name SpacePhysics
extends RefCounted
## Host-side swept collisions, inverse-square attraction and traversable gates.

const KINDS = ["asteroid", "planet", "blackhole", "wormhole", "nebula"]
const DYNAMIC_COLLIDERS = ["station", "friendly", "hostile", "derelict"]
const RADII = {"asteroid": 55.0, "planet": 300.0, "blackhole": 100.0, "wormhole": 80.0, "nebula": 400.0,
 "station": 82.0, "friendly": 28.0, "hostile": 28.0, "derelict": 30.0}

static func validate_contact(c: Dictionary) -> String:
 if c.has("radius") and not ShipOperations.number(c, "radius", 5, 2000): return "Radio del objeto fuera de rango."
 if c.has("gravity") and not ShipOperations.number(c, "gravity", 0, 1e8): return "Gravedad del objeto fuera de rango."
 if c.has("destination") and not ShipOperations.valid_position(c.destination): return "Destino del agujero de gusano inválido."
 return ""

static func radius(c: Dictionary) -> float:
 return float(c.get("radius", RADII.get(c.kind, 0.0)))

static func segment_hit(start: Vector2, end: Vector2, center: Vector2, reach: float) -> float:
 var offset = start - center
 if offset.length_squared() <= reach * reach: return 0.0
 var movement = end - start
 var a = movement.length_squared()
 if a < 0.000001: return INF
 var b = 2.0 * offset.dot(movement)
 var c = offset.length_squared() - reach * reach
 var discriminant = b * b - 4 * a * c
 if discriminant < 0: return INF
 var t = (-b - sqrt(discriminant)) / (2 * a)
 return t if t >= 0 and t <= 1 else INF

static func move(sim, delta: float, propulsion: Vector2) -> void:
 var ship: Dictionary = sim.state.ship
 ship.gate_cooldown = maxf(0, ship.gate_cooldown - delta)
 var start = Vector2(ship.position[0], ship.position[1])
 var drift = Vector2(ship.drift[0], ship.drift[1])
 var acceleration = Vector2.ZERO
 for c in sim.state.contacts:
  if c.hull <= 0 or c.kind not in ["planet", "blackhole"]: continue
  var offset = Vector2(c.position[0], c.position[1]) - start
  var mass = float(c.get("gravity", 500000.0 if c.kind == "planet" else 1500000.0))
  acceleration += offset.normalized() * minf(150.0, mass / maxf(radius(c) * radius(c), offset.length_squared()))
 drift = (drift + acceleration * delta).limit_length(5000)
 var end = start + propulsion + drift * delta
 var first = INF
 var obstacle: Dictionary = {}
 for c in sim.state.contacts:
  if c.hull <= 0 or (c.kind not in ["asteroid", "planet", "blackhole", "wormhole"] and c.kind not in DYNAMIC_COLLIDERS): continue
  if c.kind == "wormhole" and ship.gate_cooldown > 0: continue
  if c.kind == "station" and not ship.docked.is_empty() and ship.docked == c.id: continue
  var reach = radius(c) + (0.0 if c.kind == "wormhole" else ship.design.radius)
  var collision = segment_hit(start, end, Vector2(c.position[0], c.position[1]), reach)
  if collision < first:
   first = collision
   obstacle = c
 if not obstacle.is_empty():
  if obstacle.kind == "wormhole":
   var destination: Array = obstacle.get("destination", [clampf(-obstacle.position[0], -14000, 14000), clampf(-obstacle.position[1], -14000, 14000)])
   end = Vector2(destination[0], destination[1])
   drift = Vector2.ZERO
   ship.gate_cooldown = 3.0
   ship.autopilot = ""
   sim.state.operations.route = ""
   sim.fact("navigate", obstacle.id)
   sim.log_event("Navegación", "Tránsito completado por " + obstacle.name + ".")
  else:
   var center = Vector2(obstacle.position[0], obstacle.position[1])
   var hit_point = start.lerp(end, first)
   var normal = (hit_point - center).normalized()
   if normal.length_squared() < 0.01: normal = -Vector2.from_angle(deg_to_rad(ship.heading))
   end = center + normal * (radius(obstacle) + ship.design.radius + 0.1)
   var speed = (propulsion / delta + drift).length()
   var impact = minf(60, speed * (0.105 if obstacle.kind in DYNAMIC_COLLIDERS else 0.08))
   ShipModel.damage(ship, impact, obstacle.position)
   if obstacle.kind in ["friendly", "hostile", "derelict"]:
    obstacle.hull = maxf(0.0, float(obstacle.hull) - impact * 0.55)
    if obstacle.hull <= 0: sim.fact("defeat", obstacle.id)
   if obstacle.kind == "blackhole": ship.hull = 0
   drift = drift.slide(normal) * (0.25 if obstacle.kind in DYNAMIC_COLLIDERS else 1.0)
   ship.speed = 0.0
   ship.throttle = 0.0
   ship.autopilot = ""
   sim.state.operations.warp = 0
   sim.state.operations.route = ""
   if speed > 1:
    var kind_text = "otra nave" if obstacle.kind in ["friendly", "hostile", "derelict"] else ("estación" if obstacle.kind == "station" else "objeto espacial")
    sim.log_event("Navegación", "Colisión con %s (%s). Impulso detenido." % [obstacle.name, kind_text])
 ship.position = [clampf(end.x, -14000, 14000), clampf(end.y, -14000, 14000)]
 ship.drift = [drift.x, drift.y]

static func obscured(contacts: Array, origin: Array, destination: Array) -> bool:
 var start = Vector2(origin[0], origin[1])
 var end = Vector2(destination[0], destination[1])
 for c in contacts:
  if c.kind == "nebula" and segment_hit(start, end, Vector2(c.position[0], c.position[1]), radius(c)) != INF: return true
 return false
