# Campo de prácticas de asistencia

Refs #32, apartado 3.2. Este bloque cubre el aprendizaje de las cuatro asistencias;
no sustituye al tutorial de la primera misión ni al entrenamiento completo de los
ocho puestos, que siguen pendientes.

## Uso desde el juego

Abre **Puente → Asistencia** y pulsa **Entrenamiento seguro · sin órdenes a la partida**.
En la ventana de prácticas, elige Temporización, Secuencia, Precisión o Puzle de
circuitos, una semilla y **Comenzar reto**. Sigue la instrucción del panel y pulsa
**Enviar resultado**. Al superarlo aparece una propuesta, no un cambio automático
en la nave. **Aplicar como Ingeniería · sólo simulación** demuestra la aceptación
por el destinatario y aplica la refrigeración a la nave de prácticas.

**Repetir semilla** reinicia exactamente el mismo reto dentro de una misma versión
del juego. **Siguiente semilla** prepara otro. Los cuatro modos superados se cuentan
una sola vez por ventana. La cruz, **Cerrar entrenamiento** y Esc descartan la
práctica; no hay progreso guardado ni recompensas de campaña.

El reloj, los intentos, el umbral de éxito, las propuestas y su caducidad utilizan
las reglas de `Cooperation`. La secuencia se oculta después de su tiempo de
memorización. Un fallo, una cancelación o una caducidad permiten repetir la receta.

## Aislamiento y límites

`AssistanceTraining` crea una `Simulation` desechable a partir de la primera misión
pública del catálogo y de una semilla entera entre 1 y 2147483647. Nunca recibe
`Session`, documentos de campaña, guardados ni datos de otros jugadores. Sólo
avanza el reloj de asistencia: no simula enemigos, navegación, calor o recompensas.

La consola reutiliza los mismos controles de la asistencia real, pero despacha las
órdenes al modelo local cuando se le proporciona un entrenamiento. Tampoco se
suscribe a los avisos de la sesión. Fuera del entrenamiento mantiene su ruta normal
a `Session.order`. El ayudante del ejercicio es Mando y el destinatario es Ingeniería;
se llama a `Simulation.command` con ambos puestos por separado, sin saltarse la
comprobación de permisos ni duplicar la fórmula del efecto.

**La partida real continúa mientras esta ventana está abierta.** El entrenamiento
no la pausa. Los cambios que hagan el anfitrión, otros jugadores o la simulación
real no se detienen, pero la ventana de prácticas no les envía órdenes. Para
aprender sin presión, úsalo antes de una maniobra o en una sesión local pausada.

El progreso mostrado es efímero y sólo cuenta la aceptación de las propuestas. No
se ofrece importación de personajes, asistencia dnd5e, entrenamiento de los demás
sistemas, certificados de aprendizaje ni compatibilidad de semillas entre futuras
versiones del generador.

## Comprobación reproducible

Con el motor descargado y los recursos importados:

```sh
python3 tools/bootstrap.py
.toolchain/godot --headless --editor --path game --quit
python3 -m unittest discover -s tests -p test_assistance_training_runner.py -v
python3 tests/run_assistance_training.py
xvfb-run -a python3 tests/run_assistance_training.py --graphical \
  --output build/assistance-training/graphical
```

El ejecutor crea perfiles temporales aislados y añade `--test` para que las pruebas
no escriban el guardado de una persona. Ejecuta la suite nativa ya existente de
`Cooperation` y la nueva `test_assistance_training.gd`. Exige resumen de pruebas,
cero fallos, salida correcta y ausencia de `SCRIPT ERROR`/`ERROR`; un timeout o un
resumen incompleto son fallos aunque Godot devuelva código cero. La pasada gráfica
requiere una captura nueva de la ventana renderizada por Godot, no una imagen de
una ejecución anterior.

La regresión cubre los cuatro modos con varias semillas, repetibilidad, límites,
entradas inválidas, privacidad del patrón, propuestas y permisos, caducidad,
reintentos, captura de entradas desde la UI, reinicio/cierre/reapertura y
conservación exacta de una asistencia activa en la sesión real. Las pruebas Python
sólo verifican el ejecutor; no sustituyen a las pruebas de Godot.

El workflow aditivo `assistance-training.yml` conserva logs y captura en
`assistance-training-evidence`. La CI canónica de `release.yml` sigue siendo
necesaria para integrar o publicar una versión. Este bloque no declara cerrado
el conjunto del issue #32 ni valida otros sistemas o plataformas.
