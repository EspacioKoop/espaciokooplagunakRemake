# Enara · lanzadera de expedición

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../fieldkit.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/images/fieldkit_pack/enara_shuttle.png" alt="Modelo 3D real: Enara · lanzadera de expedición" width="560">

Lanzadera compacta con alas cortas, tren y rampa posterior articulada.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/art/blender/fieldkit_pack/enara_shuttle.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/fieldkit_pack/enara_shuttle.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/fieldkit_pack/manifest.json) · [Scene](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/asset_lab/fieldkit_pack/instances/enara_shuttle.tscn) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/FIELDKIT_ASSET_PACK.md) · [Viewer](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/asset_lab/fieldkit_pack/viewer.tscn)

| Campo | Valor |
| --- | --- |
| ID estable | fieldkit/enara_shuttle |
| Colección / categoría | fieldkit / Naves |
| Versión del recurso | 1 |
| Estado documental | Archivo presente en main al inventariar |
| Unidades | metres |
| Ejes | Godot +X right, +Y up, -Z forward |
| Dimensiones X × Y × Z | 9.6 × 3.418105 × 10.2125 |
| Origen / pivote | centre |
| Triángulos del GLB | 6028 |
| Licencia | MIT |
| Colisión | not_included |
| LOD | consult_pack |

## Reutilización

```text
res://assets/models/fieldkit_pack/enara_shuttle.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `Fieldkit_blue`, `Fieldkit_alloy`, `Fieldkit_chalk`, `Fieldkit_glass`, `Fieldkit_graphite`, `Fieldkit_cyan`, `Fieldkit_amber`.

**Anclajes:** `socket_cargo`, `socket_centre`, `socket_copilot`, `socket_entry`, `socket_exhaust_left`, `socket_exhaust_right`, `socket_hardpoint_left`, `socket_hardpoint_right`, `socket_pilot`.

**Clips glTF:** `field_cycle`. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Seis herramientas, dos armas ficticias y dos naves. Inspección y vista equipada; no añade hackeo, curación, daño, vuelo, IK ni inventario de campaña.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #58](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/58). Revisión de los recursos: `9e2401d7dcb4719dc831fd84093a6f9640453687`.

Foto: `repository_model_render`, 640 × 640 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
