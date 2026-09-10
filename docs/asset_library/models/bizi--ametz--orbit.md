# Ametz · mundo habitable de bosques / orbit

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../bizi.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/cae594662d17157b296b6d4c79a881b666093ee1/docs/images/bizi_planets/ametz_orbit.png" alt="Modelo 3D real: Ametz · mundo habitable de bosques / orbit" width="560">

Recurso de biblioteca; consultar su guía.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/art/blender/bizi_planets/ametz.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/assets/models/bizi_planets/ametz_orbit.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/assets/models/bizi_planets/manifest.json) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/docs/BIZI_HABITABLE_PLANETS.md) · [Viewer](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/asset_lab/bizi_planets/viewer.tscn)

| Campo | Valor |
| --- | --- |
| ID estable | bizi/ametz/orbit |
| Colección / categoría | bizi / Planetas y lunas |
| Versión del recurso | 1 |
| Estado documental | Publicado en rama de entrega; no atribuido a main |
| Unidades | metres |
| Ejes | +X right / +Y up / -Z forward |
| Dimensiones X × Y × Z | 242.200012 × 242.200005 × 242.200005 |
| Origen / pivote | planet centre; same unscaled metres in both representations |
| Triángulos del GLB | 3920 |
| Licencia | MIT |
| Colisión | consult_pack |
| LOD | consult_pack |
| HABITABLE | Sí, por diseño ficticio del mundo |
| Representación | orbit |
| Radio de referencia (m) | 120.0 |

## Reutilización

```text
res://assets/models/bizi_planets/ametz_orbit.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `B_ametz_grass`, `B_ametz_grass_light`, `B_ametz_rock`, `B_ametz_sand`, `B_ametz_soil`, `I_ceramic_ivory`, `B_ametz_wood`, `I_deep_petrol`, `B_ametz_water`.

**Anclajes:** Sin anclajes nombrados en el GLB.

**Clips glTF:** Sin clips. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Dos mundos, Ametz/Uharte, y cuatro representaciones: órbita y superficie por planeta. Habitabilidad ficticia. El laboratorio usa teletransporte y gravedad radial; no implementa aterrizaje seamless ni misiones, batallas o inventario persistente. Agua visual.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #57](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/57). Revisión de los recursos: `cae594662d17157b296b6d4c79a881b666093ee1`.

Foto: `repository_model_render`, 640 × 640 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
