class_name SubtitleBus
extends RefCounted

signal subtitle_emitted(text: String, source: String, duration: float)

var settings: AccessibilitySettings

func _init(accessibility_settings: AccessibilitySettings = null) -> void:
	settings = accessibility_settings if accessibility_settings else AccessibilitySettings.new()

func emit_notice(text: String, source: String = "Sistema", duration: float = 3.0) -> bool:
	if text.strip_edges().is_empty() or not settings.subtitles_enabled:
		return false
	subtitle_emitted.emit(text, source, maxf(0.1, duration))
	return true
