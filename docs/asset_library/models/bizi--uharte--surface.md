# Uharte · mundo habitable de islas / surface

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../bizi.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/cae594662d17157b296b6d4c79a881b666093ee1/docs/images/bizi_planets/uharte_surface.png" alt="Modelo 3D real: Uharte · mundo habitable de islas / surface" width="560">

Recurso de biblioteca; consultar su guía.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/art/blender/bizi_planets/uharte.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/assets/models/bizi_planets/uharte_surface.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/assets/models/bizi_planets/manifest.json) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/docs/BIZI_HABITABLE_PLANETS.md) · [Viewer](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/asset_lab/bizi_planets/viewer.tscn)

| Campo | Valor |
| --- | --- |
| ID estable | bizi/uharte/surface |
| Colección / categoría | bizi / Planetas y lunas |
| Versión del recurso | 1 |
| Estado documental | Publicado en rama de entrega; no atribuido a main |
| Unidades | metres |
| Ejes | +X right / +Y up / -Z forward |
| Dimensiones X × Y × Z | 201.984207 × 206.872993 × 205.693779 |
| Origen / pivote | planet centre; same unscaled metres in both representations |
| Triángulos del GLB | 72752 |
| Licencia | MIT |
| Colisión | consult_pack |
| LOD | consult_pack |
| HABITABLE | Sí, por diseño ficticio del mundo |
| Representación | surface |
| Radio de referencia (m) | 100.0 |

## Reutilización

```text
res://assets/models/bizi_planets/uharte_surface.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `B_uharte_leaves_light`, `B_uharte_wood`, `B_uharte_leaves`, `B_uharte_rock`, `B_uharte_sand`, `I_cyan_emitter`, `B_uharte_cloth`, `I_deep_petrol`, `I_amber_indicator`, `B_uharte_soil`, `I_titanium`, `I_safety_amber`, `I_ceramic_ivory`, `B_uharte_water`, `B_uharte_grass`, `B_uharte_grass_light`.

**Anclajes:** `socket_resource_arch_0`, `socket_resource_arch_1`, `socket_poi_arch`, `socket_resource_arena_0`, `socket_resource_arena_1`, `socket_encounter_0`, `socket_encounter_1`, `socket_encounter_2`, `socket_encounter_3`, `socket_poi_arena`, `socket_resource_camp_0`, `socket_resource_camp_1`, `socket_poi_camp`, `socket_resource_greenhouse_0`, `socket_resource_greenhouse_1`, `socket_poi_greenhouse`, `socket_resource_grove_0`, `socket_resource_grove_1`, `socket_poi_grove`, `socket_resource_landing_0`, `socket_resource_landing_1`, `socket_landing`, `socket_poi_landing`, `socket_return`, `socket_ship_parking`, `socket_resource_observatory_0`, `socket_resource_observatory_1`, `socket_poi_observatory`, `socket_resource_quarry_0`, `socket_resource_quarry_1`, `socket_poi_quarry`, `socket_resource_relay_0`, `socket_resource_relay_1`, `socket_poi_relay`, `socket_resource_reservoir_0`, `socket_resource_reservoir_1`, `socket_poi_reservoir`, `socket_resource_ruins_0`, `socket_resource_ruins_1`, `socket_poi_ruins`, `socket_resource_sanctuary_0`, `socket_resource_sanctuary_1`, `socket_poi_sanctuary`, `socket_resource_village_0`, `socket_resource_village_1`, `socket_poi_village`, `socket_resource_wreck_0`, `socket_resource_wreck_1`, `socket_poi_wreck`.

**Clips glTF:** Sin clips. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Dos mundos, Ametz/Uharte, y cuatro representaciones: órbita y superficie por planeta. Habitabilidad ficticia. El laboratorio usa teletransporte y gravedad radial; no implementa aterrizaje seamless ni misiones, batallas o inventario persistente. Agua visual.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #57](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/57). Revisión de los recursos: `cae594662d17157b296b6d4c79a881b666093ee1`.

Foto: `repository_model_render`, 640 × 640 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
