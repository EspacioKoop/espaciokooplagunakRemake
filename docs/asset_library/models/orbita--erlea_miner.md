# Erlea · nave minera

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../orbita.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/images/orbita_pack/erlea_miner.png" alt="Modelo 3D real: Erlea · nave minera" width="560">

Nave minera de cuatro depósitos y cabezal de extracción ficticio.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/art/blender/orbita_pack/erlea_miner.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/orbita_pack/erlea_miner.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/orbita_pack/manifest.json) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/ORBITA_ASSET_PACK.md) · [Viewer](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/asset_lab/orbita_pack/viewer.tscn)

| Campo | Valor |
| --- | --- |
| ID estable | orbita/erlea_miner |
| Colección / categoría | orbita / Naves |
| Versión del recurso | 1 |
| Estado documental | Archivo presente en main al inventariar |
| Unidades | metres |
| Ejes | Godot +Y up, -Z forward |
| Dimensiones X × Y × Z | 5.92 × 3.13 × 8.19309 |
| Origen / pivote | consult_source_and_sockets |
| Triángulos del GLB | 11988 |
| Licencia | MIT |
| Colisión | not_included |
| LOD | not_included |

## Reutilización

```text
res://assets/models/orbita_pack/erlea_miner.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `Orbita_graphite`, `Orbita_amber`, `Orbita_glass`, `Orbita_ceramic`, `Orbita_alloy`, `Orbita_cyan`, `Orbita_gold`.

**Anclajes:** `socket_cargo`, `socket_cockpit`, `socket_exhaust_0_94`, `socket_exhaust_m0_94`, `socket_mining_left`, `socket_mining_right`.

**Clips glTF:** `mechanical_cycle`. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Modelos originales y articulaciones rígidas. No incorporan automáticamente IA, inventario, daño, colisiones, LOD, vuelo ni planetas caminables.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #54](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/54). Revisión de los recursos: `9e2401d7dcb4719dc831fd84093a6f9640453687`.

Foto: `repository_model_render`, 640 × 640 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
