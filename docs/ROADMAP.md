# Roadmap y milestones

Este documento es la vista humana del plan. Los títulos y issues comprometidos se declaran explícitamente en `.platino.json`; un issue sin milestone no se asigna por inferencia.

## Hitos de producto

| Milestone | Alcance | Criterio de salida | Estado |
| --- | --- | --- | --- |
| 1.0 — Paridad funcional | Completar los pendientes reales de `FEATURE_PARITY.md` y verificar standalone | Issue #1 actualizado, pruebas canónicas verdes y release verificable | Pendiente de aprobación |
| Cosmografía y navegación | Sistema `plane → star_system → planet`, importación, procedencia y conexiones | Evidencia reproducible y pruebas de navegación/carga | Pendiente |
| Contenido y catálogo | Inventario restante de escenarios, bestiario, objetos, arte y audio | Catálogo documentado y consumido por el ejecutable | Pendiente |
| Plataforma y publicación | Validación de exportaciones y paquetes soportados | Artefactos publicados con sumas y pruebas de plataforma | Pendiente |

Estos nombres son una propuesta inicial para ordenar las milestones nuevas. Antes de crearlas en GitHub, el equipo debe aprobar títulos, descripciones, fechas e issues asignados y reflejarlos en `.platino.json`.

## Reglas de entrega

- Un milestone de publicación sólo se cierra después de publicar y verificar sus artefactos.
- Un PR abierto, una captura o un check histórico no convierten una capacidad en terminada.
- Los cambios de alcance se registran en el issue maestro y en el manifiesto mediante PR.
- No se borran ni se cierran milestones para ocultar pendientes.
