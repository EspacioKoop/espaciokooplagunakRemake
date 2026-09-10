extends SceneTree
## Synthetic exercises only; the Python runner supplies an isolated user profile.
var checks = 0
var failures = 0
var courses = 0
var first_mission = false
var ui_verified = false

func _initialize() -> void:
 call_deferred("run")

func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error("CREW_TRAINING_FAIL " + label)

func complete_step(model: CrewTraining) -> void:
 var index = model.step_index
 var step = model.current_step()
 check(not step.is_empty(), "step exists")
 check(model.select_role(step.role).ok, "select native role")
 var submitted = false
 for frame in 4000:
  if model.phase != "playing" or model.step_index != index: break
  var view = model.snapshot()
  if not submitted or (step.rule == "defeat" and float(view.ship.weapon_ready) <= float(view.time)):
   var result = model.order(step.operation, step.args)
   if result.ok:
    submitted = true
   elif step.operation not in ["fire", "missile"] or float(view.ship.weapon_ready) <= float(view.time):
    check(false, "expected native order: " + str(result.message))
    return
  model.advance(0.1)
 check(submitted, "step uses an accepted order")
 check(model.step_index == index + 1, "state-based step completion: " + str(step.title))

func complete_course(model: CrewTraining, id: String) -> void:
 check(model.reset(id).ok, "reset " + id)
 check(model.step_count() > 0 and model.phase == "playing", "playable steps " + id)
 for index in model.step_count():
  if model.phase != "playing": break
  complete_step(model)
 check(model.phase == "complete", "completed " + id)
 check(model.step_index == model.step_count(), "all steps completed " + id)
 check(id in model.completed, "course completion retained " + id)
 check(model.paused, "completed simulation stops")
 check(model.current_step().is_empty(), "no stale final step")
 check(not model.order("alert", {"level": "roja"}).ok, "complete exercise rejects new orders")

func test_courses() -> void:
 check(CrewTraining.lesson_ids().size() == 9, "first mission plus eight seats")
 var model = CrewTraining.new()
 for id in CrewTraining.lesson_ids():
  complete_course(model, id)
  if model.phase == "complete": courses += 1
  if id == CrewTraining.FIRST_MISSION:
   var view = model.snapshot()
   first_mission = view.status == "won" and view.objective == Catalog.missions()[0].objectives.size()
   check(first_mission, "entire native first mission won")
   check(view.mission.id == "itsasoratu" and view.mission.objectives == Catalog.missions()[0].objectives, "original first mission objectives unchanged")
   check(view.campaign.completed == ["itsasoratu"], "native completion reward not mocked")
   check(view.campaign.credits == Catalog.missions()[0].reward, "native first mission credits")
   check(view.ship.docked == "kaia", "first mission ends docked")
 check(model.completed.size() == 9, "all nine courses tracked")
 complete_course(model, "mando")
 check(model.completed.size() == 9, "repeat does not duplicate completed courses")

