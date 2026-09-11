extends SceneTree

var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DECK_WALK_FAIL " + label)

func settle() -> void:
	for i in 4:
		await process_frame

func run() -> void:
	print("--- INICIANDO TEST DE RECORRIDO DE CUBIERTA (FIX #29) ---")
	root.size = Vector2i(1600, 900)
	
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await settle()
	
	app._new_game()
	await settle()
	
	app._go("deck")
	await settle()
	
	check(app._deck != null, "WorldDeck instanciado correctamente")
	var deck = app._deck
	
	var total_zones = WorldDeck.ZONES.size()
	check(total_zones == 13, "Se encontraron 13 destinos en la cubierta de la nave")
	
	for i in total_zones:
		var zone_info = WorldDeck.ZONES[i]
		var zone_name = zone_info.get("name", "Zona " + str(i))
		
		deck.teleport_zone(i)
		await settle()
		
		check(deck.zone == i, "Teletransporte a la zona " + str(i) + " (" + zone_name + ") correcto")
		check(deck.body != null and is_instance_valid(deck.body), "Cuerpo de personaje válido en " + zone_name)
		
		# Probar interacción en la zona
		deck.interact()
		await settle()
		
		check(not is_queued_for_deletion(), "La escena sigue viva tras interactuar en " + zone_name)
	
	app._ambient.stop()
	app._effects.stop()
	app._ambient.stream = null
	app._effects.stream = null
	app.queue_free()
	await settle()
	
	print("FULL_DECK_WALK_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
