class_name Telemetry
extends Node
## Opt-in loopback HTTP. Foundry can observe, never issue game commands.
var get_state: Callable
var get_events: Callable
var token = ""
var origin = "http://localhost:30000"
var port = 27841
var enabled = false
var _server = TCPServer.new()
var _clients: Array = []

func start(allowed_origin: String, listen_port: int = 27841) -> String:
	var regex = RegEx.new()
	regex.compile("^https?://[a-zA-Z0-9.\\-\\[\\]:]+$")
	if regex.search(allowed_origin) == null: return "Introduce el origen exacto de Foundry, sin ruta ni barra final."
	if listen_port < 1024 or listen_port > 65535: return "Puerto inválido."
	stop()
	origin = allowed_origin
	port = listen_port
	var error = _server.listen(port, "127.0.0.1")
	if error != OK: return "No se pudo abrir el puerto local de telemetría."
	token = Crypto.new().generate_random_bytes(32).hex_encode()
	enabled = true
	return ""

func stop() -> void:
	_server.stop()
	for client in _clients: client.peer.disconnect_from_host()
	_clients.clear()
	token = ""
	enabled = false

func _process(_delta: float) -> void:
	if not enabled: return
	while _server.is_connection_available():
		var peer = _server.take_connection()
		if _clients.size() >= 8: peer.disconnect_from_host()
		else: _clients.append({"peer": peer, "data": PackedByteArray(), "since": Time.get_ticks_msec()})
	for client in _clients.duplicate():
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - client.since > 2500:
			_finish(client)
			continue
		var available = peer.get_available_bytes()
		if available > 0:
			if client.data.size() + available > 8192:
				peer.get_data(mini(available, 16384))
				_respond(client, 431, {"error": "Headers too large"}, false)
				continue
			var chunk = peer.get_data(available)
			if chunk[0] != OK:
				_finish(client)
				continue
			client.data.append_array(chunk[1])
			var request: String = client.data.get_string_from_utf8()
			if "\r\n\r\n" in request: _request(client, request)

func _request(client: Dictionary, raw: String) -> void:
	var lines = raw.split("\r\n")
	var first = lines[0].split(" ")
	if first.size() != 3 or first[2] != "HTTP/1.1":
		_respond(client, 400, {"error": "Invalid request"}, false)
		return
	var headers: Dictionary = {}
	for line in lines.slice(1):
		if line.is_empty(): break
		var colon = line.find(":")
		if colon < 1:
			_respond(client, 400, {"error": "Invalid header"}, false)
			return
		var name = line.left(colon).strip_edges().to_lower()
		if headers.has(name):
			_respond(client, 400, {"error": "Duplicate header"}, false)
			return
		headers[name] = line.substr(colon + 1).strip_edges()
	var cors = headers.get("origin", "") == origin
	if headers.has("origin") and not cors:
		_respond(client, 403, {"error": "Origin not allowed"}, false)
		return
	if first[0] == "OPTIONS":
		_respond(client, 204, {}, cors)
		return
	if first[0] != "GET":
		_respond(client, 405, {"error": "Read only"}, cors)
		return
	var provided = str(headers.get("authorization", "")).to_utf8_buffer()
	var expected = ("Bearer " + token).to_utf8_buffer()
	if not Crypto.new().constant_time_compare(expected, provided):
		_respond(client, 401, {"error": "Authentication required"}, cors)
		return
	var path: String = first[1]
	if path == "/v1/state":
		_respond(client, 200, get_state.call() if get_state.is_valid() else {}, cors)
	elif path.get_slice("?", 0) == "/v1/events":
		var after = 0
		if "?" in path:
			var query = path.get_slice("?", 1)
			if not query.begins_with("after=") or not query.substr(6).is_valid_int():
				_respond(client, 400, {"error": "Invalid event cursor"}, cors)
				return
			after = maxi(0, int(query.substr(6)))
		var events: Array = get_events.call() if get_events.is_valid() else []
		var selected: Array = []
		for event in events:
			if event.seq > after: selected.append(event)
		_respond(client, 200, {"events": selected, "cursor": events.back().seq if not events.is_empty() else after}, cors)
	else: _respond(client, 404, {"error": "Not found"}, cors)

func _respond(client: Dictionary, status: int, data: Dictionary, cors: bool) -> void:
	var body = JSON.stringify(data).to_utf8_buffer() if status != 204 else PackedByteArray()
	var labels = {200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 431: "Request Header Fields Too Large"}
	var header = "HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n" % [status, labels[status], body.size()]
	if cors: header += "Access-Control-Allow-Origin: " + origin + "\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\nAccess-Control-Allow-Headers: Authorization\r\nAccess-Control-Allow-Private-Network: true\r\n"
	if status == 405: header += "Allow: GET, OPTIONS\r\n"
	client.peer.put_data((header + "\r\n").to_utf8_buffer())
	client.peer.put_data(body)
	_finish(client)

func _finish(client: Dictionary) -> void:
	client.peer.disconnect_from_host()
	_clients.erase(client)
