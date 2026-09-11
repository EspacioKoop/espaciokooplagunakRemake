# AGENTS.md — protocolo obligatorio de colaboración

Este repositorio se desarrolla con varias sesiones/agentes en paralelo. El objetivo es terminar la paridad de producto con `EspacioKoop/espaciokooplagunak@fecd0740545f485d2402c6dfe4b47d5a859cb96c` sin convertir el remake en un fork ni reintroducir Foundry como núcleo.

## 0. Fuente de verdad

Antes de editar cualquier archivo, lee:

1. `README.md`
2. `docs/FEATURE_PARITY.md`
3. issue **#1 — Paridad final con espaciokooplagunak original**
4. issue **#7 — [COORDINACIÓN] Registro de carriles y reservas de agentes**
5. el issue concreto de tu carril (#2, #3, #4, #5, #6 o uno nuevo aprobado en #7)

El **último SHA completamente verde** está siempre escrito en la cabecera del issue #1. No asumas que el HEAD de `main` está verde si la sesión coordinadora está integrando algo en ese momento.

### Normas Platino adoptadas

Este proyecto adopta `EspacioKoop/normas_platino@b5e01a2b2060a31268507797708a92a7d14ffc52`.
Antes de editar, lee también [`docs/NORMAS_PLATINO.md`](docs/NORMAS_PLATINO.md),
[`docs/normas-platino/COOPERACION_AUTONOMA.md`](docs/normas-platino/COOPERACION_AUTONOMA.md)
y [`docs/normas-platino/PLANIFICACION_Y_ENTREGAS.md`](docs/normas-platino/PLANIFICACION_Y_ENTREGAS.md).
La adopción refuerza este contrato; no reemplaza las reservas, excepciones ni decisiones específicas del remake.

## 1. Prohibido trabajar sin reserva

Antes de modificar nada:

- revisa los comentarios de #7 y del issue elegido;
- publica en #7 un comentario con formato:

`CLAIM issue=#N agent=<nombre> branch=agent/N-slug files=<rutas principales> goal=<objetivo concreto>`

- vuelve a leer #7 justo después de publicar;
- si hay dos CLAIM que se solapan, **gana el más antiguo por timestamp de GitHub**;
- el agente posterior debe cambiar de carril, reducir su alcance a archivos no solapados o publicar `RELEASE` y reclamar otro.

Nunca des por reservada una tarea sólo porque el usuario te la describió. La reserva vive en GitHub.

## 2. Ramas y `main`

- **Nunca empujes directamente a `main`** salvo que seas la sesión coordinadora explícitamente indicada en #7.
- Crea rama propia: `agent/<issue>-<slug>`.
- Un issue grande puede dividirse en varios agentes sólo si sus archivos/criterios de aceptación no se solapan; cada subcarril requiere su propio CLAIM y PR.
- No uses `--force` sobre ramas ajenas ni reescribas historia compartida.
- Antes del PR, actualiza tu rama contra el `main` actual y resuelve únicamente conflictos de tus archivos reservados. Si el conflicto está en trabajo ajeno, documenta `WAITING_ON` en #7 en vez de pisarlo.

## 3. Carril reservado por la sesión coordinadora

Hasta que #7 diga lo contrario, NO tocar desde otros agentes:

- Atlas/cosmografía/navegación sectorial.
- `game/core/cosmography_catalog.gd`
- cambios de atlas dentro de `game/core/expedition_systems.gd`
- futuras UI/tests de cosmografía que estén reclamadas por la sesión coordinadora.

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

- implementación utilizable desde el ejecutable;
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

No edites el workflow para saltarte una prueba roja. Arregla el problema.

## 8. Protocolo de PR

Al terminar:

1. Abre PR hacia `main` desde tu rama.
2. Enlaza el issue (`Closes #N` sólo si el PR cierra todo ese issue; si no, `Refs #N`).
3. Declara archivos principales, comportamiento añadido y pruebas.
4. Publica en #7:

`PR_READY issue=#N branch=<rama> pr=#M tests=<resumen>`

5. No hagas merge por tu cuenta salvo instrucción explícita de la sesión coordinadora/usuario.

Si abandonas:

`RELEASE issue=#N branch=<rama> reason=<motivo>`

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
