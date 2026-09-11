# Paridad funcional con el original

Referencia auditada: [EspacioKoop/espaciokooplagunak](https://github.com/EspacioKoop/espaciokooplagunak), commit `fecd0740545f485d2402c6dfe4b47d5a859cb96c`.

**Criterio de cierre:** reimplementar con código y recursos propios las capacidades del producto original que sigan formando parte del juego, accesibles desde el ejecutable standalone. Foundry es siempre un adaptador opcional.

## Checkpoint reproducible

**Release 0.9 publicada:** [v0.9.0](https://github.com/VaroTv7/espaciokooplagunakRemake/releases/tag/v0.9.0), commit `b9b5566a8e5229302508c80ebad31f2ce9b67699`, CI canónica `34508171985` y publicación `34508653674`, ambas verdes. Linux/Windows y SHA256SUMS disponibles.

Esta matriz describe también avances posteriores de `main` hacia 1.0; no los atribuye a los binarios inmutables de 0.9. El checkpoint más reciente y las reservas viven en los issues #1 y #7. La paridad total sigue abierta.

Esa pasada valida campaña y guardados, operaciones, cooperación, física, cuatro cuadrantes, colisiones dinámicas, montajes/torretas, maniobra lateral continua, atlas/facciones base, sensores avanzados, reglas de tripulación, combate táctico, IA estratégica de flotas, cinco procesos ENet reales, HTTP, UI, museo/playa/social, mesas/reconexión, cliente Foundry opcional, exportación Linux/Windows, captura del ejecutable, empaquetado y smoke real de Windows.

## Nave y puestos

| Capacidad | Estado standalone comprobado | Archivos / prueba principal |
|---|---|---|
| Ocho puestos cooperativos | **Hecho** | `simulation.gd`, `ship_operations.gd`, `session.gd` |
| Potencia, calor, refrigeración y averías | **Hecho** | `ship_model.gd`, `ship_operations.gd` |
| Impulso, reversa, viraje, warp, salto, rutas y atraque | **Hecho** | `simulation.gd`, `ship_operations.gd`, `test_operations.gd` |
| Maniobra lateral clásica | **Hecho / compatible** | `strafe` se conserva para partidas y UI existentes |
| Maniobra lateral continua | **Hecho** | `continuous_maneuvering.gd`, `maneuver_console.gd`, `test_continuous_maneuvering.gd` |
| Escudos direccionales | **Hecho: 4 cuadrantes** | babor/estribor de proa/popa, migración desde dos segmentos y desbordamiento de hemisferio en `ship_model.gd` |
| Haces/tubos clásicos | **Hecho** | frecuencia, blanco automático, guiado, nuclear, mina, EMP y HVLI |
| Montajes múltiples y torretas | **Hecho como sistema modular** | `ship_armaments.gd`, `armament_console.gd`, `test_armaments.gd` |
| Loadouts | **Hecho**: cuatro plantillas propias y catálogo de 38 variantes verificadas (#25, posterior a0.9) | selector en astillero, diseño/montajes, combate y guardado; adaptaciones y límites en `docs/SHIP_TEMPLATES.md` |
| Autodestrucción coordinada | **Hecho** | tres puestos/códigos e identidad por conexión |
| Reparación automática/equipos móviles | **Hecho** | desplazamiento físico lógico, trabajo y repuestos |
| Asistencias cooperativas | **Hecho** | temporización, secuencia, precisión, puzle, propuestas consumibles y ayuda narrativa |

**Pendiente de esta área:** migrar/crear el catálogo completo de plantillas y montajes del producto original que siga siendo relevante. La edición detallada del loadout ya está integrada en el astillero (#8), con importación/exportación y pruebas de combate real.

## Física y mundo espacial

| Capacidad | Estado |
|---|---|
| Colisión barrida con asteroides | **Hecho** |
| Gravedad de planetas/agujeros negros | **Hecho** |
| Agujeros de gusano con destino | **Hecho** |
| Nebulosas que oscurecen sensores | **Hecho** |
| Colisión nave ↔ estación | **Hecho** |
| Colisión nave ↔ nave | **Hecho**, con daño para ambos participantes cuando corresponde |
| Autopiloto frente a tráfico | **Hecho**, evasión tangencial de contactos dinámicos sin borrar la ruta |
| Suministros y artefactos recogibles | **Hecho** (#24, posterior a0.9): colisión barrida, recursos con límites, objetivos y consumo persistente una sola vez; ENet real probado |
| Variantes restantes de objetos del original | **Pendiente de completar inventario** |

`tests/test_ship_physics.gd` y `tests/test_ship_quadrants_collisions.gd` fijan el comportamiento físico y la compatibilidad de guardado.

## Sensores y ciencia

| Capacidad | Estado |
|---|---|
| Banda corta / larga | **Hecho** |
| Niveles de análisis | **Hecho: 3 niveles** |
| Identidad final restringida a corto alcance | **Hecho** |
| Sonda como origen remoto | **Hecho** |
| Interferencia / nebulosa | **Hecho** |
| Minijuego nativo de análisis | **Hecho** |
| Hackeo nativo autoritativo | **Hecho**: secuencia privada, inhibición temporal, frecuencia y limpieza de interferencia |
| Archivo científico / descubrimientos | **Hecho** |

UI: `F3`. Prueba: `tests/test_advanced_sensors.gd`.

## Personajes y combate

| Capacidad | Estado |
|---|---|
| Ficha persistente | **Hecho** |
| Habilidades y enfoques | **Hecho** |
| Probabilidad / d20 host-authoritative | **Hecho** |
| Concentración como recurso | **Hecho** |
| Rasgos | **Hecho** |
| Condición | **Hecho** |
| XP, niveles e hitos | **Hecho** |
| Capacidades ligadas a ciencia/ingeniería/comunicación/pilotaje/combate | **Hecho** |
| Edición sin perder progresión | **Hecho** |
| Arena táctica | **Hecho: 10×7** |
| Iniciativa | **Hecho** |
| Movimiento y cobertura | **Hecho** |
| Armas de personaje | **Hecho: cuatro perfiles** |
| Guardia, ayuda, botiquín y extracción | **Hecho** |
| IA enemiga terrestre | **Hecho** |
| Cámaras táctica / tercera persona / POV | **Hecho** |
| Consecuencias en ficha/campaña | **Hecho** |
| Conjuros y recursos adicionales del catálogo original | **Pendiente** si forman parte del standalone final |

UI: `F4` para ficha/capacidades y `F6` para combate. Pruebas: `tests/test_crew.gd`, `tests/test_ground_combat.gd`.

## IA, facciones y comercio

| Capacidad | Estado |
|---|---|
| Reputación persistente | **Hecho** |
| Comercio en estación | **Hecho base** |
| Patrulla estratégica | **Hecho** |
| Escolta | **Hecho** |
| Intercepción | **Hecho** |
| Retirada por moral | **Hecho** |
| Tregua por relación de facción | **Hecho** |
| Convoyes y órdenes | **Hecho** |
| Combate cercano | sigue resolviéndolo `Simulation`; la IA estratégica no duplica esa autoridad |
| Comportamientos/economía completa de todo el catálogo original | **Pendiente de inventario final** |

UI: `F5`. Prueba: `tests/test_fleet_ai.gd`.

## Interiores y espacios sociales

La Itsaso mantiene cargados simultáneamente sus siete compartimentos principales. Los seis enlaces físicos tienen corredor, colisión y escotilla; no hay pantalla de carga al caminar por la nave. `DeckMap` muestra el plano vivo.

| Capacidad | Estado |
|---|---|
| Puente, pasillo, ingeniería, camarotes, bodega, comedor, enfermería | **Hecho y conectados físicamente** |
| Museo | **Hecho**: 18 esculturas propias, cinco cuadros y cartelas |
| Libro físico | **Hecho**: cinco páginas, lectura y paso de hoja |
| Playa | **Hecho**: recorrido, pasarela, dunas, iluminación, mar, elementos de escena y límites |
| Cantina / terraza | **Hecho base** |
| Estudio | **Hecho**: escenario y luces seleccionables |
| Pasillo de recuerdos | **Hecho base**: recorrido y seis textos |
| Mesas sociales | **Hecho**: póker, blackjack y dados, NPC, red, privacidad y reconexión |
| Proyección física de mesa | **Hecho**: cartas/dados/estado recipient-specific sobre la mesa 3D |
| Avatares alrededor de partidas | **Hecho visualmente** |
| Reserva autoritativa de asientos humanos y poses compartidas | **Hecho**: exclusividad, liberación y cancelación verificadas (#12) |
| Guardianes/centinelas y recuerdos ligados a campaña | **Hecho**: galería interactiva y recursos Blender propios (#17) |
| Personalidades/poses restantes de NPC de ocio y catálogo artístico completo | **Pendiente** |

## Atlas, campaña y dirección

| Capacidad | Estado |
|---|---|
| Campaña standalone | **Hecho**: seis misiones propias y editor de campañas multi-misión con dependencias, progreso y persistencia (#13) |
| Guardado local | **Hecho** |
| Inventario / bestiario / crónica / perfiles | **Hecho base y persistente** |
| Atlas por sector y marcadores | **Hecho base** |
| Dirección: tempo | **Hecho** |
| Dirección: amenaza/encuentros automáticos | **Hecho** |
| Dirección: convocatoria manual y consola GM | **Hecho base**: consola integrada en shell (`app.gd` + F8), CRUD de contactos y triggers host-only probado |
| Dirección: triggers en interiores | **Hecho base**: `interior_triggers.gd`, integración `WorldDeck`, CRUD/auditoría/persistencia, validación de guardado y redacción host-only en snapshots; `run_interior_triggers.py` y `test_interior_triggers.gd` |
| Dirección: reposición | **Hecho** |
| Cosmografía jerárquica `plane → star_system → planet` | **Base integrada**: catálogo JSON propio versionado, servicio de campaña y lectura en Atlas; corpus completo pendiente |
| Importación HYG / JSON cosmográfico | **Base integrada**: validador HYG/JSON con procedencia; importación de catálogo completo pendiente |
| Procedencia/licencia por entrada | **Base integrada** para el catálogo propio; revisión de todas las entradas originales pendiente |
| Conexiones, `map_ref` y navegación entre sistemas/sectores | **Base integrada**: rutas y `map_ref` persistentes, expuestos en sesión y Atlas; navegación jugable completa pendiente |
| Continuidades original/homebrew/Spelljammer | **Pendiente** (decisión de canon y corpus) |
| Parlamento y controles GM/escena restantes | **Pendiente** (P1) |

La referencia original ya definía el formato `espaciokoop-cosmography` v1 y un importador HYG/JSON. El remake ya incluye un catálogo propio JSON v1, validación de importaciones y servicio de campaña con persistencia; el corpus original completo, decisiones de canon y procedencia de cada entrada siguen pendientes. Todo queda como componente standalone, no como dependencia de Foundry.

## Edición de contenido

| Capacidad | Estado |
|---|---|
| Editor visual de misión | **Hecho base** |
| Astillero estructural | **Hecho** |
| Importación/exportación de diseño de nave | **Hecho** |
| Editor nativo de campañas multi-misión | **Hecho** (#13); migración original separada |
| Editor nativo de personajes | **Hecho** (#16/#19), conserva progresión y valida importación/identidad |
| Editor visual de montajes/loadouts | **Hecho** (#8), round-trip y uso en combate |
| Dependencias entre misiones de campañas nativas | **Hecho** (#13) |
| Dependencias entre tipos de recursos y formatos originales | **Pendiente** |
| Migración de formatos originales | **Pendiente** |
| Catálogo completo de escenarios/bestiario/inventario/libros/hitos | **Pendiente** |

## Arte, audio, avatares e integración

| Área | Estado | Pendiente real |
|---|---|---|
| Blender / modelos | Fuentes `.blend`, GLB propios y assets del ocio | recursos equivalentes de los bloques de contenido aún pendientes |
| Capturas | captura real automatizada del ejecutable en CI y README | ampliar galería conforme entren nuevas superficies finales |
| Audio | música procedural reactiva y controles locales (#9) | recursos restantes que estén presentes y utilizados en el original |
| Avatar | editor, retratos, variantes persistentes y presencia autenticada (#10); desconexión corregida (#20) | poses/retargeting/progresión visual restantes; auditar consumidores originales antes de exigir nuevas funciones |
| Foundry | cliente opcional, ficha propia y controles con autoridad por usuario/puesto (#15) | sincronización restante, navegador remoto y validación contra Foundry real |
| Distribución | release0.9 Linux/Windows; exportador macOS Universal2 y preflight Android (#14) | APK real y validación física macOS/Android; periféricos relevantes |
| Servidor dedicado / Docker | **Hecho** (#23, posterior a0.9): host observador, autenticación, volumen persistente y reinicio; Docker/Compose real probado en CI | acceso remoto Foundry y periféricos según requisitos verificados |
| Herramientas externas | no son necesarias para la campaña nueva | bot Discord, netboot, packs y utilidades de la referencia que sigan teniendo sentido |
| Accesibilidad y Localización | **Base integrada**: gate de localización, perfil persistente, tamaño de texto, cinco modos de filtro y movimiento reducido global probados localmente | inventario total de cadenas, prueba visual humana y validación táctil en dispositivo |

## Regla de mantenimiento

No se marca una función como cerrada por existir un botón, nombre o documento. Debe existir implementación utilizable desde el ejecutable y una prueba automática o comprobación reproducible. El issue maestro [#1](https://github.com/VaroTv7/espaciokooplagunakRemake/issues/1) conserva el último SHA completamente verde para poder retomar después de cualquier pérdida de conexión.
