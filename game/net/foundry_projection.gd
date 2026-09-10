class_name FoundryProjection
extends RefCounted
## Positive DTOs: new simulation/save fields are private until explicitly listed here.

static func fields(source: Dictionary, names: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in names:
		var value: Variant = source.get(key)
		if value is String: result[key] = value.left(4000)
		elif value is bool or Catalog.finite_number(value): result[key] = value
	return result

static func position(value: Variant) -> Array:
	if value is Array and value.size() == 2 and Catalog.finite_number(value[0]) and Catalog.finite_number(value[1]): return value.duplicate()
	return []

static func state(view: Dictionary) -> Dictionary:
	if not view.get("ship") is Dictionary or not view.get("mission") is Dictionary: return {}
	var result = fields(view, ["run_id", "status", "time", "objective"])
	result.mission = fields(view.mission, ["id", "title", "sector"])
	result.ship = fields(view.ship, ["hull", "max_hull", "shield", "shields_enabled", "energy", "fuel", "heading", "target_heading", "speed", "throttle", "alert", "docked", "autopilot", "coolant", "parts", "probes", "torpedoes"])
	result.ship.position = position(view.ship.get("position"))
	result.ship.systems = {}
	for id in Catalog.SYSTEMS:
		var system: Variant = view.ship.get("systems", {}).get(id)
		if system is Dictionary: result.ship.systems[id] = fields(system, ["power", "heat", "health"])
	result.contacts = []
	for contact in view.get("contacts", []).slice(0, 48):
		if not contact is Dictionary: continue
		var safe = fields(contact, ["id", "identified"])
		safe.position = position(contact.get("position"))
		if contact.get("identified", false) == true:
			safe.merge(fields(contact, ["name", "kind", "hull", "hailed", "probed", "jammed"]))
		else:
			safe.name = "Eco %02d" % (result.contacts.size() + 1)
			safe.kind = "unknown"
		result.contacts.append(safe)
	return result

static func crew(profile: Dictionary) -> Dictionary:
	var result = fields(profile, ["name", "approach", "focus", "condition", "level", "xp"])
	result.skills = fields(profile.get("skills", {}), ExpeditionSystems.SKILLS)
	# Narrative milestones and inventory are deliberately excluded from this surface.
	result.traits = []
	for trait_id in profile.get("traits", []).slice(0, 8):
		if trait_id is String and trait_id in CrewSystem.TRAITS: result.traits.append(trait_id)
	return result

static func events(source: Array, after: int = 0) -> Dictionary:
	var selected: Array = []
	var cursor = after
	for event in source.slice(-200):
		if not event is Dictionary or not Catalog.finite_number(event.get("seq")) or not Catalog.finite_number(event.get("time")): continue
		cursor = maxi(cursor, int(event.seq))
		if event.seq > after: selected.append(fields(event, ["seq", "time", "source", "text"]))
	return {"events": selected, "cursor": cursor}
