class_name HamachiConnection
extends RefCounted
## Local-only invitation codec. Never opens sockets, persists or logs input.

const PREFIX = "lagunak:v1"
const MAX_INVITATION_LENGTH = 512
const MIN_PORT = 1024
const MAX_PORT = 65535

static func is_valid_address(address: String) -> bool:
	var parts = address.split(".", true)
	if parts.size() != 4: return false
	var octets: Array[int] = []
	for part in parts:
		if not _decimal(part) or part.length() > 3: return false
		if part.length() > 1 and part.begins_with("0"): return false
		var value = part.to_int()
		if value > 255: return false
		octets.append(value)
	# Unicast endpoint syntax, not a guess about the 25/8 range or netmask.
	# A .0/.255 suffix can be a valid host outside /24 (including a mesh VPN).
	# Reject unspecified, loopback, multicast, reserved and limited broadcast.
	return octets[0] > 0 and octets[0] != 127 and octets[0] < 224

static func is_valid_port(text: String) -> bool:
	if not _decimal(text) or text.length() > 5 or text.begins_with("0"): return false
	return text.to_int() >= MIN_PORT and text.to_int() <= MAX_PORT

static func detect_addresses(interfaces: Array) -> PackedStringArray:
	var found = PackedStringArray()
	for entry in interfaces:
		if not entry is Dictionary: continue
		var identified = false
		for field in ["name", "friendly"]:
			var value = entry.get(field, "")
			if not value is String: continue
			var label: String = value.to_lower()
			if label == "ham0" or label.contains("hamachi"): identified = true
		if not identified: continue
		var addresses = entry.get("addresses", [])
		if not addresses is Array and not addresses is PackedStringArray: continue
		for address in addresses:
			if address is String and is_valid_address(address) and address not in found:
				found.append(address)
	found.sort()
	return found

static func create_invitation(address: String, port: int, key: String) -> String:
	if not is_valid_address(address) or port < MIN_PORT or port > MAX_PORT or not _valid_key(key): return ""
	var invitation = "%s:%s:%d:%s" % [PREFIX, address, port, _encode_key(key)]
	return invitation if invitation.length() <= MAX_INVITATION_LENGTH else ""

static func parse_invitation(text: String) -> Dictionary:
	# Check the bound before trimming, splitting or decoding hostile clipboard data.
	if text.length() > MAX_INVITATION_LENGTH: return _failure("La invitación es demasiado larga. Pide una nueva al anfitrión.")
	var parts = text.strip_edges().split(":", true)
	if parts.size() != 5 or parts[0] != "lagunak" or parts[1] != "v1":
		return _failure("Pega una invitación de Lagunak (lagunak:v1), no un enlace ni los datos de la red VPN.")
	if not is_valid_address(parts[2]): return _failure("La invitación no contiene una IPv4 válida para Hamachi.")
	if not is_valid_port(parts[3]): return _failure("El puerto de la invitación debe ser un entero entre 1024 y 65535.")
	var encoded: String = parts[4]
	if encoded.is_empty() or encoded.length() % 4 == 1: return _failure("La clave de la invitación no es válida. Pide otra invitación.")
	for i in encoded.length():
		var c = encoded.unicode_at(i)
		if not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45 or c == 95):
			return _failure("La clave de la invitación no es válida. Pide otra invitación.")
	var padded = encoded.replace("-", "+").replace("_", "/")
	while padded.length() % 4 != 0: padded += "="
	var bytes = Marshalls.base64_to_raw(padded)
	if not _valid_utf8(bytes): return _failure("La clave de la invitación no es válida. Pide otra invitación.")
	var key = bytes.get_string_from_utf8()
	if not _valid_key(key) or _encode_key(key) != encoded:
		return _failure("La clave de la invitación no es válida. Pide otra invitación.")
	return {"ok": true, "message": "Invitación válida. Elige tu puesto y pulsa Unirse.", "address": parts[2], "port": parts[3].to_int(), "key": key}

static func active_host_port(session: Node) -> int:
	if not is_instance_valid(session) or session.get("mode") != "host" or not session.is_inside_tree(): return 0
	var peer = session.multiplayer.multiplayer_peer
	if not peer is ENetMultiplayerPeer or peer.host == null: return 0
	var port: int = peer.host.get_local_port()
	return port if port >= MIN_PORT and port <= MAX_PORT else 0

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _decimal(text: String) -> bool:
	if text.is_empty(): return false
	for i in text.length():
		var c = text.unicode_at(i)
		if c < 48 or c > 57: return false
	return true

static func _valid_key(key: String) -> bool:
	if key.length() < 8 or key.length() > 128: return false
	for i in key.length():
		var c = key.unicode_at(i)
		if c < 32 or (c >= 127 and c <= 159): return false
	return true

static func _encode_key(key: String) -> String:
	return Marshalls.raw_to_base64(key.to_utf8_buffer()).replace("+", "-").replace("/", "_").replace("=", "")

static func _valid_utf8(bytes: PackedByteArray) -> bool:
	# Validate before Godot's decoder: malformed UTF-8 must not print engine errors.
	var i = 0
	while i < bytes.size():
		var first = bytes[i]
		if first < 128:
			i += 1
			continue
		var length = 0
		var codepoint = 0
		var minimum = 0
		if first >= 194 and first <= 223:
			length = 2; codepoint = first & 31; minimum = 128
		elif first >= 224 and first <= 239:
			length = 3; codepoint = first & 15; minimum = 2048
		elif first >= 240 and first <= 244:
			length = 4; codepoint = first & 7; minimum = 65536
		else: return false
		if i + length > bytes.size(): return false
		for j in range(1, length):
			var next = bytes[i + j]
			if next < 128 or next > 191: return false
			codepoint = (codepoint << 6) | (next & 63)
		if codepoint < minimum or codepoint > 1114111 or (codepoint >= 55296 and codepoint <= 57343): return false
		i += length
	return true
