# Biblioteca 3D compartida

**Punto de encuentro permanente: [issue #52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52).**

Este documento permite localizar fuentes editables, exportaciones y entregas sin depender del historial de un chat. El índice legible por herramientas es [`asset_library.json`](asset_library.json). Las reservas de archivos siguen en [#7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7), no en este documento. **No cerrar #52 al integrar un pack.**

## Antes de crear o utilizar un modelo

Consulta `AGENTS.md`, #7 y el manifiesto del pack. Reutiliza el recurso existente por su identificador y ruta en vez de copiar su geometría a otra carpeta. Reserva sólo las rutas de la nueva entrega; las fuentes y manifiestos de otros packs no se modifican sin coordinación. Cada pack se entrega mediante rama y PR. La presencia de un GLB no implica que esté conectado a una mecánica.

## Dónde está cada colección

| Colección | Estado documentado | Fuente editable | Recursos de ejecución | Guía / seguimiento |
| --- | --- | --- | --- | --- |
| Base Itsaso | Incluida en `main` al inventariar | [`lagunak_assets.blend`](../art/blender/lagunak_assets.blend) | Veinte GLB individuales, [`manifest.json`](../game/assets/models/manifest.json) | [Autoría](AUTHORING.md) |
| Museo y ocio | Incluida en `main` al inventariar | [`leisure_assets.blend`](../art/blender/leisure_assets.blend) | [`leisure_bundle.glb`](../game/assets/models/leisure_bundle.glb), seis grupos | [Autoría](AUTHORING.md) |
| Guardianes del recuerdo | Incluida en `main` al inventariar | [`memory_guardians.blend`](../art/blender/memory_guardians.blend) | [`memory_guardians.glb`](../game/assets/models/memory_guardians.glb), tres grupos; [manifiesto](../game/assets/models/memory_guardians.manifest.json) | [Entrega #17](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/17) |
| Frontera | Trabajo independiente registrado en #41; consultar allí su PR/estado actual | Ruta reservada `art/blender/frontier_pack/` | Ruta reservada `game/assets/models/frontier_pack/` | [Issue #41](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/41) |
| Órbita | Entrega de biblioteca, no integración automática en campaña; evidencia de importación en PR/CI de #52 | [Doce fuentes](../art/blender/orbita_pack/) | [Doce GLB y manifiesto](../game/assets/models/orbita_pack/) | [Catálogo y galería](ORBITA_ASSET_PACK.md), [#52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52) |

La referencia del inventario original es `8b1dcf27683a00972b03d5203606eab12f31fe2d`. No se atribuyen los packs nuevos a los binarios publicados de 0.9.1. Un pack que sólo esté en una rama/PR debe consumirse desde esa revisión hasta su integración autorizada.

### Base: modelos individuales

**Naves y espacio:** `itsaso`, `transport`, `sentinel`, `station`, `planet`, `asteroid`, `anomaly`, `beacon`.

**Tripulación y utilería:** `crew`, `chair`, `console`, `crate`, `reactor`.

**Interiores:** `bridge_room`, `engineering_room`, `quarters_room`, `cargo_room`, `mess_room`, `medbay_room`, `hallway`.

Todos se localizan como `res://assets/models/<nombre>.glb`. El planeta base utiliza además la representación de superficie del proyecto; no confundirlo con los mundos autocontenidos del pack Órbita. Los prefijos `base/`, `leisure/` y `memory/` del índice nuevo son identificadores documentales; **no cambian nombres, escenas ni APIs existentes**.

### Conjuntos con varios grupos

`leisure_bundle.glb`: `museum_hall`, `cantina`, `terrace`, `studio`, `memories_hall`, `beach`. Usar el consumidor existente y conservar los nombres de las piezas animadas.

`memory_guardians.glb`: `memory_keeper`, `memory_sentinel`, `memory_prism`. Son objetos de galería; no implican IA enemiga ni un esqueleto de avatar. El prefijo `memory/` evita confundir estos guardianes con `base/sentinel`.

### Órbita: especialización industrial y robótica

| ID estable | Uso visual previsto |
| --- | --- |
| `orbita/karramarro_tug` | Remolcador industrial, recuperación y tráfico de estación |
| `orbita/erlea_miner` | Nave minera y convoy de extracción |
| `orbita/pulse_turret` | Torreta de pulso de ciencia ficción, montaje visual |
| `orbita/containment_projector` | Proyector ficticio de campo, equipo o elemento de misión |
| `orbita/technician_robot` | Tripulante/NPC robótico técnico |
| `orbita/medic_robot` | Tripulante/NPC robótico sanitario |
| `orbita/lapa_drone` | Enemigo robótico terrestre de seis patas |
| `orbita/aingira_probe` | Sonda hostil segmentada |
| `orbita/harri_moon` | Luna con cráteres para representación espacial |
| `orbita/eraztun_giant` | Gigante bandeado con anillos |
| `orbita/docking_collar` | Módulo de atraque e infraestructura |
| `orbita/solar_array` | Satélite o módulo de paneles solares |

Estos usos son propuestas para los consumidores, no mecánicas implementadas. Los modelos no incluyen daño, reglas, red, colisiones, LOD, IA ni superficies planetarias caminables. Los robots tienen jerarquía rígida articulada, no rig humano para retargeting ni ciclo de caminar. El visor aislado permite probar los modelos sin modificar la campaña.

## Registro de una entrega

Cada modelo o revisión debe aportar: ID estable y versión, categoría, imagen real del modelo, `.blend`, GLB/escena, licencia y procedencia, escala/ejes/origen, materiales, puntos de anclaje, animaciones y límites. Su manifiesto guarda hashes y medidas obtenidas de los archivos, no valores estimados a mano.

Estados que no deben confundirse:

- **Propuesto/reservado:** no se considera disponible; enlazar issue y CLAIM.
- **Exportado:** archivos presentes y comprobados; publicar su revisión exacta.
- **Importado/verificado:** prueba de importación y del consumidor real, con comandos y resultados.
- **Integrado en mecánica:** consumidor jugable conectado y probado; enlazar la entrega correspondiente. Este estado no lo concede un render.

Usa este bloque en un comentario de #52, acompañado de PR y evidencia:

```text
ASSET id=<pack/id> version=<n> category=<tipo>
source=<.blend> runtime=<GLB/escena> preview=<imagen>
scale=<unidades> axes=<ejes> pivot=<origen>
materials=<...> sockets=<...> animations=<...>
license=<...> provenance=<...>
status=<exportado/importado/integrado> validation=<comando+resultado>
pr=<#N> known_limits=<...>
```

La PR referencia `Refs #52`, nunca `Closes #52`. Antes de sustituir un recurso existente, verifica consumidores, anclajes, escala y guardados; no renombres IDs publicados sin migración. Para packs en curso, enlaza el issue en lugar de fingir un manifiesto disponible. El índice global apunta a los manifiestos de cada pack y **no duplica sus hashes ni se convierte en otra autoridad de estado del juego**.

## Conservar el trabajo de Blender

El `.blend` editado es la fuente de verdad. Ejecuta su **exportador**, no su constructor procedural, después de cambios manuales. En Órbita el constructor aborta por defecto si existen fuentes, `--missing-only` sólo crea las ausentes y `--force` reemplaza expresamente el trabajo. El exportador combina piezas estáticas únicamente en memoria para generar el GLB y no guarda sobre la fuente.

Los recursos propios se publican bajo la licencia MIT del repositorio. No incorporar retratos, recuerdos privados, secretos, credenciales ni metadatos personales. No se necesita conexión a un servicio externo para abrir, editar o utilizar los modelos descargados.
