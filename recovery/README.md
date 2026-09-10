# Inventario de recuperación

Estado comprobado el 10 de septiembre de 2026. Esta carpeta conserva los archivos de código rescatados de los registros de desarrollo. No constituye un proyecto completo y no permite ejecutar el juego ni sus pruebas.

## Archivos disponibles

| Ubicación | Contenido recuperado |
| --- | --- |
| `../art/blender/lagunak_assets.blend` | Proyecto editable de los modelos. |
| `../docs/images/` | Siete capturas reales del juego, de 1600 × 900 píxeles. |
| `../game/assets/audio/` | `arrival.wav`, `confirm.wav` e `itsaso_ambient.wav`. |
| `source/game/project.godot` | Configuración del proyecto Godot. |
| `source/game/export_presets.cfg` | Configuración de exportación para Linux y Windows. |
| `source/game/core/catalog.gd` | Catálogo de puestos y sistemas, carga y validación de misiones. |
| `source/tests/test_core.gd` | Pruebas de la simulación; dependen del código que falta. |

Los cuatro archivos de código se han conservado a partir de los registros disponibles. No se dispone del proyecto completo original para cotejar su identidad exacta. Su contenido publicado sí se ha comparado byte a byte con las copias rescatadas.

## Componentes que siguen faltando

- Escena principal y scripts de simulación, guardado, interfaz, radar e interiores.
- Código de red, servidor de telemetría e integración opcional con Foundry.
- Datos de campaña, modelos exportados para Godot, otros sonidos, tipografía e icono.
- Generador de los modelos de Blender, herramientas de compilación y empaquetado, automatización y las demás pruebas.
- Documentación completa de arquitectura, autoría, revisión del repositorio original y validación.
- Captura `04_cubierta.png` y paquetes ejecutables para Linux y Windows.

Las capturas conservadas documentan el aspecto de la aplicación durante el desarrollo. No acreditan que esta rama se pueda compilar ni ejecutar. Las pruebas rescatadas no se han vuelto a ejecutar porque faltan sus dependencias.

## Comprobaciones de los archivos rescatados

- Las siete imágenes PNG se decodifican correctamente.
- Los tres archivos WAV tienen cabeceras y parámetros de audio legibles.
- El archivo Blender tiene cabecera `BLENDER-v405`; sus bloques se recorren hasta el final del archivo. No contiene bloques de texto con scripts que permitan recuperar el código que falta. Esta comprobación de estructura no equivale a una validación completa dentro de Blender.
- Los cuatro archivos de código descargados de GitHub coinciden con las copias rescatadas.

[`manifest.json`](manifest.json) enumera los quince archivos recuperados de desarrollo con su tamaño, SHA-256 e identificador de blob Git. Estos identificadores comprueban la integridad de la copia publicada; no demuestran que se haya recuperado toda la entrega.

## Identificar una copia de la entrega anterior

Los registros de compilación conservan estas referencias. Los archivos a los que corresponden **no están disponibles en este repositorio**:

| Paquete | Bytes | SHA-256 registrado |
| --- | ---: | --- |
| `EspaciokoopLagunak-1.0.0-linux-x86_64.zip` | 34.672.595 | `54300f519f3a8cc1a140e0b1a277e5b42a80151f2dcc30863c7b995d5333795c` |
| `EspaciokoopLagunak-1.0.0-windows-x86_64.zip` | 44.248.514 | `e1901ec75935afc1c1354f8ed698ecf9597c4d67d921a7f0bda8da2d208706b9` |

También figura el commit local `37d75bf047df3c8629d1beef98aea7343797ee54`, seguido de un commit identificado parcialmente como `d9be477`. No se han recuperado sus objetos Git. Estos datos sirven para reconocer una copia si reaparece; no son enlaces a una entrega publicada.
