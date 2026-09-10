# Espaciokoop Lagunak

Una nave. Ocho puestos. Un mismo destino.

![Pantalla inicial de la aplicación construida](docs/images/01_inicio.png)

## Estado de la publicación

**Recuperación parcial: esta rama todavía no contiene una aplicación ejecutable.**

Se conservan el proyecto editable de Blender, siete capturas reales, tres archivos de audio y cuatro archivos de código y configuración de Godot rescatados de los registros de desarrollo. Estos últimos están en [`recovery/source`](recovery/source).

Faltan el núcleo de la simulación, la interfaz, la red, la campaña, el complemento de Foundry y los ejecutables. La copia completa del proyecto no se ha recuperado. El [inventario de recuperación](recovery/README.md) detalla los archivos disponibles y sus comprobaciones.

Las capturas muestran la aplicación que se ejecutó durante el desarrollo. No se presentan como prueba de que el código y los binarios estén disponibles en esta rama.

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
