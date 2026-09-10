# Estudio del proyecto de referencia y decisiones del remake

Referencia: [EspacioKoop/espaciokooplagunak](https://github.com/EspacioKoop/espaciokooplagunak), commit `fecd0740545f485d2402c6dfe4b47d5a859cb96c`, consultado el 10 de septiembre de 2026.

La copia local de referencia contiene 4.265 archivos versionados. Se ha recorrido
su estructura y se está contrastando la lógica de las funciones con la
implementación nativa. Contar o leer bytes no certifica comprensión semántica ni
paridad funcional. El inventario detallado permanece local; este repositorio
publica únicamente la correspondencia funcional necesaria para revisar el remake.

## Qué organiza el original

| Área | Archivos | Responsabilidad observada | Decisión en esta versión |
|---|---:|---|---|
| `src/` | 557 | Simulación, objetos espaciales, puestos, red e interfaz C++ sobre SeriousProton. | Simulación propia en GDScript, paso fijo y órdenes verificadas por puesto. Godot proporciona ventana, renderizado, audio, física y ENet. |
| `scripts/` | 403 | Escenarios Lua, utilidades, catálogos y traducciones. | Seis misiones nuevas en JSON; objetivos declarativos validados y editor dentro del juego. |
| `resources/` | 2.165 | Modelos, texturas, animaciones, sonidos, fuentes y recursos heredados. | Veinte modelos creados para el remake con fuente Blender, GLB y audio propios. |
| `foundry-module/` | 639 | Operación por puestos, mapa, bitácora, presencia, espacios andables, contenido y minijuegos en el entorno Foundry. | Puestos, mapa, campaña, interiores y persistencia se ejecutan en la aplicación nativa. Foundry recibe estado y eventos mediante un complemento pequeño. |
| `bridge/` | 34 | API Python/FastAPI, autenticación, límites, modelos de órdenes y traducción a la simulación mediante Lua. | La aplicación es propietaria de su simulación. Un servidor local opcional expone únicamente dos consultas versionadas; desaparece la traducción a Lua. |
| `packs/` | 5 | Paquetes grandes de contenido. | El juego incorpora sus recursos y campaña en el ejecutable, sin packs externos necesarios. |
| `docs/` | 130 | Arquitectura, producto, operación, licencias y decisiones de autoridad. | Documentación nueva centrada en jugar, editar, compilar, validar y mantener esta implementación. |
| `tools/` y `tests/` | 164 | Generación, auditorías, pruebas y empaquetado de distintas capas. | Herramientas acotadas y un flujo de CI que ejecuta los juegos de prueba y publica descargas tras comprobar ambos sistemas. |

También se inventariaron los ficheros raíz, CI, Android, macOS, Docker, netboot, bot de Discord, web y documentación de scripting. No se han incorporado sus implementaciones al remake.

## La intención de producto

El README de la referencia ya declara la dirección standalone-first. Su ADR-0008 sitúa el progreso, atlas, misiones y consecuencias en el núcleo y sustituye el reparto anterior, que confiaba la narrativa de campaña a Foundry. El ADR-0012 concreta que la representación de una escena no debe apropiarse del progreso. Esta nueva implementación sigue esa intención: toda misión puede iniciarse, jugarse, guardarse y reanudarse con Foundry desactivado.

La división del original entre C++, escenarios Lua, puente Python y una interfaz amplia en Foundry obliga a coordinar varios contratos para completar una acción. Para esta versión se ha elegido un único estado de simulación y campaña, un despachador de órdenes y una interfaz nativa. La decisión reduce el número de procesos necesarios para jugar; no demuestra por sí sola mejor rendimiento o menos errores que el original.

## Qué se entrega

La campaña nueva combina navegación y atraque, interferencias y sondas, rescates, combate, reparaciones y negociación. Los ocho puestos tienen permisos y efectos concretos. El anfitrión resuelve la simulación y conserva el progreso; los participantes reciben vistas y envían órdenes. El guardado valida estructura e integridad y conserva la copia anterior. Los interiores son espacios 3D con colisión, movimiento y consolas que abren los puestos reales.

El editor permite crear y probar misiones con el mismo núcleo. El atlas representa los contactos de la misión y su identificación; las estadísticas y decisiones de campaña se guardan en el propio juego. La integración Foundry recibe una proyección de ese estado y permite importar eventos a Journal por acción del GM.

## Carencias detectadas en el trabajo recuperado

Este remake tiene historial independiente y no incorpora código, escenarios ni recursos de EmptyEpsilon o SeriousProton. Tampoco pretende compatibilidad binaria, de partidas o de escenarios con ellos. Los modelos recuperados durante el desarrollo pertenecen al propio remake; no proceden del repositorio de referencia.

La versión recuperada está incompleta respecto al requisito de paridad total: no incluye sus escenarios Lua, facciones y naves heredadas, poker y blackjack, minijuegos de asistencia basados en fichas dnd5e, museo, bestiario, editor de personajes, Android, macOS, Docker ni bot de Discord. La asistencia recuperada se simplificó a una orden con coste de energía. Esa simplificación se ha sustituido por cuatro retos nativos y propuestas consumibles, con comprobaciones de autoridad y caducidad. Los enfoques de personaje siguen pendientes. La integración Foundry 13 se limita a consulta y bitácora; las órdenes se ejecutan desde el juego.

Las mejoras verificables de esta entrega son autonomía del ejecutable, bucle completo de campaña con persistencia, distribución de puestos en red, editor jugable y recursos Blender editables. La calidad de la experiencia en partidas humanas largas y la conexión dentro de Foundry requieren ese uso real; el alcance de las pruebas realizadas está en [VALIDATION.md](VALIDATION.md).

Estas carencias deben implementarse. Su enumeración no las excluye del encargo. La matriz `FEATURE_PARITY.md` registra el estado comprobable y evita declarar completa una implementación parcial.

La ampliación de operaciones y asistencia se detalla, junto con todas las carencias conocidas, en [FEATURE_PARITY.md](FEATURE_PARITY.md).
