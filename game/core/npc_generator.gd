class_name NpcGenerator
extends RefCounted
## Pure, versioned authoring tool. No Session, scene, network or global RNG access.

const FORMAT = "lagunak-npc"
const VERSION = 1
const ALGORITHM = "sha256-v1"
const MAX_SEED = 2147483647
const MAX_BYTES = 65536
const ABILITIES = ["fuerza", "destreza", "constitucion", "inteligencia", "sabiduria", "carisma"]
const AFFINITIES = ["debil", "neutral", "resiste", "nulo", "absorbe", "repele"]
const NATURES = ["mineral", "vegetal", "fluida", "artificial"]
const ELEMENTS = {
	"brasa": {"damage_type": "fire", "strong": "vegetal", "weak": "mineral"},
	"escarcha": {"damage_type": "cold", "strong": "fluida", "weak": "artificial"},
	"descarga": {"damage_type": "lightning", "strong": "artificial", "weak": "vegetal"},
	"corrosion": {"damage_type": "acid", "strong": "mineral", "weak": "fluida"},
	"resonancia": {"damage_type": "thunder", "strong": "mineral", "weak": "vegetal"},
	"impulso": {"damage_type": "force", "strong": "fluida", "weak": "mineral"},
	"destello": {"damage_type": "radiant", "strong": "vegetal", "weak": "artificial"}
}
# Entirely new names, lines and action descriptions, not tables from the original.
const LINES = [
	{"id": "lente", "name": "Vigía de cristal", "nature": "mineral", "primary": "sabiduria"},
	{"id": "brote", "name": "Guardián de raíces", "nature": "vegetal", "primary": "constitucion"},
	{"id": "estela", "name": "Mensajero de bruma", "nature": "fluida", "primary": "destreza"},
	{"id": "remache", "name": "Custodio de latón", "nature": "artificial", "primary": "fuerza"}
]
const EPITHETS = ["del embarcadero", "del observatorio", "de la dársena", "de la baliza", "del invernadero", "del astillero"]
const STAGES = ["incipiente", "desarrollada", "madura"]
const RULES = {
	"title": "System Reference Document 5.1",
	"author": "Wizards of the Coast LLC",
	"source": "https://www.dndbeyond.com/srd",
	"license": "CC-BY-4.0",
	"license_url": "https://creativecommons.org/licenses/by/4.0/",
	"attribution": "Referencia de las fórmulas de características, competencia y dados de golpe: System Reference Document 5.1, Wizards of the Coast LLC, CC-BY-4.0. No implica patrocinio ni aprobación.",
	"changes": "Código, nombres, líneas, acciones y tablas propios. Afinidades, naturaleza, etapas y asignación de VD son reglas de autoría del remake, no contenido SRD ni una garantía de equilibrio."
}

static func challenges() -> Array:
	var values: Array = [0.0, 0.125, 0.25, 0.5]
	for value in range(1, 31): values.append(float(value))
	return values

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _whole(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value) >= low and float(value) <= high and floor(float(value)) == float(value)

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func modifier(score: Variant) -> Dictionary:
	if not _whole(score, 1, 30): return _fail("La característica debe ser un entero entre 1 y 30.")
	return {"ok": true, "value": floori((float(score) - 10.0) / 2.0)}

static func proficiency(challenge: Variant) -> Dictionary:
	if not _number(challenge) or not float(challenge) in challenges():
		return _fail("VD no válido: 0, 1/8, 1/4, 1/2 o un entero de 1 a 30.")
	return {"ok": true, "value": 2 + maxi(0, floori((float(challenge) - 1.0) / 4.0))}

static func _pick(seed_value: int, channel: String, count: int) -> int:
	# Independent channels keep the same lineage when only the challenge changes.
	var digest = ("lagunak-npc-v1|%d|%s" % [seed_value, channel]).sha256_text()
	return digest.substr(0, 8).hex_to_int() % count

