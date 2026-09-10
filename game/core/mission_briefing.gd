class_name MissionBriefing
extends RefCounted
## Read-only handouts built from the recipient's Session.view, never sim.state.
## This is not a campaign save, a session log or an importable mission.

const FORMAT = "espaciokoop-mission-briefing"
const VERSION = 1
const EXTENSIONS = ["md", "html", "json"]
const MAX_OUTPUT_BYTES = 262144
const NOTICE = "Instantánea de los objetivos visibles de la misión, no un registro completo de sesión. La guía del puesto es orientativa: no ejecuta órdenes ni cambia permisos. Revisa el texto antes de compartirlo."
const STATUS_NAMES = {"active": "En curso", "won": "Completada", "lost": "Fallida"}
const OBJECTIVE_NAMES = {"completed": "Completado", "current": "Actual", "pending": "Pendiente"}
const CHECKLISTS = {
	"mando": [
		"Acordad el objetivo prioritario y comunicad los cambios de alerta a toda la tripulación.",
		"Pedid confirmación a los puestos implicados antes de decidir el desenlace.",
		"Comprobad los objetivos compartidos antes de dar la misión por terminada."
	],
	"navegacion": [
		"Selecciona el destino y coordina con Ingeniería la potencia de motores.",
		"Mantén el alcance y la orientación que necesiten Sensores, Armas o Enlace.",
		"Reduce la velocidad antes del atraque y confirma que has desatracado antes de maniobrar."
	],
	"ingenieria": [
		"Reparte la potencia según la maniobra acordada y vigila el calor de cada sistema.",
		"Dirige la refrigeración al sistema que la necesite y comunica las averías a Control de daños.",
		"Coordina los escudos con Comunicaciones antes de intentar una negociación."
	],
	"armas": [
		"Pide a Sensores que identifique el blanco antes de abrir fuego.",
		"Coordina con Navegación el arco y alcance; comprueba energía, munición y recarga.",
		"Revisa tubos y blanco automático en Operaciones y respeta los acuerdos diplomáticos."
	],
	"sensores": [
		"Solicita a Navegación que mantenga el contacto dentro del alcance de análisis.",
		"Ante interferencias, pide a Comunicaciones que abra un canal.",
		"Comparte la identificación con Armas y Enlace; una sonda puede facilitar el análisis."
	],
	"comunicaciones": [
		"Abre un canal cuando el contacto esté en alcance para ayudar a Sensores.",
		"Antes de negociar, confirma identificación, canal abierto y escudos bajos con Ingeniería.",
		"Comunica el resultado a Mando para que pueda tomar la decisión de misión."
	],
	"enlace": [
		"Comprueba la disponibilidad de sondas y acuerda el objetivo con Sensores.",
		"Pide identificación y aproximación antes de recuperar materiales o rescatar supervivientes.",
		"Confirma la operación y avisa a Navegación antes de alejaros del contacto."
	],
	"reparaciones": [
		"Pide a Ingeniería una prioridad de reparación según las averías de la nave.",
		"Comprueba repuestos y disponibilidad de drones antes de iniciar otra reparación.",
		"Para reparar una estación, coordina la aproximación con Navegación y confirma el objetivo."
	]
}

static func create(view: Dictionary, role: String) -> Dictionary:
	if role not in Catalog.ROLES:
		return _failure("Selecciona uno de los ocho puestos.")
	if not view.get("mission") is Dictionary:
		return _failure("No hay una misión disponible para preparar el briefing.")
	var mission: Dictionary = view.mission
	for key in ["title", "sector", "briefing"]:
		if not _valid_text(mission.get(key), 4000):
			return _failure("La misión contiene texto ausente, demasiado largo o no válido.")
	var source: Variant = mission.get("objectives")
	if not source is Array or source.is_empty() or source.size() > 24:
		return _failure("La misión debe tener entre 1 y 24 objetivos visibles.")
	var cursor: Variant = view.get("objective", 0)
	if not Catalog.finite_number(cursor):
		return _failure("El progreso de los objetivos no es válido.")
	if float(cursor) != floorf(float(cursor)) or cursor < 0 or cursor > source.size():
		return _failure("El progreso de los objetivos está fuera de rango.")
	var state: Variant = view.get("status", "active")
	if not state is String or state not in STATUS_NAMES:
		return _failure("El estado de la misión no es válido.")
	var objectives: Array = []
	for i in range(source.size()):
		if not source[i] is Dictionary or not _valid_text(source[i].get("text"), 500):
			return _failure("Un objetivo contiene texto ausente, demasiado largo o no válido.")
		var progress = "completed" if i < int(cursor) else "pending"
		if i == int(cursor) and state == "active": progress = "current"
		# In particular, do not serialize target IDs, contacts or arbitrary extras.
		objectives.append({"number": i + 1, "text": source[i].text, "status": progress})
	return {"ok": true, "document": {
		"format": FORMAT, "version": VERSION,
		"mission": {"title": mission.title, "sector": mission.sector, "briefing": mission.briefing, "status": state},
		"station": {"id": role, "name": Catalog.role_name(role), "description": Catalog.DESCRIPTIONS[role], "checklist": CHECKLISTS[role].duplicate()},
		"objectives": objectives, "notice": NOTICE
	}}

