# Cubierta de la Itsaso

La cubierta usa una única definición, `game/world/ship_deck_layout.gd`, para la posición y orientación de las salas, los portales físicos, la detección de zonas y el plano. No se dibujan líneas entre centros como sustituto de los pasillos reales.

## Distribución

La referencia de diseño es la silueta de la nave predeterminada aportada por Varo: casco alargado, morro acristalado, sección central habitable y propulsión trasera. El plano adopta esa organización sin modificar el modelo exterior ni pretender que una imagen en perspectiva sea una medida ortográfica.

Proa es `-Z`, popa es `+Z`. Se conservan los identificadores de sala:

| ID | Compartimento | Centro X/Z | Orientación Y |
|---|---|---|---|
| 0 | Puente | 0 / -34 | 0° |
| 1 | Pasillo central | 0 / 0 | 0° |
| 2 | Ingeniería | 0 / 32 | 180° |
| 3 | Camarotes | -13 / -10 | 90° |
| 4 | Bodega | -13 / 10 | 90° |
| 5 | Comedor | 13 / 10 | -90° |
| 6 | Enfermería | 13 / -10 | -90° |

Los seis conectores son vestíbulos rectos y cortos, con dos escotillas cada uno. Las aperturas de los modelos Blender quedan enfrentadas al pasillo. Los siete módulos permanecen cargados al mismo tiempo; cruzar una escotilla sólo requiere abrirla y caminar. Los mamparos laterales cierran los huecos que no son puertas.

La silueta dibujada es una **envolvente orientativa**; los motores laterales no se anuncian como salas transitables. No es una reconstrucción volumétrica exacta del GLB exterior. Los seis destinos sociales (cantina, museo, playa, terraza, estudio y recuerdos) conservan posición, asientos y accesos existentes; no se dibujan como si una playa de cien metros estuviera dentro de esta cubierta. Sus transiciones preexistentes no se anuncian como recorrido continuo de la nave.

## Uso del plano

El plano mantiene la misma escala para X y Z. Muestra huellas de salas y pasillos, la orientación del jugador y las escotillas reales. Una barra indica una puerta cerrada; una hoja girada, una abierta. La distinción no depende sólo del color.

Libera el ratón y pulsa una sala para señalar un recorrido. Volver a pulsar la misma sala lo borra. Con el plano enfocado, las flechas cambian de destino y Escape lo limpia. La ruta sigue la circulación central y sus portales: no atraviesa paredes, no teletransporta al jugador y no abre puertas automáticamente. Es una guía de circulación, no un piloto automático ni un planificador de obstáculos móviles.

Las escotillas se operan desde ambos lados. El rótulo indica el destino del lado contrario, no una zona elegida por distancia a su centro. No se permite cerrarlas con un jugador en el umbral. Movimiento reducido elimina el desplazamiento animado del panel.

## Compatibilidad y alcance

No se añaden campos al guardado de campaña ni al protocolo de red. Se conservan IDs de salas y coordenadas de ocio/asientos; cambian las posiciones físicas de los compartimentos principales. Los participantes deben utilizar la misma compilación para compartir esta distribución: no se afirma compatibilidad espacial entre clientes con planos diferentes. Las puertas mantienen su gestión local preexistente; este cambio no añade replicación autoritativa de escotillas.

No se toca Atlas/cosmografía, simulación espacial, la consola GM del PR #34 ni el modelo exterior. El ajuste de consumo del evento antes de abrir una terminal evita acceder después a un viewport desmontado; no cierra por sí solo todas las posibles causas del issue #29.

## Verificación

`tests/test_ship_deck_layout.gd` se ejecuta desde `tests/test_leisure.gd`, dentro de la CI canónica existente, sin introducir una suite desconectada:

- correspondencia entre modelos, orientación, portales y plano;
- salas sin solapes y salas/pasillos dentro de la envolvente;
- escala uniforme y proyección inversa del mapa;
- rutas entre todas las salas que permanecen en las huellas transitables;
- entradas reales con suelo, colisión de las doce escotillas y operación desde ambos lados;
- selección de ruta sin desplazamiento ni apertura automática;
- cierre rechazado con el umbral ocupado y movimiento reducido.

Se conserva además `tests/test_ship_corridors.gd`: recorre los seis enlaces en ambos sentidos usando el movimiento normal del personaje y detecta bloqueos, caídas o teletransportes. El nuevo test geométrico no reemplaza esta comprobación física.

```sh
python3 tools/bootstrap.py --templates
.toolchain/godot --headless --editor --path game --quit
timeout 60 .toolchain/godot --headless --path game --script ../tests/test_leisure.gd -- --test
```

El resultado ejecutado y el SHA validado se consignan en el PR; la existencia de este documento no certifica una prueba pasada ni una nueva release.
