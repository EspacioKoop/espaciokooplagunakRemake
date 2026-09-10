# Arquitectura

El ejecutable contiene simulación, contenido, interfaz, recursos 3D, audio y guardado. El estado del juego no depende de Foundry ni de un servicio externo.

| Componente | Responsabilidad |
| --- | --- |
| `game/core/simulation.gd` | Estado y reglas: movimiento, recursos, órdenes, combate y objetivos. |
| `game/core/catalog.gd` | Puestos, permisos y validación de misiones JSON. |
| `game/core/storage.gd` | Validación de guardados, escritura temporal, sustitución y respaldo. |
| `game/net/session.gd` | Sesión local o ENet, puestos exclusivos, autoridad y réplica. |
| `game/net/telemetry.gd` | Consulta HTTP opcional limitada a `127.0.0.1`. |
| `game/ui/` | Interfaz nativa, radar y editor visual. |
| `game/world/` | Vista exterior e interiores recorribles con colisiones. |
| `game/data/campaign.json` | Las seis misiones de campaña. |
| `art/blender/` | Dos fuentes editables y exportadores de los modelos base y espacios de ocio. |
| `integrations/foundry/` | Cliente de consulta, panel de dirección e importación manual al diario. |

## Simulación y contenido

`Simulation` es un `RefCounted` sin dependencias de escenas o de red. Recibe órdenes por puesto y un paso de tiempo. La aplicación lo actualiza a 30 Hz; las pruebas pueden avanzar esos mismos pasos sin esperar tiempo real. Las órdenes inválidas se rechazan antes de modificar el estado.

Las misiones contienen contactos y objetivos declarativos. Los hechos completados se conservan durante la misión. La campaña registra misiones completadas, créditos, reputación, supervivientes, decisiones y refuerzos. Las recompensas solo se conceden la primera vez que se completa cada misión. Las misiones del editor usan un identificador con prefijo `custom_` al probarlas, para evitar desbloquear la campaña oficial por colisión de nombres.

La vista de clientes y consultas se obtiene mediante `snapshot()`. El catálogo de contactos de la misión no se incluye y los contactos sin identificar se convierten en ecos. La bitácora de una misión conserva los últimos 200 eventos.

## Sesión en red

El anfitrión ejecuta la simulación. Los clientes envían órdenes y reciben estado a 10 Hz, serializado como JSON y comprimido con DEFLATE. El receptor limita el tamaño declarado y descomprimido a 256 KiB. La asignación de puestos y los permisos se verifican en el anfitrión; un cliente no decide qué puesto representa una orden.

El transporte desactiva el reenvío entre clientes (`server_relay`): toda comunicación de juego pasa por el anfitrión. La tripulación y su presencia se distribuyen en las vistas autorizadas; las conexiones todavía sin autenticar no reciben anuncios de otros participantes.

La entrada usa un reto de un solo uso y HMAC-SHA256 con una clave de sesión aleatoria. Los retos caducan a los ocho segundos. Se limitan las órdenes aceptadas de cada participante a veinte por segundo. Las posiciones de tripulantes utilizan un canal no fiable separado y coordenadas acotadas. ENet no proporciona cifrado en esta implementación; la documentación recomienda una red local o VPN.

## Guardado

El estado validado se serializa preservando la precisión de los números JSON. Un sobre con versión y SHA-256 permite detectar corrupción accidental. El hash no pretende impedir que el propietario edite su propia partida. Se escribe un archivo temporal y se sustituye el principal, conservando antes una copia legible. Los archivos de guardado se limitan a 2 MiB.

Las preferencias se guardan aparte en `preferences.cfg`. La campaña no contiene claves de sesión ni tokens de Foundry. Cada ejecución de misión creada por `Session` recibe un identificador aleatorio que permite distinguir bitácoras de partidas repetidas.

## Consulta opcional

El servidor HTTP está desactivado al iniciar. Solo escucha en la interfaz de bucle local y requiere un token aleatorio para leer el estado o los eventos. Permite un origen de navegador exacto, ocho conexiones simultáneas, cabeceras acotadas y un tiempo límite por conexión. Los únicos métodos funcionales son GET y OPTIONS.

