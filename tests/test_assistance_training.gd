extends SceneTree
var checks = 0
var failures = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("ASSISTANCE_TRAINING_FAIL " + label)

func begin(model: AssistanceTraining, mode: String, recipe: int = 1) -> Dictionary:
 check(model.reset(mode, recipe).ok, "reset " + mode)
 check(model.order("assist_begin", {"recipient": "ingenieria", "mode": mode}).ok, "begin " + mode)
 var task: Dictionary = model.snapshot().cooperation.tasks.get(AssistanceTraining.PRINCIPAL, {})
 check(not task.is_empty(), "native task available")
 return task

func solve(model: AssistanceTraining, task: Dictionary) -> void:
 match task.mode:
  "precision":
   check(model.order("assist_input", {"x": task.center[0], "y": task.center[1]}).ok, "precision input")
   check(not model.order("assist_input", {"x": task.center[0], "y": task.center[1]}).ok, "single shot")
  "secuencia":
   check(not model.order("assist_input", {"value": task.sequence[0]}).ok, "preview cannot be answered")
   model.advance(3.01)
   check(model.snapshot().cooperation.tasks[AssistanceTraining.PRINCIPAL].sequence.is_empty(), "native preview redaction")
   for value in task.sequence: check(model.order("assist_input", {"value": value}).ok, "sequence input")
  "temporizacion":
   var reached = false
   for i in 600:
    if absf(Cooperation.cursor(task, model.snapshot().time) - task.center[0]) < 0.006:
     reached = true
     break
    model.advance(1.0 / 120.0)
   check(reached, "timing target reached")
   check(model.order("assist_input").ok, "native timing input")
  "puzzle":
   var solution = -1
   for mask in 512:
    var board = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    for i in 9:
     if mask & (1 << i): Cooperation.flip(board, i)
    if board == task.target:
     solution = mask
     break
   check(solution >= 0, "native puzzle solvable")
   if solution >= 0:
    for i in 9:
     if solution & (1 << i): check(model.order("assist_input", {"value": i}).ok, "circuit input")

func verify_success(model: AssistanceTraining, task: Dictionary) -> void:
 var before: Dictionary = model.snapshot()
 check(model.order("assist_finish").ok, "finish accepted")
 var proposed: Dictionary = model.snapshot()
 check(model.phase == "proposal", "proposal stage")
 check(proposed.cooperation.tokens.has(task.id), "native proposal exists")
 check(before.ship == proposed.ship and before.operations == proposed.operations, "finishing never commands ship")
 check(not model.order("assist_consume", {"id": task.id}).ok, "helper cannot consume recipient proposal")
 check(model.apply_proposal().ok, "recipient accepts with native permissions")
 check(model.phase == "complete", "completion requires recipient")
 var cooling = float(model.snapshot().operations.coolant.motores)
 check(cooling > 0 and cooling <= 2, "real bounded coolant effect on training ship")
 check(model.snapshot().cooperation.tokens.is_empty(), "token consumed")
 check(not model.apply_proposal().ok, "no replay of consumed token")

