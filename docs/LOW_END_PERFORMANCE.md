# Perfil de rendimiento low-end — Carril 6 de #32

**Firma del repositorio: OTACON Astra**

Este carril añade una sonda reproducible que ejecuta la escena de producción `game/main.tscn` y mide tres recorridos que ya existen en el juego:

- `ship_itsaso`: las siete zonas de cubierta de la Itsaso y sus seis enlaces físicos.
- `beach`: la zona de playa existente, con suelo, modelo y reloj animado.
- `tables_3d`: la cantina existente, sus tres proyecciones de mesa y una ronda real de póker proyectada en 3D.

La sonda no crea una escena paralela ni reemplaza las pruebas existentes. Sólo añade observación temporal durante la ejecución del runtime.

## Perfil fijo

| Parámetro | Valor |
| --- | --- |
| Resolución | `960×540` |
| Renderer | `gl_compatibility` |
| V-Sync | Desactivado por el runner |
| Audio | `Dummy` |
| Muestras | 60 frames por segmento por defecto |
| Rondas | 1 proceso/recorrido por defecto; admite 1–3 |
| Software | `LIBGL_ALWAYS_SOFTWARE=1` para que la comparación de CI sea repetible |

El software renderer y la resolución fija hacen comparable la ejecución del procedimiento. **No representan ni certifican el hardware del jugador.** No se publica modelo de CPU/GPU, hostname, ruta privada, guardado, sesión ni credencial.

## Uso

Desde la raíz del repositorio, con el editor oficial fijado disponible:

```sh
python3 tools/low_end_performance_profile.py \
  --profile low-end \
  --mode graphical \
  --godot .toolchain/godot \
  --build \
  --rounds 1 \
  --samples 60 \
  --output /tmp/lagunak-performance.json \
  --markdown /tmp/lagunak-performance.md
```

El modo gráfico necesita `DISPLAY`; para una ejecución CI reproducible se puede envolver en Xvfb. El modo `--mode headless` es útil para comprobar el contrato de runtime, pero no es una medición de GPU ni sustituye el modo gráfico.

Para preparar el editor y las plantillas usando las fuentes fijadas por el repositorio:

```sh
python3 tools/bootstrap.py --templates --targets linux
```

`--build` ejecuta `tools/build.py --targets linux`, mide el tiempo real del export Linux y comprueba que el ejecutable producido sea completo. El runner no publica ese ejecutable ni lo añade al commit.

## Informe saneado

El JSON y el Markdown contienen:

- SHA completo del checkout medido;
- versión observada de Godot;
- configuración fija del perfil;
- tiempo real del export Linux cuando se solicita `--build`;
- frames observados, tiempo transcurrido, FPS derivado y percentil 95 del frame de cada recorrido/segmento;
- estado `measured`, `blocked` o `failed` y el bloqueo concreto si no se puede medir.

El runner falla cerrado si falta el editor, el display, el export, la escena, cualquiera de los tres recorridos, el marcador JSON o aparece un `SCRIPT ERROR`/`ERROR`. En un informe `blocked` o `failed` no hay métricas de runtime. Una salida con cero rutas no se interpreta como cero FPS.

Ejemplos de estados honestos:

- `measured`: sólo cuando la sonda GDScript instanció `main.tscn`, validó las tres rutas y terminó sin errores.
- `blocked`: no se ejecutó la medición; por ejemplo, falta Godot 4.7.1 o `DISPLAY`.
- `failed`: se intentó ejecutar y el runtime/build no produjo una salida válida.

## Límites de evidencia

- Las cifras sólo describen el proceso y el entorno de esa ejecución. El runner no certifica hardware low-end, compatibilidad de una distribución, estabilidad de una release ni un presupuesto de FPS.
- El modo gráfico bajo Xvfb/llvmpipe es una ejecución real del renderer de Godot, pero no equivale a una GPU física concreta.
- El perfil no sustituye playtest humano, prueba en el equipo afectado ni la validación completa del paquete publicado.
- La build medida es un export Linux solicitado explícitamente; no se afirma un export Windows ni una release por ejecutar este runner.
- Los recorridos usan las entradas deterministas existentes de las pruebas de ocio para llegar a zonas, y después observan frames del código de producción. No se presenta esto como un recorrido humano libre.
- Este carril no modifica `project.godot`, `README.md`, `docs/FEATURE_PARITY.md` ni `release.yml`, y no altera el benchmark sintético de #76.

## Rollback

La entrega es aditiva: eliminar `tools/low_end_performance_profile.py`, `tools/low_end_performance_profile.gd`, `tests/test_low_end_performance_profile.py`, `docs/LOW_END_PERFORMANCE.md` y `.github/workflows/low-end-performance-profile.yml` revierte el carril sin migración de datos ni cambios en el juego. Los directorios temporales y exports generados por una ejecución local se descartan; no forman parte del informe versionado.
