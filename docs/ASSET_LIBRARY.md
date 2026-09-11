# Biblioteca visual de modelos 3D

**Una ficha y una fotografía real por modelo.** [JSON para agentes](asset_library.json) · [Protocolo y formato](asset_library/CONTRIBUTING.md) · [Registro permanente #52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52).

Este inventario contiene **99 fichas con imagen individual**, obtenidas de archivos reales y referencias Git fijas. No cuenta propuestas sin binarios. Un archivo en main no implica una nueva mecánica ni una release.

## Elegir colección

| Colección | Fichas con foto | Disponibilidad de archivos |
| --- | ---: | --- |
| [Itsaso · modelos base](asset_library/base.md) | 20 | En main al inventariar |
| [Ocio · seis entornos](asset_library/leisure.md) | 6 | En main al inventariar |
| [Guardianes del recuerdo](asset_library/memory.md) | 3 | En main al inventariar |
| [Órbita · industria y robótica](asset_library/orbita.md) | 12 | En main al inventariar |
| [Órbita · equipo y apoyo](asset_library/orbita_player_support.md) | 10 | En main al inventariar |
| [Frontera · expedición](asset_library/frontier.md) | 24 | En main al inventariar |
| [Fieldkit · herramientas de jugador](asset_library/fieldkit.md) | 10 | En main al inventariar |
| [Itsasargi · equipo y naves](asset_library/itsasargi.md) | 10 | Rama de entrega; revisar PR |
| [Bizi · dos planetas HABITABLES](asset_library/bizi.md) | 4 | Rama de entrega; revisar PR |

## Buscar por categoría

[Herramientas · 20](asset_library/categories/tools.md)  
[Armas ficticias · 10](asset_library/categories/weapons.md)  
[Naves · 15](asset_library/categories/ships.md)  
[Avatares y tripulación · 6](asset_library/categories/avatars.md)  
[Enemigos y drones · 5](asset_library/categories/enemies.md)  
[Planetas y lunas · 13](asset_library/categories/planets.md)  
[Entornos e interiores · 13](asset_library/categories/environments.md)  
[Utilería e infraestructura · 17](asset_library/categories/props.md)  

## Cómo leer las fichas

Cada ID conserva colección y nombre. La ficha enlaza la fuente `.blend`, el GLB, el manifiesto y la escena o guía disponibles. Incluye escala/ejes, dimensiones declaradas, materiales, anclajes, clips y limitaciones. Los planetas **HABITABLES** distinguen representación orbital y superficie; dos representaciones no se cuentan como dos mundos.

Las fotos existentes se enlazan por revisión inmutable; las que faltaban se renderizan importando el GLB entregado. No se ejecutan constructores ni se sobrescriben fuentes de Blender. Los submodelos de ocio y guardianes mantienen su GLB compartido y se fotografían por separado.

**Disponibilidad, validación e integración son campos distintos.** Este catálogo comprueba archivos, hashes, GLB y fotografías; las pruebas jugables siguen en cada PR. No concede daño, IA, inventario, vuelo o misiones a un modelo por tener una imagen.

## Para agentes

Leer `docs/asset_library.json` (formato `espaciokoop-asset-library`, versión 2). `assets` contiene fichas normalizadas; `packs` identifica colecciones; `manifest` apunta a la autoridad de metadatos; `revision` fija los archivos consumidos. `preview` identifica imagen, origen y dimensiones. Los prefijos documentales de recursos antiguos no renombran APIs.

```sh
python tools/asset_library/catalogue.py --check
python -m unittest discover -s tests/asset_library -v
# Refrescar deliberadamente después de traer las ramas:
python tools/asset_library/catalogue.py --refresh --render-missing
```

El comando de refresco actualiza documentación derivada, nunca el estado del juego. [Reglas para añadir modelos y preservar sus fotos](asset_library/CONTRIBUTING.md).

## Pendientes, sin fingir una entrega

Todas las colecciones incluidas en este corte tienen recursos y fotografías. Las colecciones aún no registradas deben incorporarse con su manifiesto y reserva.

Inventario referido a `main@9e2401d7dcb4719dc831fd84093a6f9640453687`; las revisiones de cada entrega están en [sources.lock.json](asset_library/sources.lock.json). [Índice anterior conservado](asset_library/LEGACY_INDEX.md). No cerrar #52 al integrar esta actualización.
