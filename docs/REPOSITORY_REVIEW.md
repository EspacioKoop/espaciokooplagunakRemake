# Revisión del repositorio — corte verificable

[Inicio](../README.md) · [Adopción](PLATINO_ADOPTION.md) · [Roadmap](ROADMAP.md)

Revisión del 11/09/2026, tarea [#72](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/72). Referencia del juego: **`f2015279bb7a8c307352a9526d1942a9df047ac4`**, árbol **`50137808aaf801615dc0391db3bcc57da73e1631`**. Los cambios posteriores de otros agentes y las ramas/PR no fusionadas no se atribuyen a este corte.

## Cobertura y método

Se han obtenido y leído los bytes de **los 1.125 archivos versionados**: **173.442.747 bytes**, **766 archivos de texto** y **359 binarios**. No hay archivos omitidos del árbol fijado. Se verificaron el archivo descargado, sus sumas internas, los blobs y el árbol Git original. La [exportación pública de auditoría](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/runs/34625837922) usa únicamente archivos versionados; no contiene `.git`, partidas ni credenciales. El workflow temporal se retira de la entrega final.

La revisión combina inventario completo, inspección estructural, lectura arquitectónica y contraste de reglas, contratos y pruebas. **Leer todos los blobs no demuestra una auditoría semántica línea por línea ni haber ejecutado todos los casos del juego.** El informe automático mantiene `semantic_review=false` y `runtime_validation=false` para no convertir cobertura de archivos en una certificación. Los binarios no se presentan como revisados visualmente en Blender ni como jugados en todas las plataformas.

| Área | Archivos en el corte |
| --- | ---: |
| Raíz | 10 |
| `.github/` | 37 |
| `art/` | 99 |
| `docs/` | 376 |
| `examples/` | 1 |
| `game/` | 417 |
| `integrations/` | 13 |
| `recovery/` | 6 |
| `schemas/` | 1 |
| `server/` | 5 |
| `tests/` | 141 |
| `third_party/` | 2 |
| `tools/` | 17 |
| **Total** | **1.125** |

Entre ellos hay **192 GDScript**, **106 Python**, **177 Markdown**, **58 JSON**, **100 GLB**, **79 Blender**, **165 PNG**, **26 escenas TSCN** y **36 YML**. Los restantes son importaciones, UID, imágenes JPG, audio, traducciones, shaders, CSS/JavaScript, configuración y otras fuentes. Los recuentos por carpeta y extensión son dimensiones diferentes, no se suman entre sí.

Las comprobaciones sintácticas de los **106 Python** y los **58 JSON** no detectaron errores de sintaxis; las cabeceras/chunks JSON de los **100 GLB** fueron estructuralmente válidas. Esto no es validación completa de glTF, animación, geometría, licencia o jugabilidad. Las **64 referencias literales** examinadas en `load/preload` y `ext_resource` del juego tenían destino presente; las rutas construidas dinámicamente y el contenido de un paquete exportado necesitan sus propias pruebas.

## Mapa de arquitectura y autoridad

### Arranque y sesión

`game/project.godot` identifica la versión 0.9.2, escena `main.tscn`, renderer de compatibilidad, física a 30 Hz y autoloads. `main.tscn` conecta `ui/app.gd`, música reactiva y guardianes. `Controls` administra entrada; `Session` centraliza juego local, conexión, autoridad de simulación y guardados. `ReleaseAcceptance` sólo activa fixtures cuando recibe argumentos de aceptación.

`core/simulation.gd`, `ship_model.gd`, `ship_operations.gd`, `space_physics.gd` y `space_pickups.gd` contienen reglas, nave, órdenes, movimiento y recogida. No debe duplicarse ese estado en editores, paneles o adaptadores. La vista espacial usa 3D, pero la propuesta de navegación 6DOF exige cambiar más que una cámara.

### Red, privacidad y persistencia

`net/session.gd` comparte la misma simulación entre local y anfitrión ENet; el protocolo fijado en este corte es 5. Gestiona reto/autenticación, roster, roles, órdenes y proyecciones. `server_relay=false`, comprobaciones de peers activos y envíos dirigidos evitan tratar a una conexión pendiente como tripulante autorizado.

`SeatPresence`, avatares, lounge/mesas y los subsistemas de tripulación/sensores/combate tienen contratos propios de proyección y permisos. Cada cambio de identidad, reconexión o snapshot debe conservar privacidad de cartas, dados, estado oculto y documentos de autoría. ENet no aporta cifrado por usar contraseña; [SECURITY](../SECURITY.md) delimita la red de confianza.

`core/storage.gd` valida tamaño, profundidad, tipos, campaña y sistemas; utiliza un sobre con suma de comprobación, precisión numérica, escritura temporal y copia anterior. La sesión permite recuperar la copia y las pruebas suprimen guardados normales. Este mecanismo no prueba por sí solo resistencia a una pérdida de alimentación. Los datos `user://` no forman parte del inventario ni de esta entrega.

### Modelo, contenido y autoría

`Catalog`, `CampaignDocument`, `CharacterDocument`, `LoadoutDocument`, `ShipTemplateCatalog`, `NpcGenerator` y los comparadores validan documentos y transformaciones. Sus editores viven en `game/ui/`, no son autoridades paralelas de progreso o combate. El inventario de paridad no equivale al inventario de archivos: tener todos los archivos del remake no demuestra haber migrado todo el corpus original.

`Crew`, `Expedition`, `Sensors`, `Combat`, `Fleet`, `Armaments` y `Thrusters` añaden reglas y consolas específicas con autoridad del anfitrión. `Cooperation`, `AssistanceTraining` y `CrewTraining` permiten ejercitar puestos; las pruebas/tutoriales no deben conceder recompensas de campaña. `GmLiveActions/GmLiveState` autorizan dirección en vivo; dossiers y briefings exportan documentos locales con límites.

### Interiores, social, interfaz y accesibilidad

`interior.gd`, `ship_deck_layout.gd` y `ship_corridors.gd` implementan cuerpo, zonas, conexiones físicas, puertas y controles. Museo, playa, lectores, guardianes, asientos y mesas se conectan a ese recorrido. No se debe sustituir una conexión física por una pantalla de carga al añadir contenido.

`ui/app.gd` organiza navegación de pantallas y abre editores/consolas; es un punto de integración grande que exige reserva específica. Los perfiles de controles, táctil, legibilidad, subtítulos sonoros y música tienen persistencia local. La existencia de un perfil de texto o subtítulos no certifica por sí sola accesibilidad completa de todas las pantallas ni cobertura íntegra de traducción.

### Integraciones, recursos y distribución

`net/telemetry.gd`, `foundry_authority.gd` y `foundry_projection.gd` separan transporte local opt-in, concesiones revocables, esquema de órdenes y campos autorizados. `integrations/foundry/` implementa el cliente opcional y workspace. `server/` y `compose.yaml` proporcionan la ruta headless; nada de ello sustituye el núcleo standalone.

`art/` conserva Blender y generadores; `game/assets/` contiene recursos de ejecución/laboratorios; `docs/` incluye galerías, manifiestos y evidencias. Las colecciones planetarias, estaciones o modelos tácticos no equivalen automáticamente a destinos/mecánicas integrados. `third_party/`, créditos y procedencia mantienen fronteras de recursos; `recovery/` conserva documentación de recuperación, no otra fuente de autoridad.

`tools/bootstrap.py`, construcción, captura, empaquetado y verificadores alimentan los workflows. `tests/release_092/` prepara y ejecuta aceptación dentro del binario descargable; no se debe asumir que una plantilla oficial ejecute un script externo. La CI canónica y la publicación son circuitos distintos y no se alteran en #72.

## Hallazgos que no deben perderse

| Hallazgo comprobado | Consecuencia y tratamiento |
| --- | --- |
| AGENTS conservaba una exclusividad histórica de Atlas ya liberada en #7. | Se corrige en la adopción; sigue siendo obligatorio comprobar reservas posteriores. No se libera trabajo ajeno por silencio. |
| La lectura inicial de milestones estaba vacía; otra sesión creó cuatro hitos y asignaciones durante esta tarea. | La vista previa abortó sin escrituras. Se reconciliaron configuración y roadmap conservando títulos, descripciones y asignaciones existentes; sólo se proponen los dos hitos que faltan. La aplicación y lectura posterior se registran en #72. |
| `docs/ARCHITECTURE.md` conserva afirmaciones antiguas sobre telemetría sólo GET, asientos locales y el volumen de fuentes/modelos. | Contrastar con `telemetry.gd`/`foundry_authority.gd`, `seat_presence.gd` y el árbol fijado. La guía necesita actualización en un carril reservado; no se modifica fuera del CLAIM de #72. |
| Existe `CosmographyCatalog` con validación jerárquica e importación, pero la búsqueda de referencias en producción no encuentra consumidores fuera de su definición. | Su existencia no completa atlas, persistencia, rutas y navegación. Las referencias visibles en tests comprueban el límite de texto/importación; se mantiene el pendiente funcional. |
| `CosmographyCatalog.from_hyg` atribuye `GPL-2.0-or-later` a la entrada raíz generada, mientras el remake declara MIT. | Revisar la procedencia pretendida antes de integrar ese importador. Es una inconsistencia de metadatos observada, no una conclusión jurídica sobre todo el código ni permiso para cambiar licencias sin comprobarlas. |
| `docs/parity/issue32_inventory.json` declara `coverage.complete=false`. | La validación estructural no autoriza cerrar la 1.0. Conservar G0–G3 y decisiones autorizadas, sin sumar modelos/PRs como porcentaje de paridad. |
| #29 separa corrección/aceptación automatizada y confirmación del informante. | No inventar una prueba en el equipo de Varo; conservar el criterio humano pendiente. |

Los hallazgos fuera del ámbito de gobernanza se dejan documentados para sus carriles existentes (#1/#32); no se convierten en cambios de runtime o licencias dentro de este PR.

## Pruebas de esta entrega y reproducción

El alcance nuevo es documental y de herramientas. Se ejecutan las **47 pruebas centrales** intactas y **25 pruebas locales**: integridad/procedencia, configuración explícita, enlaces, permisos y eventos de CI, negativos de comandos, inventario determinista, archivos no versionados, cambios locales, enlaces simbólicos, gitlinks, datos truncados, límites y contenedores corruptos. Los fixtures son sintéticos y temporales.

```sh
python3 tools/platino.py check .platino.json
python3 -m unittest discover -s docs/platino/upstream/tests -v
python3 -m unittest discover -s tests/platino -v
python3 tools/repository_inventory.py --revision f2015279bb7a8c307352a9526d1942a9df047ac4 > inventario-base.json
git diff --check
```

El inventario registra ruta, modo, blob Git, bytes, SHA-256, categoría y comprobaciones aplicables por archivo. Lee objetos locales de un commit, no el working tree, no sigue symlinks, no inicia submódulos/LFS ni descarga objetos faltantes. Requiere tener localmente el commit solicitado; si falta o supera el límite de lectura, falla, en vez de afirmar cobertura parcial como completa. El informe es determinista y no contiene cuerpos de archivos.

La CI aditiva genera el inventario del candidato en un artefacto de 14 días. El informe del corte inicial se puede reproducir con el comando anterior; el del candidato incluirá también los archivos nuevos de adopción. Los SHA y enlaces de ejecución final se anotan en el PR/#72, no se inventan aquí antes de existir.

**Límites:** esta revisión no ejecuta Godot o Blender localmente, no repite un playtest humano ni una instalación física de todas las plataformas y no verifica cada requisito semántico de todos los módulos. Tampoco estudia cada commit histórico o rama como si formara parte de main. No se afirma que el juego esté libre de errores ni que la paridad esté terminada.
