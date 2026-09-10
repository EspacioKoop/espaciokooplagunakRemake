# Órbita — equipo de jugador y naves de apoyo

Segunda tanda de modelos reales de la PR #54. Registro permanente: [biblioteca #52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52). Se conserva por separado el pack original de doce modelos. Este lote añade **seis herramientas, dos armas de ciencia ficción y dos naves**, diez fuentes Blender y diez GLB; el visor conjunto muestra 22 recursos.

No es arte conceptual generado. Las previsualizaciones técnicas del repositorio proceden de reimportar los GLB entregados en Blender o de ejecutar Godot. El estado de pruebas y de integración de la rama se registra con el SHA en la PR, no por anticipado aquí.

## Catálogo

| ID (prefijo `orbita/`) | Modelo | Uso previsto del recurso |
| --- | --- | --- |
| `argi_worklight` | Argi · lámpara magnética | Iluminación portátil, asa, base magnética y cabezal orientable. |
| `lagin_sampler` | Lagin · recolector geológico | Muestreo, sonda extensible y carrusel de recipientes. |
| `babes_shield` | Babes · escudo desplegable | Emisor de protección ficticio con pétalos y puntos para efectos. |
| `oreka_gravity_tool` | Oreka · manipulador gravitatorio | Interacción ficticia con objetos; pinzas y núcleo de campo. |
| `izpi_binoculars` | Izpi · prismáticos multiespectrales | Observación; objetivos extensibles, ocular y correa. |
| `arnasa_eva_pack` | Arnasa · mochila de soporte EVA | Equipo de espalda, depósitos, máscara, arnés y manguera. |
| `uhina_arc_emitter` | Uhina · emisor de arco | Arma visual de raíles abiertos, celda, culata y dos agarres. |
| `ezpal_coil_dispenser` | Ezpal · dispersor de bobinas | Arma visual de tres emisores con carrusel articulado. |
| `kimu_survey_ship` | Kimu · exploradora cartográfica | Nave con alas barridas, antena móvil y montajes científicos. |
| `balea_rescue_ship` | Balea · nave de evacuación | Nave con seis cápsulas, brazos de recuperación y atraque dorsal. |

Los diseños no duplican los reservados en el pack Fieldkit: éste prepara su propio equipo de hackeo/gancho/escáner/reparación/cortador/botiquín, carabina/pistola y lanzadera/corbeta. Las rutas y fuentes de ambos lotes son independientes.

## Archivos y reutilización

- Fuentes editables: `art/blender/orbita_pack/player_batch/<nombre>.blend`.
- GLB: `game/assets/models/orbita_pack/player_batch/<nombre>.glb`.
- Manifiesto de esta tanda: `game/assets/models/orbita_pack/player_batch/manifest.json`. Es la autoridad de hashes, triángulos, dimensiones, anclajes y animaciones.
- Contrato de los diez diseños: `art/blender/orbita_pack/player_batch/catalog.json`.
- Visor conjunto: `game/asset_lab/orbita_pack/player_batch.tscn`.
- El manifiesto y las fuentes de los doce originales permanecen independientes y no se sustituyen.

```gdscript
var asset := preload("res://assets/models/orbita_pack/player_batch/oreka_gravity_tool.glb").instantiate()
add_child(asset)
var grip := asset.find_child("socket_grip", true, false) as Node3D
var effect := asset.find_child("socket_effect", true, false) as Node3D
```

Para un montaje exacto, calcular el transform del anclaje relativo a la raíz del modelo y multiplicar por su inversa. No asumir que el centro de la malla es la empuñadura. El visor incluye esa operación en `_place_attachment()`. Los nombres `socket_*` son únicos dentro de cada GLB; la ruta glTF del manifiesto no se promete como NodePath relativa de Godot.

## Inspección dentro de Godot

Abrir `game/asset_lab/orbita_pack/player_batch.tscn` y ejecutar con F6. El selector contiene los 22 modelos: los doce originales y los diez nuevos. Órbita/zoom y animación conservan el visor previo. **Anclaje a escala 1:1** elimina el escalado de exposición y alinea el punto de mano o espalda exportado. No se ofrece esta opción para naves u otros modelos sin contrato de equipo.

```sh
.toolchain/godot --path game res://asset_lab/orbita_pack/player_batch.tscn
```

## Fuente Blender y exportación segura

Blender 4.5.3 LTS o Python 3.11 con `bpy==4.5.3`; se reutilizan los helpers geométricos y de exportación del primer pack. No se copian modelos del original ni se descargan texturas.

```sh
# Sólo construye las fuentes ausentes; preserva todos los .blend existentes.
python art/blender/orbita_pack/player_batch.py build
# Tras editar y guardar un .blend de esta tanda:
python art/blender/orbita_pack/player_batch.py export --render
# Alternativa con Blender instalado:
blender -b --python art/blender/orbita_pack/player_batch.py -- export --render
# Verificación sin Blender:
python tests/orbita_pack/validate_player_batch.py
# Pruebas e inspección real en Godot:
python tests/orbita_pack/run_player_batch.py
```

`build --force` reconstruye sólo las diez fuentes de esta tanda y pierde sus cambios manuales; no usar para una reexportación. El exportador trabaja en memoria, no guarda encima de las fuentes y comprueba sus hashes después. La optimización agrupa piezas estáticas por padre y conserva los pivotes animados y anclajes.

## Contrato y límites

Una unidad es un metro; +Y arriba y -Z frente en Godot. Cada objeto tiene un origen de autoría y puntos de montaje explícitos. El modo de exposición normaliza el tamaño sólo para mirar; los GLB conservan sus medidas. Materiales PBR con color, metal, rugosidad y emisión, sin texturas externas. Articulación rígida con un `mechanical_cycle` por modelo; no se incluyen manos, rig humano ni retargeting.

Los nombres expresan la función futura de cada diseño. **No se añaden daño, disparo, escudos, inventario, oxígeno, luz dinámica, IA, físicas, colisiones ni red**. El consumidor debe conectar esas mecánicas y escoger colisiones simples/LOD según el uso. Las naves son exteriores, no interiores caminables. El visor y los puntos de agarre sí son utilizables en esta entrega. Geometría original bajo MIT; sin datos personales ni retratos.

## Verificación reproducible

La CI conserva los doce originales, construye/exporta los diez nuevos, verifica la distribución 6+2+2, hashes, geometría, normales, materiales, anclajes y canales de animación, y ejecuta las dos suites Godot. La suite nueva exige movimiento real de los pivotes tras avanzar el clip, selección de los 22 modelos y alineación 1:1 de los ocho equipos. Los casos negativos rechazan catálogos incompletos, IDs repetidos, rutas manipuladas y anclajes incoherentes. El artefacto incluye los modelos, fuentes y registros; consultar la ejecución enlazada en #54 para su resultado real.
