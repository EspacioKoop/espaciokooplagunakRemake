extends SceneTree

var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error("LOADOUT_COMPARISON_FAIL " + label)

func run() -> void:
 test_differences()
 test_documents()
 await test_window()
 print("LOADOUT_COMPARISON_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)

func test_differences() -> void:
 for id in ShipArmaments.TEMPLATES:
  var runtime = ShipArmaments.template(id)
  runtime.mounts[0].auto_target = "PRIVATE_CONTACT"
  runtime.mounts[0].ready_at = 91.0
  var before = runtime.duplicate(true)
  var result = LoadoutComparison.compare(runtime, runtime)
  check(result.equal and result.changes.is_empty(), "self comparison " + id)
  check(runtime == before, "runtime not mutated " + id)
  check(not JSON.stringify(result).contains("PRIVATE_CONTACT"), "runtime target excluded " + id)
 var current = LoadoutDocument.default_loadout()
 var original = current.duplicate(true)
 var values = {"name": "Nuevo haz", "kind": "emp", "arc_center": 17.123456789,
  "arc": 0.00001, "range": 789.123456789, "damage": 13.123456789,
  "cycle": 1.234567891, "energy": 7.123456789}
 for field in values:
  var proposed = current.duplicate(true)
  proposed.mounts[0][field] = values[field]
  var proposal_before = proposed.duplicate(true)
  var result = LoadoutComparison.compare(current, proposed)
  check(result.modified == 1 and result.added == 0 and result.removed == 0, "one modified mount: " + field)
  check(result.changes.size() == 1 and result.changes[0].fields.size() == 1, "only authored field differs: " + field)
  check(result.changes[0].fields[0].field == field and result.changes[0].fields[0].after == values[field], "field and full precision: " + field)
  check(current == original and proposed == proposal_before, "both inputs unchanged: " + field)
  check(LoadoutComparison.compare(current, proposed) == result, "deterministic diff: " + field)
  result.changes[0].fields[0].after = "detached"
  check(current == original and proposed == proposal_before, "returned values detached: " + field)
 var proposed = current.duplicate(true)
 proposed.mounts.reverse()
 var result = LoadoutComparison.compare(current, proposed)
 check(result.reordered and result.modified == 0, "reordering uses stable IDs, not array indices")
 check(result.changes.size() == 1 and result.changes[0].change == "order", "single order record")
 var extra = current.mounts[0].duplicate(true)
 extra.id = "nuevo"
 extra.name = "Montaje añadido"
 proposed = current.duplicate(true)
 proposed.mounts.insert(0, extra)
 result = LoadoutComparison.compare(current, proposed)
 check(result.added == 1 and not result.reordered and result.modified == 0, "insertion is not a false reorder")
 result.changes[0].mount.name = "mutated result"
 check(proposed.mounts[0].name == "Montaje añadido", "added mount record detached")
 result = LoadoutComparison.compare(proposed, current)
 check(result.removed == 1 and not result.reordered, "removal is not a false reorder")
 proposed = current.duplicate(true)
 proposed.mounts[0].id = "renombrado"
 result = LoadoutComparison.compare(current, proposed)
 check(result.added == 1 and result.removed == 1 and result.modified == 0, "ID rename is removal plus addition")
 proposed = current.duplicate(true)
 proposed.template = "custom"
 result = LoadoutComparison.compare(current, proposed)
 check(result.template_changed and not result.equal and result.modified == 0, "template metadata reported separately")
 proposed = current.duplicate(true)
 proposed.mounts[0].auto_target = "PRIVATE_CONTACT"
 proposed.mounts[0].ready_at = 1000.0
 proposed.extra = "PRIVATE_PAYLOAD"
 result = LoadoutComparison.compare(current, proposed)
 check(result.equal and not LoadoutComparison.plain_report(result).contains("PRIVATE"), "non-authored fields ignored")
 proposed.mounts[0].name = "[url]hola[/url]\nAVISO"
 result = LoadoutComparison.compare(current, proposed)
 var text = LoadoutComparison.plain_report(result)
 check(text.contains("\\nAVISO") and not text.contains("\nAVISO"), "labels cannot inject report lines")
 proposed = current.duplicate(true)
 proposed.mounts[0].cycle = current.mounts[0].cycle + 0.000000001
 result = LoadoutComparison.compare(current, proposed)
 check(result.modified == 1, "tiny real numeric difference is not rounded away")
 check(LoadoutComparison.plain_report(result).contains(JSON.stringify(proposed.mounts[0].cycle, "", true, true)), "report retains full numeric precision")
 check(current == original, "all comparisons leave baseline untouched")

func test_documents() -> void:
 var design = ShipModel.standard_design()
 var current = LoadoutDocument.default_loadout()
 var encoded = LoadoutDocument.encode(design, current)
 var result = LoadoutComparison.compare_text(current, encoded.text)
 check(result.equal and not result.legacy, "v2 round trip compared through existing decoder")
 var legacy = JSON.stringify({"format": LoadoutDocument.FORMAT, "version": 1, "design": design})
 result = LoadoutComparison.compare_text(current, legacy)
 check(result.equal and result.legacy, "v1 follows existing default mount migration")
 check(LoadoutComparison.plain_report(result).contains("AVISO: archivo v1"), "v1 default is never presented as authored mounts")
 design.hull = 160
 result = LoadoutComparison.compare_text(current, LoadoutDocument.encode(design, current).text)
 check(result.equal and LoadoutComparison.plain_report(result).contains("No compara estructura"), "scope explicitly excludes structural changes")
 for bad in ["{bad", "[]", "null", "true", "{}", " ".repeat(LoadoutDocument.MAX_BYTES + 1)]:
  check(LoadoutComparison.compare_text(current, bad).has("error"), "invalid document rejected")
 for version in [0, 3, "2", true, 2.5]:
  var text = JSON.stringify({"format": LoadoutDocument.FORMAT, "version": version, "design": design, "loadout": current})
  check(LoadoutComparison.compare_text(current, text).has("error"), "unsupported version rejected")
 for bad in [null, [], {}, {"mounts": []}]:
  check(LoadoutComparison.compare(bad, current).has("error"), "invalid baseline rejected")
  check(LoadoutComparison.compare(current, bad).has("error"), "invalid proposal rejected")
 for value in [-1, NAN, INF, "10", true, null]:
  var invalid = current.duplicate(true)
  invalid.mounts[0].damage = value
  check(LoadoutComparison.compare(current, invalid).has("error"), "invalid number rejected by authority")
 var invalid = current.duplicate(true)
 invalid.mounts[1].id = invalid.mounts[0].id
 check(LoadoutComparison.compare(current, invalid).has("error"), "duplicate IDs cannot produce ambiguous diff")
 var too_many = current.duplicate(true)
 for i in 7:
  var mount = current.mounts[0].duplicate(true)
  mount.id = "extra_%d" % i
  too_many.mounts.append(mount)
 check(LoadoutComparison.compare(current, too_many).has("error"), "mount count limit inherited")

func settle() -> void:
 for i in 4: await process_frame

func click(node: Node, text: String) -> void:
 for button in node.find_children("*", "Button", true, false):
  if button.text == text:
   button.pressed.emit()
   return
 check(false, "button exists: " + text)

func write_fixture(path: String, text: String) -> void:
 var file = FileAccess.open(path, FileAccess.WRITE)
 check(file != null, "fixture writable in isolated user directory")
 if file != null:
  file.store_string(text)
  file.close()

func test_window() -> void:
 root.size = Vector2i(1600, 900)
 for child in root.get_children(): child.set_process(false)
 var session = root.get_node("Session")
 session.paused = true
 var live_before = session.sim.state.duplicate(true)
 var editor = ShipDesignEditor.new()
 editor.theme = ConsoleUI.make_theme()
 root.add_child(editor)
 editor.popup_centered()
 editor.tabs.current_tab = 1
 await settle()
 var panel = editor.loadout_editor
 var baseline = panel.read_loadout()
 var design_before = editor.read_design()
 var changes = {"count": 0}
 panel.changed.connect(func(): changes.count += 1)
 click(panel, "Comparar montajes…")
 await settle()
 var window = panel._comparison_window
 check(is_instance_valid(window) and window.visible, "comparison accessible from native astillero")
 if not is_instance_valid(window):
  editor.queue_free()
  return
 check(window.baseline == baseline and window.exclusive and window.transient, "modal detached baseline")
 check(not window.report.editable, "result is plain read-only text")
 var proposed = baseline.duplicate(true)
 proposed.mounts[0].damage += 1
 var encoded = LoadoutDocument.encode(ShipModel.standard_design(), proposed).text
 window.source.text = encoded
 click(window, "Comparar")
 await settle()
 check(window.last_result.get("modified", 0) == 1, "compare button shows actual changed hardpoint")
 check(window.report.text.contains("MODIFICADO"), "human readable changes visible")
 panel._open_comparison()
 check(panel._comparison_window == window, "repeated opening reuses existing modal")
 window.source.text = "{bad"
 window.source.text_changed.emit()
 check(window.last_result.is_empty() and window.report.text.is_empty(), "edits clear stale comparison")
 click(window, "Comparar")
 check(window.last_result.has("error"), "malformed pasted JSON has visible error")
 window.compare_text(encoded)
 var returned = window.compare_text(encoded)
 returned.changes.clear()
 check(not window.last_result.changes.is_empty(), "callers cannot mutate retained result")
 var path = "user://comparison-valid.json"
 write_fixture(path, encoded)
 window.compare_file(path)
 check(window.last_result.get("modified", 0) == 1, "local file uses existing document validator")
 var invalid_path = "user://comparison-invalid.json"
 write_fixture(invalid_path, "{bad")
 window.compare_file(invalid_path)
 check(window.last_result.has("error") and not window.report.text.contains("MODIFICADO"), "bad file clears previous success")
 write_fixture(invalid_path, " ".repeat(LoadoutDocument.MAX_BYTES + 1))
 window.compare_file(invalid_path)
 check(window.last_result.has("error"), "oversized file rejected before reading content")
 window.compare_file("user://comparison-missing.json")
 check(window.last_result.has("error"), "missing file fails safely")
 check(panel.read_loadout() == baseline and editor.read_design() == design_before and changes.count == 0, "preview never imports or emits draft changes")
 check(session.sim.state == live_before, "preview never mutates campaign or runtime")
 window.size = window.min_size
 await settle()
 check(window.report.get_global_rect().end.x <= window.size.x and window.report.get_global_rect().end.y <= window.size.y, "report fits minimum window with scrolling")
 check(window.source.get_global_rect().end.x <= window.size.x, "input wraps within minimum width")
 click(window, "Cerrar")
 await settle()
 check(not is_instance_valid(window), "close disposes comparison")
 panel.fields.damage.get_line_edit().text = "17.25"
 panel.fields.damage.get_line_edit().text_changed.emit("17.25")
 click(panel, "Comparar montajes…")
 await settle()
 window = panel._comparison_window
 check(window.baseline.mounts[0].damage == 17.25, "opening commits previously typed numeric input to comparison baseline")
 var detached = window.baseline.duplicate(true)
 panel.loadout.mounts[0].damage = 18.0
 check(window.baseline == detached, "baseline does not alias editor draft")
 editor.queue_free()
 await settle()
 check(not is_instance_valid(window), "owner teardown also releases comparison")
 check(session.sim.state == live_before, "all authoring remains separate from live state")
 for fixture in [path, invalid_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
