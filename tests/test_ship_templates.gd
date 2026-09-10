extends RefCounted

static func equivalent(a: Variant, b: Variant) -> bool:
 return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

static func run(runner: SceneTree) -> void:
 var records = ShipTemplateCatalog.entries()
 runner.check(records.size() == 38, "38 verified ship variants are available")
 var ids = {}
 for record in records:
  runner.check(not ids.has(record.id), "unique template " + record.id)
  ids[record.id] = true
  var configuration = ShipTemplateCatalog.configuration(record.id)
  runner.check(not configuration.has("error"), "valid configuration " + record.id)
  if configuration.has("error"): continue
  var encoded = LoadoutDocument.encode(configuration.design, configuration.loadout)
  var decoded = LoadoutDocument.decode(encoded.get("text", ""))
  runner.check(not decoded.has("error") and equivalent(decoded.get("design"), configuration.design) and equivalent(decoded.get("loadout"), configuration.loadout), "ship document round trip " + record.id)
 var phobos = ShipTemplateCatalog.configuration("phobos_t3")
 var elara = ShipTemplateCatalog.configuration("elara_p2")
 runner.check(phobos.design.hull == 70 and phobos.design.front_shield == 50 and phobos.design.impulse == 60, "Phobos source capacities")
 runner.check(elara.design.front_shield == 70 and elara.design.warp_speed == 800 and elara.loadout.mounts == phobos.loadout.mounts, "Elara overrides shields/warp and inherits Phobos beams")
 var adder = ShipTemplateCatalog.configuration("adder_mk3")
 runner.check(adder.design.hull == 35 and adder.design.impulse == 60 and adder.design.ammo.hvli == 2 and adder.loadout.mounts.size() == 3, "Adder MK3 inherits MK4 then overrides hull")
 runner.check(ShipTemplateCatalog.configuration("missing").has("error"), "unknown variant rejected without fallback")
 var broken = records[0].duplicate(true)
 broken.beams[0].range = 3001
 runner.check(ShipTemplateCatalog.from_record(broken).has("error"), "unsupported range rejected without clamp")
 broken = records[0].duplicate(true)
 broken.shields = [10, 20, 30]
 runner.check(ShipTemplateCatalog.from_record(broken).has("error"), "unsupported shield sectors rejected")
 broken = records[0].duplicate(true)
 broken.beams.append(broken.beams[0].duplicate(true))
 runner.check(ShipTemplateCatalog.from_record(broken).has("error"), "duplicate beam index rejected")

 var editor = ShipDesignEditor.new()
 runner.root.add_child(editor)
 runner.check(editor.template_picker.item_count == records.size(), "astillero offers all variants")
 runner.check(editor.select_template("mu52_hornet"), "astillero loads chosen variant")
 var design = editor.read_design()
 var loadout = editor.loadout_editor.read_loadout()
 runner.check(design.hull == 35 and loadout.mounts[0].range == 900 and loadout.mounts[0].damage == 2.5, "selector applies structure and mounts together")
 runner.check(not editor.select_template("missing") and editor.read_design() == design and editor.loadout_editor.read_loadout() == loadout, "failed selection preserves draft")
 var applied = {}
 editor.configuration_changed.connect(func(d, l): applied.merge({"design": d, "loadout": l}))
 editor._apply_design()
 runner.check(applied.get("design") == design and applied.get("loadout") == loadout, "Apply emits selected configuration through existing mission contract")

 var session = runner.root.get_node("Session")
 var armaments = runner.root.get_node("Armaments")
 session.new_campaign()
 var mission = session.sim.state.mission.duplicate(true)
 mission.ship_design = applied.design
 mission.ship_loadout = applied.loadout
 runner.check(session.start_mission(0, mission).ok, "selected configuration starts through Session")
 session.paused = true
 session.role = "armas"
 runner.check(session.sim.state.ship.max_hull == 35 and armaments.ensure().mounts[0].range == 900, "playable ship uses selected hull and armament")
 var target = runner.hostile(str(session.sim.state.contacts[0].id), [800.0, 0.0])
 target.frequency = 6
 var energy = session.sim.state.ship.energy
 runner.check(armaments.command("fire", {"mount": "beam_0", "target": target.id}).ok and target.hull == 97.5, "MU52 authored range and damage affect actual combat")
 runner.check(session.sim.state.ship.energy == energy - 10 and not armaments.command("fire", {"mount": "beam_0", "target": target.id}).ok, "native energy and source cooldown remain authoritative")
 var path = "user://ship-template-test.json"
 var save_error = LocalStorage.save_state(session.sim.state, path)
 runner.check(save_error.is_empty(), "variant campaign saves: " + save_error)
 var saved = LocalStorage.read_state(path)
 runner.check(saved.has("state"), "variant campaign reloads")
 if saved.has("state"):
  session.sim.state = saved.state
  runner.check(equivalent(session.sim.state.ship.design, design) and armaments.ensure().mounts[0].ready_at == 4.0, "save preserves selected design, hardpoints and live cooldown")
  session.sim.state.time = 4.0
  session.role = "navegacion"
  runner.check(not armaments.command("fire", {"mount": "beam_0", "target": target.id}).ok, "selected template preserves weapons role authorization")
 for cleanup in [path, path + ".bak"]:
  if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(ProjectSettings.globalize_path(cleanup))
 await runner.process_frame
