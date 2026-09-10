# Espaciokoop Lagunak

Una nave. Ocho puestos. Un mismo destino.

![Pantalla inicial de la aplicación construida](docs/images/01_inicio.png)

## Estado de la reconstrucción

La aplicación se está reconstruyendo a partir de los modelos y recursos conservados. Ya están implementados el núcleo de simulación, las seis misiones, el guardado local y los servicios de red. Las pruebas del núcleo completan las seis misiones mediante órdenes de juego: **136 comprobaciones, 0 fallos** con Godot 4.7.1.

La interfaz nativa, los interiores y el editor ya están implementados. El proyecto puede abrirse en Godot 4.7.1 desde `game/project.godot`. Los paquetes ejecutables y las comprobaciones finales de red siguen en preparación. Las imágenes que aparecen abajo pertenecen a la ejecución anterior y se sustituirán por capturas de la nueva compilación.

## Modelos en Blender

[Descargar la fuente editable con 20 colecciones de modelos](art/blender/lagunak_assets.blend).

El archivo se creó en Blender 4.5.3 LTS e incluye naves, estación, objetos, tripulante e interiores. Los modelos se crearon para este remake; el repositorio tiene historial independiente de EmptyEpsilon.

## Capturas reales del juego

### Puente y navegación

![Puente nativo con navegación, objetivos y estado de nave](docs/images/02_puente.png)

### Ingeniería

![Distribución de potencia y refrigeración](docs/images/03_ingenieria.png)

### Interior de la nave

![Sala de ingeniería y reactor](docs/images/05_reactor.png)

### Atlas

![Atlas nativo del sector](docs/images/06_atlas.png)

### Campaña

![Campaña de seis misiones](docs/images/07_campana.png)

### Editor de misiones

![Editor visual de contactos y objetivos](docs/images/08_editor.png)

## Dirección del proyecto

El objetivo es una aplicación independiente en Godot, con la simulación, la campaña, el guardado y los puestos cooperativos dentro del juego. La conexión con Foundry será un complemento opcional de consulta y bitácora.

Los recursos publicados se describen en [Créditos](CREDITS.md). La licencia de estos archivos es [MIT](LICENSE).
