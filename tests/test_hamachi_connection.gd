extends RefCounted

const Connection = preload("res://net/hamachi_connection.gd")

static func verify() -> Dictionary:
	var result = {"checks": 0, "failures": 0}
	for address in ["192.0.2.0", "192.0.2.1", "192.0.2.254", "192.0.2.255", "198.51.100.17"]:
		_check(result, Connection.is_valid_address(address), "documentation unicast accepted")
	for address in ["", "0.0.0.0", "0.1.2.3", "127.0.0.1", "127.9.1.2", "224.0.0.1", "239.1.2.3", "240.0.0.1", "255.255.255.255", "192.0.2", "192.0.2.1.2", "192.0.2.256", "192.00.2.1", " 192.0.2.1", "192.0.2.1 ", "１９２.0.2.1", "192.0.2.+1", "192.0.2.-1", "::1", "::ffff:192.0.2.1", "https://192.0.2.1", "localhost", "192.0.2.1\n"]:
		_check(result, not Connection.is_valid_address(address), "unsafe or noncanonical address rejected")
	for port in ["1024", "27840", "65535"]:
		_check(result, Connection.is_valid_port(port), "port boundary accepted")
	for port in ["", "0", "1023", "65536", "99999999999999", "027840", "27840.0", "+27840", "-27840", "2e4", " 27840", "27840 ", "２７８４０"]:
		_check(result, not Connection.is_valid_port(port), "noncanonical port rejected")
	var detected = Connection.detect_addresses([
		{"name": "eth0", "friendly": "Ethernet", "addresses": ["192.0.2.1"]},
		{"name": "ham0", "addresses": ["192.0.2.2", "::1", "127.0.0.1"]},
		{"name": "device-guid", "friendly": "LogMeIn Hamachi Virtual Ethernet Adapter", "addresses": PackedStringArray(["198.51.100.17", "192.0.2.2"])},
		{"name": "HAMACHI", "addresses": ["192.0.2.3"]},
		{"name": "ham1", "addresses": ["192.0.2.4"]},
		{"name": "Hamachi", "addresses": "192.0.2.5"},
		{"name": 1, "friendly": {}, "addresses": ["192.0.2.6"]}, null
	])
	_check(result, detected == PackedStringArray(["192.0.2.2", "192.0.2.3", "198.51.100.17"]), "only identified Hamachi adapters, IPv4 deduped and sorted")
	_check(result, Connection.detect_addresses([]).is_empty(), "no adapter never invents address")
	# Check the historic 25/8 trap without recording a real address anywhere.
	var unrelated = {"name": "eth0", "addresses": [str(25) + ".0.0.1"]}
	_check(result, Connection.detect_addresses([unrelated]).is_empty(), "25 prefix alone is not a VPN identity")
	var key = "fixture-private-key"
	for value in [key, "clave:con espacios/+=", "contraseña-sintética-🚀", "x".repeat(8), "x".repeat(128)]:
		for port in [1024, 27840, 65535]:
			var invitation = Connection.create_invitation("192.0.2.1", port, value)
			var parsed = Connection.parse_invitation(invitation)
			_check(result, not invitation.is_empty() and parsed.ok and parsed.address == "192.0.2.1" and parsed.port == port and parsed.key == value, "private invitation round trip")
	var good = Connection.create_invitation("198.51.100.17", 27840, key)
	_check(result, Connection.parse_invitation(" \n" + good + "\r\n").ok, "outer paste whitespace accepted within bound")
	for value in ["", "short", "x".repeat(129), "fixture\nkey", "fixture\u007fkey", "fixture\u0085key"]:
		_check(result, Connection.create_invitation("192.0.2.1", 27840, value).is_empty(), "unsafe key cannot be encoded")
	for port in [0, 1023, 65536]:
		_check(result, Connection.create_invitation("192.0.2.1", port, key).is_empty(), "encoder checks port")
	_check(result, Connection.create_invitation("127.0.0.1", 27840, key).is_empty(), "encoder also refuses loopback")
	var hostile = ["", "https://example.invalid/", "javascript:alert(1)", "{\"host\":\"192.0.2.1\"}", "$(touch /tmp/no)", "lagunak:v2:192.0.2.1:27840:abcdefgh", "LAGUNAK:v1:192.0.2.1:27840:abcdefgh", good + ":extra", "x".repeat(513), " ".repeat(513) + good, good.replace("27840", "27840.0"), good.replace("27840", "65536"), good.replace("198.51.100.17", "127.0.0.1"), good.replace("198.51.100.17", "224.0.0.1")]
	for encoded in ["", "A", "====", "a+b/", "YWJjZA", "___________", "wICAgICAgICAgA", "7aCA7aCA7aCA", "9ICAgICAgICAgA", "Zml4dHVyZS1wcml2YXRlLWtleR", "Zml4dHVyZQBrZXk"]:
		hostile.append("lagunak:v1:192.0.2.1:27840:" + encoded)
	for text in hostile:
		var parsed = Connection.parse_invitation(text)
		_check(result, not parsed.ok and not parsed.has("key") and not parsed.has("address") and not str(parsed.message).contains(key), "hostile input rejected without reflecting private values")
	return result

static func _check(result: Dictionary, ok: bool, label: String) -> void:
	result.checks += 1
	if not ok:
		result.failures += 1
		push_error("HAMACHI_CONNECTION_FAIL " + label)
