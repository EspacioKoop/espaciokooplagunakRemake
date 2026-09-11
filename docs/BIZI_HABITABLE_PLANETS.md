# Bizi — dos planetas HABITABLES, compactos y recorribles

Biblioteca permanente: [issue #52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52). Entrega y estado verificable: [PR #57](https://github.com/EspacioKoop/espaciokooplagunakRemake/pull/57). No cerrar el índice al integrar esta colección.

**Son planetas HABITABLES, no esferas decorativas ni mapas planos ocultos tras una pantalla de carga.** La habitabilidad es una decisión ficticia del mundo: atmósfera concebida como respirable, clima templado, vegetación, asentamientos y agua. No se pretende justificar científicamente una atmósfera en cuerpos de cien metros de radio ni simular ecología, presión o supervivencia.

Cada planeta dispone de una fuente Blender editable con dos raíces exportables: representación espacial ligera y superficie completa. Se comparte origen, escala y muestreo del terreno. La escena de laboratorio permite cambiar de órbita a superficie mediante **teletransporte explícito**, caminar con gravedad radial y colisiones, saltar, visitar los catorce lugares y recoger muestras locales. La transición de una nave desde el espacio **todavía no es seamless**. Las pruebas/estado de los binarios de cada revisión se registran en la PR, no se deducen de este documento.

## Dos mundos de escala lúdica

| Planeta | Identidad | Radio de referencia | Diámetro | Circunferencia de referencia | Lugares / muestras |
| --- | --- | ---: | ---: | ---: | ---: |
| `bizi/ametz` | Bosques templados, coníferas, suelo verde, madera, piedra y tecnología de expedición | 120 m | 240 m | unos 754 m | 14 / 28 |
| `bizi/uharte` | Islas, aguas turquesas, palmeras, arenas claras, basalto y asentamientos costeros | 100 m | 200 m | unos 628 m | 14 / 28 |

Los radios describen la esfera de referencia; relieve, vegetación y edificios sobresalen. Las circunferencias son `2πR`, no longitudes medidas de un camino sorteando obstáculos. A 4,8 m/s, una vuelta ideal sin obstáculos duraría aproximadamente 2,6 y 2,2 minutos respectivamente. Se han elegido estas dimensiones para proximidad entre descubrimientos, no para reproducir las medidas exactas de Outer Wilds.

## Catálogo de puntos de interés

Cada fila identifica un grupo geométrico propio, un lugar de entrada y dos recursos visuales reutilizables. Los roles del manifiesto son **propuestas para futuros consumidores**, no misiones o combates ya programados.

| Tipo / ID local | Ametz | Uharte | Geometría / uso previsto |
| --- | --- | --- | --- |
| `landing` | Puerto del Claro | Puerto de las Mareas | Plataforma circular con señal H, luces, rampa, puesto y anclajes de llegada/retorno/aparcamiento |
| `village` | Aldea de las Raíces | Aldea del Coral | Tres viviendas exteriores, ventanas y pozo; futuros diálogos/comercio |
| `observatory` | Observatorio del Viento | Observatorio de las Islas | Torre, escalera exterior, barandilla y telescopio; investigación |
| `grove` | Árbol de los Ecos | Bosque de Palmeras | Árbol dominante, piedras radiales y bancos; botánica/exploración |
| `ruins` | Ruinas del Círculo | Ruinas de Sal | Columnas fragmentadas, plinto y círculo luminoso; arqueología |
| `quarry` | Cantera de Ámbar | Cantera Turquesa | Vetas, cristales, roca y carro; minería futura |
| `greenhouse` | Jardín de Semillas | Huerto de la Laguna | Tres bancales, cultivos y cubierta de sombra; recolección |
| `relay` | Torre del Horizonte | Antena del Faro | Mástil, antenas, reflector y consola; reparación/comunicaciones |
| `wreck` | Sonda Silenciosa | Náufrago Celeste | Casco, ala rota, restos y baliza; recuperación de materiales |
| `sanctuary` | Santuario del Musgo | Santuario de las Conchas | Dais, cinco monolitos y aro luminoso; historia ambiental |
| `camp` | Campamento del Sur | Campamento del Viajero | Tiendas, hoguera y troncos de asiento; descanso/encargos |
| `arena` | Patio de los Guardianes | Anfiteatro de Basalto | Patio, cinco coberturas y cuatro anclajes de encuentro; futuras batallas |
| `reservoir` | Depósito del Rocío | Aljibe del Oasis | Cisterna, agua visual, pasarela, tubería y bomba; mantenimiento |
| `arch` | Arco de Piedra | Puente de los Dos Vientos | Dos pilares y arco pétreo con paso inferior; orientación y recorrido |

Los lugares se distribuyen alrededor de toda la esfera, no sólo en el hemisferio visible desde la primera cámara. Alrededor hay árboles y rocas adicionales. Los enlaces entre POI del manifiesto son conexiones de contenido para planificar investigaciones; **no constituyen un navmesh, una carretera generada ni un grafo de navegación de IA**.

## Archivos y fuente de verdad

```text
art/blender/bizi_planets/
  ametz.blend
  uharte.blend
  generate.py
  export_planets.py

game/assets/models/bizi_planets/
  ametz_orbit.glb
  ametz_surface.glb
  uharte_orbit.glb
  uharte_surface.glb
  manifest.json

game/asset_lab/bizi_planets/
  viewer.tscn
  viewer.gd
  spherical_explorer.gd
```

El manifiesto contiene hashes SHA-256, dimensiones, triángulos medidos, materiales, anclajes, coordenadas de entrada, radio, habitabilidad, recursos y roles de POI. No duplicar a mano esas estadísticas en sistemas de juego: leer esta única descripción de recursos o generar una importación explícita. El estado de campaña, inventario y autoridad sigue perteneciendo a los sistemas existentes.

Cada `.blend` editado es la fuente de verdad artística. El constructor sólo debe usarse en la primera creación o mediante `--missing-only`; `--force` destruye deliberadamente las fuentes previas. El exportador abre el `.blend`, optimiza sólo en memoria y comprueba que su hash no cambia. Los helpers de construcción/exportación se comparten con `art/blender/itsasargi_pack/` en esta entrega; no se necesita Blender ni ese Python para instanciar los GLB exportados en Godot.

Los GLB son autocontenidos, sin texturas externas. Geometría original MIT. No incorporan recursos de Outer Wilds ni de otros juegos, ni retratos, recuerdos, credenciales o datos personales.

## Ejecutar el recorrido

Abrir `game/asset_lab/bizi_planets/viewer.tscn` en el proyecto y pulsar F6, o:

```sh
.toolchain/godot --path game res://asset_lab/bizi_planets/viewer.tscn
```

El selector elige planeta; **Bajar al puerto** carga la superficie y sitúa al explorador en el anclaje de llegada. **Visitar punto de interés** es un desplazamiento de inspección explícito. **Volver a órbita** desactiva el controlador y muestra únicamente la representación espacial. No se finge una maniobra de vuelo con un botón de teletransporte.

En superficie: WASD, ratón, Mayús para correr, Espacio para saltar, E para recoger una muestra a un máximo de 3,2 metros y Escape para liberar el ratón. Un clic fuera del panel vuelve a capturarlo. En órbita: botón derecho para girar y rueda para acercar. La recogida es efímera, se reinicia al cambiar de planeta y no toca guardados, inventario, economía ni red. No se obtienen recompensas permanentes desde este laboratorio.

El controlador usa `CharacterBody3D`, gravedad local de 18 m/s² orientada hacia el centro, transporte de la orientación y `move_and_slide`. No depende de un eje vertical mundial fijo. Es un componente de inspección aislado, no un sustituto del jugador autoritativo de campaña. Las colisiones estáticas se crean desde el terreno y los props; las muestras y el agua abierta se excluyen de la colisión.

## Contrato espacial para futuros aterrizajes

**No escalar el modelo de superficie para que se parezca al orbital. Ambos ya están en metros y comparten centro.** Un consumidor puede escalar una miniatura de interfaz, pero esa transformación de presentación nunca debe convertirse en coordenadas físicas del planeta.

En Godot: +Y arriba, -Z delante. En Blender: +Z arriba, +Y delante. `position` y los anclajes del manifiesto están convertidos a Godot; `source_normal` describe el normal original de autoría en Blender. Buscar `socket_*` desde la instancia con `find_child(nombre, true, false)`; la jerarquía glTF no garantiza una NodePath relativa estable entre importadores.

Para una transformación planetaria `T`, la posición mundial se obtiene con `p_world = T * p_local`. La dirección vertical local es `normalize(p_local)` y la aceleración de prueba es `-18 * normalize(p_local)`. En una integración futura con planetas rotando o moviéndose, habrá que transformar también orientación, velocidad lineal y velocidad angular. No basta con copiar la posición ni con cambiar una malla.

La llegada usa `socket_landing`; el retorno, `socket_return`; el aparcamiento de nave, `socket_ship_parking`. Cada POI tiene `socket_poi_<tipo>` y el patio de encuentros dispone de cuatro `socket_encounter_*`. Son anclajes de contenido, no autorizaciones de red ni activadores automáticos de misión.

## Lo que está preparado y lo que falta para seamless

La representación orbital reduce terreno y decoración; la superficie divide el terreno en ocho parches con límites coincidentes. Se dispone así de un modelo lejano, una superficie real y coordenadas compartidas. **El laboratorio carga la superficie completa y cambia de representación manualmente. No implementa streaming, LOD planetario por distancia, vuelo atmosférico ni fundido continuo.**

Para la siguiente fase propongo este orden:

1. Integrar un descriptor de planeta en el sistema de espacio existente, con identificador estable y transformaciones planetarias. Mantener recursos/encuentros persistentes exclusivamente bajo el host.
2. Conservar el teletransporte como primera mecánica de campaña comprobable: el host valida planeta, zona de llegada, permisos y estado de la nave, y restaura correctamente la tripulación al regresar.
3. Añadir LOD por tamaño proyectado para mallas y HLOD por grupos de props, con histéresis para evitar parpadeo. Usar la representación orbital a distancia y la superficie cerca; diseñar una representación intermedia o transición de materiales cuando haga falta. El descenso no debe mostrar simultáneamente dos terrenos sólidos superpuestos.
4. Separar streaming de render y de colisiones. Precargar antes del cruce; garantizar colisión y suelo antes de transferir al jugador/nave. Desactivar simulación lejana, no el estado persistente. Un LOD visual por sí solo no resuelve memoria, físicas, IA o peticiones de red.
5. Reutilizar árboles/rocas con instanciación agrupada por sector y medir CPU, GPU, memoria y tiempos de carga antes de reducir detalle a ciegas. Los ocho parches entregados son una partición inicial; no un sistema de streaming completo.
6. Añadir vuelo continuo con cambio de referencia bien definido, velocidad relativa al planeta, transferencia de autoridad, regreso al espacio y pruebas de reconexión. Si el sistema solar usa distancias grandes, decidir explícitamente el marco de precisión/origen de la simulación sin alterar este contrato local en metros.

El LOD automático de Godot puede simplificar escenas 3D importadas; HLOD permite sustituir conjuntos de objetos y usar márgenes de histéresis. Son herramientas complementarias, no sinónimos de aterrizaje seamless [3][4]. No se declara una tasa de fotogramas objetivo ni compatibilidad de hardware sin medirla.

## Estudio de Outer Wilds: qué se ha trasladado

La fuente primaria de Mobius explica que una estética de formas nítidas y estilizadas ayudó a definir superficies caminables y mantener la lectura desde el suelo y desde lejos. También menciona herramientas para construir entornos esféricos [1]. La decisión aplicada aquí es conservar una silueta clara, escala pequeña y lugares distinguibles en vez de aumentar kilómetros vacíos.

La charla de Kelsey Beachum describe una progresión motivada por la curiosidad y descubrimientos conectados, no por una lista impuesta de tareas [2]. Aquí eso inspira nombres, funciones distintas y enlaces entre los catorce POI. Es una adaptación de principios: nuestro proyecto sí prevé recursos, combates y misiones; no replica la estructura narrativa del juego ni incorpora su bucle temporal.

No he auditado el código fuente interno de Outer Wilds. No se atribuye a Mobius nuestro algoritmo de terreno, nuestros radios, el controlador Godot o la propuesta concreta de LOD. Son decisiones propias de esta colección.

### Fuentes primarias consultadas

[1] Mobius Digital, **Our New Style**: https://www.mobiusdigitalgames.com/news/our-new-style

[2] GDC 2021, Kelsey Beachum, **Sparking Curiosity-Driven Exploration Through Narrative in Outer Wilds** (descripción oficial de la sesión): https://www.gdcvault.com/play/1027368/Independent-Games-Summit-Sparking-Curiosity

[3] Godot, **Mesh level of detail (LOD)**: https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html

[4] Godot, **Visibility ranges (HLOD)**: https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html

## Validación reproducible

```sh
python art/blender/bizi_planets/generate.py --missing-only
python art/blender/bizi_planets/export_planets.py --render
python tests/itsasargi_pack/validate.py
python tests/bizi_planets/validate_spheres.py
python tools/bootstrap.py
python tests/itsasargi_pack/run.py
```

La comprobación de topología examina los triángulos del GLB: cada arista del terreno pertenece a dos caras, el terreno es conexo y su característica de Euler es 2. Esto distingue una esfera cerrada de una cáscara rota o un mapa plano. También se comprueba que la geometría orbital comparte posiciones de terreno con la superficie.

Las pruebas Godot cubren selección, anclajes, llegada, apoyo en los 28 POI, rayos alrededor de toda la esfera, ambos polos, orientación radial, retorno, índices inválidos y recogida local sin duplicación. Las capturas técnicas se obtienen de Godot y los previews Blender reimportan los GLB realmente entregados. Consultar la PR para el resultado de la revisión actual; no confundir una prueba escrita con una prueba ejecutada.

## Límites artísticos y funcionales

El agua es visual: no hay natación, flotación, mareas, oxígeno ni simulación atmosférica. El terreno existe también bajo el agua; el explorador de inspección puede recorrerlo sin sistema de supervivencia. Viviendas y tiendas son exteriores, no interiores amueblados ni puertas operativas. No hay túneles excavados dentro de la esfera, fauna/IA, ciclos meteorológicos, navmesh esférico, reglas de misión, batallas o persistencia de recolección de campaña. Los patios, coberturas, recursos y anclajes están preparados para esos consumidores futuros, pero no los sustituyen.

Reservar cualquier continuación en #7 y registrar aquí y en #52 los IDs/revisiones. Cambiar radio, origen, entrada o anclajes exige versionar el contrato; no mover silenciosamente contenido que ya utilicen misiones.
