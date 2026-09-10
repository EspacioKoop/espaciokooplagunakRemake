# Alerta compartida: entradas tardías y reconexión

Subcarril de [#32, §2.3](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32). No añade otra autoridad de alerta: comprueba el circuito de producción `Session.order → Session._receive_order → Simulation.command → Simulation.snapshot → Session._snapshot`.

## Comportamiento bajo prueba

El identificador de alerta intermedia en el protocolo es `ambar`; los otros son `roja` y `verde`. Solo el puesto `mando` puede ejecutar `alert`. La simulación valida el nivel antes de cambiar el estado. `Session` distribuye vistas por destinatario a los integrantes autenticados.

La regresión arranca **ocho procesos Godot reales**: anfitrión/Mando y los siete puestos restantes. Todos los clientes llegan después de que Mando haya establecido alerta roja. Se comprueba:

1. La primera vista aceptada ya contiene `roja`, sin depender de que el cliente presenciase la orden anterior. Se conserva el puesto autenticado y no se incluye el catálogo de contactos de la misión ni el documento de autoría de campaña.
2. Cada puesto no autorizado intenta cambiar a verde, primero con una orden normal y después añadiendo `role=mando` y `principal=1` a los argumentos. Se exige una respuesta negativa del servidor y una vista posterior que siga en rojo. No se interpreta el acuse local «orden enviada» como aceptación del servidor.
3. Navegación se desconecta. El anfitrión espera su retirada real del roster, cambia a ámbar y permite la reconexión. La primera vista de Navegación debe ser ámbar, no su antiguo rojo; los otros seis clientes reciben el cambio en vivo.
4. Mando establece verde. Los siete clientes y el anfitrión deben coincidir. Los clientes salen y el anfitrión comprueba que las desconexiones no modificaron su alerta.

También se exige que un nivel inválido solicitado por Mando sea rechazado sin modificar el estado de la simulación.

Los archivos de barrera del directorio temporal contienen únicamente `ready`. Sincronizan las fases del experimento; **no transportan alertas, resultados, órdenes ni vistas de juego**. Esos datos circulan por los RPC y snapshots ENet reales. Las esperas tienen condiciones comprobables y un límite; no se dan por correctas mediante una pausa fija.

## Ejecución

Desde la raíz del repositorio, con Python 3.11 o posterior:

```sh
python3 tools/bootstrap.py
python3 -m unittest discover -s tests -p test_alert_late_join_runner.py -v
python3 tests/run_alert_late_join.py
```

El runner importa el proyecto con Godot antes de ejecutar los ocho procesos. También acepta `--godot /ruta/a/godot`, `--port 29190`, `--timeout 120` y `--output /ruta/a/evidencias`. Sin puerto explícito se selecciona un puerto UDP libre; una eventual carrera al reservarlo produce un fallo visible, no un resultado aprobado.

El resultado solo es verde si todos los procesos terminan con código cero, sin errores Godot y con exactamente un resumen válido para su propio puesto. Se rechazan resúmenes ausentes, duplicados, de otro proceso, incompletos o con fallos. Los errores con códigos ANSI también se detectan. Un resultado verde de una ejecución anterior se invalida al iniciar la siguiente.

`dist/alert-late-join/` contiene `import.log`, un log por proceso y `result.json`. El workflow aditivo [alert-late-join.yml](../.github/workflows/alert-late-join.yml) conserva esa evidencia tanto en éxito como en fallo. El resultado unitario de Python solo valida el runner: **no sustituye el resultado ENet**. Para acreditar una ejecución, enlazar su run de Actions y el SHA concreto en el PR o issue.

## Aislamiento y límites

Cada proceso utiliza directorios temporales independientes para HOME, USERPROFILE, XDG y AppData, más `--test` y supresión explícita de guardados. No se abren campañas, perfiles ni credenciales personales. La clave del experimento es sintética y las conexiones de los clientes usan exclusivamente `127.0.0.1`; no hay servicios externos. Los procesos se terminan y recogen también si falla el arranque o vence una espera.

El servidor de producción abre un socket UDP; ejecutar la prueba en un entorno de desarrollo/CI aislado, no exponer ese puerto a Internet. Esta suite no acredita cifrado ENet, resistencia a MITM, interoperabilidad con Foundry, Android/macOS físicos, accesibilidad del color ni representación gráfica de la alerta. Tampoco cierra los demás puntos de #32, ni reemplaza la CI canónica de release.

No se han cambiado archivos de producción, formato de guardado, protocolo, normas de permisos, `FEATURE_PARITY.md` ni el workflow de release. Una regresión detectada debe corregirse mediante su reserva y revisión correspondientes; no se flexibilizan las aserciones para ocultarla.
