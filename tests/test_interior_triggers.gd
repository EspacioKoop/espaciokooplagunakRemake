extends SceneTree

var checks = 0
var failures = 0

class MockSession extends Node:
	var mode = "offline"
	var sim: Simulation
	func _refresh_view() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("INTERIOR_TRIGGERS_FAIL " + label)

func settle() -> void:
	for i in 4:
		await process_frame

func run() -> void:
	print("--- INICIANDO TEST DE TRIGGERS EN INTERIORES ---")
	
	var sim = Simulation.new()
	sim.start(Catalog.missions()[0])
	check(sim.state.status == "active", "Simulación iniciada correctamente")
	
	# Test 1: Crear y registrar triggers manualmente
	var trg1 = InteriorTriggers.create_trigger("trg_cantina", 7, "enter_zone", {"action": "alert", "value": "roja"})
	var reg_res = InteriorTriggers.register_trigger(sim, trg1)
	check(reg_res.ok, "Trigger de cantina registrado")
	
	var trg2 = InteriorTriggers.create_trigger("trg_playa", 9, "enter_zone", {"action": "message", "value": "Bienvenido a la zona exterior de cantina."})
	InteriorTriggers.register_trigger(sim, trg2)
	
	var list_trgs = InteriorTriggers.list_triggers(sim)
	check(list_trgs.size() == 2, "Hay 2 triggers registrados")
	
	# Test 2: Evaluar movimiento de zona (Puente -> Cantina)
	var executed1 = InteriorTriggers.evaluate_zone_movement(sim, 0, 7)
	check(executed1.size() == 1, "Un trigger se ejecutó al entrar a la cantina")
	check(sim.state.ship.alert == "roja", "El trigger cambió la alerta a ROJA")
	
	# Evaluar de nuevo el mismo movimiento (debe ser one-shot y no volver a ejecutarse)
	var executed1_repeat = InteriorTriggers.evaluate_zone_movement(sim, 0, 7)
	check(executed1_repeat.is_empty(), "El trigger no se repite si es one_shot")
	
	# Test 3: Movimiento a la zona de playa (Cantina -> Playa)
	var executed2 = InteriorTriggers.evaluate_zone_movement(sim, 7, 9)
	check(executed2.size() == 1, "El trigger de playa se ejecutó")
	
	# Test 4: Trigger de interacción
	var trg_int = InteriorTriggers.create_trigger("trg_libro", 8, "interact", {"action": "fact", "value": "libro_leido"})
	trg_int["target_id"] = "book_historic"
	InteriorTriggers.register_trigger(sim, trg_int)
	
	var executed_int = InteriorTriggers.evaluate_interaction(sim, 8, "book_historic")
	check(executed_int.size() == 1, "Trigger de interacción ejecutado")
	check(sim.state.get("facts", {}).has("fact:libro_leido"), "Hecho registrado en la simulación")
	
	# Test 5: Integración con GMLiveActions
	var session = MockSession.new()
	session.sim = sim
	root.add_child(session)
	
	check(GMLiveActions.can_direct(session), "GMLiveActions reconoce autoridad en session mock")
	
	var gm_res = GMLiveActions.dispatch(session, "add_interior_trigger", {
		"id": "trg_gm_test",
		"zone": 1,
		"event_type": "enter_zone",
		"consequence": {"action": "damage", "value": 10.0}
	})
	check(gm_res.ok, "GMLiveActions registró trigger de interior")
	var gm_mod = GMLiveActions.dispatch(session, "modify_interior_trigger", {"id": "trg_gm_test", "changes": {"zone": -1, "consequence": {"action": "damage", "value": 20.0}, "one_shot": false}})
	check(gm_mod.ok, "GMLiveActions modificó trigger de interior de forma atómica")
	var hull_before = float(sim.state.ship.hull)
	var wildcard_run = InteriorTriggers.evaluate_zone_movement(sim, 3, 4)
	check(wildcard_run.size() == 1 and float(sim.state.ship.hull) < hull_before, "Wildcard de zona aplica la consecuencia")
	var trg_sit = InteriorTriggers.create_trigger("trg_sit", -1, "sit", {"action": "message", "value": "Asiento confirmado."})
	check(InteriorTriggers.register_trigger(sim, trg_sit).ok, "Trigger sit registrado")
	check(InteriorTriggers.evaluate_interaction(sim, 2, "seat_cockpit", "sit").size() == 1, "Trigger sit se ejecuta")
	var trg_reinforce = InteriorTriggers.create_trigger("trg_reinforce", 4, "enter_zone", {"action": "reinforcements", "value": 2})
	var contacts_before = sim.state.contacts.size()
	check(InteriorTriggers.register_trigger(sim, trg_reinforce).ok, "Trigger de refuerzos registrado")
	check(InteriorTriggers.evaluate_zone_movement(sim, 3, 4).size() >= 1 and sim.state.contacts.size() == contacts_before + 2, "Trigger despliega refuerzos validados")

	var gm_remove = GMLiveActions.dispatch(session, "remove_interior_trigger", {"id": "trg_gm_test"})
	check(gm_remove.ok, "GMLiveActions retiró trigger de interior")
	check(LocalStorage.validate_state(sim.state).is_empty(), "El estado con triggers supera la validación de guardado")
	var public_snapshot: Dictionary = sim.snapshot("navegacion", "test")
	check(not public_snapshot.has("interior_triggers"), "Los triggers de dirección no aparecen en snapshots públicos")
	var invalid_state: Dictionary = sim.state.duplicate(true)
	invalid_state.interior_triggers[0].consequence.value = "nivel-inválido"
	check(not LocalStorage.validate_state(invalid_state).is_empty(), "El guardado rechaza un trigger persistido inválido")
	
	session.queue_free()
	await settle()
	
	print("INTERIOR_TRIGGERS_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
