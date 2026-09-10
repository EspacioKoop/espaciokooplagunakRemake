# Misiones nativas: contrato v1 y validación local

Este documento desarrolla el apartado 3.4 de #32. Documenta el JSON que **ya**
consumen `Catalog.validate_mission`, el editor y `Session.start_mission`;
no inventa un segundo formato ni un cargador de código.

## Crear, comprobar y jugar

El ejemplo propio [Primer contacto con Itsasargi](../examples/missions/first-contact.json)
contiene una baliza, un puerto y tres objetivos: acercarse, analizar y atracar.
Es un archivo de misión, no el `campaign.json` del juego ni un guardado.

Desde una copia del repositorio, con Python 3.11+ y el Godot fijado por el proyecto:

```sh
# Preparación única. bootstrap descarga el motor oficial y comprueba su SHA-512.
# No hace falta ejecutarlo si ya tienes el Godot apropiado instalado.
python3 tools/bootstrap.py
.toolchain/godot --headless --editor --path game --import

# A partir de aquí, la validación es local y no descarga ni envía contenido.
python3 tools/validate_mission.py examples/missions/first-contact.json
python3 tools/validate_mission.py mi-mision.json --godot /ruta/a/godot --json
```

También se admite la variable `GODOT`. Pueden comprobarse hasta 32 archivos en una
llamada. `--timeout` fija un límite de 1 a 300 segundos **por archivo** (30 por defecto).
Si falta el motor, falla un script o vence el tiempo, el resultado nunca es «válido».

Para jugar: abre **Editor**, introduce el documento en la vista JSON, pulsa
**Aplicar JSON** y **Probar misión**. **Guardar** lo conserva en el directorio local
`missions`; **Abrir JSON** vuelve a cargar las misiones guardadas. En red, el
anfitrión sigue siendo quien inicia la misión. Consulta también [AUTHORING](AUTHORING.md).

## Esquema y compatibilidad

[mission-v1.schema.json](../schemas/mission-v1.schema.json) usa JSON Schema 2020-12.
El `$schema` del ejemplo apunta a ese archivo **local**. El identificador del
esquema es `urn:espaciokoop:mission:v1`: no es una URL de descarga.

«v1» versiona esta descripción del contrato; **no exige añadir `version: 1` al
JSON nativo** ni cambia partidas existentes. `$schema` es metadato para el editor
de texto, no una instrucción para el juego. El esquema deja abiertos campos
adicionales para no invalidar extensiones que el núcleo ya tolera; tolerarlos no
les concede comportamiento ejecutable.

| Campo | Contrato básico |
|---|---|
| `id` | 1–64 letras ASCII, cifras, guiones o guiones bajos. Usa `custom_` en contenido propio. |
| `title`, `sector`, `briefing` | Textos no vacíos, máximo 4000 caracteres cada uno. |
| `reward` | Opcional; número de 0 a 10000. |
| `contacts` | Hasta 48; IDs únicos. Cada contacto necesita `id`, `name`, `kind`, `position`. |
| `position` | Dos números finitos, entre −12000 y 12000. |
| `objectives` | De 1 a 24; cada uno necesita `type`, `target`, `text` (1–500 caracteres). |
| `ship_design`, `ship_loadout` | Opcionales; los validan los componentes nativos de nave y montajes. |

Los **13 tipos de contacto** están enumerados en el esquema: incluye objetos
físicos, portales, nebulosas, suministros y artefactos, además de los seis tipos
básicos. Los **12 tipos de objetivo** incluyen `touch` y `pickup`.

La autoridad semántica sigue siendo **`Catalog.validate_mission`** y sus
delegados `ShipModel`, `LoadoutDocument`, `SpacePhysics` y `SpacePickups`.
El esquema ayuda con forma y límites, pero no puede acreditar por sí solo que:

- un `target` exista y tenga un ID único;
- `dock`/`repair_target` apunten a una estación, `rescue` a una nave averiada,
  `salvage` a una nave averiada/anomalía, `defeat` a un hostil y `choice` a aliado/hostil;
- `touch`/`pickup` apunten a recogibles y un artefacto permita realmente recogerse;
- el diseño, los montajes y los campos físicos cumplan todas sus reglas.

La CLI ejecuta esas comprobaciones en Godot; no copia las reglas a Python.
Una misión estructuralmente válida aún necesita prueba de jugabilidad: distancias,
orden de objetivos, recursos disponibles y condiciones narrativas. La suite Godot
juega el ejemplo con órdenes reales de navegación, escaneo y atraque.

## Entradas, salida y privacidad

Se requiere JSON estricto UTF-8 sin BOM, de hasta **256 KiB**, sin claves duplicadas,
NaN/Infinity, exponentes no finitos ni Unicode incompleto. La CLI limita la
anidación a 32 niveles y los enteros al rango exacto ±(2^53−1), para evitar pérdida
de precisión al intercambiar con Godot. Estos límites de transporte son
adicionales a las reglas del juego, no una migración de su modelo.

Código **0**: todos válidos; **1**: alguno inválido; **2**: error de lectura,
ejecución, argumentos o infraestructura. El 2 tiene prioridad en lotes mixtos.
`--json` produce `lagunak-mission-validation`, versión 1, con `path`, `status` y
`message` por archivo. No incluye el documento. La salida de texto escapa caracteres
de control de nombres y mensajes para no inyectar órdenes visuales en el terminal.

La herramienta lee sólo las rutas solicitadas, no sigue enlaces `$ref`/`$schema`,
no arranca una misión ni un servidor y no tiene cliente de red. Usa una copia
local temporal y un perfil de Godot aislado; `--test` suprime guardados de los
autoloads. Al terminar se borra el directorio temporal y el original no se cambia.
Los errores del motor tampoco se confunden con una validación positiva.

## Pruebas y alcance

```sh
# Dependencia sólo de las pruebas del esquema; no de la CLI.
python3 -m pip install 'jsonschema==4.26.0'
python3 -m unittest discover -s tests -p test_mission_validator.py -v
.toolchain/godot --headless --path game --script ../tests/test_mission_validator.gd -- --test
```

[CI del contrato](../.github/workflows/mission-contract.yml) añade las comprobaciones
sin sustituir ni relajar la CI canónica. Ejecuta Python, importación, pruebas reales
de Catalog/Simulation, las misiones de la campaña y el rechazo de un objetivo roto
mediante la CLI pública. Distingue las pruebas de orquestación con dobles del motor
de las ejecuciones reales de Godot.

No se declara aquí soporte de Lua, paquetes ejecutables, migración de formatos del
original, reparto de assets, carga automática de mods, curación comunitaria ni
paridad total de #32. Compartir el JSON validado no sustituye revisar el contenido
ni jugar la misión en las condiciones reales de la mesa.
