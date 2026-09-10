class_name ShipDeckLayout
extends RefCounted
## One geometry contract for room transforms, physical portals and the live map.
## -Z is the glazed bow; +Z is engineering and propulsion. Social destinations
## retain their coordinates and are not misrepresented as rooms inside the hull.

const SHIP_COUNT = 7
const CORRIDOR_WIDTH = 3.6
const MAP_BOUNDS = Rect2(-30, -52, 60, 100)
const ZONES = [
	{"name": "Puente", "model": "bridge_room", "at": Vector3(0, 0, -34), "role": "navegacion", "depth": 20.0},
	{"name": "Pasillo central", "model": "hallway", "at": Vector3.ZERO, "role": "mando", "depth": 42.0},
	{"name": "Ingeniería", "model": "engineering_room", "at": Vector3(0, 0, 32), "role": "ingenieria", "depth": 14.0},
	{"name": "Camarotes", "model": "quarters_room", "at": Vector3(-13, 0, -10), "role": "comunicaciones", "depth": 14.0},
	{"name": "Bodega", "model": "cargo_room", "at": Vector3(-13, 0, 10), "role": "enlace", "depth": 14.0},
	{"name": "Comedor", "model": "mess_room", "at": Vector3(13, 0, 10), "role": "mando", "depth": 14.0},
	{"name": "Enfermería", "model": "medbay_room", "at": Vector3(13, 0, -10), "role": "reparaciones", "depth": 14.0},
	{"name": "Cantina", "model": "cantina", "at": Vector3(80, 0, 0), "role": "", "depth": 24.0},
	{"name": "Museo", "model": "museum_hall", "at": Vector3(150, 0, 0), "role": "", "depth": 58.0},
	{"name": "Playa", "model": "beach", "at": Vector3(0, 0, 200), "role": "", "depth": 112.0},
	{"name": "Terraza", "model": "terrace", "at": Vector3(80, 0, 80), "role": "", "depth": 24.0},
	{"name": "Estudio", "model": "studio", "at": Vector3(150, 0, 80), "role": "", "depth": 24.0},
	{"name": "Pasillo de recuerdos", "model": "memories_hall", "at": Vector3(80, 0, -80), "role": "", "depth": 64.0}
]
const ROOM_YAW = [0.0, 0.0, PI, PI * 0.5, PI * 0.5, -PI * 0.5, -PI * 0.5]
const ROOM_WIDTH = [18.0, 6.0, 14.0, 14.0, 14.0, 14.0, 14.0]
const LINK_TARGETS = [0, 3, 6, 4, 5, 2]
const HALL_PORTALS = [Vector3(0, 0, -19), Vector3(-2, 0, -10), Vector3(2, 0, -10), Vector3(-2, 0, 10), Vector3(2, 0, 10), Vector3(0, 0, 19)]
## Approximate deck envelope, not an orthographic measurement of the exterior GLB.
const HULL = [Vector2(-4, -50), Vector2(4, -50), Vector2(11, -45), Vector2(15, -27), Vector2(23, -18), Vector2(23, 12), Vector2(27, 22), Vector2(27, 40), Vector2(18, 42), Vector2(13, 39), Vector2(9, 44), Vector2(-9, 44), Vector2(-13, 39), Vector2(-18, 42), Vector2(-27, 40), Vector2(-27, 22), Vector2(-23, 12), Vector2(-23, -18), Vector2(-15, -27), Vector2(-11, -45)]

static func xz(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

static func room_point(index: int, local: Vector3) -> Vector3:
	return ZONES[index].at + local.rotated(Vector3.UP, ROOM_YAW[index])

static func room_polygon(index: int) -> PackedVector2Array:
	var half_width: float = ROOM_WIDTH[index] * 0.5
	var half_depth: float = ZONES[index].depth * 0.5
	var result = PackedVector2Array()
	for corner in [Vector3(-half_width, 0, -half_depth), Vector3(half_width, 0, -half_depth), Vector3(half_width, 0, half_depth), Vector3(-half_width, 0, half_depth)]:
		result.append(xz(room_point(index, corner)))
	return result

static func entry(index: int) -> Vector3:
	return room_point(index, Vector3(0, 0, ZONES[index].depth * 0.5 - 0.6))

static func spawn(index: int) -> Vector3:
	var local_x = 4.8 if index == 0 else (-3.0 if index == 2 else 0.0)
	return room_point(index, Vector3(local_x, 0.4, ZONES[index].depth * 0.5 - 2.0))

static func connectors() -> Array:
	var result: Array = []
	for i in LINK_TARGETS.size():
		var target: int = LINK_TARGETS[i]
		var start: Vector3 = HALL_PORTALS[i]
		var finish = entry(target)
		result.append({"source": 1, "target": target, "start": start, "finish": finish, "length": start.distance_to(finish)})
	return result

static func corridor_polygon(link: Dictionary) -> PackedVector2Array:
	var a = xz(link.start)
	var b = xz(link.finish)
	var side = (b - a).normalized().orthogonal() * CORRIDOR_WIDTH * 0.5
	return PackedVector2Array([a - side, b - side, b + side, a + side])

static func room_at(position: Vector3) -> int:
	if not position.is_finite() or position.y < -1.0 or position.y > 5.0: return -1
	for i in SHIP_COUNT:
		var local: Vector3 = (position - ZONES[i].at).rotated(Vector3.UP, -ROOM_YAW[i])
		if absf(local.x) <= ROOM_WIDTH[i] * 0.5 + 0.02 and absf(local.z) <= ZONES[i].depth * 0.5 + 0.02:
			return i
	return -1

static func connector_at(position: Vector3) -> int:
	if not position.is_finite() or position.y < -1.0 or position.y > 5.0: return -1
	var all = connectors()
	for i in all.size():
		if Geometry2D.is_point_in_polygon(xz(position), corridor_polygon(all[i])): return i
	return -1

static func zone_for(position: Vector3, current: int) -> int:
	if current >= SHIP_COUNT: return current
	var room = room_at(position)
	if room >= 0: return room
	# A connector is circulation, not whichever room centre happens to be nearest.
	return 1 if connector_at(position) >= 0 else current

static func contains(position: Vector3) -> bool:
	return room_at(position) >= 0 or connector_at(position) >= 0

static func route(position: Vector3, destination: int) -> PackedVector3Array:
	var points = PackedVector3Array()
	if destination < 0 or destination >= SHIP_COUNT or not contains(position): return points
	var room = room_at(position)
	if room == destination: return points
	points.append(Vector3(position.x, 0, position.z))
	var all = connectors()
	var current_link = connector_at(position)
	if room != 1 and current_link >= 0 and all[current_link].target == destination:
		points.append(all[current_link].finish)
	else:
		if room > 1 or room == 0:
			var link: Dictionary = all[LINK_TARGETS.find(room)]
			points.append(link.finish)
			points.append(link.start)
		elif room < 0 and current_link >= 0:
			points.append(all[current_link].start)
		points.append(Vector3(0, 0, clampf(points[-1].z, -19, 19)))
		if destination == 1:
			points.append(Vector3.ZERO)
			return points
		var target_link: Dictionary = all[LINK_TARGETS.find(destination)]
		points.append(Vector3(0, 0, target_link.start.z))
		points.append(target_link.start)
		points.append(target_link.finish)
	points.append(entry(destination) + (ZONES[destination].at - entry(destination)).normalized() * 1.4)
	return points
