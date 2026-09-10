# Controles táctiles de cubierta

En un dispositivo que Godot identifica como pantalla táctil, el HUD aparece automáticamente al entrar en **Cubierta**. En escritorio permanece oculto; para probarlo, abre **Controles · F9** y activa **Mostrar controles táctiles (esta sesión)**. La elección manual se conserva sólo hasta cerrar la aplicación y no modifica el perfil de teclado/mando ni la campaña.

Toca **Caminar** para controlar el personaje con el cursor libre. Arrastra el círculo izquierdo para caminar con velocidad proporcional. Usa otro dedo en el área derecha para mirar; comparte sensibilidad e inversión con el ajuste de ratón existente. **Correr** funciona mientras mantienes el dedo y **Interactuar** ejecuta la misma acción de InputMap que teclado/mando: consolas, puertas, asientos y objetos próximos siguen sus reglas existentes. **Menús** detiene la entrada táctil y devuelve la interfaz normal. **Controles** abre los ajustes; salir de ajustes deja los controles neutrales hasta volver a tocar Caminar.

Cada dedo conserva su función hasta soltarlo o cancelarlo. Otro dedo no puede tomar un stick ocupado. Soltar fuera del área también cancela su entrada; salir de cubierta, desactivar el HUD o perder el foco lo neutraliza por completo. Los eventos de ratón emulados por los toques del HUD se consumen para impedir clics sobre controles situados debajo. Las entradas de teclado/mando continúan disponibles y soltar Correr táctil no libera una tecla física pulsada.

El componente `game/input/touch_controls.gd` se instancia desde `Controls`, sin autoload, ajustes de proyecto ni protocolo nuevos. Combina sus vectores con los de InputMap mediante la API existente y emite un `InputEventAction` para interactuar. `interior.gd` sólo amplía los gates de actividad y consulta `Controls.action_pressed` para sprint; no cambia velocidades, colisiones, reservas de asientos ni reglas de red.

```sh
.toolchain/godot --headless --editor --path game --quit
python3 tests/run_touch_controls.py
python3 tests/run_touch_controls.py --graphical --screenshot build/touch-controls.png
```

La prueba inyecta eventos Godot `ScreenTouch` y `ScreenDrag` en la aplicación principal, incluidos toques reales sobre el checkbox y el cierre de ajustes, movimiento/cámara simultáneos y cambios de las luces del estudio. Verifica cancelación, IDs inválidos, entradas no finitas, dedos concurrentes, pérdida de foco y límites del layout. El workflow exige además el smoke gráfico bajo Xvfb y conserva su captura. La prueba no sustituye validación con un dispositivo Android físico; APK/SDK y compatibilidad específica del dispositivo siguen siendo el bloque de distribución de #4.
