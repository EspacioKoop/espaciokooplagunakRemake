extends SceneTree

var checks = 0
var failures = 0
var fixtures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error("SHIP_CONFIGURATION_DIFF_FAIL " + label)

func equivalent(a: Variant, b: Variant) -> bool:
 return JSON.parse_string(JSON.stringify(a, "", true, true)) == JSON.parse_string(JSON.stringify(b, "", true, true))

func encoded(design: Dictionary) -> String:
 var result = LoadoutDocument.encode(design, LoadoutDocument.default_loadout())
 check(result.has("text"), "fixture encodes with production document boundary")
 return result.get("text", "")

func fixture(text: String) -> String:
 var path = "user://structure-diff-test-%s-%s.json" % [Time.get_ticks_usec(), fixtures.size()]
 var file = FileAccess.open(path, FileAccess.WRITE)
 check(file != null, "local fixture opens")
 if file != null:
  file.store_string(text)
  file.close()
  fixtures.append(path)
 return path

func run() -> void:
 for child in root.get_children(): child.set_process(false)
 var session = root.get_node("Session")
 session.paused = true
 test_changes()
 test_documents()
 test_files()
 await test_ui()
 for path in fixtures:
  check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "fixture cleaned")
 print("SHIP_CONFIGURATION_DIFF_TESTS %d checks; %d failures" % [checks, failures])
 quit(1 if failures else 0)

func test_changes() -> void:
 var current = ShipModel.standard_design()
 var saved = current.duplicate(true)
 var result = ShipConfigurationDiff.compare_designs(current, current)
 check(result.changes.is_empty(), "identical structure has no changes")
 check(result.fields_compared == 2 + ShipModel.DESIGN_LIMITS.size() + ShipOperations.AMMO.size(), "all structural fields covered")
 var json_copy = JSON.parse_string(JSON.stringify(current, "", true, true))
 check(ShipConfigurationDiff.compare_designs(current, json_copy).changes.is_empty(), "JSON float/int equivalence")
 for key in ["id", "name"]:
  var candidate = current.duplicate(true)
  candidate[key] = "Nueva identidad"
  result = ShipConfigurationDiff.compare_designs(current, candidate)
  check(result.changes.size() == 1 and result.changes[0].path == key, "identity change: " + key)
  check(not result.changes[0].has("difference"), "text is not a numeric delta")
 for key in ShipModel.DESIGN_LIMITS:
  var candidate = current.duplicate(true)
  candidate[key] = ShipModel.DESIGN_LIMITS[key][0]
  if float(candidate[key]) == float(current[key]): candidate[key] = ShipModel.DESIGN_LIMITS[key][1]
  var candidate_before = candidate.duplicate(true)
  result = ShipConfigurationDiff.compare_designs(current, candidate)
  check(result.changes.size() == 1 and result.changes[0].path == key, "capability change: " + key)
  check(result.changes[0].difference == float(candidate[key]) - float(current[key]), "signed delta: " + key)
  check(candidate == candidate_before and current == saved, "no mutation: " + key)
 for ammo in ShipOperations.AMMO:
  var candidate = current.duplicate(true)
  candidate.ammo[ammo] += 1
  result = ShipConfigurationDiff.compare_designs(current, candidate)
  check(result.changes.size() == 1 and result.changes[0].path == "ammo." + ammo and result.changes[0].difference == 1, "ammo change: " + ammo)
 var precise = current.duplicate(true)
 precise.beam_cycle += 0.0000000001
 result = ShipConfigurationDiff.compare_designs(current, precise)
 check(result.changes.size() == 1 and result.changes[0].difference > 0, "tiny authored edit is not hidden by approximate equality")
 var extra = current.duplicate(true)
 extra.secret_test_only = {"ticket": "SYNTHETIC_NOT_FOR_REPORT"}
 extra.ammo.unknown = "SYNTHETIC_NOT_FOR_REPORT"
 result = ShipConfigurationDiff.compare_designs(current, extra)
 check(result.changes.is_empty(), "unknown fields not treated as structural capabilities")
 check(not JSON.stringify(result).contains("SYNTHETIC_NOT_FOR_REPORT"), "extra data absent from report model")
 check(ShipConfigurationDiff.to_text(result).contains("campos externos quedan fuera"), "equal structure never claims equal whole document")
 var compound = current.duplicate(true)
 compound.name = "Otra nave"
 compound.hull = 200
 compound.ammo.emp = 10
 var reversed: Dictionary = {}
 var keys: Array = compound.keys()
 keys.reverse()
 for key in keys: reversed[key] = compound[key]
 check(ShipConfigurationDiff.compare_designs(current, compound) == ShipConfigurationDiff.compare_designs(current, reversed), "deterministic order independent of document key order")
 result = ShipConfigurationDiff.compare_designs(current, compound)
 check(result.changes[0].path == "name" and result.changes[1].path == "hull" and result.changes[2].path == "ammo.emp", "stable identity/capabilities/ammo ordering")
 compound.name = "Nave\n[b]texto[/b]\t"
 var rendered = ShipConfigurationDiff.to_text(ShipConfigurationDiff.compare_designs(current, compound))
 check(rendered.contains("Nave\\n[b]texto[/b]\\t") and not rendered.contains("Nave\n[b]"), "control characters escaped in plain text")
 for invalid in [null, [], {}, "design"]:
  check(ShipConfigurationDiff.compare_designs(invalid, current).has("error"), "invalid baseline rejected")
  check(ShipConfigurationDiff.compare_designs(current, invalid).has("error"), "invalid candidate rejected")
 for invalid in [null, "100", true, -1, 10001, INF, NAN]:
  var candidate = current.duplicate(true)
  candidate.hull = invalid
  check(ShipConfigurationDiff.compare_designs(current, candidate).has("error"), "invalid hull rejected by existing validator")
  if not (invalid is float and is_nan(invalid)):
   check(candidate.hull == invalid, "invalid input not repaired or modified")
 var bad_ammo = current.duplicate(true)
 bad_ammo.ammo.emp = 1.5
 check(ShipConfigurationDiff.compare_designs(current, bad_ammo).has("error"), "fractional ammo rejected")
 check(current == saved, "all pure comparisons preserve current design")
 var entries = ShipTemplateCatalog.entries()
 check(not entries.is_empty(), "production template catalog available")
 for entry in entries:
  var configuration = ShipTemplateCatalog.configuration(entry.id)
  result = ShipConfigurationDiff.compare_designs(current, configuration.design)
  check(not result.has("error"), "production template compares: " + entry.id)
  check(result.changes.size() <= result.fields_compared, "bounded report: " + entry.id)

