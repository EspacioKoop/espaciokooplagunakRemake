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
 await test_editor()
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

func settle() -> void:
 for i in 4: await process_frame

func ship_window(editor: MissionEditor) -> ShipDesignEditor:
 for child in editor.get_children():
  if child is ShipDesignEditor: return child
 return null

func click(node: Node, text: String) -> void:
 for button in node.find_children("*", "Button", true, false):
  if button.text == text:
   button.pressed.emit()
   return
 check(false, "button exists: " + text)

func change_text(panel: LoadoutEditor, field: String, value: String) -> void:
 panel.fields[field].text = value
 panel.fields[field].text_changed.emit(value)

func test_editor() -> void:
 root.size = Vector2i(1600, 900)
 # Freeze autonomous timers so assertions compare only the requested UI actions.
 for child in root.get_children(): child.set_process(false)
 var session = root.get_node("Session")
 session.paused = true
 var live_before = session.sim.state.duplicate(true)
 var editor = MissionEditor.new()
 editor.theme = ConsoleUI.make_theme()
 editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.add_child(editor)
 await settle()
 var original = editor.mission.duplicate(true)
 click(editor, "Diseñar nave")
 await settle()
 var window = ship_window(editor)
 check(window != null, "astillero accessible through native mission editor button")
 if window == null:
  editor.queue_free()
  return
 window.tabs.current_tab = 1
 var panel = window.loadout_editor
 await settle()
 check(panel.mounts_list.item_count == 2, "legacy mission opens with existing exploration loadout")
 check(panel.fields.size() == 8 and panel.kind.item_count == 4, "all authored mount fields and types exposed")
 var original_loadout = panel.read_loadout()
 var narrow = original_loadout.duplicate(true)
 narrow.mounts[0].arc = 0.005
 narrow.mounts[0].cycle = 1.23456789
 panel.set_loadout(narrow)
 await settle()
 check(panel.fields.arc.value == 0.005 and panel.read_loadout() == narrow, "UI preserves valid sub-centidegree arcs and fractional cycles without edits")
 panel.fields.arc.value = 0
 check(not LoadoutDocument.validate_loadout(panel.read_loadout()).is_empty(), "zero arc still rejected by common validator")
 panel.set_loadout(original_loadout)
 var bad = original_loadout.duplicate(true)
 bad.mounts[0].energy = -1
 check(not panel.set_loadout(bad) and panel.read_loadout() == original_loadout, "invalid replacement leaves editor draft intact")
 click(panel, "Duplicar")
 check(panel.loadout.mounts.size() == 3 and panel.loadout.mounts[2].id != panel.loadout.mounts[0].id, "duplicate button creates independent unique hardpoint")
 change_text(panel, "name", "Defensa de babor")
 check(panel.loadout.mounts[0].name != "Defensa de babor", "copy edits do not alias source mount")
 click(panel, "↑")
 check(panel.selected == 1 and panel.loadout.mounts[1].name == "Defensa de babor", "move up preserves edited hardpoint")
 click(panel, "↓")
 check(panel.selected == 2, "move down changes order")
 for i in 10: panel._add_mount()
 check(panel.loadout.mounts.size() == 8 and panel._add_button.disabled and panel._copy_button.disabled, "mount limit enforced by actions and controls")
 for i in 10: panel._remove_mount()
 check(panel.loadout.mounts.size() == 1 and panel._remove_button.disabled, "last mount cannot be removed")
 panel.templates.select(1)
 click(panel, "Reemplazar por plantilla")
 check(panel.read_loadout() == LoadoutDocument.authored_loadout(ShipArmaments.template("escolta")), "template button loads four real escort mounts")
 panel._select(0)
 change_text(panel, "id", panel.loadout.mounts[1].id)
 click(window, "Aplicar diseño a la misión")
 check(not window.is_queued_for_deletion() and editor.mission == original, "duplicate identifier blocks Apply without mutating mission")
 check(not window.status.text.is_empty(), "invalid draft provides visible feedback")
 click(window, "Cancelar")
 await settle()
 check(editor.mission == original, "cancel discards all structural and loadout draft edits")
 click(editor, "Diseñar nave")
 await settle()
 window = ship_window(editor)
 panel = window.loadout_editor
 window.tabs.current_tab = 1
 window.fields.hull.value = 160
 window.fields.reverse.value = 0.456789
 change_text(panel, "id", "custom_emp")
 change_text(panel, "name", "Emisor de pruebas")
 panel.kind.select(ShipArmaments.MOUNT_KINDS.find("emp"))
 panel.kind.item_selected.emit(panel.kind.selected)
 for entry in [["arc_center", 90.0], ["arc", 70.0], ["range", 800.0], ["damage", 13.0], ["cycle", 2.5], ["energy", 9.0]]:
  panel.fields[entry[0]].value = entry[1]
 # Unsubmitted numeric input must be committed by export/apply.
 panel.fields.damage.get_line_edit().text = "17.25"
 panel.fields.damage.get_line_edit().text_changed.emit("17.25")
 var authored = panel.read_loadout()
 check(authored.mounts[0].damage == 17.25 and authored.mounts[0].kind == "emp", "pending typed input and chosen type commit to draft")
 check(session.sim.state == live_before, "editing never refits or alters active host ship")
 var path = "user://loadout-editor-ship-test.json"
 window._exporting = true
 window._file_selected(path)
 check(FileAccess.file_exists(path), "export writes a ship document")
 var exported = LoadoutDocument.decode(FileAccess.get_file_as_string(path))
 check(exported.has("design") and exported.design.hull == 160 and exported.design.reverse == 0.456789 and json_equivalent(exported.loadout, authored), "export includes structure and exact custom mounts")
 click(window, "Diseño Itsaso")
 check(window.read_design().hull == 100 and panel.read_loadout() == LoadoutDocument.default_loadout(), "reset restores structure and mounts together")
 window._exporting = false
 window._file_selected(path)
 check(window.read_design().hull == 160 and json_equivalent(panel.read_loadout(), authored), "file import restores complete authored ship")
 # Broken JSON is rejected atomically and does not emit engine errors.
 var invalid_path = "user://loadout-editor-bad-test.json"
 var file = FileAccess.open(invalid_path, FileAccess.WRITE)
 file.store_string("{bad")
 file.close()
 window._file_selected(invalid_path)
 check(window.read_design().hull == 160 and json_equivalent(panel.read_loadout(), authored), "invalid file leaves current structure and mounts intact")
 # Every preset and all edit fields fit the scrollable native window at minimum size.
 window.size = window.min_size
 await settle()
 check(window.tabs.get_global_rect().end.x <= window.size.x, "tabs fit minimum window width")
 check(panel.get_global_rect().end.x <= window.size.x, "mount form fits minimum window width without horizontal clipping")
 click(window, "Aplicar diseño a la misión")
 await settle()
 check(editor.mission.ship_design.hull == 160 and json_equivalent(editor.mission.ship_loadout, authored), "Apply commits structure and loadout to the mission together")
 var applied = editor.mission.duplicate(true)
 editor._undo_change()
 check(editor.mission == original, "one mission undo restores both structure and mounts")
 editor.set_mission(applied)
 click(editor, "Diseñar nave")
 await settle()
 window = ship_window(editor)
 check(json_equivalent(window.loadout_editor.read_loadout(), authored), "reopening astillero preserves custom loadout")
 click(window, "Cancelar")
 await settle()
 editor.mission.id = "loadout_editor_test"
 editor._save()
 var mission_path = "user://missions/loadout_editor_test.json"
 editor._load_file(mission_path)
 check(json_equivalent(editor.mission.ship_loadout, authored), "mission save and reload preserves hardpoints")
 var played: Dictionary = {}
 editor.play_requested.connect(func(value): played.merge(session.start_mission(0, value)))
 click(editor, "Probar misión")
 check(played.get("ok", false), "play button starts authored mission through Session authority")
 session.paused = true
 session.role = "armas"
 var armaments = root.get_node("Armaments")
 var runtime: Dictionary = armaments.ensure()
 check(json_equivalent(LoadoutDocument.authored_loadout(runtime), authored) and session.sim.state.ship.max_hull == 160, "playable ship uses authored structure and mounts")
 var target: Dictionary = session.sim.state.contacts[0]
 target.kind = "hostile"
 target.identified = true
 target.pacified = false
 target.jammed = true
 target.hull = 100.0
 target.position = [400.0, 0.0]
 var args = {"mount": "custom_emp", "target": target.id}
 check(not armaments.command("fire", args).ok, "custom orientation rejects target outside authored arc")
 target.position = [0.0, 900.0]
 check(not armaments.command("fire", args).ok, "custom range rejects distant target inside arc")
 target.position = [0.0, 400.0]
 var energy = session.sim.state.ship.energy
 check(armaments.command("fire", args).ok, "authored EMP can fire in actual standalone simulation")
 check(target.hull == 82.75 and session.sim.state.ship.energy == energy - 9.0, "custom damage and energy applied by existing authority")
 check(target.attack_at >= 12 and not target.jammed, "chosen EMP kind has its real inhibition effect")
 check(not armaments.command("fire", args).ok, "authored cooldown blocks immediate refire")
 session.sim.state.time = 2.49
 check(not armaments.command("fire", args).ok, "custom cycle is respected until its boundary")
 session.sim.state.time = 2.5
 check(armaments.command("fire", args).ok, "mount ready at authored cycle boundary")
 session.role = "navegacion"
 check(not armaments.command("fire", args).ok, "custom mount retains weapons station authorization")
 var save_path = "user://loadout-editor-save-test.json"
 check(LocalStorage.save_state(session.sim.state, save_path).is_empty(), "authored game saves through existing storage")
 var saved = LocalStorage.read_state(save_path)
 check(saved.has("state"), "authored game restores through existing storage")
 if saved.has("state"):
  session.sim.state = saved.state
  check(json_equivalent(LoadoutDocument.authored_loadout(armaments.ensure()), authored), "save restores exact custom mount parameters")
  check(armaments.ensure().mounts[0].ready_at == 5.0, "save keeps active cooldown instead of resetting from design")
 var broken_save = session.sim.state.duplicate(true)
 broken_save.mission.ship_loadout.mounts[0].cycle = -1
 check(not LocalStorage.validate_state(broken_save).is_empty(), "save validation rejects corrupted authored loadout")
 for cleanup in [path, invalid_path, mission_path, save_path, save_path + ".bak"]:
  if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(ProjectSettings.globalize_path(cleanup))
 editor.queue_free()
 await settle()
