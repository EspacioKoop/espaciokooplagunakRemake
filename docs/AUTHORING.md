# Crear misiones y editar modelos

## Editor del juego

Abre **Editor** y pulsa **Nueva**. Cambia identificador, título, sector y briefing. Los campos de texto se aplican al pulsar Intro o salir del campo.

Elige un tipo de contacto y pulsa en una zona vacía del mapa. Selecciona un contacto para cambiar nombre, coordenadas, identificación inicial e interferencia. Arrástralo para colocarlo; la rueda cambia la escala. Eliminar un contacto también elimina los objetivos que lo referencian. Deshacer conserva hasta sesenta cambios.

Añade objetivos indicando acción y contacto. Puedes ordenarlos, eliminarlos o cambiar su texto. La validación comprueba referencias y compatibilidad: por ejemplo, solo se puede atracar en estaciones y rescatar en naves averiadas. La vista JSON permite editar el documento completo; **Aplicar JSON** valida antes de sustituir el borrador.

**Guardar** escribe un JSON en la subcarpeta local `missions`. **Abrir JSON** permite volver a abrirlo. **Probar misión** la inicia con las mismas reglas y órdenes que la campaña. En una sesión de red, solo el anfitrión puede iniciar una misión.

## Formato de misión

```json
{
  "id": "custom_ruta_argi",
  "title": "La ruta de Argi",
  "sector": "Itsasargi",
  "briefing": "Comprueba el faro y vuelve a puerto.",
  "reward": 100,
  "contacts": [
    {"id": "argi", "name": "Faro Argi", "kind": "beacon", "position": [650, 0], "known": true},
    {"id": "kaia", "name": "Puerto Kaia", "kind": "station", "position": [1000, 300], "known": true}
  ],
  "objectives": [
    {"type": "scan", "target": "argi", "text": "Analiza el faro."},
    {"type": "dock", "target": "kaia", "text": "Atraca en Kaia."}
  ]
}
```

| Campo | Opciones o límites |
| --- | --- |
| `id` | De 1 a 64 letras, cifras, guiones o guiones bajos. |
| `contacts` | Hasta 48 contactos con identificadores únicos. |
| `kind` | `station`, `friendly`, `hostile`, `derelict`, `anomaly`, `beacon`. |
| `position` | Dos números entre −12000 y 12000. X aumenta hacia el este; Y hacia el sur del radar. |
| `known`, `jammed` | Indicadores booleanos opcionales. |
| `hull`, `survivors` | Valores opcionales entre 0 y 100; por defecto 100 de casco y 6 supervivientes. |
| `objectives` | Entre 1 y 24 objetivos. |
| `type` | `navigate`, `dock`, `hail`, `scan`, `salvage`, `rescue`, `defeat`, `repair_target`, `choice`, `probe`. |
| `reward` | Entre 0 y 10000 créditos. |

Para `choice`, utiliza como objetivo un aliado u hostil con el que se pueda negociar. Las decisiones disponibles son compartir o reservar las cartas. Prepara objetivos de contacto e identificación antes de la decisión y explica que deben bajarse los escudos.

La validación estructural evita combinaciones incompatibles, pero no sustituye una prueba de jugabilidad. Comprueba distancias, orden de objetivos y disponibilidad de sondas, torpedos y repuestos. El editor acepta archivos de hasta 256 KiB.

## Blender

Abre `art/blender/lagunak_assets.blend` con Blender 4.5 o posterior. Las veinte colecciones corresponden a naves, objetos, mobiliario, tripulante, pasillo y salas. Los objetos siguen siendo editables por separado.

Desde la raíz del repositorio:

```sh
blender --background art/blender/lagunak_assets.blend --python art/blender/export_assets.py
```

También puede utilizarse el módulo oficial `bpy` 4.5.3 con Python 3.11. El exportador está probado con esa combinación. Genera los GLB y su manifiesto en `game/assets/models`. Mantén la organización de la exposición en la cuadrícula de 48 × 55 unidades, porque el exportador elimina ese desplazamiento de cada colección.

La fuente Blender se conserva intacta durante la exportación. La combinación de mallas se hace sobre copias temporales para reducir el número de nodos del juego. La geometría del planeta procede de Blender; su superficie se representa con el shader del proyecto.

## Sonido

`python tools/generate_audio.py` regenera los efectos originales de pulso, torpedo y escaneo. Los sonidos de confirmación, llegada y ambiente se conservan como WAV originales del proyecto. El juego utiliza los recursos incluidos y no descarga audio durante la partida.
