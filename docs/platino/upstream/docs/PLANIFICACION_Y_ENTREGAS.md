# Planificación y entregas

[Inicio](../README.md) · [Cooperación](COOPERACION_AUTONOMA.md) · [Automatización](AUTOMATIZACION.md)

## Una fuente para cada pregunta

| Pregunta | Fuente canónica | No equivale a |
| --- | --- | --- |
| ¿Qué va primero ahora? | Plan maestro | Permiso para saltarse controles |
| ¿Quién puede editar qué? | Registro único de reservas | Un assignee o una tarjeta de Project |
| ¿Qué debe cumplir una tarea? | Issue y sus decisiones registradas | Una lista abreviada del README |
| ¿Qué fases y exclusiones tiene el producto? | ROADMAP del proyecto | Una segunda cola diaria |
| ¿Qué alcance está comprometido para una entrega? | Milestone y sus issues | Un porcentaje de calidad |
| ¿En qué estado operativo está cada elemento? | Project, cuando se adopte | Autoridad de merge o de reservas |
| ¿Qué cambio se ha revisado e integrado? | PR, commit y controles sobre ese SHA | Una publicación distribuible |
| ¿Qué se puede instalar o usar? | Release y artefactos identificados | El HEAD actual del repositorio |

El plan resuelve prioridades, no invalida aceptación, privacidad, instrucciones locales ni CI exigida. Ante fuentes incompatibles, detén el alcance afectado y registra la resolución de la autoridad del proyecto. Los resúmenes enlazan a las fuentes; no mantienen cifras o estados paralelos sin fecha y SHA.

## Roadmap y milestones

Cada proyecto mantiene un ROADMAP enlazado desde README y AGENTS, con objetivo de cada fase, alcance incluido y excluido, dependencias, issues canónicos y criterio de salida observable. Puede ser breve: no se exige un número de fases, motor o versión final comunes.

Para entregas versionadas, usa por defecto un milestone por versión objetivo. Un milestone de investigación, migración o documentación puede ser un hito sin release: decláralo expresamente. La asignación de un issue a una versión es una decisión de alcance, no algo que deba adivinar un agente por palabras del título.

Un issue sin milestone está pendiente de planificación, descartado con motivo o fuera de un compromiso de versión; no significa que carezca de importancia. El responsable de triaje decide y lo registra. No rellenes fechas, responsables o versiones inventados para lograr un tablero completo.

Si una épica atraviesa versiones, divide tareas independientes y sitúa los hijos en su entrega real; no prometas que toda la épica acaba porque se haya integrado un PR parcial. Los cambios de versión se justifican en el issue y se reflejan en el roadmap cuando alteran el alcance. No se borra trabajo pendiente para hacer subir el porcentaje.

**La capacidad de empaquetar debe preceder a la primera release que la necesite.** No prometas releases intermedias de un port si la exportación aparece al final del roadmap. Separa web, escritorio u otras líneas de producto y especifica qué distribuye cada artefacto.

## Projects sin estados inventados

Projects es opcional. Antes de automatizarlo, lee su propietario, identificador, permisos, campos y opciones reales. Registra en la ficha de adopción qué contenido entra, qué campo representa el estado y cómo se mapea cada transición. No hardcodees identificadores de otro proyecto ni supongas que existen `Todo`, `In Progress` o `Done`.

Distingue el backlog de **issues** de la cola de entrega de **PR**: un PR con CI fallida, conflictos o pendiente de decisión no describe necesariamente el estado completo del issue. Una reserva pausada sigue vigente aunque la tarjeta esté bloqueada. `PR_READY` tampoco significa terminado. Un issue sólo pasa a terminado tras satisfacer toda su aceptación y verificar la integración correspondiente.

Las automatizaciones nativas pueden reflejar hechos verificables como apertura o integración de un PR. No deben inferir aceptación funcional, playtesting, autorización de merge, caducidad de CLAIM ni publicación de una release. Si no hay acceso al Project, declara que su sincronización queda pendiente: no fabriques estados ni amplíes permisos.

## Publicación con evidencia

Antes de publicar una release, su responsable comprueba y deja constancia de:

1. Alcance aceptado, issues pendientes y exclusiones; ningún bloqueo de publicación sin resolver.
2. SHA exacto del candidato y controles exigidos sobre él, no sobre un commit anterior.
3. Exportación o empaquetado reproducible, artefactos del producto y plataforma correctos, e integridad verificable mediante hashes cuando proceda.
4. Instalación y recorrido de aceptación exigido, con entorno y resultado. Pruebas automáticas, revisión humana y playtest son evidencias diferentes.
5. Notas de cambios, limitaciones, compatibilidad/migración y autorización de publicación registrada.

Un borrador de release no es una publicación. Un milestone al 100 % no dispara por sí solo una release. Una etiqueta no demuestra que exista un binario. No se marca como probada una interacción humana que nadie ha realizado.

Cuando se use versionado semántico, alinea manifiestos, etiqueta y notas; identifica las pre-releases con su canal y sufijo. La versión objetivo de un milestone puede agrupar varios candidatos, pero sólo se cierra cuando se verifica su criterio de salida. Para un milestone de publicación, esto incluye la release publicada y sus artefactos; para otros hitos, la evidencia acordada. No se borran ni reescriben tags publicados para ocultar defectos.

## Estado honesto y trampas conocidas

El README separa lo disponible en una release de lo integrado pero todavía no publicado. Toda cifra de pruebas o afirmación de estado lleva fecha, SHA, comando o enlace a evidencia, entorno y límites. Ante una reescritura, declara qué versión o plataforma se ha probado. Una prueba local no se presenta como CI verde.

Cada AGENTS local incorpora una sección breve de **trampas conocidas**: archivo o contrato afectado, invariante, fallo ocurrido, regresión que lo detecta y referencia al issue o PR. Generaliza el aprendizaje —preservar contratos, guardar antes de operaciones interrumpibles, probar fallos— sin imponer el formato de datos o motor de otro juego. Revisa o retira las entradas que dejen de ser ciertas, con explicación.

## Adopción y actualización

Al comenzar cada sesión, el agente lee el AGENTS local, la revisión de normas adoptada, plan, reservas e issue con comentarios. La [ficha de adopción](../templates/ADOPCION.md) registra el commit completo de las normas y la última revisión; una referencia a `main` por sí sola no permite reproducir qué instrucciones se aplicaron.

Consulta las novedades centrales al iniciar trabajo con acceso, compara con la revisión adoptada y propón su adaptación por PR. No reemplaces AGENTS automáticamente, no ejecutes scripts descargados sin revisión y no borres convenciones locales. Sin acceso, usa la copia revisada disponible y declara que no se han comprobado novedades. La CI puede validar archivos y contratos técnicos, pero **no demuestra que cualquier agente haya leído o entendido las normas**.

## Procedencia

Generalización del [PR expediente-legado #183](https://github.com/EspacioKoop/expediente-legado/pull/183), revisado en su cabeza `40330ed684078a957a02db5a2955a43ef219dfc7`. Se conservan la separación de fuentes, el roadmap explícito, la evidencia y las trampas conocidas. No se importan sus milestones concretos, números de issue, personas, motor ni políticas de cinemáticas.

El contenido del ROADMAP de esa revisión presupone estados genéricos de Project, mientras la descripción del PR distingue una cola de PR y un backlog. Por eso esta norma exige comprobar el esquema real antes de sincronizar. Las decisiones de un ejemplo no se copian como si fueran contratos universales.
