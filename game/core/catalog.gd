class_name Catalog
extends RefCounted

const ROLES := ["mando", "navegacion", "ingenieria", "armas", "sensores", "comunicaciones", "enlace", "reparaciones"]
const ROLE_NAMES := ["Mando", "Navegación", "Ingeniería", "Armas", "Sensores", "Comunicaciones", "Enlace", "Control de daños"]
const SYSTEMS := ["reactor", "motores", "maniobra", "warp", "salto", "armas", "misiles", "escudos", "escudos_popa", "sensores"]
const SYSTEM_NAMES := {"reactor": "Reactor", "motores": "Impulso", "maniobra": "Maniobra", "warp": "Warp", "salto": "Salto", "armas": "Haces", "misiles": "Misiles", "escudos": "Escudo proa", "escudos_popa": "Escudo popa", "sensores": "Sensores"}
const CONTACT_KINDS = ["station", "friendly", "hostile", "derelict", "anomaly", "beacon", "asteroid", "planet", "blackhole", "wormhole", "nebula", "supplydrop", "artifact"]
const CONTACT_NAMES = ["Estación", "Aliado", "Hostil", "Nave averiada", "Anomalía", "Baliza", "Asteroide", "Planeta", "Agujero negro", "Agujero de gusano", "Nebulosa", "Suministro", "Artefacto"]
const PERMISSIONS := {
	"mando": ["alert", "mission_choice"],
	"navegacion": ["helm", "autopilot", "dock", "undock", "boost"],
	"ingenieria": ["power", "coolant", "shields"],
	"armas": ["fire", "missile"],
	"sensores": ["scan"],
	"comunicaciones": ["hail", "negotiate"],
	"enlace": ["probe", "salvage", "rescue"],
	"reparaciones": ["repair", "repair_target"]
}
const DESCRIPTIONS := {
	"mando": "Coordina la alerta, decide el desenlace y consulta los objetivos compartidos.",
	"navegacion": "Traza el rumbo, regula el impulso y atraca. La energía de motores cambia tu velocidad.",
	"ingenieria": "Reparte 20 unidades de potencia entre diez sistemas. Cada avería afecta a su función; la sobrecarga genera calor.",
	"armas": "Identifica el blanco y orienta la proa para los haces. Controla los tubos y el blanco automático desde Operaciones.",
	"sensores": "Revela contactos y sus puntos débiles. La interferencia necesita un canal de Comunicaciones.",
	"comunicaciones": "Abre canales, negocia y despeja la interferencia para que Sensores pueda identificar.",
	"enlace": "Lanza sondas, recupera materiales y rescata supervivientes tras identificarlos.",
	"reparaciones": "Envía drones al sistema que más lo necesita o repara un objetivo cercano con repuestos."
}

static func missions() -> Array:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign.json"))
	return raw.missions if raw is Dictionary and raw.has("missions") else []

static func validate_mission(value: Variant) -> String:
	if not value is Dictionary:
		return "La misión debe ser un objeto JSON."
	if value.has("ship_design"):
		var error = ShipModel.validate_design(value.ship_design)
		if not error.is_empty(): return error
	if value.has("ship_loadout"):
		var error = LoadoutDocument.validate_loadout(value.ship_loadout)
		if not error.is_empty(): return error
	for key in ["id", "title", "sector", "briefing", "contacts", "objectives"]:
		if not value.has(key):
			return "Falta el campo: " + key
	for key in ["id", "title", "sector", "briefing"]:
		if not value[key] is String or value[key].is_empty() or value[key].length() > 4000:
			return "Texto inválido: " + key
	var identifier = RegEx.new()
	identifier.compile("^[a-zA-Z0-9_-]{1,64}$")
	if identifier.search(value.id) == null:
		return "El identificador solo admite letras, cifras, guion y guion bajo."
	if value.has("reward") and (not finite_number(value.reward) or float(value.reward) < 0 or float(value.reward) > 10000):
		return "La recompensa debe estar entre 0 y 10000."
	if not value.contacts is Array or value.contacts.size() > 48:
		return "Se permiten hasta 48 contactos."
	if not value.objectives is Array or value.objectives.is_empty() or value.objectives.size() > 24:
		return "Se necesitan entre 1 y 24 objetivos."
	var ids: Array = []
	for contact in value.contacts:
		if not contact is Dictionary:
			return "Contacto inválido."
		for key in ["id", "name", "kind", "position"]:
			if not contact.has(key):
				return "Contacto sin " + key
		if not contact.id is String or contact.id.is_empty() or contact.id.length() > 64 or contact.id in ids:
			return "Los identificadores de contacto deben ser únicos."
		ids.append(contact.id)
		if identifier.search(contact.id) == null:
			return "Identificador de contacto inválido."
		if not contact.name is String or contact.name.length() > 80:
			return "Nombre de contacto inválido."
		if contact.kind not in CONTACT_KINDS:
			return "Tipo de contacto desconocido."
		var physics_error = SpacePhysics.validate_contact(contact)
		if not physics_error.is_empty(): return physics_error
		if not contact.position is Array or contact.position.size() != 2:
			return "Posición inválida."
		for coordinate in contact.position:
			if not finite_number(coordinate) or absf(float(coordinate)) > 12000:
				return "Coordenada fuera del sector."
		if contact.has("frequency") and (not finite_number(contact.frequency) or contact.frequency < 0 or contact.frequency > 20 or contact.frequency != floorf(contact.frequency)):
			return "Frecuencia de contacto inválida."
		for flag in ["jammed", "known"]:
			if contact.has(flag) and not contact[flag] is bool:
				return "Indicador inválido: " + flag
		for resource in ["hull", "survivors"]:
			if contact.has(resource) and (not finite_number(contact[resource]) or contact[resource] < 0 or contact[resource] > 100):
				return "Recurso de contacto fuera de rango: " + resource
	for objective in value.objectives:
		if not objective is Dictionary or not objective.get("text") is String or objective.text.is_empty() or objective.text.length() > 500:
			return "Objetivo sin texto."
		if objective.get("type") not in ["navigate", "dock", "hail", "scan", "salvage", "rescue", "defeat", "repair_target", "choice", "probe", "touch", "pickup"]:
			return "Tipo de objetivo desconocido."
		if objective.get("target", "") not in ids:
			return "Un objetivo referencia un contacto inexistente."
		var allowed_kinds: Array = {
			"dock": ["station"], "repair_target": ["station"],
			"touch": SpacePickups.KINDS, "pickup": SpacePickups.KINDS,
			"rescue": ["derelict"], "salvage": ["derelict", "anomaly"],
			"defeat": ["hostile"], "choice": ["friendly", "hostile"]
		}.get(objective.type, [])
		if not allowed_kinds.is_empty():
			for contact in value.contacts:
				if contact.id == objective.target and contact.kind not in allowed_kinds:
					return "El objetivo no es compatible con ese tipo de contacto."
				if contact.id == objective.target and objective.type == "pickup" and contact.kind == "artifact" and not contact.get("allow_pickup", false):
					return "El objetivo requiere un artefacto recogible."
	return ""

static func finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func role_name(role: String) -> String:
	var i := ROLES.find(role)
	return ROLE_NAMES[i] if i >= 0 else "Observador"
