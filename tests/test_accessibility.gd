extends SceneTree

var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ACCESSIBILITY_FAIL " + label)

func settle() -> void:
	for i in 4:
		await process_frame

func run() -> void:
	print("--- INICIANDO TEST DE ACCESIBILIDAD ---")
	
	# Test 1: Defaults del perfil de accesibilidad
	var defaults = AccessibilityProfile.defaults()
	check(defaults.text_percent == 100, "Default text percent es 100%")
	check(defaults.colorblind_mode == "none", "Default colorblind mode es none")
	check(defaults.global_reduced_motion == false, "Default global_reduced_motion es false")
	
	# Test 2: Validación de perfiles
	var valid_err = AccessibilityProfile.validate(defaults)
	check(valid_err.is_empty(), "Perfil default es válido")
	
	var invalid_mode = defaults.duplicate()
	invalid_mode.colorblind_mode = "invalid_mode"
	check(not AccessibilityProfile.validate(invalid_mode).is_empty(), "Rechaza modo de daltonismo inválido")
	
	# Test 3: Guardado y lectura de perfil
	var test_path = "user://accessibility-test-v1.json"
	var custom_prof = defaults.duplicate()
	custom_prof.colorblind_mode = "deuteranopia"
	custom_prof.global_reduced_motion = true
	
	var save_err = AccessibilityProfile.save_file(test_path, custom_prof)
	check(save_err == OK, "Guardado de perfil de accesibilidad correcto")
	
	var loaded = AccessibilityProfile.load_file(test_path)
	check(loaded.error.is_empty(), "Carga de perfil de accesibilidad sin errores")
	check(loaded.profile.colorblind_mode == "deuteranopia", "Modo deuteranopia conservado")
	check(loaded.profile.global_reduced_motion == true, "Movimiento reducido conservado")
	
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	
	print("ACCESSIBILITY_RESULT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
