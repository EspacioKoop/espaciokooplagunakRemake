# Comparación local de estructura de nave

Refs #32, §3.4 (diseños compartibles con diferencias legibles). Este bloque añade
comparación estructural al astillero; no completa por sí solo el astillero social
ni la paridad global. La comparación de montajes pertenece al carril
`agent/32-loadout-comparison-q86` y no se reimplementa aquí.

## Uso desde el ejecutable

Abre el astillero desde el editor de misiones y pulsa **Comparar estructura**.
La base de comparación es el borrador visible al abrir la ventana, incluidas las
cifras pendientes de confirmar en los controles numéricos. Elige un archivo JSON
local con **Elegir archivo local**. El informe muestra valor actual, valor del
archivo y diferencia numérica con signo, conservando las variaciones pequeñas.
El texto puede seleccionarse y copiarse de forma explícita.

La ventana conserva esa base mientras permanece abierta. Para comparar cambios
posteriores del borrador, ciérrala y vuelve a abrirla. Comparar no importa nada:
no cambia el diseño, los montajes ni la misión y no emite las señales de aplicar.
La importación existente sigue siendo una acción distinta en el astillero.

## Contrato y límites

Se reutilizan `LoadoutDocument.decode` y `ShipModel.validate_design`: documentos
nativos `lagunak-ship` v1 y v2, máximo 65 536 bytes. V1 se identifica como heredado.
V2 debe ser válido en su conjunto, incluidos sus montajes, aunque estos no se
comparen aquí. No se añade otro formato ni un segundo conjunto de reglas.

Se comparan exclusivamente `id`, `name`, los campos de `ShipModel.DESIGN_LIMITS`
y los cinco almacenes de `ShipOperations.AMMO`. El orden del informe es estable:
identidad, capacidades, munición. Los números equivalentes int/float del JSON no
producen diferencias artificiales; no se usa tolerancia aproximada que esconda
cambios pequeños. El valor numérico firmado no significa automáticamente mejora:
por ejemplo, más tiempo de recarga puede ser peor.

La igualdad estructural **no afirma igualdad de la configuración completa**.
Montajes, orden de hardpoints, campos externos y estado operativo no se comparan.
Los campos desconocidos no se recorren ni se incluyen en el informe. El resultado
contiene solo la lista blanca de valores estructurales; no incluye una copia del
documento original, rutas locales, tickets o un snapshot de simulación.
Los nombres se muestran como texto plano con controles escapados, nunca como
BBCode o HTML. Los archivos corruptos, incompatibles, sobredimensionados o
inaccesibles generan un error y sustituyen cualquier resultado previo para no
mostrar una comparación antigua como válida. Las URL remotas se rechazan.

Todo el acceso es lectura local con `FileAccess`; no se accede a `Session`, HTTP,
ENet, servicios externos ni portapapeles automáticamente. No se guardan los
archivos elegidos ni el historial de comparaciones.

## Verificación reproducible

Desde la raíz, con Python 3.11+ y el Godot fijado por `tools/bootstrap.py`:

```sh
python3 -m unittest discover -s tests -p test_ship_diff_runner.py -v
python3 tools/bootstrap.py
.toolchain/godot --headless --editor --path game --quit
xvfb-run -a python3 tests/run_ship_configuration_diff.py
```

Con un motor ya instalado: `--godot /ruta/al/godot`; sin entorno gráfico:
`--headless`. El runner no descarga software ni usa los guardados reales: aísla
HOME, XDG y las rutas de datos de usuario en un directorio temporal que limpia
al salir. Exige un único resumen completo con al menos una comprobación, cero
fallos, proceso exitoso y ausencia de errores Godot. Un timeout o crash falla la
verificación. Las 16 pruebas Python del runner comprueban su orquestación, **no
sustituyen la ejecución de las pruebas GDScript**.

`tests/test_ship_configuration_diff.gd` cubre cada campo estructural, orden,
precisión, no mutación, campos externos, todas las variantes del catálogo
presente, documentos v1/v2, negativos de validación, lectura real de archivos y
acceso desde el botón nativo. La prueba de UI recorre apertura, señal de selección
de archivo, informe, error, recuperación, cierre y reapertura; comprueba que no
se aplican diseños ni cambia la simulación. Usa datos sintéticos locales. No
automatiza el diálogo nativo del sistema operativo ni constituye una prueba de
usabilidad humana o una certificación de todas las plataformas.

El workflow aditivo `ship-configuration-diff.yml` ejecuta esas pruebas con Godot
real sobre Linux/Xvfb, más la regresión existente `test_loadout_editor.gd`.
La CI canónica `release.yml` y la revisión independiente siguen siendo necesarias
antes de integrar; la documentación describe comandos y cobertura, no declara
resultados de ejecuciones que aún no se hayan comprobado en la PR.
