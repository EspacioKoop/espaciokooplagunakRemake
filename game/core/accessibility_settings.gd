class_name AccessibilitySettings
extends RefCounted

## Local, runtime-only accessibility preferences.
## Persistence is deliberately owned by the application layer and is out of scope here.

var subtitles_enabled: bool = true
var colorblind_mode: bool = false
var reduced_motion: bool = false

func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled

func transition_duration(seconds: float) -> float:
	return 0.0 if reduced_motion else maxf(0.0, seconds)

func snapshot() -> Dictionary:
	return {
		"subtitles_enabled": subtitles_enabled,
		"colorblind_mode": colorblind_mode,
		"reduced_motion": reduced_motion,
	}
