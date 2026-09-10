extends SceneTree

const Generator = preload("res://core/npc_generator.gd")
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	for score in range(1, 31):
		check(Generator.modifier(score).value == floori((score - 10.0) / 2.0), "modifier %d" % score)
	for invalid in [0, 31, -2, 1.5, "10", true, null, NAN, INF]:
		check(not Generator.modifier(invalid).ok, "reject ability")
	for entry in [[0, 2], [0.125, 2], [4, 2], [5, 3], [8, 3], [9, 4], [12, 4], [13, 5], [16, 5], [17, 6], [20, 6], [21, 7], [25, 8], [29, 9], [30, 9]]:
		check(Generator.proficiency(entry[0]).value == entry[1], "proficiency threshold")
	for invalid in [-1, 31, 0.1, 2.5, "1", true, null, NAN, INF]:
		check(not Generator.generate(1, invalid).ok, "reject challenge")
	for invalid in [-1, 2147483648, 0.25, "1", true, null, NAN, INF]:
		check(not Generator.generate(invalid, 1).ok, "reject seed")
	for entry in [[0, "estela"], [1, "remache"], [2147483647, "lente"]]:
		check(Generator.generate(entry[0], 1).document.sheet.line == entry[1], "SHA256 v1 golden lineage")
	var seen_lines: Dictionary = {}
	for seed_value in range(512):
		var first = Generator.generate(seed_value, 1).document
		var again = Generator.generate(seed_value, 1).document
		check(first == again, "deterministic generation")
		check(Generator.decode(JSON.stringify(first)).ok, "JSON round trip")
		check(first.sheet.affinities.values().has("debil"), "at least one weakness")
		check(first.sheet.procedencia_reglas.license == "CC-BY-4.0", "attribution travels")
		seen_lines[first.sheet.line] = true
		for ability in Generator.ABILITIES:
			check(first.sheet.abilities[ability] >= 1 and first.sheet.abilities[ability] <= 30, "bounded ability")
		for section in ["action", "bonus", "reaction", "movement"]:
			check(not first.sheet.actions[section].is_empty(), "complete action economy")
		var previous_hp = 0
		var previous_stage = 0
		for challenge in [0, 0.125, 0.25, 0.5, 1, 4, 5, 10, 11, 20, 30]:
			var npc = Generator.generate(seed_value, challenge).document.sheet
			check(npc.line == first.sheet.line and npc.name == first.sheet.name, "lineage survives growth")
			check(npc.hit_points >= previous_hp and npc.stage >= previous_stage, "monotonic growth")
			previous_hp = npc.hit_points
			previous_stage = npc.stage
			check(npc.hit_points == maxi(1, floori(npc.hit_dice.count * ((npc.hit_dice.sides + 1.0) / 2.0 + npc.modifiers.constitucion))), "hit point formula")
	check(seen_lines.size() == 4, "all own lines represented")
	for challenge in Generator.challenges():
		check(Generator.validate_document(Generator.generate(42, challenge).document).ok, "all supported challenges")
	for element in Generator.ELEMENTS:
		var row: Dictionary = Generator.ELEMENTS[element]
		check(row.strong in Generator.NATURES and row.weak in Generator.NATURES and row.strong != row.weak, "matrix namespaces")
		for nature in Generator.NATURES:
			var expected = 2.0 if nature == row.strong else 0.5 if nature == row.weak else 1.0
			check(Generator.effectiveness(element, nature).multiplier == expected, "derived matrix")
	check(not Generator.effectiveness("missing", "mineral").ok, "unknown element rejected")
	check(not Generator.effectiveness("brasa", "brasa").ok, "unknown nature rejected")
	var damage_cases = [["debil", 20, 0, 0], ["neutral", 10, 0, 0], ["resiste", 5, 0, 0], ["nulo", 0, 0, 0], ["absorbe", 0, 10, 0], ["repele", 0, 0, 10]]
	for entry in damage_cases:
		var result = Generator.resolve_damage(5, "brasa", "vegetal", entry[0])
		check(result.ok and result.damage == entry[1] and result.healing == entry[2] and result.reflected == entry[3], "affinity resolution")
	check(Generator.resolve_damage(3, "brasa", "mineral", "resiste").damage == 0, "round down once")
	for invalid in [-1, 1000001, 0.5, "1", true, NAN, INF, null]:
		check(not Generator.resolve_damage(invalid, "brasa", "vegetal", "neutral").ok, "invalid damage")
	check(not Generator.resolve_damage(1, "brasa", "vegetal", "typo").ok, "invalid affinity")
	var original = Generator.generate(7, 5).document
	var snapshot = original.duplicate(true)
	check(Generator.validate_document(original).ok and original == snapshot, "validation does not mutate")
	for field in ["format", "version", "algorithm", "recipe", "sheet"]:
		var missing = original.duplicate(true)
		missing.erase(field)
		check(not Generator.validate_document(missing).ok, "required field " + field)
	var tampered = original.duplicate(true)
	tampered.sheet.hit_points += 1
	check(not Generator.validate_document(tampered).ok, "reject edited stats")
	tampered = original.duplicate(true)
	tampered.sheet.actions.action[0].text = "[url=https://invalid.example/]injection[/url]"
	check(not Generator.validate_document(tampered).ok, "reject edited actions")
	tampered = original.duplicate(true)
	tampered.sheet.procedencia_reglas.author = "Other"
	check(not Generator.validate_document(tampered).ok, "reject changed provenance")
	check(Generator.generate(7, 5).document == original, "independent nested data")
	tampered = original.duplicate(true)
	tampered.recipe.seed = 8
	check(not Generator.validate_document(tampered).ok, "reject changed recipe with old sheet")
	tampered = original.duplicate(true)
	tampered.unrelated_data = "not an NPC field"
	check(not Generator.validate_document(tampered).ok, "reject extra fields")
	for invalid in [null, true, 1, "npc", [], {}, {"version": 99}]:
		check(not Generator.validate_document(invalid).ok, "reject wrong document type")
	for text in ["", "{", "null", "[]", "true", " ".repeat(Generator.MAX_BYTES + 1)]:
		check(not Generator.decode(text).ok, "reject invalid or oversized JSON")
	check(Generator.decode_bytes(JSON.stringify(original).to_utf8_buffer()).ok, "valid UTF-8 document")
	for invalid in [[0xff], [0xc0, 0x80], [0xe0, 0x80, 0x80], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0xf0, 0x9f], [0xc2, 0x20], [0x80]]:
		check(not Generator.decode_bytes(PackedByteArray(invalid)).ok, "reject malformed UTF-8 without engine errors")
	check(Generator.describe(original).contains("ACCIÓN ADICIONAL"), "readable actions")
	check(Generator.describe(original).contains("CC-BY-4.0"), "readable attribution")
	if failures.is_empty():
		print("NPC_GENERATOR_PASS checks=%d" % checks)
		quit(0)
	else:
		for failure in failures: printerr("NPC_GENERATOR_FAIL: " + failure)
		quit(1)
