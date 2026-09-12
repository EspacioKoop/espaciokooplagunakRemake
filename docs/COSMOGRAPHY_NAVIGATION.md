# Adaptador de lectura cosmográfica y navegación

Esta rebanada añade `CosmographyNavigation`, un adaptador standalone de sólo lectura sobre el contrato `espaciokoop-cosmography` v1 de `CosmographyCatalog`.

## Alcance

- Lee una jerarquía ya validada `plane → star_system → planet` sin duplicar el catálogo.
- Lee conexiones explícitas con `from_id`, `to_id`, `map_ref` y `bidirectional`.
- Expone marcadores de nodos con `map_ref`, continuidad y la `provenance` original de cada entrada.
- Resuelve rutas por identificador mediante BFS, conservando los `map_ref` de las conexiones y los marcadores/procedencia de los nodos.
- Rechaza extremos inexistentes, bucles, IDs inseguros, conexiones duplicadas, dirección con tipo incorrecto y nodos conectados sin `map_ref`.
- Devuelve copias profundas: leer o modificar la respuesta no modifica el catálogo ni las conexiones recibidas.

El adaptador no escribe en Atlas, `ExpeditionSystems`, guardados, red, UI ni física. La integración de una ruta en un vuelo jugable requiere un consumidor posterior que pertenezca a esos sistemas y su propia reserva.

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

## Versiones y fronteras de validación

`create(catalog_data, navigation_data)` acepta en **ambos** documentos exclusivamente números finitos exactamente iguales a uno: `1` y `1.0`, incluidas sus representaciones JSON equivalentes. Se validan tipos antes de comparar; `TYPE_INT` solo rechazaría JSON válido y `int(version)` aceptaría coerciones o truncamientos inválidos.

Se rechazan booleanos, cadenas, fracciones (también las representables más próximas a uno), versiones distintas, valores no finitos, `null`, arrays y objetos. Falta de versión y documentos malformados también producen un error sin modificar las entradas ni otro adaptador ya creado. Las pruebas comparan equivalencia JSON de marcadores/rutas/procedencia, no identidad literal int/float.

La guarda del catálogo se ejecuta **antes** del validador compartido y sólo cubre esta entrada y la de [persistencia](COSMOGRAPHY_PERSISTENCE.md). `CosmographyCatalog` se reutiliza sin editarlo; no se presenta esta corrección como endurecimiento de todos sus consumidores ni de su importador.

## Canon y HYG

La prueba usa únicamente entradas sintéticas `homebrew` con procedencia `original` de prueba. No descarga HYG, no añade filas de un catálogo externo y no decide una continuidad narrativa. El importador HYG existente queda fuera de esta rebanada: cualquier selección de fuente, licencia o incorporación de datos reales requiere una decisión y revisión separadas.

## Verificación

Desde la raíz del repositorio:

```sh
python3 tools/bootstrap.py
python3 -P tests/run_cosmography_navigation.py
python3 -P -m unittest discover -s tests -p test_cosmography_contract_runners.py -f -v
```

La suite ejecuta el editor oficial Godot 4.7.1 en modo headless. Conserva todas las pruebas de jerarquía/rutas directas e inversas, `map_ref`, procedencia, entradas inválidas y destinos desconectados; añade versiones estrictas, JSON round-trip y aislamiento de copias. Su mínimo actual es 222 comprobaciones.

Comparte el [arnés aislado de persistencia](COSMOGRAPHY_PERSISTENCE.md#verificación-reproducible): proyecto temporal sin autoloads, `HOME`/XDG temporales, precargas y compilación sin editor/importación de recursos, timeout acotado, logs persistentes y validación de todas las aserciones/marcador/código de salida. Se puede indicar `--godot /ruta/al/godot`, `--output-dir` o la variable `GODOT`. El modo `--negative-control` añade un fallo **después** de la suite completa y debe devolver 1; los controles Python lo ejecutan realmente y rechazan regresiones de versión mediante mutaciones de los componentes en copias temporales.

La CI aditiva [cosmography-contracts.yml](../.github/workflows/cosmography-contracts.yml) ejecuta ambas suites nativas y esos controles en PR, push de main y lanzamiento manual; no reemplaza la canónica. Las ejecuciones locales y remotas se acreditan por separado. No es un viaje jugable completo ni certifica la conexión con navegación física, UI, sesión cooperativa o playtest humano.