func test_rules() -> void:
 var model = AssistanceTraining.new()
 for recipe in [1, 17, 90210, AssistanceTraining.MAX_SEED]:
  for mode in Cooperation.MODES:
   var task = begin(model, mode, recipe)
   solve(model, task)
   verify_success(model, task)
 check(model.completed_modes.size() == 4, "completion counts modes, not repetitions")
 check(model.guidance().contains("4/4"), "coaching shows progress")
 var original = begin(model, "precision", 123)
 model.reset("precision", 123)
 var repeated = begin(model, "precision", 123)
 check(original == repeated, "same recipe repeats exact native task")
 var other = AssistanceTraining.new()
 var different = begin(other, "precision", 124)
 check(original.center != different.center or original.phase != different.phase, "different recipes differ")
 model.order("assist_input", {"x": 0.0, "y": 0.0})
 model.order("assist_finish")
 check(model.phase == "retry" and model.snapshot().cooperation.tokens.is_empty(), "miss has no reward")
 check(float(model.snapshot().operations.coolant.motores) == 0.0, "miss has no coolant effect")
 check(other.snapshot().cooperation.tasks.size() == 1, "instances are isolated")
 var copy = other.snapshot()
 copy.ship.hull = -99
 copy.cooperation.tasks.clear()
 check(other.snapshot().ship.hull > 0 and other.snapshot().cooperation.tasks.size() == 1, "snapshots do not alias internal state")
 for invalid in [true, "1", 0, -1, 1.5, NAN, INF, AssistanceTraining.MAX_SEED + 1, [], {}]:
  var before: Dictionary = other.snapshot()
  check(not other.reset("precision", invalid).ok and before == other.snapshot(), "invalid seed leaves state intact")
 check(not other.reset("inventado", 1).ok, "unknown mode rejected")
 check(not other.order("fire", {"target": "dummy"}).ok, "non-assistance orders refused")
 check(not other.order("assist_input", {"x": NAN, "y": 0}).ok, "native nonfinite input rejected")
 check(not other.order("assist_input", {"x": -1, "y": 0}).ok, "native bounds checked")
 check(not other.order("assist_finish").ok, "unfinished challenge has no reward")
 for seconds in [-1.0, NAN, INF, 181.0]:
  var before: Dictionary = other.snapshot()
  check(not other.advance(seconds) and before == other.snapshot(), "invalid clock leaves state intact")
 other.advance(45.0)
 check(other.phase == "expired" and other.snapshot().cooperation.tasks.is_empty(), "native task expiry")
 check(not other.apply_proposal().ok, "expired challenge cannot award effect")
 var expiring = begin(other, "precision")
 solve(other, expiring)
 other.order("assist_finish")
 other.advance(120.0)
 check(other.phase == "expired" and other.snapshot().cooperation.tokens.is_empty(), "native proposal expiry")
 begin(other, "puzzle")
 check(not other.order("assist_input", {"value": 9}).ok, "puzzle bounds checked")
 check(other.order("assist_cancel").ok and other.phase == "cancelled", "cancel")
 check(other.snapshot().cooperation.tasks.is_empty(), "cancel removes task")
 other.reset("secuencia", 7)
 check(not other.order("assist_begin", {"mode": "secuencia", "recipient": "armas"}).ok, "recipient fixed for guided effect")
 check(not other.order("assist_begin", {"mode": "precision", "recipient": "ingenieria"}).ok, "mode matches lesson")
 check(not other.apply_proposal().ok, "no proposal before exercise")

func unchanged(before: Dictionary, after: Dictionary, label: String) -> void:
 var changed: Array[String] = []
 for key in before:
  if not after.has(key) or before[key] != after[key]: changed.append(str(key))
 for key in after:
  if not before.has(key): changed.append(str(key))
 check(changed.is_empty(), label + " unchanged; differing keys: " + ", ".join(changed))

func find_button(node: Node, text: String) -> Button:
 if node is Button and node.text == text: return node
 for child in node.get_children():
  var found = find_button(child, text)
  if found != null: return found
 return null