func test_documents() -> void:
 var current = ShipModel.standard_design()
 var text = encoded(current)
 var result = ShipConfigurationDiff.compare_document(current, text)
 check(result.changes.is_empty() and not result.legacy, "native v2 document compares")
 var legacy = JSON.stringify({"format": LoadoutDocument.FORMAT, "version": 1, "design": current}, "", true, true)
 result = ShipConfigurationDiff.compare_document(current, legacy)
 check(result.changes.is_empty() and result.legacy, "legacy v1 structural document compares")
 check(ShipConfigurationDiff.to_text(result).contains("v1 (heredado)"), "legacy status visible")
 var different_mounts = LoadoutDocument.default_loadout()
 different_mounts.mounts[0].damage = 0
 result = ShipConfigurationDiff.compare_document(current, LoadoutDocument.encode(current, different_mounts).text)
 check(result.changes.is_empty(), "mount comparison deliberately outside structural scope")
 for invalid in ["", "{bad", "[]", "null", " ".repeat(LoadoutDocument.MAX_BYTES + 1)]:
  check(ShipConfigurationDiff.compare_document(current, invalid).has("error"), "malformed or oversized document rejected")
 for version in [0, 3, 2.5, true, "2"]:
  var document = JSON.parse_string(text)
  document.version = version
  check(ShipConfigurationDiff.compare_document(current, JSON.stringify(document)).has("error"), "unsupported version rejected")
 var document = JSON.parse_string(text)
 document.loadout.mounts = []
 check(ShipConfigurationDiff.compare_document(current, JSON.stringify(document)).has("error"), "invalid v2 loadout still invalidates the whole importable document")
 check(ShipConfigurationDiff.compare_document({}, text).has("error"), "invalid current draft rejected before comparison")
 document = JSON.parse_string(text)
 document.design.notes = "SYNTHETIC_NOT_FOR_REPORT"
 result = ShipConfigurationDiff.compare_document(current, JSON.stringify(document))
 check(not ShipConfigurationDiff.to_text(result).contains("SYNTHETIC_NOT_FOR_REPORT"), "unrelated document fields not rendered")

