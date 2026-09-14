# Benchmark reproducible de #32

Aporta evidencia repetible para rendimiento/publicación sin afirmar que sustituya un playtest ni que mida FPS reales del ejecutable. Usa una carga sintética determinista y no modifica guardados, releases, tags, paquetes ni datos del usuario.

## Qué mide

- Tiempo de una carga artificial de registros parametrizada como siete compartimentos, entidades y proyecciones; no instancia estos objetos en Godot.
- Consistencia del digest entre tres muestras idénticas.
- Estimación de tamaño a 64 bytes por registro sintético: no es memoria RSS ni un pico de memoria medido.
- Perfiles low y recommended.

Los límites son referencias de seguimiento, no gates de release: enforced=false. Así se evita que una máquina distinta o el overhead del runner produzca un falso bloqueo de CI.

## Uso

    python3 tools/issue32_benchmark.py --profile all --rounds 1 --json benchmark.json
    python3 -m unittest discover -s tests -p test_issue32_benchmark.py -v

No requiere pytest ni paquetes Python externos. Los contratos cubren ambos perfiles, los límites inclusivos de 1–20 rondas, entradas inválidas sin creación de archivos, correspondencia entre stdout y JSON, digest entre procesos y propagación de un fallo de determinismo. Los dobles de las pruebas negativas son explícitos; no se presentan como mediciones.

El JSON contiene esquema, perfiles, muestras, métricas, límites y resultado determinista. Para certificar FPS, memoria real, tiempos de arranque o paquetes publicados aún hacen falta una ejecución del juego y la auditoría de release sobre el SHA candidato.

## CI

El workflow `issue32-benchmark.yml` ejecuta los contratos en cada cambio de este carril y falla si no descubre pruebas, si se rompe un contrato o si falta el JSON que debe adjuntar. Usa sólo permisos de lectura, acciones fijadas y Python 3.11. Se retira `continue-on-error` para no ocultar fallos de funcionamiento; los umbrales sintéticos de tiempo/memoria siguen siendo informativos (`enforced=false`). No modifica `release.yml` ni sustituye su aceptación.
