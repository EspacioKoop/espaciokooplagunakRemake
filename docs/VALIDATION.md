# Validación del remake

Comprobaciones locales realizadas el 10 de septiembre de 2026 con Godot 4.7.1 estable, Linux x86_64 y renderizado de compatibilidad mediante Mesa. Los resultados corresponden a procesos ejecutados, no a una estimación por lectura de código.

| Comprobación | Resultado y alcance |
|---|---|
| Núcleo | 136 comprobaciones, 0 fallos. Las seis misiones se completan emitiendo órdenes y avanzando la simulación; no se teletransporta la nave para satisfacer los objetivos. |
| Operaciones ampliadas | 79 comprobaciones, 0 fallos: maniobras, atraque, frecuencias, tubos, equipos, rutas, sondas y autodestrucción. |
| Asistencia nativa | 59 comprobaciones, 0 fallos: cuatro retos, identidad, caducidad, propuestas acotadas y consumo único. |
| Nave y física | 46 comprobaciones, 0 fallos: subsistemas independientes, sectores de escudo, arcos, diseños, marcha atrás, colisiones, gravedad, portales y migración de guardados. |
| Persistencia | Guardado, lectura, integridad, copia anterior, rechazo de estructuras inválidas y progreso sin duplicar recompensas, dentro de la suite del núcleo. |
| Cooperación | Cinco procesos reales: anfitrión, navegación, ingeniería, clave incorrecta y puesto ocupado. Se verifican rechazo de conexiones, permisos, órdenes, movimiento, límites de presencia y reparto privado de códigos y retos por conexión. |
| HTTP opcional | 14 comprobaciones HTTP reales, incluyendo autenticación, origen, preflight, límites, método, cursores y filtrado del estado. |
| Interfaz | 56 comprobaciones, 0 fallos. Astillero aplicado a una misión y botón de piloto automático con efecto real, ocho puestos, límites de las pantallas, colisión del suelo en siete espacios y ciclo de edición/guardado/reapertura de una misión. |
| Cliente Foundry | 10 pruebas con Node: URL local, autenticación, respuestas, cancelación, escape e importación ordenada sin repetir eventos. |
| Linux | Exportación y ejecución gráfica del binario autónomo. Once capturas de 1600 × 900 revisadas visualmente. |
| Windows | Exportación PE x86_64. El flujo de GitHub añade una comprobación de arranque del ejecutable en Windows Server 2022 antes de dar por verificados los paquetes. El checkpoint `60bf2e5` pasó la prueba de arranque en Windows y la exportación de ambos sistemas: [ejecución 34467146178](https://github.com/VaroTv7/espaciokooplagunakRemake/actions/runs/34467146178). Cada ampliación necesita volver a pasar el flujo. |
| Recursos | Fuente Blender editable, veinte GLB comprobados contra SHA-256, once PNG y ZIP con CRC y SHA-256. |

## Reproducir

Desde la raíz, en Linux con Python 3.11 o posterior y Node 22 o posterior:

```sh
python3 tools/bootstrap.py --templates
.toolchain/godot --headless --editor --path game --quit
.toolchain/godot --headless --path game --script ../tests/test_core.gd -- --test
.toolchain/godot --headless --path game --script ../tests/test_operations.gd -- --test
.toolchain/godot --headless --path game --script ../tests/test_cooperation.gd -- --test
.toolchain/godot --headless --path game --script ../tests/test_ship_physics.gd -- --test
python3 tests/run_network.py
python3 tests/run_telemetry.py
timeout 60 .toolchain/godot --headless --path game --script ../tests/test_ui.gd -- --test
node --test integrations/foundry/tests/client.test.mjs
python3 tools/build.py
python3 tools/capture.py --binary "$PWD/build/linux/EspaciokoopLagunak.x86_64"
python3 tools/package_downloads.py
python3 tools/verify_artifacts.py
```

Las capturas necesitan Xvfb y OpenGL/Mesa. Las pruebas usan sesiones efímeras y las del editor borran la misión temporal que crean. `--test` y `--capture` impiden que la simulación sobrescriba el guardado de campaña.

## Límites conocidos

La ventana y la creación de documentos Journal del módulo necesitan una comprobación dentro de una instalación licenciada de Foundry 13. Las pruebas del cliente y del HTTP no sustituyen esa prueba. El navegador también debe permitir el acceso local desde el origen configurado.

La cooperación se ha ejercitado con procesos en la misma máquina; no constituye una prueba de latencia, NAT o una partida humana larga en Internet. La clave de sesión autentica a la tripulación, pero ENet no cifra el tráfico. Las descargas incluyen Linux y Windows x86_64; macOS, móviles, mandos y pantalla táctil quedan fuera de esta versión.

Esta versión ofrece una campaña nueva de seis misiones. No importa partidas, escenarios Lua, packs de Foundry ni el catálogo completo del proyecto de referencia.

La paridad completa con el original no está terminada. Consulte [FEATURE_PARITY.md](FEATURE_PARITY.md) antes de interpretar estos tests como validación del encargo completo.
