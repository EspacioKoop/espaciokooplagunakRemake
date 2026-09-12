# Paquete base de accesibilidad

Este bloque de #32 aporta **componentes runtime independientes**, no un controlador global:

- `AccessibilitySettings`: preferencias locales en memoria; movimiento reducido convierte la duración de una transición en cero. Sin él, las duraciones negativas se limitan a cero.
- `SubtitleBus`: emite una señal con texto, origen y duración. Rechaza texto vacío o compuesto sólo por espacios y no emite nada si los subtítulos están desactivados. Conserva el texto original, usa `Sistema` y 3 segundos por defecto y limita la duración mínima a 0,1 segundos. Movimiento reducido **no elimina el tiempo de lectura**.
- `RedundantSignal`: describe información, advertencia y peligro mediante etiqueta, icono, patrón y mensaje, sin depender sólo del color. Devuelve datos; no dibuja la interfaz ni aplica un filtro de daltonismo.

No toca red, guardados ni persistencia de preferencias. La aplicación que los consuma debe decidir cómo presentar y, si procede, persistir las opciones localmente. Este baseline no sustituye ni vuelve a implementar los subtítulos de avisos ya integrados por #66.

Esto **no declara traducción completa**, certificación de todas las pantallas, modo daltónico global, compatibilidad con lectores de pantalla ni cumplimiento total de accesibilidad. Tampoco demuestra conexión de estos componentes a la shell, ejecución del ZIP exportado, revisión visual o playtest humano. Esos contratos siguen separados.

## Prueba reproducible desde un checkout limpio

Requisitos: Linux x86_64, Python 3.11 o posterior y el editor oficial **Godot 4.7.1**, fijado por `tools/export_targets.py`. El bootstrap comprueba el SHA-512 publicado por Godot; no instala globalmente ni descarga plantillas si no se solicitan.

Desde la raíz del repositorio:

```sh
python3 tools/bootstrap.py
python3 -m unittest discover -s tests -p test_accessibility_runner.py -v
python3 tests/run_accessibility_baseline.py --godot .toolchain/godot --timeout 30
```

Para reutilizar un editor ya verificado, omite el bootstrap y pasa su ruta mediante `--godot /ruta/al/godot` o `GODOT`. El runner comprueba la versión exacta `4.7.1.stable.official.<hash>`; no acepta 4.3, builds de desarrollo ni versiones personalizadas. Esta comprobación de versión no sustituye la verificación de procedencia del binario.

El runner:

1. Crea un proyecto temporal **sin autoloads, assets ni caché previa**. Copia byte a byte los tres componentes reales y `tests/test_accessibility_baseline.gd`, sin reescribir su lógica; registra sus SHA-256.
2. Aísla `HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` y `XDG_STATE_HOME`. No utiliza partidas ni preferencias del jugador y no importa el proyecto `game/`. El modo headless usa audio Dummy y `--accessibility disabled` impide la detección automática del lector del escritorio: esta prueba de componentes no evalúa el backend de accesibilidad de Godot.
3. Ejecuta `--headless --editor --import`, comprueba que se ha generado la caché de clases globales y ejecuta la prueba mediante `res://tests/test_accessibility_baseline.gd` **dentro del proyecto temporal**.
4. Impone un máximo de 30 segundos por proceso (10 para la consulta de versión; configurable hasta 120). Rechaza código de salida no cero, timeout y diagnósticos `ERROR`/`SCRIPT ERROR`, aunque el proceso salga con cero.
5. Exige el marcador final único `ACCESSIBILITY_BASELINE_OK checks=36 failures=0` y **36 comprobaciones distintas** en el log. Una salida truncada, un resultado de otra suite o contadores incoherentes fallan. Sólo entonces emite `ACCESSIBILITY_RUNNER_OK checks=36 failures=0`.
6. Elimina proyecto y perfiles temporales. Conserva `version.log`, `import.log`, `suite.log` y `summary.json` en un subdirectorio nuevo de `build/accessibility-baseline/` por intento (`--log-dir` cambia el directorio padre). Los logs de etapas no iniciadas no existen; el fallo consta en el resumen. La salida parcial se escribe directamente a disco y se conserva incluso si un proceso agota el tiempo.

La ruta antigua `res://../tests/...` no apunta a una prueba importada del proyecto `game/`. Cambiar únicamente esa ruta tampoco resuelve las clases globales sin caché o los autoloads del juego: por eso este contrato de componentes utiliza una importación mínima explícita.

## Cobertura y CI

La suite Godot conserva las ocho aserciones originales y añade negativos y límites hasta 36: desactivación sin señales, cadenas vacías/espacios, valores por defecto, preservación de origen/duración/texto, duración mínima, ajustes independientes, snapshots sin alias, reversibilidad del movimiento reducido y descripciones redundantes completas sin estado compartido.

`tests/test_accessibility_runner.py` prueba el lector de resultados, versiones incompatibles, contadores y marcadores falsos, salida con errores, códigos no cero, aislamiento, orden de importación, caché ausente, fuentes/binarios ausentes y resultados antiguos. Incluye subprocesos Python reales para verificar captura de stdout/stderr y timeout con salida parcial; los dobles del motor verifican la orquestación, **no son evidencia de Godot real**.

El [workflow específico](../.github/workflows/accessibility-baseline.yml) ejecuta ambos comandos de prueba y el bootstrap oficial, con `contents: read`, acciones fijadas a SHA, checkout sin credenciales persistidas y logs adjuntos incluso ante fallo. Cubre PR, cambios relevantes de `main` y ejecución manual, incluyendo cambios del runner y de la versión del motor. Es aditivo: **no sustituye la CI canónica de `release.yml`**, sus pruebas del juego ni sus exportaciones. La ejecución local no acredita una ejecución verde en GitHub; la coordinación debe verificar ambas sobre el SHA que publique.