func test_files() -> void:
 var current = ShipModel.standard_design()
 var text = encoded(current)
 var path = fixture(text)
 check(ShipConfigurationDiff.compare_file(current, path).changes.is_empty(), "real local file compares")
 check(FileAccess.get_file_as_string(path) == text, "comparison never rewrites source file")
 check(ShipConfigurationDiff.compare_file(current, path + ".missing").has("error"), "missing file controlled")
 check(ShipConfigurationDiff.compare_file(current, "https://invalid.example/design.json").has("error"), "remote URL refused before opening")
 check(ShipConfigurationDiff.compare_file(current, fixture(" ".repeat(LoadoutDocument.MAX_BYTES + 1))).has("error"), "oversized local file rejected")
 check(ShipConfigurationDiff.compare_file(current, fixture("{broken")).has("error"), "corrupt local file rejected")

func settle() -> void:
 for i in 4: await process_frame

func comparison_window(editor: ShipDesignEditor) -> ShipComparisonDialog:
 for child in editor.get_children():
  if child is ShipComparisonDialog: return child
 return null

func press_comparison(editor: ShipDesignEditor) -> void:
 for node in editor.find_children("*", "Button", true, false):
  if node.text == "Comparar estructura":
   node.pressed.emit()
   return
 check(false, "native comparison access exists")

func test_ui() -> void:
 root.size = Vector2i(1600, 900)
 var session = root.get_node("Session")
 var state_before = session.sim.state.duplicate(true)
 var editor = ShipDesignEditor.new()
 root.add_child(editor)
 editor.popup_centered()
 await settle()
 var emissions = {"design": 0, "configuration": 0}
 editor.design_changed.connect(func(_value): emissions.design += 1)
 editor.configuration_changed.connect(func(_design, _loadout): emissions.configuration += 1)
 editor.fields.hull.get_line_edit().text = "123"
 editor.fields.hull.get_line_edit().text_changed.emit("123")
 press_comparison(editor)
 await settle()
 var panel = comparison_window(editor)
 check(panel != null, "button opens usable comparison window")
 if panel == null:
  editor.queue_free()
  await settle()
  return
 check(panel.source_design.hull == 123, "pending numeric draft included in comparison baseline")
 check(not panel.report.editable, "report read-only plain text")
 var baseline = editor.read_design().duplicate(true)
 var mounts_before = editor.loadout_editor.read_loadout().duplicate(true)
 var candidate = baseline.duplicate(true)
 candidate.hull = 234
 candidate.ammo.emp += 2
 var text = encoded(candidate)
 var path = fixture(text)
 panel.file_dialog.file_selected.emit(path)
 check(panel.report.text.contains("[hull]") and panel.report.text.contains("[ammo.emp]"), "file picker signal renders structural changes")
 check(panel.status.text.contains("2 diferencias"), "change count visible")
 check(equivalent(editor.read_design(), baseline), "comparison never applies candidate structure")
 check(equivalent(editor.loadout_editor.read_loadout(), mounts_before), "comparison never changes mounts")
 check(FileAccess.get_file_as_string(path) == text, "UI comparison never writes selected file")
 panel.file_dialog.file_selected.emit(path + ".missing")
 check(panel.report.text.begins_with("No se puede comparar.") and not panel.report.text.contains("[hull]"), "failed comparison clears stale successful results")
 panel.file_dialog.file_selected.emit(path)
 check(panel.status.text.contains("2 diferencias"), "valid comparison recovers after file failure")
 panel.close_requested.emit()
 await settle()
 check(comparison_window(editor) == null, "close removes comparison window")
 editor.fields.hull.value = 321
 press_comparison(editor)
 await settle()
 panel = comparison_window(editor)
 check(panel != null and panel.source_design.hull == 321, "reopen uses fresh draft rather than stale snapshot")
 if panel != null: panel.queue_free()
 await settle()
 editor.fields.name.text = ""
 press_comparison(editor)
 await settle()
 check(comparison_window(editor) == null and not editor.status.text.is_empty(), "invalid draft rejected without opening window")
 check(emissions.design == 0 and emissions.configuration == 0, "comparison emits no apply signals")
 check(session.sim.state == state_before, "live simulation unchanged by UI comparisons")
 editor.queue_free()
 await settle()
