extends SceneTree
var checks = 0
var failures = 0
var session: Node
var sensors: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SENSORS_FAIL " + label)

func solve() -> bool:
	var task: Dictionary = sensors.operator().task.duplicate(true)
	if task.is_empty(): return false
	for pulse in task.pattern:
		var response = sensors.command("input", {"value": int(pulse)})
		if not response.ok: return false
	return true

func add_contact(id: String, kind: String, position: Array, known: bool = false, probed: bool = false) -> Dictionary:
	var contact = {"id": id, "name": id.capitalize(), "kind": kind, "position": position, "identified": known, "jammed": false, "known": known, "hull": 100.0, "hailed": false, "negotiated": false, "rescued": false, "salvaged": false, "probed": probed, "pacified": false, "attack_at": 0.0, "survivors": 4, "frequency": 7}
	session.sim.state.contacts.append(contact)
	return contact

func run() -> void:
	session = root.get_node("Session")
	sensors = root.get_node("Sensors")
	sensors.state = {"operators": {}, "levels": {}, "hacks": {}}
	session.new_campaign()
	session.role = "sensores"
	var target = add_contact("sensor_test", "anomaly", [700.0, 0.0])
	check(sensors.command("band", {"band": "long"}).ok, "sensor operator selects long range band")
	check(sensors.command("analysis_begin", {"target": target.id}).ok, "long range starts first analysis")
	check(solve() and sensors.analysis_level(target.id) == 1, "first puzzle reveals signal signature")
	check(sensors.command("analysis_begin", {"target": target.id}).ok, "long range starts classification analysis")
	check(solve() and sensors.analysis_level(target.id) == 2, "second puzzle reaches classification level")
	check(not sensors.command("analysis_begin", {"target": target.id}).ok, "long range cannot reveal final identity")
	check(sensors.command("band", {"band": "short"}).ok, "operator switches to short range")
	check(sensors.command("analysis_begin", {"target": target.id}).ok and solve(), "short range completes final identity puzzle")
	check(target.identified and sensors.analysis_level(target.id) == 3, "final analysis changes authoritative contact identity")
	check(session.sim.state.facts.has("scan:" + target.id), "advanced identity satisfies normal scan objectives")
	var far_target = add_contact("far_target", "beacon", [3200.0, 0.0])
	var probe = add_contact("relay_probe", "beacon", [2500.0, 0.0], true, true)
	check(not sensors.command("analysis_begin", {"target": far_target.id}).ok, "short range cannot reach distant contact from ship")
	check(sensors.command("probe_origin", {"target": probe.id}).ok, "operator links a deployed probe as remote origin")
	check(sensors.command("analysis_begin", {"target": far_target.id}).ok, "same short range reaches target from remote probe")
	check(solve() and sensors.analysis_level(far_target.id) == 1, "probe-origin analysis resolves normally")
	check(sensors.command("probe_clear", {}).ok and sensors.operator().origin.is_empty(), "sensor origin returns to ship")
	var hostile = add_contact("hack_target", "hostile", [600.0, 150.0], true)
	check(sensors.command("hack_begin", {"target": hostile.id}).ok, "short range starts hack against identified hostile")
	var before = session.sim.state.time
	check(solve(), "host validates complete hacking sequence")
	check(hostile.attack_at >= before + 22.0 and sensors.state.hacks.has(hostile.id), "successful hack inhibits hostile attack window")
	check(not hostile.jammed and sensors.state.hacks[hostile.id].frequency == 7, "hack exposes frequency and clears sensor jamming")
	check(sensors.command("band", {"band": "long"}).ok, "operator restores long range for distant cancellation target")
	check(sensors.command("analysis_begin", {"target": far_target.id}).ok, "analysis can be started for cancellation test within selected range")
	check(sensors.command("cancel", {}).ok and sensors.operator().task.is_empty(), "active sensor puzzle can be cancelled")
	session.role = "mando"
	check(not sensors.command("band", {"band": "long"}).ok, "another station cannot operate advanced sensors")
	print("ADVANCED_SENSOR_TESTS ", checks, " checks; ", failures, " failures")
	quit(1 if failures else 0)
