class_name Telemetry
extends Node
## Opt-in loopback transport. v1 is public read-only; v2 requires host-issued delegation.
const MAX_HEADERS = 8192
const MAX_BODY = 2048
var get_state: Callable
var get_events: Callable
var token = ""
var origin = "http://localhost:30000"
var port = 27841
var enabled = false
var authority: FoundryAuthority
var _panel: FoundryAccessPanel
var _server = TCPServer.new()
var _clients: Array = []

func _ready() -> void:
	authority = FoundryAuthority.new(get_tree().root.get_node_or_null("Session"))

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
	if DisplayServer.get_name() != "headless" and "--test" not in OS.get_cmdline_user_args(): call_deferred("open_access_panel")
	return ""

func open_access_panel() -> void:
	if not enabled or authority.session == null or authority.session.mode == "client": return
	if not is_instance_valid(_panel):
		_panel = FoundryAccessPanel.new()
		add_child(_panel)
		_panel.setup(self)
	_panel.popup_centered()

func stop() -> void:
	_server.stop()
	for client in _clients: client.peer.disconnect_from_host()
	_clients.clear()
	if authority != null: authority.clear()
	if is_instance_valid(_panel): _panel.hide()
	token = ""
	enabled = false

func _process(_delta: float) -> void:
	if not enabled: return
	# Remove delegations as soon as a role/connection/run changes, even if the
	# identity returns to its earlier role before its next HTTP request.
	if authority != null: authority.grants()
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
			if client.data.size() + available > MAX_HEADERS + MAX_BODY:
				peer.get_data(mini(available, 16384))
				_respond(client, 431, {"error": "Request too large"}, false)
				continue
			var chunk = peer.get_data(available)
			if chunk[0] != OK: _finish(client); continue
			client.data.append_array(chunk[1])
			_consume(client)

func _consume(client: Dictionary) -> void:
	var raw: String = client.data.get_string_from_utf8()
	var end = raw.find("\r\n\r\n")
	if end < 0:
		if client.data.size() > MAX_HEADERS: _respond(client, 431, {"error": "Headers too large"}, false)
		return
	var header_bytes = raw.left(end + 4).to_utf8_buffer().size()
	if header_bytes > MAX_HEADERS: _respond(client, 431, {"error": "Headers too large"}, false); return
	var lines = raw.left(end).split("\r\n")
	var first = lines[0].split(" ")
	if first.size() != 3 or first[2] != "HTTP/1.1": _respond(client, 400, {"error": "Invalid request"}, false); return
	var headers: Dictionary = {}
	for line in lines.slice(1):
		var colon = line.find(":")
		if colon < 1: _respond(client, 400, {"error": "Invalid header"}, false); return
		var name = line.left(colon).to_lower()
		if name != name.strip_edges() or headers.has(name): _respond(client, 400, {"error": "Duplicate or invalid header"}, false); return
		headers[name] = line.substr(colon + 1).strip_edges()
	if headers.get("host", "") not in ["127.0.0.1:%d" % port, "localhost:%d" % port]: _respond(client, 403, {"error": "Host not allowed"}, false); return
	var cors = headers.get("origin", "") == origin
	if headers.has("origin") and not cors: _respond(client, 403, {"error": "Origin not allowed"}, false); return
	if headers.has("transfer-encoding"): _respond(client, 400, {"error": "Chunked requests unsupported"}, cors); return
	var length_text: String = headers.get("content-length", "0")
	if length_text.is_empty() or length_text.length() > 5 or not length_text.is_valid_int() or str(int(length_text)) != length_text: _respond(client, 400, {"error": "Invalid body length"}, cors); return
	var length = int(length_text)
	if length > MAX_BODY: _respond(client, 413, {"error": "Body too large"}, cors); return
	if first[0] != "POST" and length != 0: _respond(client, 400, {"error": "Unexpected body"}, cors); return
	if client.data.size() < header_bytes + length: return
	if client.data.size() != header_bytes + length: _respond(client, 400, {"error": "Unexpected trailing bytes"}, cors); return
	if first[0] == "OPTIONS": _respond(client, 204, {}, cors); return
	var path: String = first[1]
	if path.begins_with("/v2/"):
		_request_v2(client, first[0], path, headers, client.data.slice(header_bytes).get_string_from_utf8(), cors)
		return
	if first[0] != "GET": _respond(client, 405, {"error": "Read only"}, cors); return
	var provided = str(headers.get("authorization", "")).to_utf8_buffer()
	var expected = ("Bearer " + token).to_utf8_buffer()
	if not Crypto.new().constant_time_compare(expected, provided): _respond(client, 401, {"error": "Authentication required"}, cors); return
	if path == "/v1/state":
		_respond(client, 200, FoundryProjection.state(get_state.call()) if get_state.is_valid() else {}, cors)
	elif path.get_slice("?", 0) == "/v1/events":
		var after = 0
		if "?" in path:
			var query = path.get_slice("?", 1)
			var cursor = query.substr(6)
			if not query.begins_with("after=") or not cursor.is_valid_int() or cursor.length() > 10 or int(cursor) < 0 or str(int(cursor)) != cursor or path.count("?") != 1:
				_respond(client, 400, {"error": "Invalid event cursor"}, cors); return
			after = int(cursor)
		_respond(client, 200, FoundryProjection.events(get_events.call() if get_events.is_valid() else [], after), cors)
	else: _respond(client, 404, {"error": "Not found"}, cors)

func _request_v2(client: Dictionary, method: String, path: String, headers: Dictionary, body: String, cors: bool) -> void:
	if method not in ["GET", "POST"]: _respond(client, 405, {"error": "Method not allowed"}, cors); return
	var bearer: String = headers.get("authorization", "")
	var grant: Dictionary = authority.authenticate(bearer.substr(7) if bearer.begins_with("Bearer ") else "", headers.get("x-lagunak-user", ""))
	if grant.is_empty(): _respond(client, 401, {"error": "User access expired or invalid"}, cors); return
	if method == "GET" and path == "/v2/view":
		_respond(client, 200, authority.view(grant), cors)
	elif method == "POST" and path == "/v2/command":
		if headers.get("content-type", "") != "application/json": _respond(client, 415, {"error": "JSON required"}, cors); return
		var parser = JSON.new()
		if parser.parse(body) != OK: _respond(client, 400, {"error": "Invalid JSON"}, cors); return
		var result = authority.dispatch(grant, parser.data)
		_respond(client, result.status, result.body, cors)
	else: _respond(client, 404, {"error": "Not found"}, cors)

func _respond(client: Dictionary, status: int, data: Dictionary, cors: bool) -> void:
	var body = JSON.stringify(data).to_utf8_buffer() if status != 204 else PackedByteArray()
	var labels = {200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 413: "Payload Too Large", 415: "Unsupported Media Type", 429: "Too Many Requests", 431: "Request Header Fields Too Large"}
	var header = "HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n" % [status, labels[status], body.size()]
	if cors: header += "Access-Control-Allow-Origin: " + origin + "\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Authorization, X-Lagunak-User, Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\n"
	if status == 405: header += "Allow: GET, POST, OPTIONS\r\n"
	client.peer.put_data((header + "\r\n").to_utf8_buffer())
	client.peer.put_data(body)
	_finish(client)

func _finish(client: Dictionary) -> void:
	client.peer.disconnect_from_host()
	_clients.erase(client)
