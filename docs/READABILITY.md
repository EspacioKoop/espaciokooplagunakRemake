# Tamaño del texto local

Refs #32 §2.5. Este bloque añade legibilidad de texto; no cierra el paquete de accesibilidad ni la paridad completa.

## Uso

Pulsa **F9 → Tamaño del texto**. Escoge **100 %, 115 %, 130 % o 150 %**: el cambio es inmediato y se guarda en este equipo. El diálogo tiene vista previa, desplazamiento horizontal/vertical, orden de foco y restauración al 100 %. Tabulador y las acciones de navegación UI permiten recorrer sus botones. **Escape/F9** cierra únicamente el diálogo y devuelve el foco a su entrada en Controles. Se mantiene libre el ratón; no se reanuda la cámara automáticamente.

La lista de asignaciones de F9 admite desplazamiento horizontal para que los controles con letras más grandes no queden inaccesibles por recorte horizontal.

## Alcance y límites

Se escalan los tamaños temáticos de `Label`, `Button` (incluidas sus variantes), `LineEdit`, `TextEdit`, `ItemList`, `Tree`, `TabBar`, `MenuBar` y las cinco familias de `RichTextLabel`. También se aplica a controles creados después del cambio y al contenido de ventanas Godot. Los tamaños originales definidos por cada pantalla se respetan: no hay una fuente única impuesta ni multiplicaciones acumuladas al abrir/cerrar.

No se modifican recursos `Theme` compartidos, `ConsoleUI.font_scale`, modelos/cámara 3D, `Label3D`, texto dentro de `SubViewport`, títulos nativos de ventana, menús `PopupMenu`, tamaños explícitos dentro de BBCode ni texto dibujado manualmente. Un contenedor puede excluir su subárbol con `set_meta("readability_exempt", true)`. No se promete remaquetación completa de todas las pantallas a 150 % o en cualquier resolución: las superficies antiguas con geometría fija necesitan validación específica. El diálogo de ajuste sí conserva restauración y cierre mediante desplazamiento y foco en ventana reducida.

Daltonismo, subtítulos, movimiento reducido, traducción completa y validación física de dispositivos quedan fuera de este cambio.

## Persistencia y privacidad

`user://readability-v1.json` contiene únicamente `format`, `version` y `text_percent`. No forma parte del guardado de campaña, no se replica por red y no invoca servicios externos. Se aceptan sólo los cuatro porcentajes admitidos, una versión conocida y JSON de hasta 1 KiB; tipos erróneos, campos extra, rutas externas y documentos dañados se rechazan. Una configuración ausente usa 100 %; una configuración inválida conserva ese valor seguro y muestra el error al abrir el panel.

La escritura usa un archivo temporal en el mismo directorio y renombrado final. Sólo se cambia el ajuste activo tras guardar correctamente: un fallo de escritura conserva tanto la configuración anterior como la interfaz. El cambio de tamaño no altera asignaciones de teclado/mando.

## Mantenimiento y pruebas

`readability_service.gd` es hijo del servicio de controles existente. Observa entrada/salida del árbol y cambios de tema; no recorre toda la interfaz en cada frame. Conserva referencias débiles y restaura la herencia o el override original al volver al 100 % o retirar un control. Las preferencias de pruebas se aíslan con `--test` y directorios temporales.

```sh
python3 tools/bootstrap.py
.toolchain/godot --headless --editor --path game --quit
python3 tests/run_readability.py --graphical --screenshot build/readability.png
python3 tests/run_input_controls.py --graphical
```

La suite propia comprueba validación negativa, lectura/escritura, corrupción/límites, fallo de escritura sin mutación, escalado reversible y no acumulativo, temas compartidos, aparición/reparentado/eliminación de controles, exclusiones, apertura real con F9, vista previa, foco y scroll del diálogo reducido, cierre modal y persistencia en un **segundo proceso Godot**. La captura es del render real, no un diseño simulado. El workflow aditivo `readability.yml` ejecuta la suite; los checks existentes de controles y release permanecen sin cambios. Los resultados de cada entrega se registran en el PR: la existencia de esta documentación no equivale a una ejecución verde.