static func render(view: Dictionary, role: String, extension: String) -> Dictionary:
	if extension not in EXTENSIONS: return _failure("Formato de briefing no admitido.")
	var result = create(view, role)
	if not result.ok: return result
	var document: Dictionary = result.document
	var text = ""
	match extension:
		"json": text = JSON.stringify(document, "\t", true) + "\n"
		"md": text = _markdown(document)
		"html": text = _html(document)
	if text.to_utf8_buffer().size() > MAX_OUTPUT_BYTES:
		return _failure("El briefing supera el límite de exportación.")
	return {"ok": true, "text": text, "extension": extension}

static func write_new(path: String, prepared: Dictionary) -> Dictionary:
	# Only the explicit save action calls this function; never overwrite a save.
	if prepared.get("ok") != true or not prepared.get("text") is String:
		return _failure("No hay un briefing válido para guardar.")
	var extension: Variant = prepared.get("extension")
	if not extension is String or extension not in EXTENSIONS:
		return _failure("Formato de exportación no admitido.")
	if path.is_empty() or path.begins_with("res://") or ("://" in path and not path.begins_with("user://")):
		return _failure("Elige un archivo local fuera de los recursos del juego.")
	if not path.is_absolute_path() and not path.begins_with("user://"):
		return _failure("Elige una ruta local absoluta.")
	if path.get_extension().to_lower() != extension:
		return _failure("La extensión del archivo debe ser ." + extension + ".")
	var bytes: PackedByteArray = prepared.text.to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > MAX_OUTPUT_BYTES:
		return _failure("El contenido está vacío o supera el límite de exportación.")
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return _failure("Ese archivo ya existe. Elige otro nombre; no se sobrescribirá.")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("No se pudo crear el archivo local (error %d)." % FileAccess.get_open_error())
	file.store_buffer(bytes)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(path)
		return _failure("No se pudo completar la escritura (error %d)." % error)
	return {"ok": true, "message": "Briefing guardado localmente: " + path}

static func _valid_text(value: Variant, limit: int) -> bool:
	if not value is String or value.is_empty() or value.length() > limit: return false
	if value.strip_edges().is_empty(): return false
	for i in range(value.length()):
		var code: int = value.unicode_at(i)
		if (code < 32 and code not in [9, 10, 13]) or code == 127: return false
	return true

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _md(text: String) -> String:
	# Treat authored text as text, not Markdown/HTML or remote images.
	var safe = text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ").replace("\t", " ")
	for mark in ["\\", "`", "*", "_", "{", "}", "[", "]", "<", ">", "(", ")", "#", "+", "-", ".", "!", "|", "~", "&"]:
		safe = safe.replace(mark, "\\" + mark)
	return safe

static func _markdown(document: Dictionary) -> String:
	var mission: Dictionary = document.mission
	var station: Dictionary = document.station
	var lines: Array[String] = ["# Briefing · " + _md(mission.title), "", "**Puesto:** " + station.name, "**Sector:** " + _md(mission.sector), "**Estado:** " + STATUS_NAMES[mission.status], "", "## Situación", "", _md(mission.briefing), "", "## Objetivos compartidos", ""]
	for objective in document.objectives:
		lines.append("%d. [%s] %s" % [objective.number, OBJECTIVE_NAMES[objective.status], _md(objective.text)])
	lines.append_array(["", "## Tu puesto: " + station.name, "", station.description, "", "## Coordinación antes de actuar", ""])
	for step in station.checklist: lines.append("- [ ] " + step)
	lines.append_array(["", "---", "", NOTICE, ""])
	return "\n".join(lines)

static func _html(document: Dictionary) -> String:
	var mission: Dictionary = document.mission
	var station: Dictionary = document.station
	var text = "<!doctype html>\n<html lang=\"es\"><head><meta charset=\"utf-8\">"
	text += "<meta name=\"referrer\" content=\"no-referrer\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\">"
	text += "<title>Briefing · " + mission.title.xml_escape(true) + "</title>"
	text += "<style>@page{size:A4;margin:18mm}body{font-family:system-ui,sans-serif;line-height:1.5;max-width:48rem;margin:2rem auto;padding:0 1rem}h1{font-size:1.7rem}h2{font-size:1.15rem;margin-top:1.5rem}li{margin-bottom:.6rem;break-inside:avoid}h1,h2{break-after:avoid}footer{border-top:1px solid;margin-top:2rem;font-size:.85rem}.situation{white-space:pre-wrap}@media print{body{margin:0;padding:0}}</style></head><body>"
	text += "<h1>Briefing · " + mission.title.xml_escape(true) + "</h1>"
	text += "<p><strong>Puesto:</strong> " + station.name.xml_escape(true) + "<br><strong>Sector:</strong> " + mission.sector.xml_escape(true) + "<br><strong>Estado:</strong> " + STATUS_NAMES[mission.status] + "</p>"
	text += "<h2>Situación</h2><p class=\"situation\">" + mission.briefing.xml_escape(true) + "</p><h2>Objetivos compartidos</h2><ol>"
	for objective in document.objectives:
		text += "<li><strong>" + OBJECTIVE_NAMES[objective.status] + ":</strong> " + objective.text.xml_escape(true) + "</li>"
	text += "</ol><h2>Tu puesto: " + station.name.xml_escape(true) + "</h2><p>" + station.description.xml_escape(true) + "</p><h2>Coordinación antes de actuar</h2><ul>"
	for step in station.checklist: text += "<li>☐ " + step.xml_escape(true) + "</li>"
	return text + "</ul><footer>" + NOTICE.xml_escape(true) + "</footer></body></html>\n"
