class_name ScoreComposer
extends RefCounted
## Original, deterministic four-voice score. No samples, network or game-state writes.
const RATE = 11025
const THEMES = ["bridge", "tension", "shore", "memories", "social"]
const TITLES = {"bridge": "La guardia", "tension": "Alerta a bordo", "shore": "Itsasoa", "memories": "Lo que vuelve", "social": "Mesa compartida"}
const TEMPOS = {"bridge": 72.0, "tension": 112.0, "shore": 60.0, "memories": 52.0, "social": 92.0}
const SCALE = [0, 2, 3, 5, 7, 9, 10]
const MOTIF = [0, 2, 4, 3, 1, 5, 4, 2, 6, 4, 1, 3, 2, 0, 4, 1]
var theme = "bridge"
var seed_value = 0
var sample_index = 0
var _beat_frames = 9187.5
var _voices: Array = []

func _init(selected: String = "bridge", seed_number: int = 0) -> void:
	theme = selected if selected in THEMES else "bridge"
	seed_value = posmod(seed_number, MOTIF.size())
	_beat_frames = RATE * 60.0 / TEMPOS[theme]
	for i in 4:
		_voices.append({"step": -1, "phase": 0.0, "increment": 0.0, "duration": _beat_frames, "start": 0, "gain": 0.0})

static func select_theme(view: Dictionary, zone: int = -1) -> String:
	# Presentation reads only the recipient's existing public view. Unknown echoes
	# never influence music, including when supplied a hidden hostile flag.
	var ship = view.get("ship", {})
	if ship is Dictionary and not ship.is_empty() and view.get("status", "") == "active":
		var hull = ship.get("hull", 100.0)
		var maximum = ship.get("max_hull", 100.0)
		if _finite(hull) and _finite(maximum) and float(maximum) > 0 and float(hull) < float(maximum) * 0.3:
			return "tension"
		var contacts = view.get("contacts", [])
		if contacts is Array:
			for contact in contacts:
				if contact is Dictionary and contact.get("identified", false) == true and contact.get("hostile", false) == true and contact.get("alive", true) != false:
					if contact.get("kind", "unknown") != "unknown" and _finite(contact.get("hull", 1)) and float(contact.get("hull", 1)) > 0:
						return "tension"
	if zone == 9: return "shore"
	if zone in [8, 12]: return "memories"
	if zone in [7, 10, 11]: return "social"
	return "bridge"

static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func validate_preferences(value: Variant) -> Dictionary:
	var fallback = {"version": 1, "enabled": true, "volume": 45.0, "mode": "auto"}
	if not value is Dictionary or value.get("version") != 1: return fallback
	if not value.get("enabled") is bool or not _finite(value.get("volume")): return fallback
	if value.get("mode") not in ["auto"] + THEMES: return fallback
	return {"version": 1, "enabled": value.enabled, "volume": clampf(float(value.volume), 0, 100), "mode": value.mode}

func next_frame() -> Vector2:
	var result = Vector2.ZERO
	for i in 4:
		var voice: Dictionary = _voices[i]
		var length = _beat_frames * ([4.0, 4.0, 1.0, 0.5][i])
		var step = int(floor(sample_index / length))
		if step != voice.step:
			voice.step = step
			voice.start = sample_index
			voice.duration = length
			var chord = [0, 3, 5, 2][int(sample_index / (_beat_frames * 16)) % 4]
			var degree = chord + [0, 4, 7, 9][i]
			if i >= 2: degree += MOTIF[(step + seed_value + i * 3) % MOTIF.size()]
			var midi = 43 + SCALE[posmod(degree, 7)] + 12 * int(floor(degree / 7.0))
			if theme == "shore": midi += 2
			if theme == "memories": midi -= 2
			voice.increment = TAU * (440.0 * pow(2.0, (midi - 69.0) / 12.0)) / RATE
			voice.gain = [0.12, 0.085, 0.09, 0.045][i]
			# Leave deliberate breathing spaces instead of endless arpeggios.
			if i == 3 and (theme in ["shore", "memories"] or step % 8 >= 6): voice.gain = 0.0
		var progress = clampf((sample_index - int(voice.start)) / float(voice.duration), 0, 1)
		var envelope = sin(PI * progress)
		envelope *= envelope
		var value = sin(float(voice.phase)) * envelope * float(voice.gain)
		if theme in ["tension", "social"] and i >= 2:
			value += sin(float(voice.phase) * 2.0) * envelope * float(voice.gain) * 0.18
		voice.phase = fmod(float(voice.phase) + float(voice.increment), TAU)
		var pan = [-0.1, 0.1, -0.45, 0.45][i]
		result += Vector2(value * (1.0 - pan), value * (1.0 + pan))
	sample_index += 1
	return result
