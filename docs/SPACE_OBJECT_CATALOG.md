# Catálogo de objetos espaciales

Este subcarril cubre las **cuatro plantillas de estación** declaradas en
`EspacioKoop/espaciokooplagunak` en el commit
`fecd0740545f485d2402c6dfe4b47d5a859cb96c`,
`scripts/shiptemplates/stations.lua`. No copia Lua, meshes ni texturas del
original. La reimplementación vive en
`game/data/space_object_templates.json` y la valida
`game/core/space_object_catalog.gd`.

## Estado verificable

| ID nativo | Original | Perfil reescrito | Recurso visual propio consumido por runtime | Decisión |
| --- | --- | --- | --- | --- |
| `small_station` | Small Station | casco 150 · escudo `[300]` | `orbita/docking_collar` | incluido |
| `medium_station` | Medium Station | casco 400 · escudo `[800]` | `base/station` | incluido |
| `large_station` | Large Station | casco 500 · escudos `[1000,1000,1000]` | `orbita/solar_array` | incluido |
| `huge_station` | Huge Station | casco 800 · escudos `[1200,1200,1200,1200]` | `base/station` | incluido |

Los recursos visuales están allowlistados en `runtime_asset_library.json` y
son recursos propios del remake. `SpaceView` sólo muestra el modelo cuando el
contacto está identificado, respetando la redacción existente. La biblioteca
de assets del ejecutable también los puede previsualizar sin convertir un ID
en una ruta de fichero.

## Ruta de producción

1. `game/data/campaign.json` asigna una plantilla y un `visual_model` a la
   estación de cada una de las seis misiones.
2. `Catalog.validate_mission`, que ya utiliza el editor de misiones al aplicar,
   abrir y guardar JSON, delega la validación de `space_object_template` y de
   la compatibilidad visual en `SpaceObjectCatalog`.
3. `Simulation` conserva esos campos en el contacto runtime.
4. `SpaceView` resuelve el modelo exclusivamente a través de
   `RuntimeAssetLibrary.contact_model`.
5. `LocalStorage` conserva y recarga la referencia en el estado de partida.

`contact_from_template()` permite a código de preparación crear un contacto
válido sin duplicar las reglas de IDs, tipo, radio visual o recurso allowlistado.

## Límites deliberados

- Esto completa el catálogo de estaciones como contenido authored + visual y
  conserva la jugabilidad ya existente de contactos `station` (atraque,
  reparación y colisión). `Simulation` sigue usando su envolvente de colisión
  común y el porcentaje de casco del contacto para daño: `hull_capacity` y
  `shield_quadrants` quedan preservados como metadatos de plantilla, pero no se
  presentan como una nueva autoridad de durabilidad. No se declara equivalencia
  completa de la economía/combate de estaciones.
- `Defense platform` se **excluye** explícitamente en el JSON de decisiones:
  el original exige seis sectores de escudo, clases de atraque y torretas con
  orientación independiente. Reducirlo a una estación normal sería una
  pérdida de comportamiento, así que permanece pendiente/no producto de este
  subcarril.
- No se toca `game/data/ship_templates.json`, `ship_template_catalog.gd` ni
  `ship_design_editor.gd`: las 38 variantes del PR #25 quedan intactas y no se
  vuelven a contar. Tampoco se modifica la rama ni los archivos documentales
  del PR #78.
- Los libros, hitos/trofeos, bestiario, inventario de evidencias y Atlas tienen
  carriles separados; este catálogo no los marca como cubiertos.

## Pruebas

Desde la raíz del repositorio:

```text
python3 tests/run_space_object_catalog.py
```

La prueba usa Godot y las rutas de producción reales para comprobar el contrato
JSON, los cuatro recursos visuales, el rechazo de referencias incompatibles,
la importación/aplicación/guardado del `MissionEditor`, el arranque de una
`Simulation` y el round-trip de `LocalStorage`. También vuelve a validar las
seis misiones integradas. `tests/test_space_object_catalog.py` cubre además el
contrato offline y confirma que las 38 entradas de naves del PR #25 no se han
duplicado.
