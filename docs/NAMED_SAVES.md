# Guardados con nombre — entrega parcial conservada

Refs #32 §3.1. Rama `agent/32-named-saves-s7`; base `d7b7670c7931c63647eaf12fb8ca59619e897f3c`.

## Estado: NO INTEGRABLE

Esta rama conserva únicamente los archivos cuya publicación directa se completó: `CampaignCheckpoint`, `NamedSaveStore`, `NamedSaveWindow`, sus tres UID y la extracción de `LocalStorage.prepare_state`. **No se ha conectado el gestor al ejecutable de esta rama. No fusionar ni marcar completa la casilla de #32.**

La implementación completa se escribió y ejecutó con Godot 4.7.1, pero su publicación no se completó. Primero, el publicador temporal pasó las pruebas y falló al intentar publicar un workflow con el token de Actions. Después, el conector bloqueó la modificación del publicador y también la escritura directa de `expedition_systems.gd`. No se han solicitado permisos adicionales ni repetido la escritura bloqueada por otra vía. El publicador temporal se retiró. Se retira también el workflow permanente de esta rama parcial porque sus pruebas aún no se han publicado; esto no es un check verde ni una exención de la CI requerida para completar la entrega.

## Función desarrollada en la implementación completa

Acceso previsto y probado: **Ajustes → Guardados de campaña…**. Hasta 32 guardados con nombre, listado y vista previa; guardar, sustituir, cargar, eliminar, importar y exportar mediante archivos locales `.lagunak`.

El documento reúne los dos almacenes duraderos existentes: vuelo/progreso/campañas personalizadas y expedición —fichas, inventarios, facciones, atlas archivado, bestiario y crónica—. Importar crea un slot separado, nunca activa la partida. Cargar exige modo offline, confirmación y conservación conjunta del progreso anterior. Un cursor persistente por `run_id` evita volver a consumir eventos al restaurar/reiniciar; los archivos históricos sin ese cursor tienen el límite documentado de no poder reconstruir retrospectivamente el consumo.

El archivo puede contener datos de campaña y secretos del director; no es un informe público ni un contenedor cifrado. No hay subida a servicios, micrófono ni nueva red. Los checksums detectan corrupción accidental, no autentican al autor. Las pruebas sólo usan datos sintéticos y perfiles aislados; no se consultaron partidas privadas.

La restauración cancela mesas, encuentros tácticos y otras capacidades transitorias que el formato nativo no guarda. No reasigna identidades de jugadores al cambiar de equipo. Los dos archivos nativos se instalan con copia y recuperación ante errores gestionados, pero **no son una transacción atómica ante cortes eléctricos o escritores concurrentes**.

## Evidencia de la implementación completa, NO de esta rama parcial

[Run 34607657304](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/runs/34607657304): importación y pruebas correctas; el paso posterior de publicación falló. Por tanto, el resultado global del workflow no se presenta como success.

[Artefacto de pruebas y captura real 10266313316](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/runs/34607657304/artifacts/10266313316): cuatro logs de pruebas, `report.json` con hashes de diez fuentes y `named-saves.png`. No incluye perfiles, guardados ni claves. Se descargó, se comprobó su SHA-256 y se contrastaron todos los hashes con las fuentes locales. La captura PNG 1600×900 se decodificó y revisó. El artefacto tiene la retención temporal de GitHub Actions; no se confunde con una imagen ya versionada.

- Headless: 243 comprobaciones / 0 fallos; segundo proceso de reinicio: 6 / 0.
- Interfaz real Xvfb/Mesa: 244 / 0; segundo proceso de reinicio: 6 / 0.
- 13 tests Python correctos del ejecutor y sus casos negativos.
- Regresión nativa de guardados: semillas `3204301` y `641709`, 64 muestras, 3980 comprobaciones / 0 fallos por semilla.
- Regresiones locales adicionales: núcleo 136/0, expedición 18/0, UI 63/0, audio 61/0, legibilidad 106+2/0 y cinco procesos ENet sin fallos.

Las comprobaciones comunes de las modalidades no deben sumarse como casos únicos. No hay CI canónica de la entrega completa, prueba humana entre equipos ni prueba física de corte eléctrico.

Artefacto ZIP: SHA-256 `e1275445c66fd21a6f5e8043e8c480b60b7d15dbc12ea630d5cc52f970262b6c`.
Captura: SHA-256 `053a4e3fd1c58ca1b5be7c55afe0c6b9f9fd1a394ff37b17ace0001faf2d55de`.

## Continuación

La entrega completa se conserva además en un paquete local entregado a Varo con fuentes explícitas, parche, hashes, documentación y evidencia. Esta rama no contiene ese paquete completo. Antes de continuar, reservar de nuevo en #7 y revisar el estado del PR; la reserva de esta sesión no debe bloquear a otra persona.

Falta publicar/revisar la integración de `game/core/expedition_systems.gd`, `game/net/session.gd` y `game/ui/app.gd`, los tres archivos `tests/*named_save*`, el workflow específico, la documentación de uso definitiva y la captura real. No rehacer los componentes existentes ni utilizar el publicador temporal retirado.

Verificar las fuentes completas con las pruebas y casos negativos, ejecutar la CI canónica sobre el candidato, comprobar compatibilidad con el PR #66 —que toca otros puntos de la misma shell— y sólo entonces pasar a revisión para integración. No modificar `main`, protecciones, permisos o releases para resolver una transferencia incompleta.