func test_boundaries() -> void:
 var model = CrewTraining.new()
 var before = model.snapshot()
 check(not model.reset("missing").ok and model.snapshot() == before, "unknown lesson preserves state")
 check(not model.select_role("admin").ok and model.role == "mando", "invalid role refused")
 for invalid in [null, true, "1", -1, 2.1, NAN, INF, -INF, [], {}]:
  before = model.snapshot()
  check(not model.advance(invalid), "invalid elapsed time refused")
  check(model.snapshot() == before, "invalid elapsed time is read-only")
 check(not model.order("gm_spawn", {"role": "mando"}).ok, "unknown command not dispatched")
 before = model.snapshot()
 check(not model.order("helm", {"heading": 0, "throttle": 1, "role": "navegacion"}).ok, "role cannot be spoofed in args")
 check(model.snapshot() == before, "wrong role leaves simulation unchanged")
 model.reset("ingenieria")
 model.select_role("ingenieria")
 before = model.snapshot()
 check(not model.order("power", {"system": "motores", "value": 4}).ok, "real power budget refuses excess")
 check(model.step_index == 0 and model.snapshot() == before, "rejected order cannot complete lesson")
 for value in [true, "4", NAN, 1.5, -1, 5]:
  before = model.snapshot()
  check(not model.order("power", {"system": "motores", "value": value}).ok, "native input validation preserved")
  check(before == model.snapshot(), "invalid power is read-only")
 check(model.order("shields", {"enabled": false}).ok and model.step_index == 0, "unrelated successful operation does not skip step")
 model.reset("navegacion")
 model.select_role("navegacion")
 model.set_paused(true)
 check(model.order("helm", {"heading": 0, "throttle": 0.4}).ok, "native orders allowed while teaching clock paused")
 before = model.snapshot()
 for i in 20: model.advance(2.0)
 check(model.snapshot() == before and model.step_index == 0, "paused clock cannot complete movement")
 model.set_paused(false)
 model.advance(0.01)
 check(model.snapshot().time == before.time, "no wall-clock catch-up on resume")
 model.advance(0.04)
 check(is_equal_approx(float(model.snapshot().time), 0.05), "fixed native tick")
 var other = CrewTraining.new()
 var unrelated = other.snapshot()
 model.advance(1.0)
 check(other.snapshot() == unrelated, "model instances independent")
 var copy = model.snapshot()
 copy.ship.hull = -1
 copy.contacts.clear()
 check(model.snapshot().ship.hull > 0 and not model.snapshot().contacts.is_empty(), "snapshot does not alias simulation")
 var step_copy = model.current_step()
 step_copy.args.throttle = 99
 check(model.current_step().args.throttle == 0.4, "step recipe does not alias")
 model.reset("sensores")
 model.select_role("sensores")
 var safe = model.snapshot()
 check(not safe.mission.has("contacts"), "source contact catalogue redacted")
 check(safe.contacts[1].name == "Eco 02" and safe.contacts[2].name == "Eco 03", "unidentified names remain hidden")
 check(model.order("scan", {"target": "signal"}).ok, "start scan")
 check(model.step_index == 0, "scan start is not completion")
 check(not model.order("scan", {"target": "wreck"}).ok, "one native scan at a time")
 model.advance(2.0)
 check(model.step_index == 0, "early scan still incomplete")
 for i in 4: model.advance(1.0)
 check(model.step_index == 1 and model.snapshot().contacts[1].identified, "scan resolves through native ticks")
 model.reset("comunicaciones")
 model.select_role("comunicaciones")
 check(not model.order("negotiate", {"target": "envoy"}).ok, "real negotiation prerequisites required")
 model.select_role("mando")
 check(not model.order("mission_choice", {"choice": "compartir"}).ok, "no narrative decision before negotiation")
 model.reset("reparaciones")
 model.select_role("reparaciones")
 var parts = model.snapshot().ship.parts
 check(model.order("repair", {"system": "motores"}).ok, "start native repair")
 check(model.snapshot().ship.parts == parts - 2 and model.step_index == 0, "repair spends resources and waits")
 check(not model.order("repair", {"system": "motores"}).ok, "busy repair rejected")
 var pristine = CrewTraining.new()
 for i in 451: pristine.advance(2.0)
 check(pristine.phase == "expired" and pristine.paused, "idle exercise time is bounded")
 check(pristine.reset("mando").ok and pristine.phase == "playing", "expired exercise can restart")

func choose_option(selector: OptionButton, value: Variant) -> bool:
 for i in selector.item_count:
  if selector.get_item_metadata(i) == value:
   selector.select(i)
   selector.item_selected.emit(i)
   return true
 return false

func ui_order(window: Window, role: String, operation: String, args: Dictionary) -> void:
 check(choose_option(window.roles, role), "UI selects role")
 check(choose_option(window.operations, operation), "UI selects operation")
 for key in args:
  check(window.inputs.has(key), "UI parameter present")
  if not window.inputs.has(key): return
  var control = window.inputs[key]
  if control is SpinBox:
   control.get_line_edit().text = str(args[key])
  else:
   check(choose_option(control, args[key]), "UI selects parameter")
 window.send_button.pressed.emit()

