extends SceneTree

const AccessibilitySettingsScript = preload("res://core/accessibility_settings.gd")
const SubtitleBusScript = preload("res://ui/accessibility/subtitle_bus.gd")
const RedundantSignalScript = preload("res://ui/accessibility/redundant_signal.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _init() -> void:
	var settings := AccessibilitySettingsScript.new()
	check(settings.transition_duration(0.4) == 0.4, "motion enabled keeps duration")
	settings.set_reduced_motion(true)
	check(settings.transition_duration(0.4) == 0.0, "reduced motion removes transition")
	check(settings.snapshot()["reduced_motion"] == true, "snapshot exposes reduced motion")

	var bus := SubtitleBusScript.new(settings)
	var received := []
	bus.subtitle_emitted.connect(func(text: String, source: String, duration: float): received.append([text, source, duration]))
	check(bus.emit_notice("Puerta abierta", "Nave", 2.0), "subtitle notice accepted")
	check(received.size() == 1 and received[0][0] == "Puerta abierta", "subtitle signal emitted")
	settings.subtitles_enabled = false
	check(not bus.emit_notice("oculto"), "disabled subtitles are not emitted")

	var warning := RedundantSignalScript.describe(RedundantSignalScript.Severity.WARNING, "Energía baja")
	check(warning["icon"] == "▲" and warning["pattern"] == "striped", "warning is not color-only")
	var danger := RedundantSignalScript.describe(RedundantSignalScript.Severity.DANGER, "Incendio")
	check(danger["icon"] == "!" and danger["pattern"] == "hatch", "danger is not color-only")

	if failures.is_empty():
		print("ACCESSIBILITY_BASELINE_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
