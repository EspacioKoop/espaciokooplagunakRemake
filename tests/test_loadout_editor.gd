extends SceneTree

var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error("LOADOUT_EDITOR_FAIL " + label)

func json_equivalent(actual: Variant, expected: Variant) -> bool:
 # JSON numbers parse as float even when the source represented an ammo count as int.
 return JSON.parse_string(JSON.stringify(actual, "", true, true)) == JSON.parse_string(JSON.stringify(expected, "", true, true))

func run() -> void:
 test_documents()
 print("LOADOUT_EDITOR_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)

func test_documents() -> void:
 var design = ShipModel.standard_design()
 var loadout = LoadoutDocument.default_loadout()
 check(LoadoutDocument.validate_loadout(loadout).is_empty(), "default authored loadout validates")
 for id in ShipArmaments.TEMPLATES:
  var source = ShipArmaments.template(id)
  source.mounts[0].ready_at = 45.0
  source.mounts[0].auto_target = "private_target"
  var before = source.duplicate(true)
  var encoded = LoadoutDocument.encode(design, source)
  check(encoded.has("text"), "export template " + id)
  var imported = LoadoutDocument.decode(encoded.text)
  check(json_equivalent(imported.design, design) and json_equivalent(imported.loadout, LoadoutDocument.authored_loadout(source)), "round trip template " + id)
  check(source == before, "export does not mutate runtime " + id)
  check(not encoded.text.contains("private_target") and not encoded.text.contains("ready_at") and not encoded.text.contains("auto_target"), "runtime target and cooldown excluded " + id)
 loadout.mounts[0].cycle = 1.23456789
 loadout.mounts[0].arc_center = -37.123456789
 var precise = LoadoutDocument.decode(LoadoutDocument.encode(design, loadout).text)
 check(absf(precise.loadout.mounts[0].cycle - loadout.mounts[0].cycle) < 1e-10, "cycle precision survives export")
 check(absf(precise.loadout.mounts[0].arc_center - loadout.mounts[0].arc_center) < 1e-10, "orientation precision survives export")
 var legacy = LoadoutDocument.decode(JSON.stringify({"format": "lagunak-ship", "version": 1, "design": design}))
 check(legacy.legacy and json_equivalent(legacy.design, design) and legacy.loadout == LoadoutDocument.default_loadout(), "v1 structural design migrates to existing default mounts")
 check(LoadoutDocument.decode("[]").has("error"), "reject non-object document")
 check(LoadoutDocument.decode("{bad").has("error"), "reject malformed JSON")
 check(LoadoutDocument.decode(" ".repeat(LoadoutDocument.MAX_BYTES + 1)).has("error"), "reject oversized file")
 for version in [0, 3, "2", true, 2.5]:
  check(LoadoutDocument.decode(JSON.stringify({"format": "lagunak-ship", "version": version, "design": design, "loadout": loadout})).has("error"), "reject unsupported version " + str(version))
 check(LoadoutDocument.decode(JSON.stringify({"format": "lagunak-ship", "version": 2, "design": design})).has("error"), "v2 must contain loadout")
 var bad_design = design.duplicate(true)
 bad_design.hull = -1
 check(LoadoutDocument.encode(bad_design, loadout).has("error"), "reject invalid structure on export")
 for field in ["arc_center", "arc", "range", "damage", "cycle", "energy"]:
  for invalid in [null, "10", true, NAN, INF]:
   var broken = loadout.duplicate(true)
   broken.mounts[0][field] = invalid
   check(not LoadoutDocument.validate_loadout(broken).is_empty(), "reject invalid " + field + ": " + str(invalid))
 for entry in [["arc_center", -181], ["arc_center", 181], ["arc", 0], ["arc", 361], ["range", 49], ["range", 3001], ["damage", -1], ["damage", 101], ["cycle", 0.09], ["cycle", 31], ["energy", -1], ["energy", 41], ["id", 7], ["name", 7], ["id", " "], ["name", " "], ["kind", "unknown"]]:
  var broken = loadout.duplicate(true)
  broken.mounts[0][entry[0]] = entry[1]
  check(not LoadoutDocument.validate_loadout(broken).is_empty(), "reject out-of-contract " + str(entry))
 var duplicate = loadout.duplicate(true)
 duplicate.mounts[1].id = duplicate.mounts[0].id
 check(LoadoutDocument.encode(design, duplicate).has("error"), "duplicate hardpoints cannot export")
 for mounts in [[], [null], loadout.mounts + loadout.mounts + loadout.mounts + loadout.mounts + loadout.mounts]:
  check(not LoadoutDocument.validate_loadout({"mounts": mounts}).is_empty(), "reject invalid mount collection")
 var mission = Catalog.missions()[0].duplicate(true)
 check(Catalog.validate_mission(mission).is_empty(), "legacy mission without authored loadout remains valid")
 mission.ship_loadout = loadout.duplicate(true)
 check(Catalog.validate_mission(mission).is_empty(), "valid authored mission accepted")
 mission.ship_loadout = duplicate
 check(not Catalog.validate_mission(mission).is_empty(), "mission boundary rejects invalid loadout")
 var session = root.get_node("Session")
 session.new_campaign()
 session.paused = true
 var before = session.sim.state.duplicate(true)
 check(not session.start_mission(0, mission).ok and session.sim.state == before, "rejected import cannot replace active game")
 mission.ship_loadout = loadout
 session.mode = "client"
 check(not session.start_mission(0, mission).ok and session.sim.state == before, "client cannot install an authored mission on host")
 session.mode = "offline"
