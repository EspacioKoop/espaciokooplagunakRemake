# Propiedades del guardado y migración

Subcarril del issue #32, apartado 4.3. Estas pruebas verifican persistencia local; no certifican por sí solas la paridad completa ni sustituyen el workflow de publicación.

## Ejecución reproducible

Desde la raíz del repositorio, con Python 3.10 o posterior:

```sh
python3 tools/bootstrap.py
.toolchain/godot --headless --editor --path game --quit
python3 tests/run_storage_properties.py --self-test
python3 tests/run_storage_properties.py --seed 3204301 --samples 64
python3 tests/run_storage_properties.py --seed 641709 --samples 64
```

El ejecutable también se puede indicar con `--godot /ruta/a/godot` o la variable `GODOT`. Se aceptan semillas entre 0 y 2147483647 y entre 1 y 512 muestras. Cada muestra usa `semilla + índice`; un fallo imprime ambos valores para reproducirlo con la misma versión del repositorio y del motor.

El runner ejecuta Godot en modo headless, con un límite de 180 segundos. Exige una única línea de resultados, un número positivo de comprobaciones, cero fallos y los parámetros solicitados. También rechaza errores del motor o del script aunque el proceso termine con código cero. Sus diez pruebas Python verifican esta detección y el aislamiento de directorios.

## Datos y aislamiento

Las partidas se generan a partir de las misiones incluidas en el repositorio, nunca de archivos de jugadores. El runner aísla `HOME`, los directorios XDG y los directorios de datos de Windows en una carpeta temporal. Las pruebas crean además un subdirectorio exclusivo de `user://` y eliminan sus fixtures al terminar. Ejecutar mediante el runner conserva este aislamiento, incluso si Godot falla antes de limpiar los archivos.

No se necesitan credenciales, Foundry, servidores externos ni archivos personales. Los mensajes de error contienen nombres de propiedades, semilla e índice, no volcados de partidas.

## Propiedades cubiertas

- **Persistencia completa:** variaciones deterministas de misión, campaña, créditos, reputación, supervivientes, decisiones, posición, rumbo, casco, sistemas, cuadrantes, munición y eventos Unicode. Todos los campos duraderos se comparan después de guardar y cargar; repetir el ciclo debe ser idempotente. También se prueba un estado alcanzado con órdenes reales de navegación y carga de un tubo en curso.
- **Migración:** guardados nativos antiguos con dos segmentos de escudo, sin cuadrantes, y guardados con los cuatro sistemas originales, sin diseño ni operaciones. Se comprueba conservación del progreso y de los sistemas originales, creación de las estructuras nuevas e idempotencia tras la migración.
- **Rechazo sin efectos secundarios:** valores negativos, superiores a capacidad, de tipo incorrecto, no finitos, cuadrantes incompletos, referencias rotas, identificadores duplicados y estructuras inválidas. Se compara la representación de la entrada antes y después de validar y guardar. Los casos serializables también se leen desde sobres con un checksum válido recalculado: el checksum no puede eludir la validación semántica.
- **Formato y límites:** sobres incompletos, versiones incompatibles, JSON truncado, archivos excesivos, checksum desactualizado y límites de tamaño, profundidad y números finitos del árbol JSON.
- **Copias y estado transitorio:** conservación byte a byte de la copia anterior, rechazo de un guardado inválido sin sustituir el principal ni el `.bak`, recuperación explícita de la copia tras corrupción del principal, protección de una copia sana frente a un principal corrupto y limpieza del `.tmp`. Las tareas, bonificaciones y enfriamientos cooperativos transitorios se cancelan al restaurar, conservando el próximo identificador y los datos duraderos.

## Regresión corregida

`ShipModel.validate_ship` llamaba a `ensure_quadrants`, una rutina de normalización que rellena campos ausentes, convierte tipos y recorta cargas. Así, validar podía modificar el estado recibido y aceptar datos inválidos después de corregirlos silenciosamente. Un intento de guardar con una carga excesiva podía acabar sustituyendo tanto el guardado principal como su copia anterior.

La validación ahora examina los cuadrantes recibidos sin modificarlos. Sólo la ausencia completa del campo se interpreta como formato antiguo de dos segmentos: se deriva una vista temporal para comprobar coherencia, sin escribir en la entrada. Un campo presente pero nulo, de otro tipo, incompleto o fuera de rango se rechaza. La migración efectiva sigue ocurriendo en la inicialización posterior a la validación completa del guardado.

## CI y alcance de la evidencia

`.github/workflows/storage-properties.yml` ejecuta los diez tests del runner y dos semillas de 64 muestras. Es un workflow aditivo: no elimina ni rebaja ninguna prueba de `.github/workflows/release.yml`. Los resultados y el SHA comprobado quedan en los logs de GitHub Actions y en el PR asociado.

Estas propiedades son pruebas deterministas con muestras y casos frontera explícitos, no una exploración exhaustiva ni un sistema de reducción automática de contraejemplos. El checksum detecta corrupción accidental; no es autenticación ni firma. La recuperación de `.bak` aquí se realiza de forma explícita: no se afirma que exista recuperación automática en la interfaz. Tampoco se simulan cortes eléctricos, fallos reales de disco, concurrencia entre escritores o todos los permisos y sistemas de archivos. La ejecución headless no sustituye una prueba manual del flujo visual de guardar/cargar.

## Diagnóstico reproducible y contrato numérico

`test_storage_runtime.gd` verifica que la clase global `LocalStorage`, la carga explícita
y el archivo del checkout son el mismo recurso, comparando SHA-256. Prueba por
separado arrays y diccionarios de 0, 1, 599, 600, 601 y 4096 elementos, tanto nativos
como decodificados. El límite sigue siendo 600: no se amplía ni se retiran negativos.
La CI conserva el SHA de checkout, los hashes de fuentes y los registros de ambas
semillas.

JSON no conserva la distinción entre `int` y `float` de los diccionarios GDScript.
Las comparaciones de migración normalizan ambos lados mediante el mismo round-trip
JSON; no descartan campos ni toleran cambios de valor. Hay controles independientes
que distinguen números de cadenas, booleanos y números diferentes. La ausencia de
cuadrantes y los cuatro sistemas antiguos se siguen migrando, sin mutar la entrada.

La lectura usa `JSON.parse` y comprueba su resultado antes de acceder a `data`, en
la cabecera y en el payload. Un archivo truncado o un payload inválido con checksum
correcto devuelve un error de guardado controlado, sin emitir un error del motor ni
sustituir la copia válida. El checksum continúa siendo integridad, no autenticación.
