# Publicar un modelo en la biblioteca

[← Biblioteca visual](../ASSET_LIBRARY.md) · [Catálogo JSON](../asset_library.json) · [Esquema v2](schema.json) · [Coordinación #7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7)

## Una foto y una ficha por modelo

Toda nueva alta debe aportar **una imagen individual real del recurso**, además de fuente `.blend`, GLB o escena reutilizable, identificador estable y manifiesto. Una imagen general del pack puede acompañar la entrega, pero no sustituye la imagen individual. La ficha y la galería enlazan la foto, el modelo y su fuente: no hay que buscar esos archivos entre comentarios.

La fotografía debe proceder del GLB publicado reimportado en Blender o del modelo instanciado en Godot. No usar arte conceptual ni imágenes generativas como prueba de un modelo que no existe. Encuadrar la pieza completa, con iluminación y fondo legibles. En un entorno, mostrar un ángulo que permita reconocer el espacio; cuando haga falta, añadir una captura interior. En un planeta habitable, distinguir órbita y superficie y aportar la vista de recorrido en su PR.

Una colección compartida puede contener varios submodelos: por ejemplo, el GLB de ocio. Esos grupos tienen ficha y foto independientes, pero conservan el enlace al mismo GLB y el campo `group` para identificarlos. **No duplicar mallas sólo para tener una ficha separada.** Los modelos base y Frontera reciben prefijos documentales en el catálogo; `source_id` mantiene el nombre original, sin renombrar APIs.

## Para personas

El índice `docs/ASSET_LIBRARY.md` da acceso por colección y categoría. Cada galería muestra miniaturas con nombre e ID. Al pulsar una miniatura se abre una ficha con fotografía ampliada, descripción, enlaces directos, dimensiones, escala/ejes, materiales, anclajes, clips, colisión, LOD y limitaciones. Los valores que no declara el manifiesto se identifican como no declarados o como consulta necesaria; no se inventan capacidades para completar la tabla.

## Para IA y herramientas

`docs/asset_library.json` usa `schema: espaciokoop-asset-library`, **version: 2**. Es documentación derivada, no un registro de inventario ni una autoridad del juego.

| Campo | Interpretación |
| --- | --- |
| `assets[].id` | Identificador único del catálogo. Conservarlo entre revisiones. |
| `source_id` | Nombre/ID original en el manifiesto o adaptador de un recurso antiguo. |
| `pack`, `category`, `title`, `description` | Organización y búsqueda. |
| `source`, `runtime`, `resource`, `group` | Fuente Blender, archivo de ejecución, URI Godot y subgrupo opcional. |
| `revision` | Commit Git inmutable de los archivos consultados. No es la versión del juego. |
| `manifest` | Ruta, revisión y JSON Pointer del registro autoritativo. Un adaptador de un bundle puede no tener un registro individual; en ese caso el puntero es `null`, no inventado. |
| `preview` | Ruta, revisión o ubicación local en este catálogo, URL cuando procede, tipo de imagen, tamaño y hash. |
| `card`, `links` | Ficha humana y enlaces verificables a fuente, GLB, manifiesto y guía/escena cuando existen. |
| `availability` | Archivos presentes, pertenencia al corte de main, comprobación documental y estado de integración separado. |
| `statistics`, `dimensions_xyz`, `units`, `axes`, `pivot` | Datos medidos del GLB o declarados por su manifiesto. No estimaciones manuales. |
| `declared_sockets`, `declared_status` | Declaraciones originales del pack, conservadas para cotejo. |
| `habitable`, `representation`, `radius_m` | Contrato adicional cuando lo declara un planeta. Habitabilidad ficticia, no una afirmación astrofísica. |
| `known_limits`, `pull_request` | Qué no incluye y dónde comprobar la entrega. |

`statistics.triangles` cuenta mallas únicas referenciadas por el GLB, o las del submodelo seleccionado. No es necesariamente el total de triángulos dibujados con todas las instancias de una escena. `animations_gltf` conserva nombres glTF; Godot puede normalizarlos al importar. `dimensions_xyz` usa el orden de ejes de Godot; cuando procede de `dimensions_blender_xyz`, se convierte X,Z,Y. Consultar `units`: no presuponer metros en un modelo de representación.

Los manifiestos de cada pack siguen mandando. El catálogo guarda un **corte reproducible**: sus hashes y datos son derivados y pueden quedar antiguos hasta el próximo refresco. No modificar JSON ni Markdown generados a mano ni sincronizarlos al estado de una partida.

### Migración desde el índice v1

La versión 1 sólo enumeraba colecciones. La v2 añade registros `assets`, referencias fijadas, fotos y fichas, y modifica la estructura descriptiva de `packs`. Los consumidores documentales deben comprobar `version` antes de leer. Se preserva el original en `legacy.v1.json` y `LEGACY_INDEX.md`; no se migra ningún guardado ni formato de juego.

## Disponibilidad no significa mecánica integrada

`files_present` prueba la presencia de archivos en la revisión consultada. `in_main_at_snapshot` compara el blob del GLB con el del corte de main; no garantiza que esté incluido en una release o conectado a una mecánica. `catalogue_validation` describe exclusivamente las comprobaciones documentales. `godot_validation` remite a las pruebas del pack; esta actualización no ejecuta por sí misma sus mecánicas. `gameplay_integration: not_inferred` evita convertir una foto en una afirmación de combate, vuelo o misiones implementados.

## Flujo de alta y actualización

Primero leer `AGENTS.md` y reservar en #7 los archivos concretos. Crear o editar la fuente en la carpeta del pack; exportar sin reconstruir destructivamente `.blend` con cambios manuales. Publicar fuente, GLB, imagen individual y manifiesto en una rama propia. Ejecutar las pruebas del pack y añadir capturas visibles en la PR. Registrar esa entrega en el issue permanente #52.

Para incluirla en el catálogo común, reservar `tools/asset_library/sources.json` y añadir el descriptor de colección con su manifiesto, rama alternativa, guía, categoría y límites. El catálogo intenta main primero; si el manifiesto aún no está allí, utiliza la rama de entrega expresamente registrada. Una colección requerida sin manifiesto, un hash incoherente o un modelo sin foto detienen la publicación: no se omiten silenciosamente.

```sh
# Requiere historial Git y las ramas registradas ya disponibles localmente.
# Verificación del corte comprometido; no actualiza documentación ni genera fotos.
python tools/asset_library/catalogue.py --check
python -m unittest discover -s tests/asset_library -v

# Refresco deliberado tras traer las ramas autorizadas.
# Python 3.11 + Pillow; bpy 4.5.3 sólo para las fotos individuales que falten.
python tools/asset_library/catalogue.py --refresh --render-missing
python tools/asset_library/catalogue.py --check
```

El refresco escribe `sources.lock.json`, fichas, galerías y JSON, no fuentes de Blender ni manifiestos ajenos. Las nuevas fotografías llevan un comprobante con hash del GLB y subgrupo; un GLB cambiado exige nueva foto. Las fotos existentes se referencian por commit, no por una rama móvil ni por un artefacto temporal de CI. `--check` falla si falta el lock o cualquier salida está desactualizada.

El workflow de biblioteca valida las fichas y, únicamente en su rama de autoría, conserva la documentación/fotos generadas. **No hace merge, no publica una release y no sustituye la CI canónica.** Añadir las nuevas galerías a #52 mediante `Refs #52`, nunca `Closes #52`.

No subir datos personales, capturas con claves, perfiles privados o archivos ajenos al proyecto. Los renders de biblioteca sólo necesitan la geometría pública del repositorio. Mantener licencias y procedencia por recurso.
