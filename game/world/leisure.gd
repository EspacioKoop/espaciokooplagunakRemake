class_name LeisurePlaces
extends RefCounted

const MODELS = ["cantina", "museum_hall", "beach", "terrace", "studio", "memories_hall"]
const BOOK_PAGES = [
 {"title": "Una nave, muchas miradas", "text": "Este cuaderno acompaña el viaje de la Itsaso. En un museo podemos dar una vuelta completa a una forma y descubrir algo que desde la entrada no se veía. La exploración espacial comienza de la misma manera: cambiar de posición y volver a mirar."},
 {"title": "Objeto e interpretación", "text": "Las esculturas de esta sala son estudios estilizados nuevos. Sus nombres recuerdan obras conocidas, pero sus mallas se han modelado para este juego. Una cartela debe permitir distinguir una obra, una copia, un escaneo y una interpretación. Aquí encontrarás la naturaleza de cada pieza."},
 {"title": "La materia y la luz", "text": "La piedra clara recoge la luz cálida de las vitrinas y la luz azul del recinto. Camina entre los pedestales y observa cómo cambia una silueta. En el estudio puedes comparar distintas iluminaciones; en la playa, el mismo recorrido cambia con el viento y el reflejo del agua."},
 {"title": "Cartas del mar", "text": "La orilla es el límite de esta excursión. Sigue el paseo hasta la cabina para regresar a la cantina. El reloj y los aerogeneradores comparten el ritmo de la escena. Puedes detener el movimiento decorativo desde Ajustes sin perder ninguna interacción."},
 {"title": "Lo que vuelve con nosotros", "text": "Las decisiones, los descubrimientos y los rescates de la expedición se conservan en la campaña. El pasillo de recuerdos invita a detenerse antes de volver al puente. Cuando quieras continuar, las puertas de la cantina te llevarán de vuelta a la nave."}
]

static func exhibits() -> Array:
 var document = JSON.parse_string(FileAccess.get_file_as_string("res://data/museum.json"))
 return document.get("exhibits", []) if document is Dictionary else []

static func interactions(zone: int) -> Array:
 var result: Array = []
 if zone == 8:
  for piece in exhibits():
   result.append({"id": piece.id, "kind": "plaque", "title": piece.title, "position": Vector3(piece.position[0], 0, piece.position[2]), "text": piece.text})
  result.append({"id": "museum_book", "kind": "book", "title": "Leer el libro del museo", "position": Vector3(5, 0, 25.6)})
  for i in 5:
   result.append({"id": "painting_%d" % i, "kind": "plaque", "title": "Paisaje geométrico %d" % (i + 1), "position": Vector3(-16, 0, -20 + i * 10), "text": "Composición nueva de relieves geométricos realizada en Blender. Forma, color y luz se construyen con mallas; esta pieza no reproduce una pintura histórica."})
 elif zone == 9:
  result.append({"id": "beach_lion", "kind": "plaque", "title": "León de la orilla", "position": Vector3(2, 0, -29.5), "text": "Estudio nuevo y estilizado del motivo del león de Al-Lāt, modelado en Blender. Esta escultura de juego comparte su interpretación con el museo; no es el modelo histórico ni un escaneo."})
 elif zone in [7, 10]:
  var seats = [Vector3(-5, 0, 1.8), Vector3(5, 0, 1.8), Vector3(-5, 0, 7.8), Vector3(5, 0, 7.8)] if zone == 7 else [Vector3(-6, 0, -4), Vector3(-2, 0, -4), Vector3(3, 0, 3), Vector3(7, 0, 3)]
  for i in seats.size(): result.append({"id": "seat_%d_%d" % [zone, i], "kind": "seat", "title": "Sentarse", "position": seats[i] + Vector3(0, 0, 0.85), "seat": seats[i]})
  if zone == 7:
   for i in 3:
    result.append({"id": "table_" + ["poker", "blackjack", "dados"][i], "kind": "table", "table": ["poker", "blackjack", "dados"][i], "title": ["Jugar al póker", "Jugar al blackjack", "Jugar a los dados"][i], "position": [Vector3(-5, 0, -1.8), Vector3(5, 0, -1.8), Vector3(-5, 0, 4.2)][i]})
  if zone == 10: result.append({"id": "fishing", "kind": "plaque", "title": "Mirador de la caña", "position": Vector3(10, 0, -8), "text": "Un asiento junto al horizonte. El aparejo forma parte del mirador; este punto no concede recursos de la nave."})
 elif zone == 11: result.append({"id": "studio_lights", "kind": "lights", "title": "Cambiar iluminación del estudio", "position": Vector3(0, 0, -1)})
 elif zone == 12:
  result = MemoryCatalog.interactions()
 return result
