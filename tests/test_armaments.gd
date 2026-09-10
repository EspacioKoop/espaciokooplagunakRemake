extends SceneTree
var checks = 0
var failures = 0
var session: Node
var armaments: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error("ARMAMENT_FAIL " + label)

func hostile(id: String, position: Array) -> Dictionary:
 var c: Dictionary = session.sim.state.contacts[0]
 c.id = id
 c.name = id.capitalize()
 c.kind = "hostile"
 c.position = position
 c.identified = true
 c.hull = 100.0
 c.pacified = false
 c.jammed = true
 c.attack_at = 0.0
 c.frequency = 6
 return c

func run() -> void:
 session = root.get_node("Session")
 armaments = root.get_node("Armaments")
 session.new_campaign()
 session.role = "armas"
 var loadout = armaments.ensure()
 check(loadout.mounts.size() == 2 and loadout.template == "exploracion", "default Itsaso starts with exploration multi-mount loadout")
 check(ShipArmaments.validate_loadout(loadout).is_empty(), "default loadout validates")
 check(armaments.command("template", {"template": "escolta"}).ok, "weapons station can apply loadout before departure")
 loadout = session.sim.state.ship.loadout
 check(loadout.mounts.size() == 4 and loadout.template == "escolta", "escort template exposes four independent mounts")
 var target = hostile("mount_target", [400.0, 0.0])
 var energy = float(session.sim.state.ship.energy)
 var first = armaments.command("fire", {"mount": "proa_babor", "target": target.id})
 check(first.ok and target.hull < 100, "forward port mount damages target inside its authored arc")
 check(session.sim.state.ship.energy < energy, "mount firing consumes authoritative ship energy")
 check(not armaments.command("fire", {"mount": "proa_babor", "target": target.id}).ok, "individual mount cooldown blocks immediate repeated shot")
 target.position = [0.0, 400.0]
 session.sim.state.time += 2.0
 check(not armaments.command("fire", {"mount": "proa_babor", "target": target.id}).ok, "forward beam refuses target outside its arc")
 check(armaments.command("fire", {"mount": "torreta_estribor", "target": target.id}).ok, "starboard turret engages same lateral target")
 session.sim.state.time += 2.0
 var before_auto = float(target.hull)
 check(armaments.command("auto_target", {"mount": "torreta_estribor", "target": target.id}).ok, "turret accepts automatic target")
 armaments._process(0.25)
 check(target.hull < before_auto, "automatic turret fires host-side when target is ready and in arc")
 check(armaments.command("auto_target", {"mount": "torreta_estribor", "target": ""}).ok, "automatic target can be cleared")
 session.sim.state.ship.docked = session.sim.state.contacts[1].id if session.sim.state.contacts.size() > 1 else "dock"
 check(armaments.command("template", {"template": "ciencia"}).ok, "docked ship can refit to science template")
 target.position = [300.0, 0.0]
 target.hull = 100.0
 target.attack_at = 0.0
 target.jammed = true
 var emp = armaments.command("fire", {"mount": "emisor_emp", "target": target.id})
 check(emp.ok and target.attack_at >= session.sim.state.time + 12.0, "EMP mount inhibits hostile attack window")
 check(not target.jammed and target.hull < 100, "EMP clears jamming and applies limited damage")
 var broken = ShipArmaments.template("exploracion")
 broken.mounts[1].id = broken.mounts[0].id
 check(not ShipArmaments.validate_loadout(broken).is_empty(), "duplicate hardpoint identifiers are rejected")
 session.role = "navegacion"
 check(not armaments.command("fire", {"mount": "torreta_omni", "target": target.id}).ok, "non-weapons station cannot fire modular mounts")
 session.role = "armas"
 check(not armaments.command("template", {"template": "no_existe"}).ok, "unknown ship loadout template is rejected")
 print("ARMAMENT_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)
