# Itsasargi — herramientas, armas ficticias y naves

Índice permanente: [#52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52). Entrega, binarios y pruebas de la revisión actual: [PR #57](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/57). Colección independiente y complementaria de Órbita, Frontera y Lantegi. No sobrescribe sus modelos ni índices reservados.

## Diez recursos originales

| ID estable | Modelo | Categoría | Partes móviles / anclajes principales |
| --- | --- | --- | --- |
| `itsasargi/arc_welder` | Lotu · soldador de arco | Herramienta | Colimador retráctil; agarre, arco, batería |
| `itsasargi/eva_winch` | Amarra · cabrestante EVA | Herramienta | Tambor, bobina y mosquetón; agarre, salida de cable, montaje |
| `itsasargi/rescue_beacon` | Argi · baliza de emergencia | Herramienta | Trípode y reflector; señal, agarre, suelo |
| `itsasargi/specimen_case` | Hazi · maletín de especímenes | Herramienta | Tapa articulada, cierres, seis cápsulas; asa y seis alojamientos |
| `itsasargi/oxygen_rebreather` | Arnasa · respirador portátil | Herramienta | Depósitos, regulador, tubo y máscara; espalda, máscara, agarre |
| `itsasargi/field_transceiver` | Irrati · transceptor de campo | Herramienta | Antena desplegable, dial y panel; agarre, cinturón, señal |
| `itsasargi/prism_sidearm` | Prisma · pistola fotónica | Arma ficticia | Carcasa deslizante y prisma; agarre, boca de efectos, celda, funda |
| `itsasargi/gravity_lance` | Indar · lanza gravitatoria | Arma ficticia | Tres anillos móviles y emisores; dos agarres, boca y culata |
| `itsasargi/marra_interceptor` | Marra · interceptor de ala manta | Nave | Aletas móviles, cabina, emisores y dos motores; escapes, cabina, atraque, centro de referencia |
| `itsasargi/hodei_surveyor` | Hodei · corbeta de exploración | Nave | Casco catamarán, pontones y observatorio giratorio; sensor, motores, cargas, cabina, atraque |

Las armas y herramientas son geometría de ciencia ficción para el juego, no planos de fabricación ni simulaciones de dispositivos reales. Cada recurso dispone de `.blend` propio y GLB autocontenido. Los diez incluyen un ciclo de articulación rígida `mechanical_cycle`; no son animaciones de brazos humanos ni acciones de un controlador de combate.

## Rutas

```text
art/blender/itsasargi_pack/<id_local>.blend
game/assets/models/itsasargi_pack/<id_local>.glb
game/assets/models/itsasargi_pack/manifest.json
game/asset_lab/itsasargi_pack/viewer.tscn
docs/images/itsasargi_pack/<id_local>.png
```

El manifiesto es la referencia verificable de hashes, triángulos, bytes, dimensiones, ejes, materiales, anclajes y clips. Las imágenes del repositorio son previews técnicos obtenidos reimportando el GLB; las capturas `godot_*` muestran el visor real. No se necesita ninguna imagen para reutilizar los modelos.

## Uso en Godot

Abrir `game/asset_lab/itsasargi_pack/viewer.tscn` y pulsar F6, o:

```sh
.toolchain/godot --path game res://asset_lab/itsasargi_pack/viewer.tscn
```

El visor permite seleccionar los diez modelos, girar con botón derecho, acercar con la rueda y reproducir el mecanismo. Sólo normaliza el tamaño de presentación. Los GLB conservan metros reales de autoría.

Para instanciar un recurso desde otro componente:

```gdscript
var model := preload("res://assets/models/itsasargi_pack/arc_welder.glb").instantiate()
add_child(model)
var grip := model.find_child("socket_grip_primary", true, false) as Node3D
var emitter := model.find_child("socket_effect_arc", true, false) as Node3D
```

Resolver anclajes por nombre desde la instancia; no asumir una NodePath relativa derivada de la jerarquía glTF. El consumidor coloca el objeto usando la transformación del anclaje, no modificando los vértices. Si el anclaje está bajo una pieza articulada, su transformación cambia con la animación. La posición del manifiesto corresponde a reposo y no sustituye el transform del nodo durante el juego.

Godot: +X derecha, +Y arriba, -Z delante. Blender: +Z arriba y +Y delante. Una unidad es un metro. Las bocas de herramientas/armas miran hacia -Z local; escapes y montajes traseros declaran su orientación propia. Herramientas y armas usan origen de autoría mecánico, no todas reposan en Y=0; consultar AABB antes de apoyarlas o guardarlas. Las naves conservan un origen central de montaje con anclajes explícitos. No cambiar escala/origen o nombres de anclajes sin versionar los IDs publicados.

## Materiales y edición

Estilo industrial de cerámica clara, azul petróleo, metal, agarres oscuros, detalles ámbar y emisores cian/violeta. Materiales Principled PBR con color, metalicidad, rugosidad y emisión. El cristal azul es opaco y estilizado, evitando depender de transparencia o refracción. No hay texturas externas ni materiales procedurales que desaparezcan al exportar.

La fuente editable es el `.blend`, no el constructor. El constructor conserva las piezas; el exportador aplica biseles y agrupa estáticos por pivote únicamente en memoria. No guarda sobre la fuente y verifica su SHA-256.

```sh
# Primera construcción: Python con bpy==4.5.3, o Blender 4.5.3.
python art/blender/itsasargi_pack/build.py --missing-only
# Después de modificar manualmente un .blend:
python art/blender/itsasargi_pack/export.py --render
# Equivalente desde Blender:
blender -b --python art/blender/itsasargi_pack/export.py -- --render
```

`--missing-only` crea únicamente lo que falta. Sin esa opción, el constructor se niega a reemplazar fuentes existentes. `--force` es una reconstrucción destructiva explícita: no usarlo sobre trabajo artístico manual que deba conservarse.

Los helpers `build.py` y `export.py` también sirven a la colección Bizi de esta misma entrega. Mantener sus interfaces al continuar la autoría de planetas. Los GLB son independientes de Python/Blender en ejecución.

## Validación y límites

```sh
python tests/itsasargi_pack/validate.py
python tests/bizi_planets/validate_spheres.py
python tools/bootstrap.py
python tests/itsasargi_pack/run.py
```

El validador comprueba contenedor/accesores GLB, geometría finita, índices, triángulos no degenerados, normales, materiales PBR, anclajes, tiempos de animación, hashes y nueve entradas corruptas. Godot comprueba importación, instanciación, selección inválida, materiales/anclajes y reproducción real del mecanismo de cada modelo. El workflow propio no sustituye la CI canónica de integración. El resultado ejecutado de cada revisión vive en la PR y en `build/itsasargi` del artefacto de evidencias.

Esta colección **no añade** daño, IA, reglas de herramientas, inventario, colisiones de estos diez modelos, vuelo, selección de nave, avatar humano, retargeting, simulación de cuerda, oxígeno ni estado de red. Son recursos utilizables y un visor funcional; un modelo de arma no implica un arma jugable conectada a la campaña. Los consumidores deben reservar sus sistemas en #7.

Geometría original y licencia MIT del repositorio, sin recursos importados de otros juegos, datos personales ni servicios externos de generación de imágenes. Las altas y revisiones se registran en #52 con ID, versión, fuente, GLB, anclajes y validación. La otra colección de esta entrega se documenta en [BIZI_HABITABLE_PLANETS.md](BIZI_HABITABLE_PLANETS.md).
