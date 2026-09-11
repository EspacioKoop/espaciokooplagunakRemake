# Adaptador de lectura cosmográfica y navegación

Esta rebanada añade `CosmographyNavigation`, un adaptador standalone de sólo lectura sobre el contrato `espaciokoop-cosmography` v1 de `CosmographyCatalog`.

## Alcance

- Lee una jerarquía ya validada `plane → star_system → planet` sin duplicar el catálogo.
- Lee conexiones explícitas con `from_id`, `to_id`, `map_ref` y `bidirectional`.
- Expone marcadores de nodos con `map_ref`, continuidad y la `provenance` original de cada entrada.
- Resuelve rutas por identificador mediante BFS, conservando los `map_ref` de las conexiones y los marcadores/procedencia de los nodos.
- Rechaza extremos inexistentes, bucles, IDs inseguros, conexiones duplicadas, dirección con tipo incorrecto y nodos conectados sin `map_ref`.
- Devuelve copias profundas: leer o modificar la respuesta no modifica el catálogo ni las conexiones recibidas.

El adaptador sigue siendo de sólo lectura y no escribe en Atlas, `ExpeditionSystems`, guardados, red, UI ni física. El servicio `CosmographyService` lo consume desde `Session`, persiste la ubicación seleccionada y expone el snapshot a la pestaña Atlas; integrar una ruta en un vuelo jugable requiere todavía un consumidor físico y su propia reserva.

## Documento de navegación v1

```json
{
  "format": "espaciokoop-cosmography-navigation",
  "version": 1,
  "connections": [
    {
      "id": "sol-auri",
      "from_id": "sol",
      "to_id": "auri",
      "map_ref": "route-sol-auri",
      "bidirectional": true
    }
  ]
}
```

`map_ref` es un identificador estable de representación cartográfica; no contiene rutas de filesystem, coordenadas físicas ni una escena concreta. La procedencia se lee del catálogo y no se inventa ni se sustituye en la conexión.

## Canon y HYG

La prueba usa únicamente entradas sintéticas `homebrew` con procedencia `original` de prueba. No descarga HYG, no añade filas de un catálogo externo y no decide una continuidad narrativa. El importador HYG existente queda fuera de esta rebanada: cualquier selección de fuente, licencia o incorporación de datos reales requiere una decisión y revisión separadas.

## Verificación

Desde la raíz del repositorio:

```sh
python3 tests/run_cosmography_navigation.py
```

La suite ejecuta Godot 4 en un proceso headless efímero, cubre jerarquía/rutas directas e inversas, `map_ref`, procedencia, entradas inválidas, destinos desconectados y no mutación del adaptador. No es un viaje jugable completo ni certifica la conexión con la navegación física, la UI o una sesión cooperativa.