func test_ui() -> void:
 var session = root.get_node("Session")
 session.new_campaign()
 session.paused = true
 session.set_process(false)
 session.set_physics_process(false)
 check(session.order("assist_begin", {"recipient": "ingenieria", "mode": "precision"}).ok, "live challenge fixture begins")
 check(session.sim.state.cooperation.tasks.has("local"), "live fixture has an active task")
 var real_before: Dictionary = session.sim.state.duplicate(true)
 var view_before: Dictionary = session.view.duplicate(true)
 # --script is compiled before autoloads; load UI only after Session exists.
 var live = load("res://ui/assistance_console.gd").new()
 live.size = Vector2(1000, 800)
 root.add_child(live)
 await process_frame
 var entry = live.get_node_or_null("OpenAssistanceTraining")
 check(entry is Button, "accessible from existing assistance console")
 if entry == null:
  live.queue_free()
  return
 entry.pressed.emit()
 await process_frame
 await process_frame
 var window = live.get_node_or_null("AssistanceTraining")
 check(window is Window and window.get_script().resource_path == "res://ui/assistance_training_window.gd", "entry opens native training window")
 if window == null:
  live.queue_free()
  return
 var practice = window.console
 check(practice.training != null, "practice model installed before ready")
 check(practice.recipient.disabled and practice.chooser.item_count == 4, "guided recipient and four modes")
 var text_before = practice.status.text
 session.notice.emit("Aviso de la partida real", false)
 check(practice.status.text == text_before and live.status.text == "Aviso de la partida real", "training does not subscribe to live notices")
 var index = Cooperation.MODES.find("precision")
 practice.chooser.select(index)
 practice.chooser.item_selected.emit(index)
 window.seed_input.value = 49
 window.restart()
 practice.start_button.pressed.emit()
 await process_frame
 check(practice.training.phase == "playing" and practice.start_button.disabled, "UI begins native challenge")
 var click = InputEventMouseButton.new()
 click.button_index = MOUSE_BUTTON_LEFT
 click.pressed = true
 click.position = Vector2(practice.task.center[0] * practice.panel.size.x, practice.task.center[1] * practice.panel.size.y)
 practice.panel.gui_input.emit(click)
 var submit = find_button(practice, "Enviar resultado")
 check(submit != null, "submit control present")
 if submit != null: submit.pressed.emit()
 check(practice.training.phase == "proposal" and not practice.consume_button.disabled, "UI proposal step")
 practice.consume_button.pressed.emit()
 check(practice.training.phase == "complete", "UI recipient acceptance")
 unchanged(real_before, session.sim.state, "live state")
 unchanged(view_before, session.view, "live view")
 check(session.role == "mando" and session.mode == "offline" and session.paused, "live identity and pause untouched")
 window.restart()
 check(practice.training.phase == "ready" and practice.controls.get_child_count() == 0, "restart clears stale controls")
 var initial_seed = practice.training.practice_seed
 window._next_seed()
 check(practice.training.practice_seed == initial_seed + 1, "next recipe control")
 entry.pressed.emit()
 check(live.get_node("AssistanceTraining") == window, "one window per console")
 # Optional evidence from the real Godot-rendered window, not a mock-up.
 var screenshot = OS.get_environment("TRAINING_SCREENSHOT")
 if not screenshot.is_empty() and DisplayServer.get_name() != "headless":
  index = Cooperation.MODES.find("puzzle")
  practice.chooser.select(index)
  practice.chooser.item_selected.emit(index)
  practice.start_button.pressed.emit()
  await process_frame
  await RenderingServer.frame_post_draw
  check(window.get_texture().get_image().save_png(screenshot) == OK, "rendered training screenshot")
 window.close_requested.emit()
 await process_frame
 await process_frame
 check(live.get_node_or_null("AssistanceTraining") == null, "window close frees training")
 entry.pressed.emit()
 await process_frame
 var reopened = live.get_node("AssistanceTraining")
 check(reopened.training.completed_modes.is_empty(), "no persistence across windows")
 var escape = InputEventKey.new()
 escape.keycode = KEY_ESCAPE
 escape.pressed = true
 reopened._unhandled_key_input(escape)
 await process_frame
 check(live.get_node_or_null("AssistanceTraining") == null, "escape closes window")
 unchanged(real_before, session.sim.state, "live state after closing")
 live.queue_free()
 await process_frame

func run() -> void:
 if "--test" not in OS.get_cmdline_user_args():
  printerr("Run this suite with -- --test in an isolated test profile.")
  quit(2)
  return
 test_rules()
 await test_ui()
 print("ASSISTANCE_TRAINING_TESTS ", checks, " checks; ", failures, " failures")
 quit(1 if failures else 0)
