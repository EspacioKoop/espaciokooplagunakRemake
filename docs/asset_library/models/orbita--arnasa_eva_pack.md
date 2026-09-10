# Arnasa · mochila de soporte EVA

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../orbita_player_support.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/images/orbita_pack/player_batch/arnasa_eva_pack.png" alt="Modelo 3D real: Arnasa · mochila de soporte EVA" width="560">

Mochila espacial de doble depósito, arnés, manguera, máscara acoplada y filtro articulado.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/art/blender/orbita_pack/player_batch/arnasa_eva_pack.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/orbita_pack/player_batch/arnasa_eva_pack.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/orbita_pack/player_batch/manifest.json) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/ORBITA_PLAYER_BATCH.md) · [Viewer](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/asset_lab/orbita_pack/player_batch.tscn)

| Campo | Valor |
| --- | --- |
| ID estable | orbita/arnasa_eva_pack |
| Colección / categoría | orbita_player_support / Herramientas |
| Versión del recurso | 1 |
| Estado documental | Archivo presente en main al inventariar |
| Unidades | metres |
| Ejes | Godot +Y up, -Z forward |
| Dimensiones X × Y × Z | 0.532619 × 0.588 × 0.430529 |
| Origen / pivote | consult_source_and_sockets |
| Triángulos del GLB | 5944 |
| Licencia | MIT |
| Colisión | not_included |
| LOD | not_included |

## Reutilización

```text
res://assets/models/orbita_pack/player_batch/arnasa_eva_pack.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `Orbita_graphite`, `Orbita_ceramic`, `Orbita_teal`, `Orbita_alloy`, `Orbita_amber`, `Orbita_glass`, `Orbita_cyan`.

**Anclajes:** `socket_back`, `socket_grip`, `socket_hose`, `socket_supply`.

**Clips glTF:** `mechanical_cycle`. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Seis herramientas, dos armas ficticias y dos naves. Montaje visual a escala no equivale a inventario, disparo, oxígeno, escudo o vuelo de campaña.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #54](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/54). Revisión de los recursos: `9e2401d7dcb4719dc831fd84093a6f9640453687`.

Foto: `repository_model_render`, 640 × 640 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