static func generate(seed_value: Variant, challenge: Variant) -> Dictionary:
	if not _whole(seed_value, 0, MAX_SEED): return _fail("La semilla debe ser un entero de 0 a 2147483647.")
	var pb = proficiency(challenge)
	if not pb.ok: return pb
	var seed_number = int(seed_value)
	var cr = float(challenge)
	var line: Dictionary = LINES[_pick(seed_number, "line", LINES.size())]
	var stage = 3 if cr >= 11.0 else 2 if cr >= 5.0 else 1
	var scores: Dictionary = {}
	var mods: Dictionary = {}
	for ability in ABILITIES:
		var score = 8 + _pick(seed_number, "ability:" + ability, 10) + floori(cr / 4.0)
		if ability == line.primary: score += 4
		scores[ability] = clampi(score, 1, 30)
		mods[ability] = modifier(scores[ability]).value
	var die = [6, 8, 10][stage - 1]
	var dice = maxi(1, 1 + floori(cr * 2.0))
	var hp = maxi(1, floori(dice * ((die + 1.0) / 2.0 + mods.constitucion)))
	var affinities: Dictionary = {}
	var elements = ELEMENTS.keys()
	for element in elements:
		affinities[element] = AFFINITIES[_pick(seed_number, "affinity:" + element, AFFINITIES.size())]
	affinities[elements[_pick(seed_number, "weakness", elements.size())]] = "debil"
	var attack_element: String = elements[_pick(seed_number, "attack", elements.size())]
	var attack_mod = maxi(mods.fuerza, mods.destreza)
	var movement = 6 + stage * 3
	var sheet = {
		"id": "npc-v1-%d-%s" % [seed_number, str(cr).replace(".", "_")],
		"name": "%s %s · %d" % [line.name, EPITHETS[_pick(seed_number, "name", EPITHETS.size())], seed_number],
		"challenge": cr, "line": line.id, "nature": line.nature,
		"stage": stage, "stage_name": STAGES[stage - 1],
		"size": ["pequena", "mediana", "grande"][stage - 1],
		"abilities": scores, "modifiers": mods, "proficiency": pb.value,
		"armor_class": 10 + mods.destreza + stage - 1,
		"hit_points": hp, "hit_dice": {"count": dice, "sides": die, "constitution_per_die": mods.constitucion},
		"speed_m": movement, "affinities": affinities,
		"elements": ELEMENTS.duplicate(true),
		"actions": {
			"action": [{"id": "golpe", "name": "Golpe de encuentro", "attack_bonus": pb.value + attack_mod,
				"damage": {"dice": stage, "sides": 6, "bonus": maxi(0, attack_mod), "element": attack_element, "type": ELEMENTS[attack_element].damage_type},
				"text": "Un ataque contra un objetivo al alcance de 1,5 m. Tira d20 y suma el bono; si alcanza su CA, tira el daño indicado."}],
			"bonus": [{"id": "paso", "name": "Paso cauteloso", "distance_m": 1.5,
				"text": "Desplázate 1,5 m sin atravesar obstáculos. Consume la acción adicional del turno."}],
			"reaction": [{"id": "amparo", "name": "Amparo fugaz", "armor_bonus": 2,
				"text": "Cuando un ataque vaya a impactar, suma 2 a tu CA contra ese ataque. Consume tu reacción hasta tu siguiente turno."}],
			"movement": [{"id": "mover", "name": "Desplazamiento", "distance_m": movement,
				"text": "Reparte esta distancia durante el turno; respeta obstáculos y terreno de la escena."}]
		},
		"procedencia_reglas": RULES.duplicate(true)
	}
	return {"ok": true, "document": {"format": FORMAT, "version": VERSION, "algorithm": ALGORITHM,
		"recipe": {"seed": seed_number, "challenge": cr}, "sheet": sheet}}

static func effectiveness(element: String, nature: String) -> Dictionary:
	if not ELEMENTS.has(element): return _fail("Elemento desconocido.")
	if not nature in NATURES: return _fail("Naturaleza desconocida.")
	var row: Dictionary = ELEMENTS[element]
	var multiplier = 2.0 if nature == row.strong else 0.5 if nature == row.weak else 1.0
	return {"ok": true, "multiplier": multiplier, "damage_type": row.damage_type}

static func resolve_damage(amount: Variant, element: String, nature: String, affinity: String) -> Dictionary:
	if not _whole(amount, 0, 1000000): return _fail("El daño debe ser un entero entre 0 y 1000000.")
	if not affinity in AFFINITIES: return _fail("Afinidad desconocida.")
	var match_up = effectiveness(element, nature)
	if not match_up.ok: return match_up
	var factor = 2.0 if affinity == "debil" else 0.5 if affinity == "resiste" else 1.0
	var adjusted = floori(float(amount) * match_up.multiplier * factor)
	return {"ok": true, "damage": adjusted if affinity in ["debil", "neutral", "resiste"] else 0,
		"healing": adjusted if affinity == "absorbe" else 0,
		"reflected": adjusted if affinity == "repele" else 0}

static func _same_json(left: Variant, right: Variant, depth: int = 0) -> bool:
	if depth > 16: return false
	if _number(left) and _number(right): return float(left) == float(right)
	if typeof(left) != typeof(right): return false
	if left is Dictionary:
		if left.size() != right.size(): return false
		for key in right:
			if not left.has(key) or not _same_json(left[key], right[key], depth + 1): return false
		return true
	if left is Array:
		if left.size() != right.size(): return false
		for index in right.size():
			if not _same_json(left[index], right[index], depth + 1): return false
		return true
	return left == right

