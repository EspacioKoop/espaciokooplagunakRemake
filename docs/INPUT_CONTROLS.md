# Controles del personaje

Abre **Controles · F9**, disponible en la esquina inferior derecha cuando el ratón está libre. **F9 siempre abre el panel**, incluso si reasignas la acción del panel. Los cambios se guardan al instante en un perfil local independiente de la campaña y la red.

| Acción | Teclado inicial | Mando inicial |
|---|---|---|
| Avanzar / retroceder / desplazarse | W / S / A / D | Stick izquierdo |
| Mirar | Ratón o flechas | Stick derecho |
| Correr | Mayús | L3 |
| Interactuar / levantarse | E | A / Cross |
| Controlar personaje | C o clic en la vista | Start |
| Liberar ratón y volver a menús | Escape | B / Circle |
| Abrir controles | F9 | Back / Select |

En menús, la cruceta mueve el foco, A confirma y LB/RB pasa al control anterior/siguiente. Si no hay foco, la primera pulsación de A enfoca un control; la siguiente lo activa. Desde la pantalla inicial se puede navegar hasta Cubierta mediante el foco y entrar en el personaje con Start. La apertura del panel libera el ratón y bloquea movimiento/interacción. Al cerrarlo se reanuda deliberadamente con C, Start o un clic. Desconectar un mando también libera el ratón.

Pulsa la celda de teclado o mando para asignar una entrada. La captura dura diez segundos; Escape o **Cancelar asignación** la cancelan. Los ejes sólo se capturan al superar 0,7, para ignorar ruido. Se rechazan entradas duplicadas dentro de las acciones del personaje: para intercambiar dos, usa primero una entrada libre. Escape, F9, los números 1–8 y los atajos de función existentes conservan su uso de recuperación/puestos. **Restaurar controles** recupera el perfil inicial.

El perfil permite sensibilidad de ratón y mando entre 0,2 y 3, zona muerta entre 0,05 y 0,6 e inversión vertical. Se valida el documento completo antes de reemplazar el archivo mediante escritura temporal y renombrado. Una lectura corrupta, un formato desconocido o un archivo mayor de 32 KiB recupera valores iniciales e informa en el panel. Una escritura fallida conserva el perfil activo anterior.

Español e inglés se seleccionan en vivo para esta superficie. El CSV `game/localization/controls.csv` y los recursos Translation de Godot permiten ampliar idiomas. La campaña, otras pantallas, atajos de consolas, órbita/zoom espacial, precisión de asistencia y controles táctiles siguen fuera de este bloque; **Refs #4**, no cierre del issue.

## Contrato de integración

El autoload `Controls` instala las trece acciones de `ControlProfile.ACTIONS` en InputMap. No borra acciones ajenas ni cambia comandos/red/reglas. El interior consume:

- `movement_vector()`: vector analógico limitado al círculo unitario.
- `look_vector()`: mirada en radianes por segundo, con sensibilidad e inversión.
- `mouse_look(relative)`: desplazamiento de ratón transformado en radianes.
- `gameplay_blocked()`: bloqueo por panel, edición de texto o ventana modal incrustada.
- `binding_label(action, device="")`: etiqueta de la asignación; por defecto usa el último dispositivo.

El propietario de interior creó los commits mínimos `8cd4e38` y `4c3437b`, transportados con autorización explícita en #7. Se mantiene fallback de teclado para ramas donde no exista el servicio. Las preferencias se guardan como `user://controls-v1.json`, versión 1; nunca entran en snapshots ni guardados de campaña.

## Verificación reproducible

```sh
.toolchain/godot --headless --editor --path game --quit
python3 tests/run_input_controls.py
python3 tests/run_input_controls.py --graphical
```

El runner aísla preferencias mediante directorios XDG temporales y rechaza códigos de salida no nulos y cualquier `SCRIPT ERROR` / `ERROR` de Godot. La primera prueba cubre formato, conflictos, persistencia, recuperación, límites, InputMap y traducciones. La segunda usa eventos reales de teclado/mando sobre el panel y la escena principal; verifica captura de asignaciones, foco, salida segura y bloqueo modal.

El modo `--graphical` requiere DISPLAY o `xvfb-run` y comprueba captura del cursor, movimiento físico con la tecla reasignada, velocidad analógica del stick, giro real de cámara y retorno con Start. El modo headless informa explícitamente que el backend no puede capturar el cursor y omite esas cinco comprobaciones físicas. El workflow `input-controls.yml` exige el modo gráfico con Xvfb; un entorno sin display no puede dar por superado ese requisito.