El módulo de Foundry consulta cada dos segundos después de que la dirección de juego lo conecte. El token se mantiene en memoria y se borra al cerrar el cliente. Los textos se insertan como texto DOM o se escapan al generar contenido del diario. Importar es una acción manual; no se transmite ninguna orden de juego desde Foundry.

## Recursos y construcción

Los modelos editables permanecen organizados por colecciones dentro del archivo Blender. El exportador evalúa modificadores, combina copias temporales, elimina el desplazamiento de la exposición y genera GLB centrados; no modifica el archivo fuente. Los veinte modelos publicados se verifican con un manifiesto SHA-256.

Godot 4.7.1 se descarga desde sus publicaciones oficiales y se comprueba con la suma SHA-512 publicada. Las exportaciones incorporan el paquete de recursos en el ejecutable. Los ZIP incluyen instrucciones, licencia del proyecto y los avisos de licencia de Godot.

## Operaciones y asistencia nativas

`ship_operations.gd` implementa las órdenes ampliadas y sus temporizadores. `cooperation.gd` mantiene los cuatro retos y las propuestas. El despachador de `Simulation` conserva la autorización y resuelve el efecto de cada orden; las interfaces no asignan resultados de victoria ni permisos.

El protocolo ENet es ahora **5**: los snapshots se proyectan para cada conexión, de modo que los códigos de autodestrucción y los retos solo llegan al destinatario. Las conexiones con protocolo anterior se rechazan con indicación de actualizar. La telemetría de Foundry usa la proyección sin códigos ni retos privados.

El guardado continúa leyendo el formato 1 anterior. Si faltan las nuevas secciones, las inicializa con valores definidos; las operaciones nuevas se validan antes de restaurar. Las asistencias efímeras se cancelan al recuperar la partida.

## Nave y objetos físicos

`ship_model.gd` separa el diseño estructural del estado operativo. Los nueve subsistemas de la referencia tienen potencia, calor e integridad propias, junto con Sensores. El escudo agregado de la interfaz se deriva de proa y popa; el daño se resuelve en el sector orientado hacia el impacto. Los misiles de acceso rápido y los tubos comparten almacén.

`space_physics.gd` resuelve el primer contacto de cada trayectoria con asteroides, planetas, horizontes y portales, aplica atracción gravitatoria y conserva la deriva. Las nebulosas bloquean los análisis a más de 300 m. El anfitrión calcula estos efectos; la interfaz dibuja el estado recibido.

Los guardados con cuatro sistemas se validan contra su contrato anterior antes de añadir los subsistemas nuevos y dividir su porcentaje de escudo entre proa y popa. Un diseño personalizado forma parte de la misión y del guardado; las capacidades se validan en ambos límites. El protocolo 5 exige que anfitrión y clientes conozcan este modelo de nave.

## Espacios recorribles

`WorldDeck` construye trece destinos con colisiones derivadas de las mallas Blender y selecciona el grupo visible. `LeisurePlaces` aporta puntos de interacción y textos. El lector del museo presenta cinco páginas y sincroniza la animación local del libro; asientos y focos son locales por ahora. El mar usa un shader propio y la preferencia de movimiento reducido inmoviliza el agua y los elementos decorativos. La presencia ENet admite coordenadas de hasta 400 metros por eje, necesarias para los nuevos destinos.

## Mesas de ocio

`TableCards` evalúa naipes y `TableRounds` resuelve las reglas de póker, blackjack y dados. `ShipLounge` mantiene asientos, espectadores, saldos efímeros, turnos, revisiones y respuestas idempotentes. El anfitrión genera la aleatoriedad; las proyecciones se construyen expresamente sin incluir la baraja ni las cartas de otro asiento. El agente NPC recibe esa misma proyección limitada.

El protocolo 5 añade una credencial aleatoria privada para recuperar la identidad de mesa tras reconectar al mismo anfitrión. La credencial permanece en memoria, no se escribe en el guardado ni viaja en snapshots públicos. Cambiar de puesto no cambia esa identidad. Las apuestas necesitan una revisión exacta; las entradas, observación y salidas simultáneas se combinan tras validar los asientos, sin consumir turnos. El cierre del anfitrión cancela los repartos y borra sus secretos. La telemetría HTTP excluye la sección de mesas.
