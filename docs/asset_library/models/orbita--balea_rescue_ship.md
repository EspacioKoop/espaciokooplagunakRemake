# Balea · nave de evacuación

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../orbita_player_support.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/images/orbita_pack/player_batch/balea_rescue_ship.png" alt="Modelo 3D real: Balea · nave de evacuación" width="560">

Nave de apoyo con seis cápsulas de evacuación, brazos de recuperación, puente y atraque dorsal.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/art/blender/orbita_pack/player_batch/balea_rescue_ship.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/orbita_pack/player_batch/balea_rescue_ship.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/orbita_pack/player_batch/manifest.json) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/ORBITA_PLAYER_BATCH.md) · [Viewer](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/asset_lab/orbita_pack/player_batch.tscn)

| Campo | Valor |
| --- | --- |
| ID estable | orbita/balea_rescue_ship |
| Colección / categoría | orbita_player_support / Naves |
| Versión del recurso | 1 |
| Estado documental | Archivo presente en main al inventariar |
| Unidades | metres |
| Ejes | Godot +Y up, -Z forward |
| Dimensiones X × Y × Z | 6.78 × 2.8 × 12.9 |
| Origen / pivote | consult_source_and_sockets |
| Triángulos del GLB | 12484 |
| Licencia | MIT |
| Colisión | not_included |
| LOD | not_included |

## Reutilización

```text
res://assets/models/orbita_pack/player_batch/balea_rescue_ship.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `Orbita_graphite`, `Orbita_ceramic`, `Orbita_teal`, `Orbita_glass`, `Orbita_amber`, `Orbita_alloy`, `Orbita_cyan`.

**Anclajes:** `socket_rescue_left`, `socket_rescue_right`, `socket_cargo`, `socket_cockpit`, `socket_dock`, `socket_evac_left_1`, `socket_evac_left_2`, `socket_evac_left_3`, `socket_evac_right_1`, `socket_evac_right_2`, `socket_evac_right_3`, `socket_exhaust_2_48`, `socket_exhaust_m2_48`, `socket_origin`.

**Clips glTF:** `mechanical_cycle`. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Seis herramientas, dos armas ficticias y dos naves. Montaje visual a escala no equivale a inventario, disparo, oxígeno, escudo o vuelo de campaña.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #54](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/54). Revisión de los recursos: `9e2401d7dcb4719dc831fd84093a6f9640453687`.

Foto: `repository_model_render`, 640 × 640 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
