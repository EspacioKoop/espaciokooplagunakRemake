# AGENTS.md — protocolo obligatorio de colaboración

Este repositorio se desarrolla con varias sesiones/agentes en paralelo. El objetivo es terminar la paridad de producto con `EspacioKoop/espaciokooplagunak@fecd0740545f485d2402c6dfe4b47d5a859cb96c` sin convertir el remake en un fork ni reintroducir Foundry como núcleo.

## 0. Fuente de verdad

Antes de editar cualquier archivo, lee:

1. `README.md`, `CONTRIBUTING.md`, `docs/PLATINO_ADOPTION.md` y `docs/ROADMAP.md`
2. `docs/FEATURE_PARITY.md`
3. issue **#1 — Paridad final con espaciokooplagunak original**
4. issue **#7 — [COORDINACIÓN] Registro de carriles y reservas de agentes**
5. el issue concreto de tu carril (#2, #3, #4, #5, #6 o uno nuevo aprobado en #7)

Lee además la copia revisada de [cooperación](docs/platino/upstream/docs/COOPERACION_AUTONOMA.md), [planificación](docs/platino/upstream/docs/PLANIFICACION_Y_ENTREGAS.md) y [automatización](docs/platino/upstream/docs/AUTOMATIZACION.md), fijada en la ficha de adopción. Sus ejemplos y números de issue pertenecen al repositorio central: **aquí el plan es #1 y el único registro es #7**. La copia `upstream` es una referencia inmutable, no otro carril de trabajo.

#1 conserva checkpoints, pero una cabecera puede quedar atrasada: verifica siempre el SHA y la ejecución canónica enlazada en el issue/PR de entrega. No presupongas que `main` esté verde ni que equivalga a la última release. Una contradicción se registra y resuelve con la autoridad del proyecto, sin saltarse privacidad, aceptación o CI.

## 1. Prohibido trabajar sin reserva

Antes de modificar nada:

- revisa el cuerpo y todos los comentarios paginados de #7 y del issue elegido; si la lectura está incompleta, no presupongas una reserva libre;
- publica en #7 un comentario con formato:

`CLAIM issue=#N agent=<nombre> branch=agent/N-slug files=<rutas principales> goal=<objetivo concreto>`

- vuelve a leer #7 justo después de publicar;
- si hay dos CLAIM que se solapan, **gana el más antiguo por fecha de creación de GitHub; en empate, el menor ID de comentario**;
- el agente posterior debe cambiar de carril, reducir su alcance a archivos no solapados o publicar `RELEASE` y reclamar otro.

Nunca des por reservada una tarea sólo porque el usuario te la describió. La reserva vive en GitHub.

## 2. Ramas y `main`

- **No empujes directamente a `main`**, tampoco por una autorización histórica de otra sesión. La integración se realiza por PR con autorización explícita y controles satisfechos; coordinar no exime de ese circuito.
- Crea rama propia: `agent/<issue>-<slug>`.
- Un issue grande puede dividirse en varios agentes sólo si sus archivos/criterios de aceptación no se solapan; cada subcarril requiere su propio CLAIM y PR.
- Usa checkout/worktree propio; no alteres cambios desconocidos. Prohibidos force-push y reescritura compartida. Conserva commits pequeños y súbelos antes de una pausa, tras revisar diff, privacidad y estado remoto.
- Antes del PR, actualiza tu rama contra el `main` actual y resuelve únicamente conflictos de tus archivos reservados. Si el conflicto está en trabajo ajeno, documenta `WAITING_ON` en #7 en vez de pisarlo.

## 3. Reservas vigentes, no propietarios históricos

Sólo #7 determina la titularidad activa. La antigua exclusividad de Atlas/cosmografía fue liberada expresamente en [5626070739](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7#issuecomment-5626070739): no se conserva como un bloqueo perpetuo en este archivo. Eso **no** otorga una reserva nueva; comprueba las reclamaciones posteriores antes de tocar Atlas o cualquier otro sistema.

Una ampliación de archivos requiere otro CLAIM y relectura; su prioridad nueva sólo cubre el alcance añadido. Un archivo compartido necesita un único escritor o una secuencia acordada explícitamente, incluso si se proponen regiones distintas. No basta con tener issues, assignees o tarjetas diferentes.

## 4. Archivos calientes: coordinación obligatoria

Aunque tu issue sea diferente, no modifiques estos archivos sin declararlo expresamente en tu CLAIM y comprobar que nadie los tiene reservados:

- `game/project.godot`
- `game/net/session.gd`
- `game/core/simulation.gd`
- `game/core/ship_operations.gd`
- `game/core/ship_model.gd`
- `game/core/space_physics.gd`
- `game/core/expedition_systems.gd`
- `.github/workflows/release.yml`
- `README.md`
- `docs/FEATURE_PARITY.md`
- `AGENTS.md`, `CONTRIBUTING.md`, `docs/PLATINO_ADOPTION.md`, `docs/ROADMAP.md`
- `.platino.json`, `docs/platino/`, herramientas/workflows de Platino y metadatos de milestones

Cuando sea posible, añade un componente nuevo en vez de ensanchar un archivo caliente.

## 5. Arquitectura que no se negocia

- **Standalone-first**. El juego debe arrancar, jugar campaña, guardar y hacer red sin Foundry.
- Foundry, Discord, Docker y herramientas externas son adaptadores/opcionales.
- **Una autoridad por dato**: no dupliques estado entre sistemas.
- En multijugador, el **host es autoritativo** para reglas, daño, economía, secretos y resultados.
- Un cliente sólo recibe lo que necesita. No filtres cartas, dados privados, credenciales, inventario de otros ni información oculta.
- Mantén compatibilidad de guardado/protocolo o incluye migración/versionado explícito.
- No copies código/assets del original: reimplementa funcionalidad con código y recursos propios.
- No añadas prototipos, TODO visuales, placeholders ni botones sin mecánica real.
- No conviertas accesos físicos de la nave en pantallas de carga o teleportes cuando existe recorrido seamless.

## 6. Calidad mínima de cada entrega

Cada PR debe incluir:

- implementación utilizable desde el ejecutable cuando cambia el juego; para documentación/herramientas, un resultado utilizable y verificable en su propio ámbito;
- validación de entradas/límites/autorización;
- pruebas automáticas nuevas para la nueva lógica;
- actualización de pruebas existentes si el comportamiento cambia deliberadamente;
- cero `SCRIPT ERROR`/`ERROR` nuevos en Godot;
- cero secretos o credenciales en commits;
- documentación mínima sólo cuando ayuda a usar/mantener la función.

Si tocas red, privacidad, guardados, autoridad o formatos: añade casos negativos, no sólo happy path.

## 7. Tests y CI

La referencia de cierre es `.github/workflows/release.yml`. No declares terminado un carril sólo porque una prueba local concreta pasa.

Antes del PR ejecuta todo lo que puedas del área. En el PR enumera exactamente las pruebas ejecutadas. La sesión coordinadora decidirá si hace falta ampliar CI antes de merge.

No edites el workflow para saltarte una prueba roja. Arregla el problema. Conserva también los workflows específicos exigidos para el área y verifica todos sobre el SHA final. Pruebas locales, CI, pruebas gráficas automatizadas y playtest humano son evidencias distintas.

Para cambios de Platino, desde la raíz con Python 3.11 o posterior:

```sh
python3 tools/platino.py check .platino.json
python3 -m unittest discover -s docs/platino/upstream/tests -v
python3 -m unittest discover -s tests/platino -v
git diff --check
```

La validación aditiva es `.github/workflows/platino.yml`; no reemplaza la CI canónica. Nunca afirma que una IA haya leído o entendido las normas.

## 8. Protocolo de PR

Al terminar:

1. Abre PR hacia `main` desde tu rama.
2. Enlaza el issue (`Closes #N` sólo si el PR cierra todo ese issue; si no, `Refs #N`).
3. Declara archivos principales, comportamiento añadido y pruebas.
4. Publica en #7:

`PR_READY issue=#N agent=<nombre> branch=<rama> pr=#M claim=<comentario> sha=<SHA> tests=<resumen> ci=<run/estado> pending=<límites>`

5. No hagas merge por tu cuenta salvo instrucción explícita de la sesión coordinadora/usuario.

`PR_READY` no autoriza merge, no cierra el issue y **no libera la reserva**. Antes de integrar, la persona autorizada relee PR, revisiones, base/cabeza, reservas y checks; usa protección del SHA esperado y verifica el commit resultante y su CI.

Para pausar: `PAUSE` o `WAITING_ON`, con issue, agente, CLAIM, rama, SHA, motivo y siguiente paso. La reserva no caduca por silencio, un fallo de CI o un estado de Project. `RESUME` exige comprobar que sigue siendo tuya.

Al completar o abandonar, publica explícitamente:

`RELEASE issue=#N agent=<nombre> claim=<comentario> branch=<rama> sha=<SHA> reason=<motivo> next=<paso pendiente>`

Conserva el checkpoint y el estado del PR antes de liberar. Para retomar una reserva liberada, publica un CLAIM nuevo. El mensaje `RELEASE` libera trabajo; **no publica una GitHub Release**.

## 9. Si entran más agentes

No hay límite conceptual de agentes, pero sí de áreas independientes. Cuando todos los carriles estén reclamados:

- busca dentro de un issue un subproblema con archivos y tests claramente independientes;
- comenta una propuesta de subdivisión en #7;
- reclama sólo esos archivos/objetivo;
- si no existe una división limpia, no empieces a editar: ayuda revisando un PR, escribiendo tests que no toquen archivos reservados o auditando paridad y abre un issue nuevo con evidencia.

Nunca “aceleres” creando dos implementaciones del mismo sistema.

## 10. Estado y comunicación

GitHub es el registro persistente. Cada agente debe dejar suficiente contexto en issue/PR para que otra IA pueda retomar sin memoria de chat.

La sesión coordinadora mantiene #1 como plan maestro y #7 como registro de reservas. Si una conversación se pierde, esos dos issues y los SHAs/PRs son la ruta de recuperación.

## 11. Roadmap, milestones y publicación

[ROADMAP](docs/ROADMAP.md) define fases y exclusiones; #1 prioriza; el issue define aceptación; #7 reserva; la milestone agrupa alcance; el PR demuestra integración y la release identifica lo instalable. No cierres épicas por una entrega parcial ni inventes versiones/fechas para completar el tablero.

`.platino.json` enumera decisiones explícitas. `check` es local; `sync` sólo consulta por defecto. Aplicar requiere revisar el plan, reservar metadatos como único escritor y proporcionar su huella exacta con `--apply --approve`. No mueve issues ya asignados ni modifica milestones manuales incompatibles. El workflow manual sólo usa código confiable de `main`; no existe sincronización por PR, cron, auto-merge o porcentaje de completitud. Projects no está adoptado: no inventes campos o permisos.

Antes de publicar: alcance aceptado, exclusiones, SHA exacto, checks exigidos, paquetes/instalación/hashes, recorrido requerido, límites y autorización registrada. No cambies tags/activos publicados. El cierre de 1.0 exige los gates G0–G3 y el inventario completo, no contar PRs ni modelos.

## 12. Trampas conocidas

| Contrato | Invariante / fallo observado | Regresión y referencia |
| --- | --- | --- |
| `game/core/storage.gd` | Preservar precisión numérica del JSON y validar antes de sustituir el guardado; una copia recuperable no demuestra tolerancia a cortes eléctricos. | `tests/test_storage_properties.gd`, `tests/test_storage_runtime.gd`; #48. |
| `game/net/session.gd` | Sólo peers autenticados reciben presencia/notificaciones; la contraseña autentica pero ENet no cifra. | `tests/test_authenticated_aux_rpc.gd`, `tests/test_network_boundary.gd`; #18/#45 y SECURITY.md. |
| Terminales y `game/release_acceptance/` | Abrir, usar, cerrar y reabrir en el ZIP real. Las plantillas oficiales no permiten asumir ejecución de `--script` externo. | `tests/release_092/`; #29/#68. La confirmación humana de #29 sigue separada. |
| `docs/parity/issue32_inventory.json` | `coverage.complete=false` no es paridad completa aunque el validador estructural pase. | `tools/check_parity_evidence.py --help`, `tests/test_parity_evidence.py`; #36/#32. |
| Biblioteca 3D y exportación | Modelo/laboratorio/galería no equivalen a mecánica integrada; incluir manifiestos locales en el paquete. | `tests/release_092/test_export_contract.gd`; #52/#68. |

Revisa las rutas y vigencia al modificar un contrato; retira una trampa obsoleta con justificación y conserva la regresión que corresponda.

## 13. Actualización y límites de autonomía

Al comenzar con acceso, compara las novedades centrales con el SHA de `docs/PLATINO_ADOPTION.md`; su adaptación se propone por PR, nunca descargando/ejecutando automáticamente `main` ni sobrescribiendo reglas locales. Sin acceso, usa la copia revisada y declara que no has contrastado novedades.

El mandato no autoriza cambios en otros repositorios, ampliación de credenciales, automatizaciones persistentes o exposición de datos de jugadores. No publiques partidas, preferencias, tokens, registros privados ni capturas identificables; usa datos sintéticos y evidencias públicas acotadas. Al acabar, sólo elige otro bloque si está dentro del encargo vigente y libre en #7.
