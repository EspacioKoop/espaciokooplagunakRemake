# Roadmap y milestones

Este documento es la vista humana del plan. Los títulos, descripciones e issues comprometidos se declaran explícitamente en `.platino.json`; un issue sin milestone no se asigna por inferencia.

Las cuatro milestones siguientes están activas en GitHub. No tienen fecha de vencimiento hasta que el equipo acuerde fechas reales.

## Hitos de producto

| Milestone | Alcance | Criterio de salida | Estado |
| --- | --- | --- | --- |
| 1.0 — Paridad funcional | Completar los pendientes reales de `FEATURE_PARITY.md` y verificar standalone | Issue #1 actualizado, pruebas canónicas verdes y release verificable | Activa; issues #29 y #32 |
| Cosmografía y navegación | Sistema `plane → star_system → planet`, importación, procedencia y conexiones | Evidencia reproducible y pruebas de navegación/carga | Activa; issues #56 y #59 |
| Contenido y catálogo | Inventario restante de escenarios, bestiario, objetos, arte y audio | Catálogo documentado y consumido por el ejecutable | Activa; issues #2, #3, #6 y #52 |
| Plataforma y publicación | Validación de exportaciones y paquetes soportados | Artefactos publicados con sumas y pruebas de plataforma | Activa; issues #4, #5 y #30 |

Las asignaciones vigentes están reflejadas en `.platino.json`. No se asignaron el plan maestro #1, el registro #7, PRs abiertos ni debates no aprobados. Los cambios de alcance se registran mediante PR.

## Reglas de entrega

- Un milestone de publicación sólo se cierra después de publicar y verificar sus artefactos.
- Un PR abierto, una captura o un check histórico no convierten una capacidad en terminada.
- Los cambios de alcance se registran en el issue maestro y en el manifiesto mediante PR.
- No se borran ni se cierran milestones para ocultar pendientes.
