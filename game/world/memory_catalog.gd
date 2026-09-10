class_name MemoryCatalog
extends RefCounted
## Read-only interpretation of the public campaign snapshot. No rewards or save state.

const ZONE = 12
const MISSIONS = ["itsasoratu", "oihartzuna", "aterpe", "zaindari", "berpiztu", "elkarlana"]
const TITLES = ["La partida", "El eco", "El refugio", "La guardia", "El regreso", "La cooperación"]
const STORIES = [
	"La primera luz del corredor dejó de ser una coordenada. Argi volvió a tener una voz y Kaia pudo confirmar el regreso. La Itsaso aprendió a avanzar escuchando a todos sus puestos.",
	"Una señal repetida exigió paciencia antes que velocidad. La sonda y el canal compartido permitieron distinguir el eco del mensaje. La tripulación regresó con algo que podía comprender.",
	"El refugio comenzó mucho antes del puerto: en el momento de reconocer a la Lorea y enviar ayuda. La distancia dejó de medirse sólo en metros cuando hubo personas esperando al otro lado.",
	"La guardia no consistió únicamente en disparar. Identificar, proteger y sostener la nave fueron decisiones de una misma tripulación. El corredor de suministros pudo volver a recorrerse.",
	"Zubi necesitaba energía y el remolcador necesitaba un lugar al que llegar. Los repuestos se convirtieron en una bienvenida. Una reparación también puede construir un refugio.",
	"El encuentro con Haize pidió confianza visible. Abrir el canal y escuchar hizo posible compartir un camino. La última memoria de este viaje queda abierta a lo que la tripulación haga después."
]

static func reading_point(index: int) -> Vector3:
	return Vector3(3.1, 0, 25.0 - index * 10.0)

static func interactions() -> Array:
	var result: Array = [{"id": "memory_keeper", "kind": "memory_keeper", "title": "Guardiana · Ambiente y guía", "position": Vector3(-2.3, 0, 28.0), "text": "La guardiana acompaña el recorrido de la campaña."}]
	for i in MISSIONS.size():
		result.append({"id": "memory_%d" % i, "kind": "memory", "index": i, "title": TITLES[i], "position": reading_point(i), "text": "Recuerdo aún no vivido. Completa su misión para abrirlo."})
		result.append({"id": "memory_sentinel_%d" % i, "kind": "memory_sentinel", "index": i, "title": "Centinela · " + TITLES[i], "position": Vector3(-1.6, 0, reading_point(i).z), "text": "El centinela señala el recuerdo al otro lado del pasillo."})
	return result

static func memories(view: Dictionary) -> Array:
	var campaign: Dictionary = view.get("campaign", {}) if view.get("campaign", {}) is Dictionary else {}
	var completed: Array = campaign.get("completed", []) if campaign.get("completed", []) is Array else []
	var mission: Dictionary = view.get("mission", {}) if view.get("mission", {}) is Dictionary else {}
	var result: Array = []
	for i in MISSIONS.size():
		var unlocked = MISSIONS[i] in completed
		var current = mission.get("id", "") == MISSIONS[i] and not unlocked
		var state = "Conservado" if unlocked else ("En curso" if current else "Aún no vivido")
		var text = STORIES[i] if unlocked else "Este relato se abrirá cuando la tripulación complete su misión."
		if current: text += "\n\nLa misión actual pertenece a este recuerdo. Puedes continuarla desde el puente; el corredor no concede progreso."
		if unlocked and i in [2, 4]:
			var survivors = campaign.get("survivors", 0)
			if (survivors is int or survivors is float) and is_finite(float(survivors)):
				text += "\n\nPersonas rescatadas en esta campaña: %d (total acumulado)." % clampi(int(survivors), 0, 1000000)
		result.append({"index": i, "mission": MISSIONS[i], "title": TITLES[i], "state": state, "unlocked": unlocked, "current": current, "text": state + " · " + TITLES[i] + "\n\n" + text})
	return result

static func guide_index(memories_list: Array, visited: Array) -> int:
	for memory in memories_list:
		if memory.unlocked and memory.index not in visited: return memory.index
	for memory in memories_list:
		if memory.current: return memory.index
	for memory in memories_list:
		if memory.unlocked: return memory.index
	return -1

static func campaign_variant(memories_list: Array) -> String:
	var count = memories_list.filter(func(memory): return memory.unlocked).size()
	return "alba" if count == MISSIONS.size() else ("travesia" if count > 0 else "vigilia")
