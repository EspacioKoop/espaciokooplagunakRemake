# Contrato de persistencia cosmográfica standalone

`CosmographyPersistence` conecta un catálogo `espaciokoop-cosmography` v1 con una posición cosmográfica persistible. Es un componente puro: no abre archivos de partida ni escribe en `ExpeditionSystems`, Atlas, UI, red o física. Su integración jugable pertenece al consumidor posterior; esta entrega no cierra #32.

## Alcance y API

- `create(catalog_data, catalog_id)` y `register_catalog(...)` comprueban la versión **antes** de delegar el resto de la validación en `CosmographyCatalog` y conservan una copia profunda del catálogo aceptado.
- `select_location(system_id, planet_id = "")` exige un sistema existente y, si se indica planeta, que sea hijo de ese sistema.
- `serialize()` produce JSON del estado; `snapshot()` devuelve una copia profunda.
- `restore(serialized)` valida completamente el documento y la ubicación antes de cambiarla. Un rechazo de registro, selección o restauración conserva el catálogo y la posición previos.
- Registrar correctamente otro catálogo vacía la posición. Hay que seleccionar un sistema antes de generar un estado restaurable; el planeta es opcional.

## Contrato de estado v1

```json
{
  "format": "lagunak-cosmography-state",
  "version": 1,
  "catalog_id": "fixture-v1",
  "current_system_id": "sol",
  "current_planet_id": "tierra"
}
```

Todos los campos son obligatorios y no se permiten campos adicionales. Los identificadores de estado son cadenas; el catálogo debe coincidir con el registrado. El documento está limitado a 64 KiB de UTF-8. JSON malformado produce un rechazo controlado mediante `JSON.parse`, no un diagnóstico del motor por `JSON.parse_string`.

### Versiones sin coerciones

Tanto el catálogo recibido por este componente como el estado aceptan exclusivamente un **número finito exactamente igual a uno**: `1` y `1.0` en GDScript y sus representaciones JSON equivalentes, como `1e0`. Godot convierte los números JSON en `float`; no se exige identidad literal `int`/`float` ni se redondean versiones.

Se rechazan `true`, `false`, `"1"`, `"1.0"`, fracciones (incluidas las representables más próximas a uno), números de otras versiones, `null`, arrays, objetos y valores no finitos. Las comprobaciones de tipo preceden cualquier operación numérica; no se usa `int(version)` como validación.

Esta guarda pertenece a las fronteras de `CosmographyPersistence` y [CosmographyNavigation](COSMOGRAPHY_NAVIGATION.md). **No corrige ni sustituye las otras entradas directas de `CosmographyCatalog`**, cuyo código permanece intacto. Tampoco decide datos HYG, continuidad o licencias nuevas.

## Verificación reproducible

Desde la raíz, Python 3.11 o posterior y el editor oficial Godot 4.7.1:

```sh
python3 tools/bootstrap.py
python3 -P tests/run_cosmography_persistence.py
python3 -P -m unittest discover -s tests -p test_cosmography_contract_runners.py -f -v
```

También se puede reutilizar un editor ya instalado, sin modificarlo:

```sh
python3 -P tests/run_cosmography_persistence.py --godot /ruta/al/godot
GODOT=/ruta/al/godot python3 -P -m unittest discover -s tests -p test_cosmography_contract_runners.py -f -v
```

El runner conserva el argumento posicional histórico del binario. Cada ejecución crea un proyecto mínimo sin autoloads, recursos del juego ni caché previa; copia sin alterar el catálogo, el componente y la suite completa. Las precargas explícitas permiten compilar con `--check-only` y ejecutar sin arrancar el editor. Aísla `HOME` y los directorios XDG, utiliza datos sintéticos y elimina el proyecto temporal al acabar. No necesita importar modelos ni exportar paquetes.

Se conservan las pruebas originales y se añaden versiones válidas/hostiles en catálogo, documento y restauración, round-trip JSON, no mutación, campos obligatorios, tipos y tamaños. El arnés exige código cero, ausencia de `ERROR`/`SCRIPT ERROR`, un único resultado de la suite y correspondencia exacta con todas las aserciones numeradas. El mínimo actual es 269 comprobaciones de persistencia. `--timeout` limita cada fase (60 s por defecto, rango 1–120); los logs parciales sobreviven al timeout.

Los logs `version.log`, `parse.log`, `suite.log` e informe `report.json` se guardan bajo `build/cosmography-contracts/`; `--output-dir` permite elegir otro destino. Usar destinos distintos para conservar ejecuciones anteriores. El informe sólo acredita conteos de una ejecución completamente válida.

`--negative-control` ejecuta **toda** la suite y añade una aserción falsa final: debe salir con código 1, nunca es un modo de éxito. Los tests Python comprueban ese fallo nativo y la concordancia de su marcador, además de timeout, errores de compilación, marcadores corruptos y mutaciones ejecutables `TYPE_INT`/coerción que deben ser rechazadas. No se omiten pruebas si falta Godot: la suite falla indicando el requisito.

La CI aditiva [cosmography-contracts.yml](../.github/workflows/cosmography-contracts.yml) ejecuta ambas suites y los controles del runner, descarga sólo el editor oficial con comprobación SHA-512 y conserva los logs. Usa `contents: read`, acciones fijadas por SHA y checkout sin credenciales persistidas. No sustituye la CI canónica, la revisión independiente ni el smoke de un consumidor runtime/UI; una ejecución local no acredita un run remoto.
