# Copia revisada de Normas Platino

[Ficha local](../PLATINO_ADOPTION.md) · [Roadmap](../ROADMAP.md) · [README central copiado](upstream/README.md)

Fuente: `EspacioKoop/normas_platino`, commit completo `b5e01a2b2060a31268507797708a92a7d14ffc52`, revisado el 11/09/2026 en #72. `upstream/` conserva **los 13 archivos versionados**, byte por byte y con sus rutas relativas. No incluye `.git`, credenciales, código descargado al ejecutar ni datos de jugadores. [upstream-lock.json](upstream-lock.json) registra ruta, SHA-256 y blob Git de cada archivo.

Las tres guías son [cooperación](upstream/docs/COOPERACION_AUTONOMA.md), [planificación](upstream/docs/PLANIFICACION_Y_ENTREGAS.md) y [automatización](upstream/docs/AUTOMATIZACION.md). También se conservan las plantillas, el CLI y sus pruebas. El workflow dentro de `upstream/.github/` es sólo material de referencia: no es un workflow activo del juego.

**No editar esta copia para adaptar el proyecto.** Las adaptaciones viven en el AGENTS de la raíz, ficha, roadmap, `.platino.json` y workflows de la raíz. Los números de issue de `upstream/AGENTS.md` pertenecen al repositorio central: el registro local sigue siendo #7, no #2.

`tools/platino.py` es un lanzador de esta copia, no un segundo sincronizador. Sus pruebas originales se ejecutan sin modificar imports ni rutas, conservando sus casos negativos. Las pruebas locales adicionales verifican la integridad del snapshot y las adaptaciones.

Actualizar requiere revisar una revisión central nueva, sustituir copia y lock juntos y proponer un PR. No hay descarga automática, cron o autoaprobación. Revertir archivos no revierte milestones sincronizados: revisar los efectos remotos por separado.
