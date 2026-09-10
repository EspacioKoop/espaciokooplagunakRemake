# Transición segura desde las terminales — issue #29

## Problema y alcance

`WorldDeck._input()` emite `station_requested` desde `interact()` y después marca la entrada como atendida mediante `get_viewport()`. El receptor anterior de `app.gd` ejecutaba `_go("bridge")` sincrónicamente. `ConsoleUI.clear()` separaba entonces la cubierta del árbol antes de que terminase su callback de entrada. La regresión comprueba esta vida del emisor, además del resultado visible, porque un error de script no siempre termina el proceso con un código distinto de cero.

El receptor usa ahora `CONNECT_DEFERRED` y vincula el identificador de la cubierta. Antes de cambiar de rol y pantalla verifica la página, la identidad y pertenencia al árbol de la fuente, su borrado pendiente y la validez del rol. Las solicitudes duplicadas, de una cubierta sustituida o pendientes al cerrar la aplicación se descartan. No se cambia la autoridad de `Session.select_role`, ni red, persistencia, geometría o catálogo de terminales.

Es complementario a marcar la entrada antes de emitir una transición dentro del propio `WorldDeck`. Ese archivo pertenece al carril de distribución de la nave reservado en #7, y esta PR no lo modifica.

## Pruebas reproducibles

```sh
python3 tools/bootstrap.py
python3 tests/run_terminal_transition.py --self-test
xvfb-run -a -s '-screen 0 1600x900x24 -nolisten tcp' \
  python3 tests/run_terminal_transition.py --verify-baseline
```

En Linux se necesitan Xvfb y Mesa, como instala `.github/workflows/terminal-transition.yml`. La opción de baseline requiere que el historial contenga `8b1dcf27683a00972b03d5203606eab12f31fe2d` (`git fetch --unshallow` en clones superficiales). El blob de `app.gd` se comprueba antes de usarlo. Sólo se sustituye ese archivo en una copia temporal del proyecto: el árbol de trabajo no se altera.

La suite instancia la escena real `main.tscn`, conserva física, render y enrutamiento de entrada de Godot, y prueba teclado y mando en las seis salas que tienen terminal física en el baseline: puente, ingeniería, camarotes, bodega, comedor y enfermería. La colocación inicial en cada sala es una fixture; **no se presenta como un recorrido físico completo por todos los pasillos**. La proximidad se calcula con la física del juego, no se fuerza la bandera de interacción. También se ejecutan órdenes de navegación/alerta, se abre/cierra Operaciones, se vuelve con el botón público de cubierta y se reabre la terminal. Los casos de vida útil y solicitudes obsoletas son pruebas de integración del receptor, no pruebas de red.

El control negativo debe reproducir el fallo específico de vida del emisor y el acceso a `set_input_as_handled` con la fuente anterior. Un timeout o un error de compilación no cuentan como reproducción. El candidato debe finalizar con un único resultado, al menos 100 comprobaciones, cero fallos y sin diagnósticos del motor no permitidos. Se conservan los mensajes: las únicas excepciones son el aviso gráfico exacto de VSync y, exclusivamente durante importación, el diagnóstico NUL ya acotado por SHA-256 del archivo en `run_character_editor.py`. No se acepta ese diagnóstico durante juego.

`build/terminal-transition/` contiene logs y dos capturas del juego ejecutado desde fuente, junto con los hashes de motor y aplicación. Las 12 comprobaciones de `--self-test` validan el runner con procesos sintéticos: **no son pruebas del juego**.

## Privacidad y límite de cierre

Cada ejecución usa directorios XDG temporales separados. No se leen ni suben partidas, configuraciones, claves o diagnósticos personales del jugador; los artefactos sólo incluyen las salidas y capturas del escenario de prueba.

La evidencia de esta suite corresponde al motor ejecutando el proyecto, no al paquete release descargado por el jugador. La revisión independiente, CI canónica del candidato final, validación del ejecutable distribuido y repetición en el equipo Linux afectado deben registrarse por separado en #29/PR #42. No cerrar el reporte ni anunciar una release reparada sólo por añadir este test o por una ejecución verde aislada.
