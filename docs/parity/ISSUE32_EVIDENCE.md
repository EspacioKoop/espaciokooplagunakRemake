# #32 — Inventario inicial y evidencia pendiente

**Referencia original:** `fecd0740545f485d2402c6dfe4b47d5a859cb96c`. **Lectura del remake:** `8b1dcf27683a00972b03d5203606eab12f31fe2d`. Este documento recoge el bloque P0 de inventario/evidencias de [#32](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32); no cierra ese issue ni certifica la 1.0.

La fuente editable es [issue32_inventory.json](issue32_inventory.json). El [comprobador](../../tools/check_parity_evidence.py) genera la tabla completa, incluida una fila por declaración de nave del catálogo actual, sin duplicar los datos numéricos. [Uso y reglas de evidencia](README.md).

## Original → remake: bloques de trabajo

Esta tabla es una vista del alcance inicial, no el inventario exhaustivo de cada escenario, libro o recurso. Los números de issue indican responsabilidad de seguimiento, no reservas de archivos ni asignaciones personales. «Parcial» se refiere al alcance/evidencia de la fila; no anula las pruebas previas de los sistemas base.

| Elemento original o requisito por contrastar | Equivalente actual | Estado del alcance | Decisión de trabajo | Responsable y cierre pendiente |
|---|---|---|---|---|
| Paseo y uso de terminales | Interiores nativos, incidencia Linux | Parcial | Reimplementar/corregir | #29: reproducir y probar los 13 destinos, abrir/cerrar/reabrir sin crash |
| Autoridad, red y guardados | Session, campaña y almacenamiento local | Parcial en evidencias del candidato | Sustituir por sistemas propios | #1: adjuntar regresiones, migraciones e identidades al SHA candidato |
| Linux/Windows | Paquetes y smoke canónico | Parcial en evidencias del candidato | Sustituir distribución | #4: build/exportación/checksums/arranque del mismo SHA |
| Android/macOS | Preflight/exportador | Parcial | Completar | #4: dispositivo real, ejecución y condiciones de distribución |
| Host headless | Servidor observador Docker/Compose | Parcial en evidencias del candidato | Sustituir servidor | #5: contenedor, reinicio, persistencia y alcance GM remoto |
| «Lagunak: Primera guardia» | Seis misiones nuevas no acreditan equivalencia individual | Pendiente | Reimplementar con contenido propio | #2: objetivos, fases, desenlaces y recompensas contrastados |
| Resto de escenarios y dependencias | Editor nativo multi-misión | Parcial | Reimplementar el corpus | #2: inventario por escenario y dependencia; editor no equivale a migración |
| Bestiario/inventario/libros/hitos/conjuros | Sistemas persistentes base | Parcial; consumidores originales por auditar | Reimplementar lo perteneciente al producto | #2: recurso por recurso, procedencia, uso, progresión y guardado |
| Generador NPC semilla/desafío | Fichas y NPC de ocio no acreditan el motor equivalente | Pendiente | Reimplementar | #2: determinismo, límites, afinidades, acciones y uso por GM |
| Jerarquía cosmográfica, HYG, rutas y continuidades | Atlas base por sector | Parcial | Reimplementar | #1: carril Atlas reservado; prueba de viaje, importación y persistencia |
| Plantillas nominales de nave | Catálogo actual de adaptaciones y exclusiones | Parcial/pendiente por declaración | Reimplementar diferencias | #2: filas automáticas con método no soportado o motivo de exclusión |
| Cargueros dinámicos/expresiones no enumeradas | Fuera del alcance probado del catálogo actual | Pendiente | Reimplementar tras inventario | #2: configuraciones efectivas e IDs; no deducir completitud del recuento nominal |
| Asistencia con modificadores dnd5e | Cuatro minijuegos nativos y ficha propia | Parcial | Completar adaptador opcional | #5: ficha real, identidad, caducidad y consumo sólo por titular |
| Alerta para entradas tardías | Estado replicado, prueba específica no enlazada aquí | Pendiente de verificación | Auditar antes de duplicar | #5: conexión/reconexión en roja sin filtrar telemetría |
| Puestos, mapa, destino/ETA y bitácora Foundry | Puestos nativos y 13 controles opcionales | Parcial | Sustituir UI con equivalencias explícitas | #5: tabla control-a-control y prueba real de los flujos conservados |
| Consola caliente GM | Dirección base; propuesta en PR #34 | Parcial | Completar integración existente | #32: UI accesible, contactos vivos, validación, autoridad y bitácora |
| Parlamento e iniciativa social | Iniciativa táctica no acredita escena social | Pendiente | Reimplementar | #1: escena dirigida completa y consecuencias |
| Tutorial heredado citado en #32 | Ayuda F1 | Pendiente de contraste | Auditar y adaptar | #32: itinerario por puesto y prueba humana de aprendizaje |
| es-ES y accesibilidad | Panel ES/EN, remapeo/mando/táctil parciales | Parcial | Completar | #4: catálogo de todas las pantallas, gate de cobertura y accesibilidad verificable |
| Música procedural | ScoreComposer, cinco perfiles y controles locales | Parcial en alcance/evidencias restantes | Sustituir composiciones por música propia | #6: ejecución del candidato, diferencias de catálogo y escucha humana |
| Museo, arte y procedencia | Modelos Blender propios, cuadros y guardianes | Parcial | Sustituir con recursos propios | #6: correspondencia por recurso funcional y cartelas veraces |
| Expresión de avatar/NPC | Editor, presencia, asientos y poses base | Parcial | Completar tras auditar consumidores | #3: gestos, mirada y variantes restantes, privacidad y reconexión |
| Integración en una mesa Foundry real | Contratos automáticos del cliente/HTTP | Parcial | Completar comprobación de producto | #5: versión real, permisos, navegador remoto, Journal y autonomía standalone |

Las propuestas de dossier de sesión, replay/métricas, euskera, modo foto, triggers interiores y segunda pantalla están separadas como `scope: proposal`. No se usan para inflar el porcentaje de paridad ni para aumentar automáticamente el cierre de #1. Las demás ideas de §3 de #32 siguen en su issue; este inventario inicial no afirma haberlas desglosado todas.

## Catálogo de naves: evitar una falsa equivalencia

[SHIP_TEMPLATES.md](../SHIP_TEMPLATES.md) declara 38 adaptaciones y 60 declaraciones nominales examinadas excluidas. No afirma que sean el universo completo del original. Por eso el informe transforma cada entrada existente en una fila independiente con fuente/línea, ID, responsable #2 y aceptación, y mantiene además abierta la auditoría de las variantes dinámicas.

Las 38 adaptaciones no se marcan completas: hay prestaciones comunes no representadas incluso cuando `unsupported` está vacío. Las 60 exclusiones conservan sus motivos técnicos y permanecen pendientes, no aprobadas como renuncia. Una evolución del catálogo cambia automáticamente esas filas al regenerar el informe.

## Cuatro premisas reconciliadas con las fuentes

**Audio:** [REACTIVE_AUDIO.md](../REACTIVE_AUDIO.md) ya describe selección contextual, cinco perfiles, volumen/activación locales y F12, además de su prueba canónica. La frase de #32 que daba esos controles por ausentes no justifica crear otro sistema. Queda enlazar la evidencia del candidato y evaluar lo que realmente falte del catálogo y de la escucha humana.

**NPC:** el [documento original del motor](https://github.com/EspacioKoop/espaciokooplagunak/blob/fecd0740545f485d2402c6dfe4b47d5a859cb96c/docs/NPC_GENERADOR.md) excluye expresamente conversación, aparición en salas y memoria. Son propuestas distintas del motor de ficha/afinidades; no deben contabilizarse como tres pérdidas ya demostradas por esa fuente.

**Arte:** el [README original](https://github.com/EspacioKoop/espaciokooplagunak/blob/fecd0740545f485d2402c6dfe4b47d5a859cb96c/README.md) admite cuatro PNG prerrenderizados propios y escaneos CC0 con procedencia. «Generar y no distribuir» no era una regla absoluta. La paridad debe contrastar uso y contenido, no imponer una técnica de renderizado por una premisa incompleta.

**Headless:** la matriz identifica el host observador y Docker como implementados. «Observador» no demuestra que la autoridad de simulación falte. Hay que probar las operaciones GM remotas y su integración antes de proponer una segunda autoridad o dar toda la dirección por resuelta.

## Gates de cierre: resultado inicial bloqueado

| Gate | Qué debe demostrarse | Por qué no se certifica todavía |
|---|---|---|
| G0 — Integridad de plataforma | Candidato exacto: build, red, guardados, exportaciones y arranque real | Incidencia #29 y comprobaciones físicas/evidencias del candidato abiertas |
| G1 — Paridad de modelo | Contenidos y dependencias por elemento, migración, esquemas, catálogo íntegro | Cobertura declarada no exhaustiva; corpus y variantes dinámicas abiertos |
| G2 — Paridad jugable | Capacidades accesibles desde el ejecutable, autoridad y consecuencias reales | GM/escena y diferencias de integración sin cierre por prueba registrada |
| G3 — Paridad de producto | Accesibilidad, idiomas, arte/audio y validación de mesa/dispositivos | Matriz general conserva pendientes de esas áreas; no se inventa playtest |

El verificador comprueba que cada gate tenga filas de paridad. En modo estricto rechaza el cierre mientras la cobertura no sea completa y revisada, existan filas abiertas o los SHAs de las ejecuciones no correspondan al candidato. La presencia de un archivo de pruebas nunca se interpreta como una ejecución superada.

## Próxima actualización verificable del registro

Para avanzar un bloque, añadir sus fuentes originales y la correspondencia por elemento; conservar el responsable/criterio; adjuntar implementación, prueba y run reproducible del mismo SHA; actualizar el estado únicamente con esa evidencia. Las renuncias requieren decisión explícita revisable, no sólo un motivo técnico. La revisión debe comprobar el contenido real de los enlaces, que este validador sin red no autentica.

No modificar el estado histórico de releases ni las reservas del plano, la consola GM o Atlas al mantener este registro. No cerrar #1 o #32 por el mero merge de esta herramienta.
