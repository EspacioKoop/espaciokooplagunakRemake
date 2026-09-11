# Benchmark reproducible de #32

Aporta evidencia repetible para rendimiento/publicación sin afirmar que sustituya un playtest ni que mida FPS reales del ejecutable. Usa una carga sintética determinista y no modifica guardados, releases, tags, paquetes ni datos del usuario.

## Qué mide

- Tiempo de una carga representativa de siete compartimentos, entidades y proyecciones de mesa.
- Consistencia del digest entre tres muestras idénticas.
- Tamaño aproximado de los registros sintéticos.
- Perfiles low y recommended.

Los límites son referencias de seguimiento, no gates de release: enforced=false. Así se evita que una máquina distinta o el overhead del runner produzca un falso bloqueo de CI.

## Uso

    python3 tools/issue32_benchmark.py --profile all --rounds 1 --json benchmark.json
    pytest -q tests/test_issue32_benchmark.py

El JSON contiene esquema, perfiles, muestras, métricas, límites y resultado determinista. Para certificar FPS, memoria real, tiempos de arranque o paquetes publicados aún hacen falta una ejecución del juego y la auditoría de release sobre el SHA candidato.

## CI

El workflow issue32-benchmark.yml ejecuta la prueba en cada cambio de este carril. Es informativo y no modifica release.yml.
