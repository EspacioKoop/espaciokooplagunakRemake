extends SceneTree
var checks = 0
var failures = 0
var sim: Simulation
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error("COOPERATION_FAIL " + label)
func ticks(seconds: float) -> void:
 for i in ceili(seconds * 30): sim.tick(1.0 / 30)
func begin(mode: String) -> Dictionary:
 sim = Simulation.new()
 sim.start(Catalog.missions()[0])
 check(sim.command("mando", "assist_begin", {"recipient": "ingenieria", "mode": mode}, "helper").ok, "begin " + mode)
 return sim.state.cooperation.tasks.helper
func finish_success(task: Dictionary) -> void:
 var before: Dictionary = sim.state.ship.duplicate(true)
 check(sim.command("mando", "assist_finish", {}, "helper").ok, "submit skill result")
 check(before == sim.state.ship, "skill result never emits a ship command")
 check(sim.state.cooperation.tokens.has(task.id), "success creates consumable proposal")
 var token: Dictionary = sim.state.cooperation.tokens.get(task.id, {})
 if token.is_empty(): return
 check(not sim.command("armas", "assist_consume", {"id": task.id}, "other").ok, "wrong station cannot consume proposal")
 check(sim.command("ingenieria", "assist_consume", {"id": task.id}, "engineer").ok, "recipient consumes authorized order")
 check(sim.state.operations.coolant.motores > 0 and sim.state.operations.coolant.motores <= 2, "proposal effect stays inside allowed range")
 check(not sim.command("ingenieria", "assist_consume", {"id": task.id}, "engineer").ok, "spent token cannot be replayed")
func run() -> void:
 var task = begin("secuencia")
 var sequence = task.sequence.duplicate()
 check(not sim.command("mando", "assist_input", {"value": sequence[0]}, "helper").ok, "cannot answer during preview")
 check(sim.snapshot("armas", "other").cooperation.tasks.is_empty(), "other peer never receives another task")
 ticks(3.1)
 check(sim.snapshot("mando", "helper").cooperation.tasks.helper.sequence.is_empty(), "sequence no longer transmitted after preview")
 for value in sequence: check(sim.command("mando", "assist_input", {"value": value}, "helper").ok, "sequence input")
 finish_success(task)
 task = begin("precision")
 check(not sim.command("mando", "assist_input", {"x": NAN, "y": 0}, "helper").ok, "precision rejects non-finite coordinate")
 check(sim.command("mando", "assist_input", {"x": task.center[0], "y": task.center[1]}, "helper").ok, "actual precision input")
 check(not sim.command("mando", "assist_input", {"x": task.center[0], "y": task.center[1]}, "helper").ok, "precision allows a single attempt")
 finish_success(task)
 task = begin("temporizacion")
 for i in 500:
  if absf(Cooperation.cursor(task, sim.state.time) - task.center[0]) < 0.015: break
  sim.tick(1.0 / 30)
 check(sim.command("mando", "assist_input", {}, "helper").ok, "host evaluates timing from simulation clock")
 finish_success(task)
 task = begin("puzzle")
 var solution = -1
 for mask in 512:
  var board = [0, 0, 0, 0, 0, 0, 0, 0, 0]
  for i in 9:
   if mask & (1 << i): Cooperation.flip(board, i)
  if board == task.target: solution = mask; break
 check(solution >= 0, "generated circuit is solvable")
 if solution >= 0:
  for i in 9:
   if solution & (1 << i): check(sim.command("mando", "assist_input", {"value": i}, "helper").ok, "circuit move")
  finish_success(task)
 task = begin("secuencia")
 check(not sim.command("mando", "assist_finish", {}, "helper").ok, "unfinished challenge cannot award a token")
 check(not sim.command("mando", "assist_input", {"value": 0}, "intruder").ok, "principal cannot act on somebody else's task")
 check(not sim.command("mando", "assist_begin", {"recipient": "armas", "mode": "puzzle"}, "helper").ok, "duplicate tasks refused")
 ticks(46)
 check(sim.state.cooperation.tasks.is_empty(), "abandoned tasks expire")
 task = begin("precision")
 sim.command("mando", "assist_input", {"x": task.center[0], "y": task.center[1]}, "helper")
 sim.command("mando", "assist_finish", {}, "helper")
 ticks(121)
 check(sim.state.cooperation.tokens.is_empty(), "unspent proposals expire")
 var restored = LocalStorage.save_state(sim.state, "user://cooperation-test.json")
 check(restored.is_empty(), "cooperative campaign can be saved")
 var loaded = LocalStorage.read_state("user://cooperation-test.json")
 check(loaded.has("state") and loaded.state.cooperation.tasks.is_empty(), "restore does not resume transient challenges")
 DirAccess.remove_absolute("user://cooperation-test.json")
 DirAccess.remove_absolute("user://cooperation-test.json.bak")
 print("COOPERATION_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)
