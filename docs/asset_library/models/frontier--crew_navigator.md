# Navegante

[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../frontier.md) · [JSON para agentes](../../asset_library.json)

<img src="https://raw.githubusercontent.com/EspacioKoop/espaciokooplagunakRemake/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/images/frontier_pack/crew_navigator.png" alt="Modelo 3D real: Navegante" width="560">

Traje naval ligero, casco y arnés de navegación.

[Source](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/art/blender/frontier_pack/sources/crew_navigator.blend) · [Runtime](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/frontier_pack/crew_navigator.glb) · [Manifest](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/game/assets/models/frontier_pack/manifest.json) · [Guide](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/9e2401d7dcb4719dc831fd84093a6f9640453687/docs/FRONTIER_ASSET_PACK.md)

| Campo | Valor |
| --- | --- |
| ID estable | frontier/crew_navigator |
| Colección / categoría | frontier / Avatares y tripulación |
| Versión del recurso | 1 |
| Estado documental | Archivo presente en main al inventariar |
| Unidades | metres |
| Ejes | glTF +Y up, -Z forward |
| Dimensiones X × Y × Z | 1.04844 × 1.9365 × 0.51 |
| Origen / pivote | consult_source_and_sockets |
| Triángulos del GLB | 10216 |
| Licencia | MIT |
| Colisión | consult_pack |
| LOD | consult_pack |

## Reutilización

```text
res://assets/models/frontier_pack/crew_navigator.glb
```

Instanciar el GLB o su escena, sin copiar la geometría. Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.

**Materiales:** `Carbon`, `Crew_Teal`, `Brushed_Titanium`, `Hardware_Brass`, `Ceramic_Ivory`, `Opaque_Visor`, `Emitter_Cyan`, `Hull_Slate`.

**Anclajes:** `Socket_Head_top`, `Socket_Hand_L`, `Socket_Hand_R`, `Socket_Back`, `Socket_Feet`.

**Clips glTF:** `Idle`, `Walk`, `Wave`. Godot puede normalizar nombres al importar; consultar la guía del pack.

## Alcance y trazabilidad

Biblioteca de expedición. El prefijo frontier/ es documental y no cambia IDs originales. Consultar su PR para rigs, animaciones, pruebas y consumidores pendientes.

La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. [Pruebas y revisión de la entrega #55](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/55). Revisión de los recursos: `9e2401d7dcb4719dc831fd84093a6f9640453687`.

Foto: `repository_model_render`, 720 × 720 píxeles. Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.

Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).
