extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("ACCESSIBILITY_CHECK_FAILED ", message)
	else:
		print("ACCESSIBILITY_CHECK_OK ", message)

func _init() -> void:
	var settings := AccessibilitySettings.new()
	check(settings.transition_duration(0.4) == 0.4, "motion enabled keeps duration")
	settings.set_reduced_motion(true)
	check(settings.transition_duration(0.4) == 0.0, "reduced motion removes transition")
	check(settings.snapshot()["reduced_motion"] == true, "snapshot exposes reduced motion")
	check(settings.subtitles_enabled, "subtitles enabled by default")
	check(not settings.colorblind_mode, "colorblind preference disabled by default")
	check(settings.transition_duration(-2.0) == 0.0, "reduced motion clamps negative duration")
	settings.set_reduced_motion(false)
	check(settings.transition_duration(0.4) == 0.4, "motion can be restored")
	check(settings.transition_duration(-2.0) == 0.0, "normal motion clamps negative duration")
	check(settings.transition_duration(0.0) == 0.0, "zero transition stays zero")
	var snapshot := settings.snapshot()
	check(snapshot == {"subtitles_enabled": true, "colorblind_mode": false, "reduced_motion": false}, "snapshot contains exactly local preferences")
	snapshot["subtitles_enabled"] = false
	check(settings.subtitles_enabled, "snapshot mutation does not change settings")

	var bus := SubtitleBus.new(settings)
	var received := []
	bus.subtitle_emitted.connect(func(text: String, source: String, duration: float): received.append([text, source, duration]))
	check(bus.emit_notice("Puerta abierta", "Nave", 2.0), "subtitle notice accepted")
	check(received.size() == 1 and received[0][0] == "Puerta abierta", "subtitle signal emitted")
	check(received[0] == ["Puerta abierta", "Nave", 2.0], "subtitle preserves source and duration")
	settings.subtitles_enabled = false
	check(not bus.emit_notice("oculto"), "disabled subtitles are not emitted")
	check(received.size() == 1, "disabled subtitles produce no signal")
	settings.subtitles_enabled = true
	check(not bus.emit_notice(""), "empty subtitle is rejected")
	check(not bus.emit_notice(" \t\n "), "whitespace subtitle is rejected")
	check(received.size() == 1, "empty subtitles produce no signal")
	check(bus.emit_notice("  Aviso  "), "subtitles can be reenabled")
	check(received[-1] == ["  Aviso  ", "Sistema", 3.0], "notice defaults and original text preserved")
	check(bus.emit_notice("Breve", "Prueba", -1.0), "negative subtitle duration is accepted and clamped")
	check(received[-1][2] == 0.1, "negative subtitle duration has readable minimum")
	check(bus.emit_notice("Instantáneo", "Prueba", 0.0), "zero subtitle duration is accepted and clamped")
	check(received[-1][2] == 0.1, "zero subtitle duration has readable minimum")
	settings.set_reduced_motion(true)
	check(bus.emit_notice("Leer", "Nave", 2.0) and received[-1][2] == 2.0, "reduced motion does not erase subtitle reading time")
	var independent_bus := SubtitleBus.new()
	check(independent_bus.settings != settings and independent_bus.settings.subtitles_enabled, "default bus owns independent settings")
	independent_bus.settings.subtitles_enabled = false
	check(settings.subtitles_enabled, "independent bus does not mutate supplied settings")

	var warning := RedundantSignal.describe(RedundantSignal.Severity.WARNING, "Energía baja")
	check(warning["icon"] == "▲" and warning["pattern"] == "striped", "warning is not color-only")
	var danger := RedundantSignal.describe(RedundantSignal.Severity.DANGER, "Incendio")
	check(danger["icon"] == "!" and danger["pattern"] == "hatch", "danger is not color-only")
	var info := RedundantSignal.describe(RedundantSignal.Severity.INFO, "Listo")
	check(info == {"label": "Información", "icon": "●", "pattern": "solid", "message": "Listo"}, "info has full redundant description")
	check(warning["label"] == "Advertencia" and warning["message"] == "Energía baja", "warning preserves label and message")
	check(danger["label"] == "Peligro" and danger["message"] == "Incendio", "danger preserves label and message")
	check(RedundantSignal.describe(RedundantSignal.Severity.INFO, "")["message"] == "", "empty redundant message is preserved")
	warning["label"] = "modificado"
	check(RedundantSignal.describe(RedundantSignal.Severity.WARNING, "nuevo")["label"] == "Advertencia", "descriptions do not share mutable state")
	check(not AccessibilitySettings.new().reduced_motion, "new settings do not inherit reduced motion")

	if failures.is_empty():
		print("ACCESSIBILITY_BASELINE_OK checks=%d failures=0" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