static func validate_document(value: Variant) -> Dictionary:
	if not value is Dictionary: return _fail("Se necesita un documento NPC JSON.")
	if value.size() != 5 or value.get("format") != FORMAT or value.get("algorithm") != ALGORITHM:
		return _fail("Formato o algoritmo NPC no compatible.")
	if not _whole(value.get("version"), VERSION, VERSION): return _fail("Versión NPC no compatible.")
	var recipe: Variant = value.get("recipe")
	if not recipe is Dictionary or recipe.size() != 2: return _fail("Receta NPC no válida.")
	var result = generate(recipe.get("seed"), recipe.get("challenge"))
	if not result.ok: return result
	# Never trust imported stats, text, attribution or extensions. Recompute all fields.
	if not _same_json(value, result.document): return _fail("La ficha no corresponde a su receta o contiene campos ajenos.")
	return result

static func decode_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_BYTES: return _fail("El documento supera 64 KiB.")
	# Reject malformed UTF-8 before Godot's decoder can emit an engine error.
	var index = 0
	while index < bytes.size():
		var lead = int(bytes[index])
		if lead <= 0x7f:
			index += 1
			continue
		var count = 2 if lead >= 0xc2 and lead <= 0xdf else 3 if lead >= 0xe0 and lead <= 0xef else 4 if lead >= 0xf0 and lead <= 0xf4 else 0
		if count == 0 or index + count > bytes.size(): return _fail("El archivo no contiene UTF-8 válido.")
		var codepoint = lead & (0x7f >> count)
		for offset in range(1, count):
			var continuation = int(bytes[index + offset])
			if (continuation & 0xc0) != 0x80: return _fail("El archivo no contiene UTF-8 válido.")
			codepoint = (codepoint << 6) | (continuation & 0x3f)
		if codepoint < [0, 0, 0x80, 0x800, 0x10000][count] or codepoint > 0x10ffff or (codepoint >= 0xd800 and codepoint <= 0xdfff):
			return _fail("El archivo no contiene UTF-8 válido.")
		index += count
	return decode(bytes.get_string_from_utf8())

static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return _fail("El documento supera 64 KiB.")
	var parser = JSON.new()
	if parser.parse(text) != OK: return _fail("JSON no válido.")
	return validate_document(parser.data)

static func describe(document: Dictionary) -> String:
	var valid = validate_document(document)
	if not valid.ok: return valid.error
	var npc: Dictionary = valid.document.sheet
	var lines = PackedStringArray([
		npc.name, "VD %s · %s · %s · etapa %d (%s)" % [str(npc.challenge), npc.nature, npc["size"], npc.stage, npc.stage_name],
		"CA %d · PG %d · competencia %+d · velocidad %d m" % [npc.armor_class, npc.hit_points, npc.proficiency, npc.speed_m],
		"Dados de golpe: %dd%d; CON %+d por dado." % [npc.hit_dice.count, npc.hit_dice.sides, npc.hit_dice.constitution_per_die], "", "CARACTERÍSTICAS"
	])
	for ability in ABILITIES: lines.append("%s: %d (%+d)" % [ability.capitalize(), npc.abilities[ability], npc.modifiers[ability]])
	lines.append("\nAFINIDADES · debil ×2 / neutral ×1 / resiste ×0,5 / nulo / absorbe / repele")
	for element in ELEMENTS: lines.append("%s (%s): %s · contra naturaleza %s ×2 / %s ×0,5" % [element.capitalize(), ELEMENTS[element].damage_type, npc.affinities[element], ELEMENTS[element].strong, ELEMENTS[element].weak])
	lines.append("La naturaleza añade ×2/×0,5/×1 antes de la afinidad. Redondea el resultado hacia abajo una vez. Absorber cura; repeler devuelve daño sin bucle de reflexión.")
	for section in ["action", "bonus", "reaction", "movement"]:
		lines.append("\n" + {"action": "ACCIÓN", "bonus": "ACCIÓN ADICIONAL", "reaction": "REACCIÓN", "movement": "MOVIMIENTO"}[section])
		for action in npc.actions[section]:
			lines.append(action.name + ": " + action.text)
			if action.has("attack_bonus"):
				lines.append("Ataque %+d · daño %dd%d%+d (%s)." % [action.attack_bonus, action.damage.dice, action.damage.sides, action.damage.bonus, action.damage.type])
			if action.has("distance_m"): lines.append("Distancia: %s m." % str(action.distance_m))
	lines.append("\nRECETA · algoritmo %s · semilla %d · VD %s" % [ALGORITHM, document.recipe.seed, str(document.recipe.challenge)])
	lines.append("\n" + RULES.attribution + "\n" + RULES.source + "\n" + RULES.license_url + "\n" + RULES.changes)
	lines.append("\nFicha de autoría local para dirigir una escena. No crea habitantes ni cambia combate, campaña o fichas de tripulación.")
	return "\n".join(lines)
