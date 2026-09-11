class_name SoundCaptionQueue
extends RefCounted
## Local audio cue descriptions, never arbitrary messages or simulation data.

const MAX_VISIBLE = 3
const MAX_REPEATS = 99
const CUES = {
	"confirm": ["[Sonido] Confirmación de la consola", "[Sound] Console confirmation"],
	"pulse": ["[Sonido] Disparo de pulso", "[Sound] Pulse fired"],
	"torpedo": ["[Sonido] Lanzamiento de torpedo", "[Sound] Torpedo launched"],
	"scan": ["[Sonido] Barrido de sensores", "[Sound] Sensor sweep"],
	"arrival": ["[Sonido] Señal de atraque", "[Sound] Docking signal"],
}
var _entries: Array[Dictionary] = []

func clear() -> void:
	_entries.clear()

func expire(now: float) -> bool:
	if not is_finite(now) or now < 0.0: return false
	var previous = _entries.size()
	for index in range(_entries.size() - 1, -1, -1):
		if _entries[index].until <= now: _entries.remove_at(index)
	return previous != _entries.size()

func push(cue: String, now: float, duration: float) -> bool:
	if not CUES.has(cue) or not is_finite(now) or now < 0.0: return false
	if not is_finite(duration) or duration < 2.0 or duration > 12.0: return false
	expire(now)
	var repeats = 1
	for index in _entries.size():
		if _entries[index].cue == cue:
			repeats = mini(MAX_REPEATS, int(_entries[index].repeats) + 1)
			_entries.remove_at(index)
			break
	_entries.append({"cue": cue, "repeats": repeats, "until": now + duration})
	while _entries.size() > MAX_VISIBLE: _entries.pop_front()
	return true

func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

func lines(locale: String = "es") -> PackedStringArray:
	var result = PackedStringArray()
	var language = 1 if locale.to_lower().begins_with("en") else 0
	for entry in _entries:
		var text: String = CUES[entry.cue][language]
		if entry.repeats > 1: text += " × %d" % entry.repeats
		result.append(text)
	return result
