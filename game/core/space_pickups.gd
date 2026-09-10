class_name SpacePickups
extends RefCounted
## Collision effects run inside the existing host simulation. Facts survive saves.

const KINDS = ["supplydrop", "artifact"]
const FIELDS = ["allow_pickup", "supply_energy", "supply_ammo"]

static func validate_contact(c: Dictionary) -> String:
	for field in FIELDS:
		if c.has(field) and c.get("kind") not in KINDS: return "Recursos de recogible en un contacto incompatible."
	if c.get("kind") not in KINDS: return ""
	if c.has("allow_pickup") and (c.kind != "artifact" or not c.allow_pickup is bool): return "Recogida de artefacto inválida."
	if c.kind == "artifact":
		if c.has("supply_energy") or c.has("supply_ammo"): return "Un artefacto no es un suministro."
		return ""
	if c.has("supply_energy") and not ShipOperations.number(c, "supply_energy", 0, 100): return "Energía de suministro fuera de rango."
	if c.has("supply_ammo"):
		if not c.supply_ammo is Dictionary or c.supply_ammo.size() > ShipOperations.AMMO.size(): return "Munición de suministro inválida."
		for kind in c.supply_ammo:
			if kind not in ShipOperations.AMMO or not ShipOperations.number(c.supply_ammo, kind, 0, 1000, true): return "Munición de suministro fuera de rango."
	return ""

static func collect_path(sim, start: Vector2, end: Vector2) -> void:
	if sim.state.status != "active" or sim.state.ship.hull <= 0: return
	for c in sim.state.contacts:
		if c.kind not in KINDS or c.hull <= 0 or sim.state.facts.has("pickup:" + c.id): continue
		if SpacePhysics.segment_hit(start, end, Vector2(c.position[0], c.position[1]), SpacePhysics.radius(c) + sim.state.ship.design.radius) == INF: continue
		c.identified = true
		if not sim.state.facts.has("touch:" + c.id):
			sim.fact("touch", c.id)
			sim.log_event("Enlace", "Contacto físico con " + c.name + ".")
		if c.kind == "artifact" and not c.get("allow_pickup", false): continue
		# Commit consumption before applying the effect; no second resource ledger.
		sim.fact("pickup", c.id)
		c.hull = 0.0
		if c.kind == "supplydrop":
			var ship: Dictionary = sim.state.ship
			ship.energy = minf(100.0, ship.energy + float(c.get("supply_energy", 25.0)))
			var cargo: Dictionary = c.get("supply_ammo", {"homing": 2})
			for kind in cargo:
				var loaded = 0
				for tube in sim.state.operations.tubes:
					if tube.ammo == kind: loaded += 1
				var capacity = maxi(0, int(ship.design.ammo[kind]) - loaded)
				sim.state.operations.ammo[kind] = mini(capacity, int(sim.state.operations.ammo[kind]) + int(cargo[kind]))
			ship.torpedoes = sim.state.operations.ammo.homing
		sim.log_event("Enlace", "Recogido: " + c.name + ".")

static func validate_state(state: Dictionary) -> String:
	for original in state.mission.contacts:
		for c in state.contacts:
			if c.id != original.id or (c.kind not in KINDS and original.kind not in KINDS): continue
			if c.kind != original.kind: return "Tipo de recogible alterado."
			for field in FIELDS:
				if c.get(field) != original.get(field): return "Contenido de recogible alterado."
			for event in ["touch", "pickup"]:
				var key = event + ":" + c.id
				if state.facts.has(key) and (not state.facts[key] is bool or not state.facts[key]): return "Hecho de recogible inválido."
			if state.facts.has("pickup:" + c.id):
				if c.hull != 0 or not state.facts.has("touch:" + c.id) or (c.kind == "artifact" and not c.get("allow_pickup", false)): return "Recogible consumido incoherente."
	return ""
