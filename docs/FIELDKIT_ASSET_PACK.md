# Fieldkit — equipo de jugadores y naves

Segunda tanda de la [biblioteca permanente #52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52). **Diez recursos: seis herramientas, dos armas ficticias y dos naves.** Fuentes Blender editables, GLB autocontenidos y escenas Godot; no son ilustraciones ni un paquete de prompts. Recursos originales bajo MIT.

La entrega y su validación se registran en #52 y en su PR. No confundir disponibilidad en una rama con inclusión en `main` o en una release.

## Catálogo

| ID `fieldkit/…` | Recurso | Parte móvil | Anclajes principales |
| --- | --- | --- | --- |
| `giltza_hack_tool` | Giltza, brazalete de hackeo | Consola abatible | `socket_wrist`, `socket_effect`, `socket_screen` |
| `kako_tether` | Kako, gancho magnético | Tres pétalos de garra | `socket_grip`, `socket_offhand`, `socket_cable_exit`, `socket_hook` |
| `argi_scanner` | Argi, escáner de campo | Cabezal orientable | `socket_grip`, `socket_scan_origin`, `socket_screen`, `socket_offhand` |
| `jostun_repair` | Jostun, reparador | Dos pinzas | `socket_grip`, `socket_effect`, `socket_contact_left`, `socket_contact_right`, `socket_offhand` |
| `ebaki_cutter` | Ebaki, cortador ficticio | Anillo de corte | `socket_grip`, `socket_cut_origin`, `socket_offhand` |
| `soros_medkit` | Soros, botiquín portátil | Tapa con bisagra | `socket_grip`, `socket_belt`, `socket_treatment`, `socket_offhand` |
| `tximista_carbine` | Tximista, carabina de pulsos | Emisor móvil | `socket_grip`, `socket_offhand`, `socket_aim`, `socket_muzzle`, `socket_holster`, `socket_power_cell` |
| `txinparta_sidearm` | Txinparta, pistola iónica | Corredera | `socket_grip`, `socket_aim`, `socket_muzzle`, `socket_holster`, `socket_power_cell` |
| `enara_shuttle` | Enara, lanzadera de expedición | Rampa y tren | `socket_pilot`, `socket_copilot`, `socket_entry`, `socket_cargo`, `socket_centre`, dos escapes y dos montajes |
| `hontz_corvette` | Hontz, corbeta de patrulla | Antena de exploración | `socket_bridge`, `socket_dock`, `socket_scan_origin`, `socket_centre`, dos escapes y cuatro montajes |

Por cada nombre existen:

```text
art/blender/fieldkit_pack/<nombre>.blend
game/assets/models/fieldkit_pack/<nombre>.glb
game/asset_lab/fieldkit_pack/instances/<nombre>.tscn
```

El [manifiesto](../game/assets/models/fieldkit_pack/manifest.json) es la fuente única para hashes, dimensiones, materiales, anclajes y presupuestos geométricos. [fieldkit_assets.json](fieldkit_assets.json) es un índice ligero para agentes; no duplica hashes. No modifica los índices o archivos de Órbita y Frontera.

## Probar en Godot

Abrir `game/asset_lab/fieldkit_pack/viewer.tscn` y pulsar **F6**, o desde la raíz:

```sh
.toolchain/godot --path game res://asset_lab/fieldkit_pack/viewer.tscn
```

El visor contiene los diez modelos exportados. Selección mediante desplegable o flechas; órbita con botón derecho, zoom con rueda y R para restablecer. Espacio pausa/reanuda el clip. **V alterna la vista de equipo 1:1** en las ocho herramientas/armas: sitúa su anclaje de mano/muñeca frente a la cámara sin reescalar la geometría. Las naves no se pueden equipar como herramientas.

La inspección presenta dimensiones en metros. No incluye manos humanas ni un rig de personaje; no simula la conexión con el inventario. No cambia el estado de campaña, los guardados ni las reglas de red.

## Reutilizar sin duplicar geometría

Se puede arrastrar la escena `.tscn` o el `.glb` desde el sistema de archivos del editor a otra escena. Las escenas `.tscn` sólo envuelven el GLB: no mantienen una copia de sus mallas.

```gdscript
var scene = preload("res://asset_lab/fieldkit_pack/instances/tximista_carbine.tscn")
var model = scene.instantiate()
add_child(model)
var muzzle = model.find_child("socket_muzzle", true, false) as Node3D
```

Resolver los anclajes por nombre desde la instancia, no mediante una ruta interna supuesta: el importador puede introducir una raíz adicional. Los nombres son únicos dentro de cada modelo. Los puntos de efecto/boca y los modelos miran al **-Z local**; los escapes se orientan hacia la popa en la geometría y su consumidor debe emitir hacia **+Z**. Son marcadores de colocación, no sistemas de partículas ya configurados.

**Coordenadas:** X derecha, Y arriba, -Z delante; una unidad es un metro. La fuente Blender usa Z arriba y el exportador convierte. El origen de las herramientas coincide con el agarre/muñeca salvo el pequeño desplazamiento del asa del botiquín, registrado por `socket_grip`. Naves centradas en su origen de diseño; usar el AABB para medidas y apoyos.

**Animación:** cada GLB tiene un clip `field_cycle` de articulación rígida. Demuestra apertura, giro o movimiento de sus piezas. No implica disparo, consumo, curación, cable físico o daño. El visor duplica localmente la animación antes de activar su bucle, sin modificar el recurso importado compartido. Para integrar un estado de juego, controlar los pivotes o copiar/recortar el clip en el consumidor.

## Editar y reexportar

Cada `.blend` conserva piezas, pivotes y modificadores editables. Las partes estáticas se agrupan por pivote sólo durante la exportación para reducir nodos. Materiales PBR con color, metalicidad, rugosidad y emisión; no necesitan texturas externas. Las mallas creadas por loft reciben UVs de exportación cuando no tienen una capa de UVs; se conservan las UVs ya editadas.

```sh
# Primera construcción: Python 3.11 y bpy==4.5.3.
python art/blender/fieldkit_pack/build.py --missing-only

# Después de editar y guardar los .blend (sin reemplazarlos):
python art/blender/fieldkit_pack/export.py --render

# Equivalente con Blender instalado:
blender -b --python art/blender/fieldkit_pack/export.py -- --render

# Validaciones:
python tests/fieldkit_pack/validate.py
python tools/bootstrap.py
python tests/fieldkit_pack/run.py
```

El constructor sin opciones rechaza fuentes existentes; `--missing-only` las conserva y `--force` las reemplaza explícitamente. **El exportador nunca guarda sobre las fuentes** y comprueba que no cambien sus SHA-256. Abrir fuentes desactiva la ejecución automática de scripts embebidos. El flag opcional `--render` reimporta el GLB antes de renderizar la ficha: la evidencia corresponde al recurso entregado, no a otro modelo más detallado.

## Validación y límites

El validador comprueba exactamente seis herramientas, dos armas y dos naves, contenedores GLB, accesores, índices, normales, triángulos, anclajes, materiales, clips, hashes y escenas. Incluye entradas corruptas y rechaza texturas/buffers externos. Las pruebas Godot cargan cada escena, comparan dimensiones, comprueban los anclajes y verifican que las animaciones muevan nodos reales; también recorren el selector, pausa y vista de equipo. La prueba gráfica captura los diez modelos y las ocho poses equipadas con audio Dummy en un entorno aislado.

**No incluido:** conexión al inventario/combate, daño, física de gancho, curación, hackeo funcional, control de vuelo, IA, colisiones, IK de manos, esqueleto humano, interiores recorribles de estas naves ni versiones LOD. Es una entrega de modelos para reutilizar, como Órbita. Esas mecánicas se conectan después desde sus sistemas autoritativos y con reserva propia en #7.

No cerrar #52 al entregar este pack. Registrar revisiones y conservar los IDs; los cambios incompatibles de escala, origen o anclajes requieren versionado explícito.
