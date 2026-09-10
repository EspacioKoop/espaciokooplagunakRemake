# Exportación local de sesión

Subbloque de #32 §3.1. No cierra el issue completo ni declara paridad 1.0.

## Uso desde el juego

Abre o continúa una misión, pulsa **F2**, selecciona **Crónica y bestiario** y pulsa
**Exportar sesión…**. El diálogo muestra una captura fija: puedes alternar entre
Markdown (lectura e impresión desde tu editor) y JSON versionado antes de pulsar
**Guardar archivo…**. La carpeta inicial es `user://session-reports`; el selector
permite elegir otra carpeta. No se abre ningún navegador ni se transmite el informe.

Elige un nombre nuevo. Un archivo o una carpeta ya existentes se rechazan incluso
si el selector del sistema operativo ofrece confirmar su sustitución. Si falla la
escritura, el diálogo conserva la vista previa y muestra el error. Cerrar y volver a
abrir la exportación genera una captura nueva; cambiar el formato no cambia la captura.

## Qué contiene

El informe usa exclusivamente una proyección por lista blanca de `Session.view` y
la crónica/facciones ya disponibles en `Expedition.data`. No lee `Session.sim.state`,
archivos del jugador, cuentas externas, Foundry ni el documento fuente de campaña.

Incluye identificador/título/sector de misión, estado y tiempo, número de objetivos
completados, créditos/reputación/supervivientes/refuerzos acumulados, misiones
completadas y decisiones registradas; además, reputación de las cuatro facciones,
bitácora de misión y crónica persistente. **Los hitos son misiones completadas, no
los hitos privados ni la progresión individual de las fichas.**

No incluye contactos, objetivos futuros ni briefing, inventarios, perfiles de
personaje, retratos, datos de red, identidades de conexión, claves, tokens,
configuración del servidor, cartas, dados o estados privados de mesas. Los campos
adicionales desconocidos se descartan: no se convierten objetos arbitrarios a texto.

**Esto no es anonimización automática.** Los títulos y textos que ya forman parte
de la bitácora pueden contener nombres o información escrita durante la partida.
Revísalos antes de compartir el archivo. El exportador no intenta inferir secretos
ocultos dentro de un texto público ni cambia los permisos existentes de la sesión.

## Formato y límites

JSON: `format = "lagunak-session-report"`, `version = 1`. Campos raíz:
`format`, `version`, `generated_at_utc`, `scope`, `mission`, `campaign`, `factions`,
`events` y `chronicle`. Es un documento de salida, **no un formato importable de
guardado**. No hay migración de partidas ni carga de recursos a partir de este JSON.

- `events`: hasta los últimos 200 eventos disponibles, con secuencia y segundos
  transcurridos de la misión (`scope.events_clock = "mission_seconds"`).
- `chronicle`: hasta los últimos 300 registros disponibles, con segundos Unix UTC
  (`scope.chronicle_clock = "unix_seconds"`). Se conserva su orden registrado.
- Misiones completadas y decisiones: hasta 256 de cada colección. Los registros
  descartados por límite o estructura se cuentan en `scope.omitted_records`.

Las dos escalas temporales se presentan separadas, no se mezclan ni se deduplican
por coincidencia de texto. Los buffers del juego pueden haber eliminado historia
anterior: `scope.history_complete` siempre es `false`. No es un replay ni un
historial exhaustivo de toda la campaña. No corrige la captación histórica de eventos
de `ExpeditionSystems`; refleja exactamente los registros que recibe en ese momento.

Texto acotado: identificadores, sectores y fuentes hasta 80 caracteres, título y
opciones hasta 160, texto de evento hasta 2048. Se normalizan controles, saltos de
línea y controles bidireccionales. Markdown escapa HTML y sintaxis de enlaces e
imágenes; la vista previa usa `TextEdit` de solo lectura, sin interpretar marcado.
Los números inválidos/no finitos se omiten como registro o se representan como
`null`/«No disponible», nunca como un cero inventado. Máximo 2 MiB por archivo.

La escritura usa un temporal del mismo directorio, comprueba errores y después lo
renombra. Se rechazan rutas relativas, `res://`, segmentos `..`, esquemas de red,
extensiones equivocadas y destinos existentes. Se comprueba de nuevo el destino
antes de renombrar. No es una garantía de exclusión atómica frente a otro proceso
que cree el mismo archivo en ese último instante, ni un sandbox de un sistema de
archivos con enlaces o montajes administrados por el usuario.

## Validación reproducible

```sh
python3 tools/bootstrap.py
python3 tests/run_session_report.py --self-test
python3 tests/run_session_report.py
xvfb-run -a python3 tests/run_session_report.py --graphics
```

El runner crea directorios XDG desechables para cada ejecución. **No ejecutes la
suite directamente con los datos de tu partida.** Las pruebas usan únicamente
fixtures sintéticas y una misión nativa iniciada en ese entorno aislado.

La suite cubre proyección y round-trip JSON, Unicode, tipos inválidos, límites,
privacidad, marcado inerte, independencia de la captura, escritura/lectura UTF-8,
errores de ruta, rechazo de sobrescritura y limpieza de temporales. Ejercita el
handler F2, la consola real, su botón, vista previa, cambio de formato, señal de
selección de archivo, mensajes de error y cierre/reapertura. El workflow adicional
`session-report.yml` ejecuta la suite en headless y con Xvfb; no altera `release.yml`.

El runner falla ante salida no nula, errores del motor, ausencia del marcador o
cero comprobaciones. Incluye 12 controles sintéticos en subprocesos para demostrar
ese contrato. Reutiliza la excepción de importación cosmográfica preexistente,
limitada a una aparición y al SHA-256 original; nunca se tolera durante runtime.
Solo en el display de software se permite el aviso exacto de V-Sync no soportado.

Esta prueba de UI llama al handler y emite señales sobre controles reales; **no
sustituye una prueba manual con teclado/ratón de un binario exportado**, una sesión
ENet entre máquinas o una comprobación física de Windows/macOS/Android. Los resultados
concretos y el SHA evaluado deben consultarse en la ejecución CI vinculada al PR.

## Fuera de este bloque

Briefings imprimibles por puesto, replay de eventos, historial completo sin límite,
gestión de slots, importación de informes, traducción completa y cambios en captura
o privacidad del protocolo siguen fuera de este PR. No se cambia Atlas, cosmografía,
interiores, consola GM ni los trabajos reservados por otros agentes en #7.
