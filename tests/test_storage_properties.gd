extends SceneTree
## Synthetic states only. The runner isolates user:// from the player's saves.

var checks = 0
var failures = 0
var seed_value = 3204301
var samples = 64
var sample_index = -1
var directory = ""
var missions: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("STORAGE_PROPERTY_FAIL seed=%d sample=%d: %s" % [seed_value, sample_index, label])

func fresh(index: int = 0) -> Dictionary:
	var sim = Simulation.new()
	sim.start(missions[index % missions.size()])
	return sim.state

func generated(index: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + index
	var state = fresh(index)
	var ship: Dictionary = state.ship
	state.time = rng.randi_range(0, 100000) / 8.0
	state.campaign.credits = rng.randi_range(0, 1000000)
	state.campaign.reputation = rng.randi_range(0, 1000000)
	state.campaign.survivors = rng.randi_range(0, 1000000)
	state.campaign.decisions = {"synthetic-choice": "compartir" if index % 2 else "conservar"}
	state.campaign.completed = []
	for i in range(index % (missions.size() + 1)):
		state.campaign.completed.append(missions[i].id)
	ship.position = [rng.randi_range(-12000, 12000) / 2.0, rng.randi_range(-12000, 12000) / 2.0]
	ship.heading = rng.randi_range(0, 359)
	ship.target_heading = rng.randi_range(0, 359)
	ship.hull = rng.randi_range(1, 800) / 8.0
	ship.energy = rng.randi_range(0, 800) / 8.0
	ship.fuel = rng.randi_range(0, 800) / 8.0
	ship.alert = ["verde", "amarilla", "roja"][index % 3]
	for quadrant in ShipModel.QUADRANTS:
		ship.shield_quadrants[quadrant] = ShipModel.quadrant_capacity(ship, quadrant) * rng.randi_range(0, 16) / 16.0
	ShipModel.sync_shield(ship)
	for system in ship.systems.values():
		system.heat = rng.randi_range(0, 960) / 8.0
		system.health = rng.randi_range(0, 800) / 8.0
	for ammo in state.operations.ammo:
		state.operations.ammo[ammo] = rng.randi_range(0, int(ship.design.ammo[ammo]))
	ship.torpedoes = state.operations.ammo.homing
	state.sequence = index + 1
	state.events = [{"seq": state.sequence, "time": state.time, "source": "Prueba sintética", "text": "Itsaso · navegación, reparación y decisión ñ %d" % index}]
	return state

func json_copy(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func write_text(path: String, text: String) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "open synthetic fixture")
		return false
	file.store_string(text)
	file.flush()
	var error = file.get_error()
	file.close()
	check(error == OK, "write synthetic fixture")
	return error == OK

func envelope(state: Dictionary) -> String:
	var payload = JSON.stringify(state, "", true, true)
	return JSON.stringify({"format": "lagunak-save", "version": 1, "sha256": payload.sha256_text(), "payload": payload})

func round_trip(state: Dictionary, path: String) -> Dictionary:
	var before = var_to_bytes(state)
	var error = LocalStorage.validate_state(state)
	check(error.is_empty(), "generated state validates: " + error)
	check(var_to_bytes(state) == before, "validation does not mutate input")
	if not error.is_empty():
		return {}
	error = LocalStorage.save_state(state, path)
	check(error.is_empty(), "save succeeds: " + error)
	check(var_to_bytes(state) == before, "saving does not mutate input")
	if not error.is_empty():
		return {}
	var loaded = LocalStorage.read_state(path)
	check(loaded.has("state"), "read succeeds: " + str(loaded.get("error", "")))
	if not loaded.has("state"):
		return {}
	check(LocalStorage.validate_state(loaded.state).is_empty(), "restored state validates")
	return loaded.state

func test_round_trip(state: Dictionary) -> void:
	var restored = round_trip(state, directory + "/round-trip.json")
	if restored.is_empty():
		return
	check(restored == json_copy(state), "all durable fields survive JSON round-trip")
	var again = round_trip(restored, directory + "/round-trip-again.json")
	check(again == restored, "second save/load is idempotent")

func test_two_segment_migration(state: Dictionary) -> void:
	var legacy = state.duplicate(true)
	legacy.ship.erase("shield_quadrants")
	var before = var_to_bytes(legacy)
	var restored = round_trip(legacy, directory + "/segments.json")
	check(var_to_bytes(legacy) == before, "two-segment fixture stays legacy in memory")
	if restored.is_empty():
		return
	for quadrant in ShipModel.QUADRANTS:
		var segment = "front" if quadrant.begins_with("front") else "rear"
		check(is_equal_approx(float(restored.ship.shield_quadrants[quadrant]), float(legacy.ship.shield_segments[segment]) / 2.0), "migration splits " + quadrant)
	var without_quadrants = restored.duplicate(true)
	without_quadrants.ship.erase("shield_quadrants")
	check(without_quadrants == json_copy(legacy), "two-segment migration changes no unrelated data")
	var again = round_trip(restored, directory + "/segments-again.json")
	check(again == restored, "two-segment migration is idempotent")

func test_four_system_migration(state: Dictionary) -> void:
	var legacy = state.duplicate(true)
	for field in ["design", "shield_segments", "shield_quadrants", "target_heading", "drift", "gate_cooldown"]:
		legacy.ship.erase(field)
	for system in legacy.ship.systems.keys():
		if system not in ShipModel.LEGACY_SYSTEMS:
			legacy.ship.systems.erase(system)
	legacy.erase("operations")
	legacy.erase("cooperation")
	var restored = round_trip(legacy, directory + "/four-systems.json")
	if restored.is_empty():
		return
	check(restored.ship.systems.size() == Catalog.SYSTEMS.size(), "legacy ship gains the native systems")
	for system in ShipModel.LEGACY_SYSTEMS:
		check(restored.ship.systems[system] == json_copy(legacy.ship.systems[system]), "legacy system preserved: " + system)
	check(is_equal_approx(float(restored.ship.shield), float(legacy.ship.shield)), "legacy shield percentage preserved")
	for field in ["mission", "campaign", "facts", "events", "contacts"]:
		check(restored[field] == json_copy(legacy[field]), "legacy migration preserves " + field)
	check(restored.operations.coolant.size() == Catalog.SYSTEMS.size(), "migration initializes all coolant channels")
	var again = round_trip(restored, directory + "/four-systems-again.json")
	# Migration inserts native int defaults; JSON represents all numbers as floats.
	check(json_copy(again) == json_copy(restored), "four-system migration is idempotent")

func reject_without_mutation(state: Dictionary, label: String, check_disk: bool = true) -> void:
	var before = var_to_bytes(state)
	check(not LocalStorage.validate_state(state).is_empty(), label + " rejected")
	check(var_to_bytes(state) == before, label + " validation is read-only")
	if check_disk:
		var path = directory + "/invalid-envelope.json"
		# Recomputed hashes must not bypass semantic validation.
		if write_text(path, envelope(state)):
			check(LocalStorage.read_state(path).has("error"), label + " rejected with valid checksum")

func test_invalid_quadrants() -> void:
	for quadrant in ShipModel.QUADRANTS:
		var over = fresh()
		over.ship.shield_quadrants[quadrant] = ShipModel.quadrant_capacity(over.ship, quadrant) + 1.0
		reject_without_mutation(over, "overcharged " + quadrant)
		var negative = fresh()
		negative.ship.shield_quadrants[quadrant] = -1.0
		reject_without_mutation(negative, "negative " + quadrant)
		var text = fresh()
		text.ship.shield_quadrants[quadrant] = str(text.ship.shield_quadrants[quadrant])
		reject_without_mutation(text, "string " + quadrant)
		var missing = fresh()
		missing.ship.shield_quadrants.erase(quadrant)
		reject_without_mutation(missing, "partial dictionary " + quadrant)
		for nonfinite in [NAN, INF, -INF]:
			var invalid = fresh()
			invalid.ship.shield_quadrants[quadrant] = nonfinite
			reject_without_mutation(invalid, "nonfinite " + quadrant, false)
	for wrong_type in [null, [], true, "legacy", 7, {}]:
		var invalid = fresh()
		invalid.ship.shield_quadrants = wrong_type
		reject_without_mutation(invalid, "invalid quadrant container")

func test_invalid_structure() -> void:
	var invalid = fresh()
	invalid.erase("campaign")
	reject_without_mutation(invalid, "missing campaign")
	invalid = fresh()
	invalid.version = 2
	reject_without_mutation(invalid, "unknown state version")
	invalid = fresh()
	invalid.objective = 0.5
	reject_without_mutation(invalid, "fractional objective")
	invalid = fresh()
	invalid.ship.autopilot = "absent-contact"
	reject_without_mutation(invalid, "dangling contact reference")
	invalid = fresh()
	invalid.contacts[1].id = invalid.contacts[0].id
	reject_without_mutation(invalid, "duplicate contact identity")
	invalid = fresh()
	invalid.campaign.credits = -1
	reject_without_mutation(invalid, "negative credits")
	invalid = fresh()
	invalid.campaign.completed = "not-an-array"
	reject_without_mutation(invalid, "invalid progress container")
	invalid = fresh()
	invalid.ship.systems.armas.health = "100"
	reject_without_mutation(invalid, "string system health")
	invalid = fresh()
	invalid.ship.shield_segments.front = 0
	reject_without_mutation(invalid, "incoherent aggregate shield")
	invalid = fresh()
	invalid.contacts[0].position = [0]
	reject_without_mutation(invalid, "incomplete contact position")
	invalid = fresh()
	invalid.events = [{"source": 42, "text": "synthetic", "seq": 1, "time": 0}]
	reject_without_mutation(invalid, "invalid event source")

func test_json_limits() -> void:
	check(LocalStorage.validate_json("x".repeat(8000), 0), "string at limit accepted")
	check(not LocalStorage.validate_json("x".repeat(8001), 0), "oversized string rejected")
	var items: Array = []
	items.resize(600)
	check(LocalStorage.validate_json(items, 0), "array at limit accepted")
	items.append(null)
	check(not LocalStorage.validate_json(items, 0), "oversized array rejected")
	var mapping = {}
	for i in 600:
		mapping[str(i)] = i
	check(LocalStorage.validate_json(mapping, 0), "dictionary at limit accepted")
	mapping["overflow"] = 601
	check(not LocalStorage.validate_json(mapping, 0), "oversized dictionary rejected")
	check(LocalStorage.validate_json({"x".repeat(128): true}, 0), "key at limit accepted")
	check(not LocalStorage.validate_json({"x".repeat(129): true}, 0), "oversized key rejected")
	var nested: Variant = 0
	for i in 18:
		nested = [nested]
	check(LocalStorage.validate_json(nested, 0), "depth at limit accepted")
	check(not LocalStorage.validate_json([nested], 0), "excessive depth rejected")
	for number in [NAN, INF, -INF]:
		check(not LocalStorage.validate_json(number, 0), "nonfinite JSON number rejected")

func test_numeric_contract() -> void:
	check(json_copy({"n": 2}) == json_copy({"n": 2.0}), "JSON numeric representations are equivalent")
	check(json_copy({"n": 2}) != json_copy({"n": "2"}), "numeric string never equals JSON number")
	check(json_copy({"n": 2}) != json_copy({"n": 2.125}), "changed numeric value never compares equal")
	check(json_copy({"n": 2}) != json_copy({"n": true}), "boolean never equals JSON number")

func test_envelope_integrity() -> void:
	var path = directory + "/integrity.json"
	var valid = envelope(fresh())
	for text in ["{", "[]", "null", "", "{}", "x".repeat(LocalStorage.MAX_BYTES + 1)]:
		if write_text(path, text):
			check(LocalStorage.read_state(path).has("error"), "broken or oversized envelope rejected")
	for field in ["format", "version", "sha256", "payload"]:
		var broken: Dictionary = JSON.parse_string(valid)
		broken.erase(field)
		if write_text(path, JSON.stringify(broken)):
			check(LocalStorage.read_state(path).has("error"), "missing envelope " + field + " rejected")
	var future: Dictionary = JSON.parse_string(valid)
	future.version = 999
	if write_text(path, JSON.stringify(future)):
		check(LocalStorage.read_state(path).has("error"), "future envelope rejected")
	var tampered: Dictionary = JSON.parse_string(valid)
	var payload: Dictionary = JSON.parse_string(tampered.payload)
	payload.campaign.credits += 1
	tampered.payload = JSON.stringify(payload, "", true, true)
	if write_text(path, JSON.stringify(tampered)):
		check(LocalStorage.read_state(path).has("error"), "changed payload with stale hash rejected")
	for text in ["{", "[", "", "not-json", "null", "[]"]:
		var broken: Dictionary = JSON.parse_string(valid)
		broken.payload = text
		broken.sha256 = text.sha256_text()
		if write_text(path, JSON.stringify(broken)):
			check(LocalStorage.read_state(path).has("error"), "invalid payload with valid hash rejected")
	check(LocalStorage.read_state(directory + "/absent.json").has("error"), "missing save returns error")

func test_backup_and_transients() -> void:
	var path = directory + "/backup.json"
	var first = fresh()
	check(LocalStorage.save_state(first, path).is_empty(), "initial backup fixture saved")
	var first_bytes = FileAccess.get_file_as_string(path)
	var second = fresh()
	second.campaign.credits = 42
	check(LocalStorage.save_state(second, path).is_empty(), "second backup fixture saved")
	var second_bytes = FileAccess.get_file_as_string(path)
	check(FileAccess.get_file_as_string(path + ".bak") == first_bytes, "backup equals previous valid save")
	var invalid = second.duplicate(true)
	invalid.ship.shield_quadrants.front_left = 9999
	var before = var_to_bytes(invalid)
	check(not LocalStorage.save_state(invalid, path).is_empty(), "invalid save rejected before write")
	check(var_to_bytes(invalid) == before, "rejected save does not modify caller")
	check(FileAccess.get_file_as_string(path) == second_bytes, "invalid save does not replace primary")
	check(FileAccess.get_file_as_string(path + ".bak") == first_bytes, "invalid save does not replace backup")
	write_text(path, "{corrupt")
	var backup = LocalStorage.read_state(path + ".bak")
	check(backup.has("state"), "backup can be explicitly recovered after primary corruption")
	if backup.has("state"):
		check(backup.state == json_copy(first), "recovered backup keeps original progress")
	check(LocalStorage.save_state(second, path).is_empty(), "valid save replaces corrupt primary")
	check(FileAccess.get_file_as_string(path + ".bak") == first_bytes, "corrupt primary never replaces healthy backup")
	check(not FileAccess.file_exists(path + ".tmp"), "successful save leaves no temporary file")
	check(not LocalStorage.save_state(first, directory + "/missing-parent/save.json").is_empty(), "write failure reported")
	var transient = fresh()
	transient.cooperation = {"next_id": 123, "tasks": {"synthetic": {"pending": true}}, "tokens": {"synthetic": {"bonus": 1}}, "cooldowns": {"synthetic": 10.0}}
	var restored = round_trip(transient, directory + "/transient.json")
	if not restored.is_empty():
		check(restored.cooperation == json_copy({"next_id": 123, "tasks": {}, "tokens": {}, "cooldowns": {}}), "restore cancels transient assistance but preserves next_id")
		var expected = json_copy(transient)
		expected.cooperation = restored.cooperation.duplicate(true)
		check(restored == expected, "cancelling assistance changes no durable fields")

func test_reachable_state() -> void:
	var sim = Simulation.new()
	sim.start(missions[0])
	check(sim.command("navegacion", "helm", {"heading": 135, "throttle": 0.5}).ok, "real helm command accepted")
	check(sim.command("armas", "tube_load", {"tube": 0, "ammo": "homing"}).ok, "real loading command accepted")
	for i in 30:
		sim.tick(1.0 / 30.0)
	check(sim.state.operations.tubes[0].remaining > 0, "save fixture contains in-flight loading")
	test_round_trip(sim.state)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			seed_value = int(argument.get_slice("=", 1))
		elif argument.begins_with("--samples="):
			samples = int(argument.get_slice("=", 1))
	if samples < 1 or samples > 512 or seed_value < 0 or seed_value > 2147483647:
		push_error("STORAGE_PROPERTY_FAIL invalid test arguments")
		quit(2)
		return
	directory = "user://storage-properties-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		push_error("STORAGE_PROPERTY_FAIL cannot create isolated fixtures")
		quit(2)
		return
	missions = Catalog.missions()
	check(not missions.is_empty(), "native mission catalogue available")
	if not missions.is_empty():
		for i in samples:
			sample_index = i
			var state = generated(i)
			test_round_trip(state)
			test_two_segment_migration(state)
			test_four_system_migration(state)
		sample_index = -1
		test_invalid_quadrants()
		test_invalid_structure()
		test_json_limits()
		test_numeric_contract()
		test_envelope_integrity()
		test_backup_and_transients()
		test_reachable_state()
	for file in DirAccess.get_files_at(directory):
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(file))) == OK, "remove synthetic fixture")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(directory)) == OK, "remove fixture directory")
	print("STORAGE_PROPERTY_TESTS %d checks; %d failures; seed=%d; samples=%d" % [checks, failures, seed_value, samples])
	quit(1 if failures else 0)
