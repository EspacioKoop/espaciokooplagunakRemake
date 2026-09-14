class_name RedundantSignal
extends RefCounted

enum Severity { INFO, WARNING, DANGER }

static func describe(severity: Severity, message: String) -> Dictionary:
	var label := "Información"
	var icon := "●"
	var pattern := "solid"
	match severity:
		Severity.WARNING:
			label = "Advertencia"
			icon = "▲"
			pattern = "striped"
		Severity.DANGER:
			label = "Peligro"
			icon = "!"
			pattern = "hatch"
	return {"label": label, "icon": icon, "pattern": pattern, "message": message}
