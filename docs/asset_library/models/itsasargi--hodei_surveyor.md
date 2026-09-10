# Hodei · corbeta de exploración

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../itsasargi.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/cae594662d17157b296b6d4c79a881b666093ee1/docs/images/itsasargi_pack/hodei_surveyor.png" alt="Modelo 3D real: Hodei · corbeta de exploración" width="560">

Casco catamarán, observatorio giratorio y bahía científica exterior.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/art/blender/itsasargi_pack/hodei_surveyor.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/assets/models/itsasargi_pack/hodei_surveyor.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/assets/models/itsasargi_pack/manifest.json) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/docs/ITSASARGI_ASSET_PACK.md) · [Viewer](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/cae594662d17157b296b6d4c79a881b666093ee1/game/asset_lab/itsasargi_pack/viewer.tscn)

| Campo | Valor |
| --- | --- |
| ID estable | itsasargi/hodei_surveyor |
| Colección / categoría | itsasargi / Naves |
| Versión del recurso | 1 |
| Estado documental | Publicado en rama de entrega; no atribuido a main |
| Unidades | metres |
| Ejes | +X right / +Y up / -Z forward |
| Dimensiones X × Y × Z | 7.9 × 3.225 × 12.0767 |
| Origen / pivote | consult_source_and_sockets |
| Triángulos del GLB | 7328 |
| Licencia | MIT |
| Colisión | consult_pack |
| LOD | consult_pack |

## Reutilización

```text
res://assets/models/itsasargi_pack/hodei_surveyor.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `I_titanium`, `I_deep_petrol`, `I_opaque_blue_glass`, `I_safety_amber`, `I_ceramic_ivory`, `I_cyan_emitter`.

**Anclajes:** `socket_sensor`, `socket_payload_left`, `socket_survey_engine_left_exhaust`, `socket_payload_right`, `socket_survey_engine_right_exhaust`, `socket_centre_of_mass`, `socket_cockpit`, `socket_dock`.

**Clips glTF:** `mechanical_cycle`. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Seis herramientas, dos armas ficticias y dos naves. Articulación e inspección visual; no se añaden reglas de combate, vuelo, simulación de cuerda u oxígeno.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #57](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/57). Revisión de los recursos: `cae594662d17157b296b6d4c79a881b666093ee1`.

Foto: `repository_model_render`, 480 × 480 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
