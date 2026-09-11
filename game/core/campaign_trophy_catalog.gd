class_name CampaignTrophyCatalog
extends RefCounted
## Deterministic, read-only projection of public campaign progress.
## The host/save remains authoritative; this class never writes campaign state.

const FORMAT := "lagunak-campaign-trophies"
const VERSION := 1
const MAX_COMPLETED := 256
const MAX_TEXT := 64
const MAX_COUNTER := 1000000

const TROPHIES: Array[Dictionary] = [
	{
		"id": "first_route",
		"title": "Primera singladura",
		"placard": "La primera misión completada queda expuesta como recuerdo del comienzo.",
		"criterion": "completed_missions",
		"threshold": 1
	},
	{
		"id": "three_routes",
		"title": "Tres rutas compartidas",
		"placard": "Tres misiones completadas demuestran que la tripulación ya conoce el corredor.",
		"criterion": "completed_missions",
		"threshold": 3
	},
	{
		"id": "survivor_manifest",
		"title": "Manifiesto de supervivientes",
		"placard": "Al menos un superviviente rescatado conserva su lugar en la memoria de la Itsaso.",
		"criterion": "survivors",
		"threshold": 1
	},
	{
		"id": "reinforced_itsaso",
		"title": "Casco reforzado",
		"placard": "Una mejora de campaña queda registrada junto a la nave que la hizo posible.",
		"criterion": "upgrades",
		"threshold": 1
	},
	{
		"id": "veteran_route",
		"title": "Tripulación veterana",
		"placard": "Seis misiones completadas forman la primera colección de una expedición veterana.",
		"criterion": "completed_missions",
		"threshold": 6
	}
]

static func project(campaign: Variant) -> Dictionary:
	if not campaign is Dictionary:
		return _error("El progreso de campaña no es un objeto público válido.")
	var completed: Variant = campaign.get("completed", [])
	if not completed is Array or completed.size() > MAX_COMPLETED:
		return _error("La lista pública de misiones completadas no es válida.")
	var seen: Array[String] = []
	for identifier in completed:
		if not identifier is String or identifier.is_empty() or identifier.length() > MAX_TEXT:
			return _error("La lista pública contiene un identificador inválido.")
		if identifier in seen:
			return _error("La lista pública contiene misiones repetidas.")
		seen.append(identifier)
	var survivors = _counter(campaign.get("survivors", 0), MAX_COUNTER)
	var upgrades = _counter(campaign.get("upgrades", 0), 4)
	var credits = _counter(campaign.get("credits", 0), MAX_COUNTER)
	var reputation = _counter(campaign.get("reputation", 0), MAX_COUNTER)
	if survivors == null or upgrades == null or credits == null or reputation == null:
		return _error("Los contadores públicos de campaña no son válidos.")
	var progress := {
		"completed_missions": completed.size(),
		"survivors": survivors,
		"upgrades": upgrades
	}
	var trophies: Array[Dictionary] = []
	for definition in TROPHIES:
		var current: int = int(progress[definition.criterion])
		var threshold: int = int(definition.threshold)
		trophies.append({
			"id": definition.id,
			"title": definition.title,
			"placard": definition.placard,
			"location": "museo",
			"unlocked": current >= threshold,
			"status": "expuesto" if current >= threshold else "pendiente",
			"progress": "%d / %d" % [mini(current, threshold), threshold]
		})
	return {
		"format": FORMAT,
		"version": VERSION,
		"scope": {
			"authority": "host_campaign_or_offline_save",
			"history_complete": false,
			"description": "Trofeos derivados de progreso público persistido; no se guarda una copia paralela."
		},
		"summary": {
			"completed_missions": completed.size(),
			"survivors": survivors,
			"upgrades": upgrades,
			"credits": credits,
			"reputation": reputation
		},
		"trophies": trophies
	}

static func _counter(value: Variant, maximum: int) -> Variant:
	if not (value is int or value is float) or not is_finite(float(value)):
		return null
	if float(value) < 0.0 or float(value) > float(maximum) or float(value) != floorf(float(value)):
		return null
	return int(value)

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
