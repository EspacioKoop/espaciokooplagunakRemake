class_name CosmographyNavigation
extends RefCounted
## Read-only adapter for a validated CosmographyCatalog v1.
## It owns no Atlas, physics, UI, network or persistence state.

const FORMAT := "espaciokoop-cosmography-navigation"
const VERSION := 1
const MAX_CONNECTIONS := 512
const ID_PATTERN := "^[a-z0-9][a-z0-9_-]{0,63}$"
const CONNECTION_KEYS := ["id", "from_id", "to_id", "map_ref", "bidirectional"]

var _catalog: Dictionary = {}
var _navigation: Dictionary = {}
var _nodes: Dictionary = {}

static func create(catalog_data: Variant, navigation_data: Variant) -> Dictionary:
	var catalog_error := CosmographyCatalog.validate(catalog_data)
	if not catalog_error.is_empty():
		return _fail("Catálogo inválido: " + catalog_error)
	var navigation_error := _validate_navigation(catalog_data, navigation_data)
	if not navigation_error.is_empty():
		return _fail(navigation_error)
	var adapter := CosmographyNavigation.new()
	adapter._catalog = catalog_data.duplicate(true)
	adapter._navigation = navigation_data.duplicate(true)
	adapter._nodes = CosmographyCatalog.by_id(adapter._catalog)
	return {"ok": true, "adapter": adapter}

static func _validate_navigation(catalog_data: Dictionary, navigation_data: Variant) -> String:
	if not navigation_data is Dictionary:
		return "Navegación: debe ser un objeto."
	for key in navigation_data.keys():
		if key not in ["format", "version", "connections"]:
			return "Navegación: campo no permitido: " + str(key)
	for key in ["format", "version", "connections"]:
		if not navigation_data.has(key):
			return "Navegación: falta " + key
	if navigation_data.format != FORMAT or int(navigation_data.version) != VERSION:
		return "Navegación: formato o versión no compatible."
	if not navigation_data.connections is Array or navigation_data.connections.size() > MAX_CONNECTIONS:
		return "Navegación: conexiones inválidas o demasiadas."
	var nodes := CosmographyCatalog.by_id(catalog_data)
	var connection_ids: Dictionary = {}
	for index in navigation_data.connections.size():
		var connection = navigation_data.connections[index]
		var path := "connections[%d]" % index
		if not connection is Dictionary:
			return path + ": debe ser un objeto."
		for key in connection.keys():
			if key not in CONNECTION_KEYS:
				return path + ": campo no permitido: " + str(key)
		for key in CONNECTION_KEYS:
			if not connection.has(key):
				return path + ": falta " + key
		for key in ["id", "from_id", "to_id", "map_ref"]:
			if not _valid_id(connection[key]):
				return path + "." + key + ": ID no válido."
		if typeof(connection.bidirectional) != TYPE_BOOL:
			return path + ".bidirectional: debe ser booleano."
		if connection.from_id == connection.to_id:
			return path + ": una conexión no puede volver al mismo nodo."
		if not nodes.has(connection.from_id) or not nodes.has(connection.to_id):
			return path + ": los extremos deben existir en el catálogo."
		for endpoint in [connection.from_id, connection.to_id]:
			if not nodes[endpoint].has("map_ref"):
				return path + ": cada extremo navegable necesita map_ref."
		if connection_ids.has(connection.id):
			return path + ".id: ID de conexión duplicado."
		connection_ids[connection.id] = true
	return ""

static func _valid_id(value: Variant) -> bool:
	if not value is String:
		return false
	var regex := RegEx.new()
	regex.compile(ID_PATTERN)
	return regex.search(value) != null

func markers() -> Array:
	var result: Array = []
	for entry in _catalog.entries:
		if entry.has("map_ref"):
			result.append(_marker(entry))
	return result

func marker(entry_id: String) -> Dictionary:
	if not _nodes.has(entry_id):
		return _fail("El nodo cosmográfico no existe.")
	if not _nodes[entry_id].has("map_ref"):
		return _fail("El nodo cosmográfico no tiene map_ref.")
	return {"ok": true, "marker": _marker(_nodes[entry_id])}

func route(from_id: String, to_id: String) -> Dictionary:
	if not _nodes.has(from_id) or not _nodes.has(to_id):
		return _fail("La ruta necesita nodos existentes.")
	if not _nodes[from_id].has("map_ref") or not _nodes[to_id].has("map_ref"):
		return _fail("La ruta necesita map_ref en sus nodos.")
	var queue: Array = [from_id]
	var previous: Dictionary = {from_id: ""}
	var previous_edge: Dictionary = {}
	while not queue.is_empty():
		var current: String = str(queue.pop_front())
		if current == to_id:
			break
		for connection in _navigation.connections:
			var candidate := ""
			var reverse := false
			if connection.from_id == current:
				candidate = connection.to_id
			elif connection.bidirectional and connection.to_id == current:
				candidate = connection.from_id
				reverse = true
			if candidate.is_empty() or previous.has(candidate):
				continue
			previous[candidate] = current
			var edge: Dictionary = connection.duplicate(true)
			if reverse:
				edge.from_id = current
				edge.to_id = candidate
			previous_edge[candidate] = edge
			queue.append(candidate)
	if not previous.has(to_id):
		return _fail("No existe una ruta entre los nodos seleccionados.")
	var path: Array = []
	var edges: Array = []
	var cursor := to_id
	while not cursor.is_empty():
		path.push_front(cursor)
		if cursor == from_id:
			break
		edges.push_front(previous_edge[cursor].duplicate(true))
		cursor = str(previous[cursor])
	var route_markers: Array = []
	for node_id in path:
		route_markers.append(_marker(_nodes[node_id]))
	return {"ok": true, "from_id": from_id, "to_id": to_id, "path": path, "edges": edges, "markers": route_markers}

func _marker(entry: Dictionary) -> Dictionary:
	var marker := {
		"id": entry.id,
		"type": entry.type,
		"parent_id": str(entry.get("parent_id", "")),
		"name": entry.name.duplicate(true),
		"continuity": entry.continuity,
		"map_ref": entry.map_ref,
		"provenance": entry.provenance.duplicate(true)
	}
	return marker

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
