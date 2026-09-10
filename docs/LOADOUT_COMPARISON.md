# Comparación local de montajes

Parte del astillero social solicitado en #32 §3.4. La herramienta permite revisar los montajes de un diseño compartido antes de importarlo. No reemplaza el importador ni cambia el formato existente.

## Uso

En el editor de misiones, abre **Diseñar nave → Montajes → Comparar montajes…**. En la ventana nueva, pulsa **Leer archivo…** para seleccionar un JSON local o pega el documento y pulsa **Comparar**.

El informe distingue montajes añadidos, eliminados y modificados, cambios de orden entre identificadores conservados y cambios de etiqueta de configuración. Los valores se muestran como **actual → archivo**, con precisión numérica completa. Un cambio de identificador se presenta como eliminación y alta, no como modificación de otro montaje.

La ventana es de solo lectura respecto al diseño: no importa, aplica ni envía órdenes. Para utilizar el diseño revisado, cierra la comparación y utiliza **Importar nave** en el astillero; ese flujo conserva su validación y confirmación existentes. **Cancelar** el astillero mantiene el comportamiento anterior.

## Alcance y compatibilidad

Se comparan únicamente los campos de autoría de los montajes: nombre, tipo, orientación, arco, alcance, daño, ciclo y energía, además del identificador, orden y etiqueta de configuración. **No se comparan estructura, casco, escudos ni almacenes de munición.** Que el informe no encuentre diferencias en montajes no significa que dos diseños completos sean iguales.

La validación, los límites y la migración pertenecen a `LoadoutDocument`; no existe un segundo validador de reglas. Se aceptan los documentos `lagunak-ship` v1/v2 admitidos por ese componente y se mantiene su límite de 64 KiB. Un documento v1 no contiene montajes: la comparación advierte expresamente que usa los montajes de exploración predeterminados de la migración existente, no montajes definidos por su autor.

Los montajes se emparejan por identificador. Añadir o quitar uno no marca falsamente como reordenados todos los posteriores; se comprueba el orden relativo de los identificadores que existen en ambos diseños. La comparación es determinista y no redondea diferencias pequeñas válidas.

## Privacidad y ciclo de vida

Solo se lee el archivo seleccionado explícitamente o el texto pegado por la persona. No hay descarga, telemetría, lectura automática del portapapeles ni ejecución de código del documento. Los blancos, recargas en curso y otros campos de ejecución quedan fuera del informe por la lista blanca de `LoadoutDocument.authored_loadout`.

Al abrir se toma una copia del borrador actual; como en la lectura normal del editor, los números ya escritos y todavía pendientes de confirmar se incorporan a esa copia mediante `read_loadout`. El documento propuesto nunca se instala en el borrador. Editar el JSON borra el informe anterior para no mostrar resultados obsoletos. Cerrar y volver a abrir toma una copia nueva. Cerrar el astillero destruye también su ventana de comparación.

El informe se presenta como texto plano no editable. Las etiquetas de usuario se escriben como literales JSON, escapando saltos de línea y caracteres de control en lugar de interpretarlos como formato.

## Validación reproducible

Pruebas del ejecutor en Python, incluidos procesos reales sintéticos, límites, detección de errores y aislamiento del directorio de usuario:

```sh
python3 -m unittest discover -s tests -p 'test_loadout_comparison_runner.py' -v
```

Pruebas de Godot con interfaz gráfica y regresión del editor de montajes existente:

```sh
python3 tools/bootstrap.py
xvfb-run -a python3 tests/run_loadout_comparison.py
```

En un escritorio con pantalla disponible, se puede ejecutar el mismo comando sin `xvfb-run -a`. Para una comprobación sin ventana:

```sh
python3 tests/run_loadout_comparison.py --headless
```

La ejecución sin ventana no sustituye a la validación gráfica. El ejecutor utiliza directorios HOME/XDG/AppData temporales, importa los recursos y ejecuta `test_loadout_comparison.gd` y `test_loadout_editor.gd`. Exige salida cero, ausencia de `ERROR`/`SCRIPT ERROR`, un resumen único por suite, al menos una comprobación y cero fallos. Un fallo o un tiempo de espera agotado interrumpe la ejecución.

Las pruebas cubren diferencias, referencias independientes, precisión, privacidad, archivos corruptos o demasiado grandes, versiones, identidades duplicadas, acceso desde el astillero, cierre de ventanas, tamaño mínimo y conservación del borrador y de la partida. El workflow aditivo `loadout-comparison.yml` ejecuta Python y ambas suites de Godot gráficamente. Sus resultados deben consultarse por SHA; la existencia del workflow o de estas instrucciones no certifica una ejecución verde ni cierra toda la #32.
