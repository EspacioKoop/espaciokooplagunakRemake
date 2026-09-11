# Torlo · técnico mecánico

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../orbita.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/images/orbita_pack/technician_robot.png" alt="Modelo 3D real: Torlo · técnico mecánico" width="560">

Tripulante robótico con articulaciones rígidas y anclajes de equipo.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/art/blender/orbita_pack/technician_robot.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/orbita_pack/technician_robot.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/orbita_pack/manifest.json) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/ORBITA_ASSET_PACK.md) · [Viewer](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/asset_lab/orbita_pack/viewer.tscn)

| Campo | Valor |
| --- | --- |
| ID estable | orbita/technician_robot |
| Colección / categoría | orbita / Avatares y tripulación |
| Versión del recurso | 1 |
| Estado documental | Archivo presente en main al inventariar |
| Unidades | metres |
| Ejes | Godot +Y up, -Z forward |
| Dimensiones X × Y × Z | 1.2263 × 2.01 × 0.775 |
| Origen / pivote | consult_source_and_sockets |
| Triángulos del GLB | 3328 |
| Licencia | MIT |
| Colisión | not_included |
| LOD | not_included |

## Reutilización

```text
res://assets/models/orbita_pack/technician_robot.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `Orbita_graphite`, `Orbita_alloy`, `Orbita_ceramic`, `Orbita_amber`, `Orbita_cyan`, `Orbita_teal`.

**Anclajes:** `socket_hand_left`, `socket_hand_right`, `socket_view`, `socket_back`.

**Clips glTF:** `mechanical_cycle`. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Modelos originales y articulaciones rígidas. No incorporan automáticamente IA, inventario, daño, colisiones, LOD, vuelo ni planetas caminables.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #54](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/54). Revisión de los recursos: `9e2401d7dcb4719dc831fd84093a6f9640453687`.

Foto: `repository_model_render`, 640 × 640 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
