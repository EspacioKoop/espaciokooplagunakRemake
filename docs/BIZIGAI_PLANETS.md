# Bizigai: planetas HABITABLES

Seguimiento: issue #56. Biblioteca permanente: #52. Rama de trabajo: `agent/56-bizigai-planets`.

## Mundos

- **Lurga**: radio base 240 m, mesetas templadas de roca roja, praderas y arboledas de copa ancha.
- **Elur**: radio base 200 m, altiplano alpino templado, tundra florida y lagunas geotérmicas.

Ambos son habitables por diseño de ficción: aire respirable, agua y vegetación. Su tamaño es deliberadamente lúdico, no astronómico. La habitabilidad no implica que ya exista un sistema de supervivencia o colonización.

## Contrato de recursos

Dos representaciones por mundo como mínimo: orbital ligero y superficie esférica completa. Metros, centro común `(0,0,0)`, +Y norte, -Z longitud cero. Los puntos de interés tienen identificadores estables y posiciones planetarias; el orbital conserva su colocación. La primera transición será por teletransporte a un anclaje validado. El aterrizaje seamless, inventario, batallas y misiones son consumidores futuros, no se declaran implementados por existir modelos.

## Referencias primarias estudiadas

Alex Beachum explica en su entrevista con Nintendo de 28/12/2023 la exploración motivada por curiosidad, los vínculos entre lugares y la importancia de probar desplazamientos reales, no sólo saltos de depuración. Esto inspira lugares legibles y compactos, no copia sus mapas ni su narrativa.

Fuente: https://www.nintendo.com/jp/topics/article/47da8511-6ee9-42d8-af6e-03bfe127aacb

Godot distingue LOD de malla (reducción de geometría) y HLOD por rangos de visibilidad (sustitución de grupos). Ninguno implementa por sí solo gravedad radial, colisiones, carga asíncrona o transferencia de velocidad entre marcos planetarios.

Fuentes:
- https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html
- https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html
- https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html

## Estado

Diseño y reserva publicados. La entrega de modelos y sus validaciones se registrará aquí con resultados reales; este documento no acredita todavía binarios exportados.
