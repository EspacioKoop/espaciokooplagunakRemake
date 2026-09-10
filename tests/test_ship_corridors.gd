extends RefCounted

static func walk(runner: SceneTree, point: Vector3, label: String, expected_zone: int = -1) -> bool:
 var deck = runner.deck
 Input.action_press("move_forward")
 Input.action_press("sprint")
 var previous: Vector3 = deck.body.position
 var stuck = 0
 for frame in 1400:
  var at: Vector3 = deck.body.position
  if Vector2(at.x - point.x, at.z - point.z).length() < 0.3:
   Input.action_release("move_forward")
   var arrived = expected_zone < 0 or deck.zone == expected_zone
   runner.check(arrived, label + " physical arrival and zone")
   return arrived
  deck.body.look_at(Vector3(point.x, at.y, point.z))
  if deck._near_corridor_door >= 0 and not deck._corridors.doors[deck._near_corridor_door].open: deck.interact()
  await runner.physics_frame
  # Includes the real WorldDeck fall recovery: any teleport would fail here.
  if deck.body.position.distance_to(previous) > 0.3 or deck.body.position.y < -0.2: break
  stuck = stuck + 1 if deck.body.position.distance_to(previous) < 0.0001 else 0
  if stuck > 50: break
  previous = deck.body.position
 Input.action_release("move_forward")
 runner.check(false, label + " blocked/discontinuous at " + str(deck.body.position))
 return false

static func run(runner: SceneTree) -> void:
 var deck = runner.deck
 var controls = runner.root.get_node("Controls")
 var previous_touch = controls.touch.enabled
 var previous_paused = runner.session.paused
 var previous_scale = Engine.time_scale
 var previous_ticks = Engine.physics_ticks_per_second
 var models = deck._zone_models.map(func(model): return model.get_instance_id())
 var player_id = deck.body.get_instance_id()
 # Exercise normal WorldDeck movement in headless Godot via its supported touch gate.
 controls.touch.set_enabled(true)
 controls.touch.walking = true
 runner.session.paused = true
 Engine.physics_ticks_per_second = 480
 Engine.time_scale = 8.0
 var link = deck._corridors.links[0]
 var okay = await walk(runner, link.finish + Vector3(0, 0, -1.2), "bridge approach", 0)
 if okay:
  deck._corridors.set_open(link.b_door, false)
  for frame in 3: await runner.physics_frame
  runner.check(deck.body.test_move(deck.body.global_transform, Vector3(0, 0, 2.0)), "closed bridge hatch physically blocks the player")
  okay = await walk(runner, link.start + Vector3(0, 0, 1.3), "bridge to hallway", 1)
 var crossings = 1 if okay else 0
 if okay:
  for i in range(1, 6):
   link = deck._corridors.links[i]
   var approach: Vector3 = link.start + Vector3(0, 0, -1.5 if i == 5 else 0)
   approach.x = 0
   if not await walk(runner, approach, "hallway approach %d" % i, 1): break
   if not await walk(runner, link.finish, "connector %d" % i, link.target): break
   var inside: Vector3 = link.finish + (runner.zones[link.target].at - link.finish).normalized() * 2.4
   if not await walk(runner, inside, "enter compartment %d" % link.target, link.target): break
   crossings += 1
   if not await walk(runner, link.finish, "compartment exit %d" % link.target, link.target): break
   if not await walk(runner, approach, "return corridor %d" % i, 1): break
   crossings += 1
 if crossings == 11:
  link = deck._corridors.links[0]
  if await walk(runner, link.start + Vector3(0, 0, 1.3), "return bridge approach", 1):
   if await walk(runner, link.finish + Vector3(0, 0, -1.2), "hallway to bridge", 0): crossings += 1
 runner.check(crossings == 12, "all six links traversed in both directions without teleporting")
 runner.check(deck._corridors.doors.all(func(door): return door.open and door.collider.disabled), "all twelve hatches opened through proximity interaction")
 runner.check(deck.body.get_instance_id() == player_id and deck._zone_models.map(func(model): return model.get_instance_id()) == models, "same player and all compartments remain loaded throughout")
 Input.action_release("move_forward")
 Input.action_release("sprint")
 controls.touch.set_enabled(previous_touch)
 runner.session.paused = previous_paused
 Engine.time_scale = previous_scale
 Engine.physics_ticks_per_second = previous_ticks