func test_ui() -> void:
 var session = root.get_node("Session")
 session.new_campaign()
 session.paused = true
 for service in root.get_children():
  service.set_process(false)
  service.set_physics_process(false)
 session.order("assist_begin", {"recipient": "ingenieria", "mode": "precision"})
 var before: Dictionary = session.sim.state.duplicate(true)
 var before_view: Dictionary = session.view.duplicate(true)
 var console = load("res://ui/assistance_console.gd").new()
 root.add_child(console)
 await process_frame
 var button = console.get_node_or_null("OpenCrewTraining")
 check(button is Button, "school accessible from real assistance console")
 if button == null:
  console.queue_free()
  return
 button.pressed.emit()
 await process_frame
 await process_frame
 var window = console.get_node_or_null("CrewSchool")
 check(window is Window, "entry opens actual native window")
 if window == null:
  console.queue_free()
  return
 window.set_process(false)
 check(window.lessons.item_count == 9 and window.roles.item_count == 8, "all courses and seats in UI")
 check(choose_option(window.lessons, "ingenieria"), "UI selects engineering lesson")
 ui_order(window, "ingenieria", "power", {"system": "sensores", "value": 0})
 check(window.model.step_index == 1 and window.model.snapshot().ship.systems.sensores.power == 0, "UI order reaches isolated native simulation")
 ui_order(window, "ingenieria", "power", {"system": "motores", "value": 4})
 check(window.model.step_index == 2, "UI numeric and system inputs")
 ui_order(window, "ingenieria", "coolant", {"system": "motores"})
 ui_order(window, "ingenieria", "shields", {"enabled": false})
 ui_order(window, "ingenieria", "shields", {"enabled": true})
 check(window.model.phase == "complete" and window.send_button.disabled, "UI completes actual lesson")
 var feedback = window.feedback.text
 session.notice.emit("SYNTHETIC_LIVE_NOTICE", false)
 check(window.feedback.text == feedback, "live notices do not enter training")
 check(session.sim.state == before and session.view == before_view, "live campaign and private challenge unchanged")
 check(session.role == "mando" and session.paused and session.mode == "offline", "live role mode and pause unchanged")
 button.pressed.emit()
 check(console.get_node("CrewSchool") == window, "single live school window")
 window._restart()
 check(window.model.step_index == 0 and window.model.phase == "playing", "UI restart resets practice only")
 window.pause_button.pressed.emit()
 var time = window.model.snapshot().time
 window.model.advance(1.0)
 check(window.model.snapshot().time == time and window.model.paused, "UI pause stops simulation")
 window.pause_button.pressed.emit()
 check(not window.model.paused, "UI resume")
 window._open_assistance()
 await process_frame
 var assistance = window.get_node_or_null("AssistancePractice")
 check(assistance is Window and assistance.training != null, "existing four minigames reused")
 if assistance != null: assistance.queue_free()
 await process_frame
 var capture = OS.get_environment("CREW_TRAINING_SCREENSHOT")
 if not capture.is_empty():
  check(DisplayServer.get_name() != "headless", "capture requires real renderer")
  if DisplayServer.get_name() != "headless":
   window._refresh()
   await process_frame
   await RenderingServer.frame_post_draw
   check(window.get_texture().get_image().save_png(capture) == OK, "fresh rendered school capture")
 window.close_requested.emit()
 await process_frame
 await process_frame
 check(console.get_node_or_null("CrewSchool") == null, "window close frees practice")
 button.pressed.emit()
 await process_frame
 var reopened = console.get_node("CrewSchool")
 check(reopened.model.completed.is_empty(), "progress not persisted after close")
 var escape = InputEventKey.new()
 escape.keycode = KEY_ESCAPE
 escape.pressed = true
 reopened._unhandled_key_input(escape)
 await process_frame
 await process_frame
 check(console.get_node_or_null("CrewSchool") == null, "Escape closes school")
 check(session.sim.state == before and session.view == before_view, "live session unchanged after reopen and close")
 console.queue_free()
 await process_frame
 ui_verified = true

func run() -> void:
 if "--test" not in OS.get_cmdline_user_args():
  printerr("Run with -- --test and an isolated profile.")
  quit(2)
  return
 test_courses()
 test_boundaries()
 await test_ui()
 print("CREW_TRAINING_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "courses": courses, "first_mission": first_mission, "ui": ui_verified}))
 quit(1 if failures else 0)
