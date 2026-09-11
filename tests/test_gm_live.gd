extends SceneTree
## Synthetic states: no player saves, keys or external services.
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("GM_LIVE_FAIL " + label)

func fresh() -> Simulation:
	var sim = Simulation.new()
	sim.start(Catalog.missions()[0])
	return sim

func contact_args() -> Dictionary:
	return {"id": "gm_contact", "name": "Synthetic contact", "kind": "hostile", "x": 1000.0, "y": 200.0, "identified": true}

func run() -> void:
	var sim = fresh()
	check(LocalStorage.validate_state(sim.state).is_empty(), "baseline save is valid")
	check(GMLiveActions.spawn_contact(sim, contact_args()).ok, "spawn succeeds")
	check(LocalStorage.validate_state(sim.state).is_empty(), "spawn preserves save validity")
	var before = var_to_bytes(sim.state)
	check(not GMLiveActions.modify_contact(sim, "gm_contact", {"name": "MUST_NOT_COMMIT", "x": INF}).ok, "invalid position is rejected")
	check(var_to_bytes(sim.state) == before, "failed multi-field modification is atomic")
	for field in ["hull", "frequency", "survivors", "identified", "jammed", "pacified"]:
		for invalid in [null, "7", [], {}, INF]:
			var candidate = contact_args()
			candidate[field] = invalid
			var other = fresh()
			var original = var_to_bytes(other.state)
			check(not GMLiveActions.spawn_contact(other, candidate).ok, "invalid spawn type rejected: " + field)
			check(var_to_bytes(other.state) == original, "failed spawn does not mutate: " + field)
	for field in ["x", "y"]:
		var candidate = contact_args()
		candidate[field] = 14001
		var other = fresh()
		check(not GMLiveActions.spawn_contact(other, candidate).ok, "coordinates obey persistence limits")
	for count in [0, -1, 1.5, "3", true, 13]:
		var other = fresh()
		var original = var_to_bytes(other.state)
		check(not GMLiveActions.trigger_event(other, "reinforcements", {"count": count}).ok, "invalid reinforcement count rejected")
		check(var_to_bytes(other.state) == original, "invalid reinforcement batch is atomic")
	var other = fresh()
	check(GMLiveActions.trigger_event(other, "alert", {"level": "ambar"}).ok, "canonical amber alert accepted")
	check(other.state.ship.alert == "ambar", "canonical alert stored")
	var hidden = fresh()
	var secret = contact_args()
	secret.name = "SYNTHETIC_HIDDEN_CONTACT"
	secret.identified = false
	check(GMLiveActions.spawn_contact(hidden, secret).ok, "hidden contact can be authored")
	check(not JSON.stringify(hidden.snapshot("navegacion", "test")).contains(secret.name), "public event log does not reveal hidden contact")

	_extended()
	print("GM_LIVE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _extended() -> void:
	var sim = fresh()
	var source = var_to_bytes(sim.state.mission)
	var args = contact_args()
	args.visual_model = "frontier/haizea_scout"
	args.jammed = true
	args.pacified = true
	var response = GMLiveActions.spawn_contact(sim, args)
	check(response.ok, "spawn curated visual: " + response.message)
	if not response.ok: return
	check(sim.contact("gm_contact").visual_model == args.visual_model, "model selected by stable ID")
	check(sim.contact("gm_contact").jammed and sim.contact("gm_contact").pacified, "initial authoring flags survive creation")
	check(var_to_bytes(sim.state.mission) == source, "source mission is immutable")
	var before = var_to_bytes(sim.state)
	check(not GMLiveActions.modify_contact(sim, "gm_contact", {"visual_model": "user://private.glb"}).ok, "arbitrary paths rejected")
	check(var_to_bytes(sim.state) == before, "rejected visual edit is atomic")
	check(not GMLiveActions.modify_contact(sim, "gm_contact", {"visual_model": "fieldkit/soros_medkit"}).ok, "incompatible visual rejected")
	var path = "user://synthetic-gm-save.json"
	check(LocalStorage.save_state(sim.state, path).is_empty(), "live contact saves")
	var restored = LocalStorage.read_state(path)
	check(restored.has("state"), "live contact restores")
	if restored.has("state"):
		check(restored.state.gm_live == JSON.parse_string(JSON.stringify(sim.state.gm_live)), "membership and private audit preserved")
		check(restored.state.contacts == JSON.parse_string(JSON.stringify(sim.state.contacts)), "full contact and model round trip")
		var again = Simulation.new()
		again.state = restored.state
		check(LocalStorage.validate_state(again.state).is_empty(), "restored save validates")
		check(GMLiveActions.modify_contact(again, "gm_contact", {"name": "Restored"}).ok, "restored contacts remain editable")
	for role in Catalog.ROLES:
		var safe = sim.snapshot(role, "test")
		check(not safe.has("gm_live"), "no private GM record in station snapshot")
		check(not safe.mission.has("contacts"), "source catalogue remains private")
		for operation in ["spawn", "modify", "remove", "gm_spawn", "damage", "reinforcements"]:
			check(not sim.command(role, operation, {}).ok, "station command cannot acquire GM authority")
	var required: String = sim.state.mission.objectives[0].target
	before = var_to_bytes(sim.state)
	check(not GMLiveActions.remove_contact(sim, required).ok, "objective contact cannot be removed")
	check(not GMLiveActions.modify_contact(sim, required, {"kind": "hostile"}).ok, "objective kind cannot change")
	check(var_to_bytes(sim.state) == before, "protected target remains unchanged")
	# Original non-goal removal is an explicit tombstone, not a modified mission.
	var custom = Catalog.missions()[0].duplicate(true)
	custom.contacts.append({"id": "extra", "name": "Extra", "kind": "friendly", "position": [1000, 1000]})
	var editable = Simulation.new()
	editable.start(custom)
	check(GMLiveActions.remove_contact(editable, "extra").ok, "non-goal original can be removed")
	check(LocalStorage.validate_state(editable.state).is_empty(), "removed original can be saved")
	check(editable.state.mission.contacts.size() == custom.contacts.size(), "source definition never deleted")
	check(not GMLiveActions.spawn_contact(editable, {"id":"extra", "name":"Again", "kind":"friendly", "x":0, "y":0}).ok, "retired original id cannot be reused")
	# References have a single owner; clear all references stored in Simulation.
	sim.state.ship.autopilot = "gm_contact"
	sim.state.ship.docked = "gm_contact"
	sim.state.ship.loadout = {"mounts": [{"auto_target": "gm_contact"}]}
	sim.state.scan = {"target":"gm_contact", "remaining": 1.0}
	for key in ["docking", "weapon_target", "science_link"]: sim.state.operations[key] = "gm_contact"
	sim.state.operations.comms.target = "gm_contact"
	check(GMLiveActions.remove_contact(sim, "gm_contact").ok, "dynamic contact removed")
	check(sim.state.ship.autopilot.is_empty() and sim.state.ship.docked.is_empty(), "ship references cleared")
	check(sim.state.scan.target.is_empty(), "scan stopped")
	for key in ["docking", "weapon_target", "science_link"]: check(sim.state.operations[key].is_empty(), "operation reference cleared: " + key)
	check(sim.state.operations.comms.target.is_empty() and sim.state.ship.loadout.mounts[0].auto_target.is_empty(), "comms and mounts cleared")
	check(not GMLiveActions.spawn_contact(sim, args).ok, "retired dynamic id cannot be reused")
	for value in [null, [], {}, true, {"version": 2, "added": [], "removed": [], "audit": []}]:
		var broken = fresh().state
		broken.gm_live = value
		check(not GMLiveState.validate(broken).is_empty(), "invalid GM envelope rejected")
	var valid = editable.state.duplicate(true)
	for alteration in ["missing_contact", "duplicate_contact", "undeclared_contact", "duplicate_added", "removed_target", "bad_audit", "bad_visual", "bad_version"]:
		var broken = valid.duplicate(true)
		match alteration:
			"missing_contact": broken.contacts.pop_back()
			"duplicate_contact": broken.contacts.append(broken.contacts[0].duplicate(true))
			"undeclared_contact":
				var added = broken.contacts[0].duplicate(true)
				added.id = "undeclared"
				broken.contacts.append(added)
			"duplicate_added": broken.gm_live.added = ["same", "same"]
			"removed_target": broken.gm_live.removed.append(broken.mission.objectives[0].target)
			"bad_audit": broken.gm_live.audit[0].seq = broken.sequence + 1
			"bad_visual": broken.contacts[0].visual_model = "../bad"
			"bad_version": broken.gm_live.version = true
		var serialized = var_to_bytes(broken)
		check(not GMLiveState.validate(broken).is_empty(), "invalid state rejected: " + alteration)
		check(var_to_bytes(broken) == serialized, "validation is read-only: " + alteration)
	var batch = fresh()
	batch.state.ship.position = [13900.0, 0.0]
	before = var_to_bytes(batch.state)
	check(not GMLiveActions.trigger_event(batch, "reinforcements", {"count":3}).ok, "out-of-sector batch rejected")
	check(var_to_bytes(batch.state) == before, "failed batch commits no contact or log")
	var full = fresh()
	while full.state.contacts.size() < GMLiveState.MAX_CONTACTS:
		var item = contact_args()
		item.id = "gm_fill_%d" % full.state.contacts.size()
		check(GMLiveActions.spawn_contact(full, item).ok, "contact capacity fill")
	before = var_to_bytes(full.state)
	check(not GMLiveActions.trigger_event(full, "reinforcements", {"count":2}).ok, "batch capacity enforced")
	check(var_to_bytes(full.state) == before, "over-capacity batch is atomic")
	check(LocalStorage.validate_state(full.state).is_empty(), "capacity limit is saveable")
	var fatal = fresh()
	check(GMLiveActions.trigger_event(fatal, "damage", {"amount": 1000}).ok, "fatal scene damage supported")
	check(fatal.state.status == "lost" and fatal.state.ship.throttle == 0, "fatal event ends mission immediately")
	check(not GMLiveActions.trigger_event(fatal, "repair", {"amount": 1000}).ok, "finished mission cannot be resurrected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
