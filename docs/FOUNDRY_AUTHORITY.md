# Foundry: delegación de autoridad y proyección privada

Avance parcial de #5. La campaña, las fichas, los puestos y los resultados siguen perteneciendo al juego standalone. Esta entrega añade un panel de Foundry 13 con ficha propia y 13 órdenes básicas, concedidas por el anfitrión y verificadas en Godot. No instala ni necesita Foundry para arrancar, jugar, guardar o hacer red ENet.

## Uso desde el ejecutable

1. Abre una campaña en Lagunak como jugador local o anfitrión ENet. El tripulante al que delegues un puesto debe estar conectado y autenticado en esa sesión nativa.
2. En **Sesión → Enlace con Foundry**, introduce el origen exacto de la página de Foundry y activa la consulta local. Se abre una ventana nativa adicional de accesos personales. Reactivar el enlace vuelve a abrirla y rota todos los tokens.
3. Cada persona abre el módulo en Foundry y comunica el **ID de usuario** que muestra su panel. El anfitrión escribe ese ID, elige un tripulante nativo y decide si concede sólo ficha/lectura o también órdenes básicas de su puesto.
4. Pulsa **Emitir / sustituir acceso**, copia el token y entrégalo sólo a la persona elegida. En Foundry selecciona **Acceso personal**, pega el token y conecta. Su ficha actual, los datos públicos de nave y los controles permitidos aparecen juntos.
5. La ventana nativa permite revocar un acceso o todos. Los accesos expiran en una hora y se revocan al cambiar misión, puesto o conexión. Desactivar/reiniciar el enlace los elimina. Tras una revocación el panel borra los datos mostrados en el siguiente sondeo (dos segundos).

El token que conserva la pantalla original de Sesión sigue siendo **consulta pública**: únicamente `/v1/state` y `/v1/events`. No permite fichas ni órdenes, ni puede emitir accesos. En el panel nuevo se puede elegir esa modalidad expresamente.

El transporte permanece en `127.0.0.1:27841`: **el navegador debe ejecutarse en el mismo equipo que el host de Lagunak**. El servidor web de Foundry puede estar en otra máquina. Delegar a un tripulante ENet remoto no hace accesible el loopback del host desde su ordenador; debe usar un navegador en el equipo host para este adaptador. No se anuncia control Foundry remoto desde otras máquinas. Un Lagunak en modo cliente no puede emitir accesos personales ni controlar su simulación local por HTTP.

## Autoridad y límites

La credencial efectiva es el token aleatorio de 256 bits concedido por el host. `X-Lagunak-User` debe coincidir con su etiqueta, pero **no demuestra por sí solo una sesión autenticada en Foundry**. El host no acepta el rol, ID nativo, GM, identidad o propietario declarados en el cuerpo de una orden. Quien obtenga un token ajeno podrá utilizar la delegación: debe tratarse como una contraseña temporal.

La vinculación vive sólo en memoria y contiene usuario, peer nativo, puesto al emitir, modo, ejecución de misión y conexión. Cada petición comprueba el roster real y la conexión ENet; los cambios de Session y la señal de desconexión purgan permisos inmediatamente. Un cierre abrupto se detecta según el timeout de ENet. No se conserva la delegación al reconectar ni se reserva un segundo puesto. Por identidad nativa y por usuario hay como máximo una delegación; emitir otra revoca la anterior.

Las órdenes pasan por `Simulation.command(puesto_resuelto, operación, argumentos, principal_nativo)` y su validación existente. No se crea otra simulación ni se modifica Session. Los resultados refrescan el estado nativo y su difusión ENet habitual. Cada token admite cinco órdenes por segundo y comparte también el límite nativo por peer. El cuerpo incluye ejecución de misión y secuencia exacta; las repeticiones, órdenes de otra misión y llamadas concurrentes se rechazan. Un resultado recibido con `ok: false` consume secuencia si la simulación llegó a ejecutarse. Un timeout nunca provoca un reintento automático: se consulta de nuevo antes de otra decisión del jugador.

| Puesto nativo | Controles expuestos con permiso de control |
|---|---|
| Mando | Alerta verde/ámbar/roja |
| Navegación | Rumbo e impulso, piloto automático, atraque y desatraque |
| Ingeniería | Potencia, refrigeración y escudos |
| Armas | Disparo de haces |
| Sensores | Análisis de contacto |
| Comunicaciones | Abrir canal |
| Enlace | Lanzar sonda |
| Control de daños | Reparar sistema |

Autodestrucción, códigos, cartas/dados, apuestas, inventario, edición de fichas, recompensas, herramientas GM, cambios de campaña y operaciones fuera de esta tabla no tienen ruta de escritura externa. Las reglas nativas conservan costes, alcance, identificación y requisitos; el panel no promete éxito antes de la respuesta del host.

## Protocolo

Todas las respuestas son JSON sin caché. CORS permite sólo el origen elegido. Se comprueba también Host de loopback y puerto, se rechazan cabeceras duplicadas, Transfer-Encoding, bytes fuera del contrato ASCII de peticiones y datos adicionales. Límites: ocho conexiones, 2,5 segundos, 8 KiB de cabeceras y 2 KiB de cuerpo. Las respuestas y nombres/textos pueden contener Unicode. Las órdenes sólo contienen identificadores, enums, booleanos y números acotados.

| Ruta | Método | Credencial | Respuesta |
|---|---|---|---|
| `/v1/state` | GET | Token público de Sesión | Misión básica, nave y contactos públicos |
| `/v1/events?after=0` | GET | Token público de Sesión | Hasta 200 eventos públicos y cursor |
| `/v2/view` | GET | Token personal + `X-Lagunak-User` | Protocolo 2, ejecución, identidad/puesto concedidos, ficha propia, nave/contactos, lista de órdenes, secuencia y eventos del mismo instante |
| `/v2/command` | POST JSON | Token personal de control + `X-Lagunak-User` | `{ok, message, sequence}` tras aplicar las reglas nativas |

Cuerpo de orden: `{"run_id":"…","sequence":1,"operation":"alert","args":{"level":"ambar"}}`. Las claves son exactas; no se admiten extras. 400 indica formato/límites inválidos, 401 acceso incorrecto/caducado, 403 falta de permiso, 409 ejecución/secuencia caducada o pausa y 429 límite de frecuencia.

La proyección usa una lista positiva: añadir campos al estado o al guardado no los publica automáticamente. Excluye documentos de campaña, inventarios, fichas ajenas, hitos narrativos privados, director, lounge, códigos y estructuras internas de cooperación/sensores. Los contactos sin identificar mantienen únicamente eco, ID, posición y estado de identificación. La ficha propia sólo incluye nombre, enfoque, habilidades, rasgos conocidos, condición, concentración, nivel y XP; leerla no crea perfiles nuevos ni guarda datos. El registro expuesto es el registro público de Simulation, nunca los logs privados de mesas o fichas. El contrato v1 mantiene lo consumido por el módulo anterior y elimina campos internos que antes viajaban por duplicación del snapshot.

El módulo no escribe fichas Actor ni flags de otros User. La creación manual de Journal requiere GM y usa la autorización documental del propio Foundry; un Journal nuevo empieza privado (`ownership.default = 0`). Sólo se importan eventos públicos escapados, nunca la ficha personal. La lectura v2 incorpora estado y eventos en una sola respuesta para evitar mezclar misiones.

## Validación automatizada

```sh
.toolchain/godot --headless --editor --path game --quit
.toolchain/godot --headless --path game --script ../tests/test_foundry_authority.gd -- --test
python3 tests/run_foundry_authority.py
python3 tests/run_telemetry.py
node --test integrations/foundry/tests/client.test.mjs integrations/foundry/tests/authority.test.mjs integrations/foundry/tests/panel.test.mjs
```

El runner nuevo levanta tres procesos reales de Godot, autentica dos clientes ENet y verifica HTTP mediante sockets y el cliente Node contra la simulación en marcha. Incluye positivos, fichas ajenas, tokens incorrectos, puesto ajeno, cuerpo/argumentos inválidos, CORS, Host, POST fragmentado, secuencias repetidas, frecuencia y revocación por desconexión. Los datos de prueba son sintéticos y temporales. Las pruebas del panel usan un fixture DOM/ApplicationV2 y comprueban formularios, borrado tras revocación y Journal; **no equivalen a ejecutar Foundry**. El workflow `foundry-authority.yml` se añade a la CI de release existente sin omitir sus gates.

## Prueba reproducible en Foundry real (pendiente)

No se ha proporcionado una instalación ni licencia de Foundry en este entorno. No se ha lanzado Foundry real ni se afirma compatibilidad comprobada fuera de v13. API de referencia: [ApplicationV2 v13](https://foundryvtt.com/api/v13/classes/foundry.applications.api.ApplicationV2.html), [botones de escena v13](https://foundryvtt.com/api/v13/functions/hookEvents.getSceneControlButtons.html) y [JournalEntry v13](https://foundryvtt.com/api/v13/classes/foundry.documents.JournalEntry.html).

Para cerrar esa comprobación, en una instalación propia/autorizada de Foundry 13:

1. Copia los seis archivos del módulo a `Data/modules/espaciokoop-lagunak/`, actívalo en un mundo de prueba y abre cuentas GM y jugador en dos perfiles de navegador del equipo host.
2. Concede al jugador un token de Navegación y al GM uno público; verifica ficha propia, ausencia de ficha ajena y disponibilidad de controles según permiso. El GM público no debe poder usar `/v2/view` ni enviar órdenes.
3. Aplica rumbo/impulso y observa el cambio real en Lagunak y en otro cliente ENet. Fuerza una orden de otro puesto mediante HTTP con el mismo token: debe obtener 403 y no modificar el juego.
4. Cambia el puesto nativo, desconecta ese peer y desactiva el enlace, en pruebas separadas: el acceso anterior debe fallar y el panel borrar la ficha. Una pestaña cerrada no debe seguir sondeando.
5. Importa dos veces la bitácora como GM: no debe duplicar eventos ni incorporar fichas; el Journal nuevo debe ser privado hasta compartirlo expresamente. Cambia de misión y verifica un Journal distinto.
6. Registra versión exacta de Foundry/navegador/SO, política de acceso local/mixed content, resultados y cualquier error de consola. Si el navegador bloquea el acceso loopback, informa de ese límite; no se recomienda desactivar su seguridad.

## Herramientas heredadas y trabajo restante

Inventario funcional contrastado contra `EspacioKoop/espaciokooplagunak@fecd0740545f485d2402c6dfe4b47d5a859cb96c`; reimplementación propia sin copiar código.

| Herramienta original | Tratamiento en este subbloque |
|---|---|
| `bridge/` FastAPI y traducción Lua | Sustituido para lectura y controles de la tabla por HTTP loopback de Godot. No se habilitan rutas Lua, shell ni passthrough. |
| Relé de órdenes Foundry por flags User | Sustituido por capacidades que concede el host nativo. El original resolvía el puesto en el relé; aquí el límite se verifica en el propio host. |
| `discordBot/` start/stop/pause/unpause | Se conserva el control local de sesión en Lagunak; se descarta ese bot heredado dependiente del servidor original. Un bot nuevo de administración remota no forma parte de esta entrega ni dispone de credenciales. |
| `netboot/` PXE/DHCP y administración de equipos | No se porta: la distribución mediante paquetes versionados/checksums sustituye la copia manual del cliente. El arranque PXE de salas sin disco sigue sin implementarse y no se declara equivalente. |
| `packs/` y generadores del motor anterior | Sustituidos como entrega por recursos y campaña incluidos en el ejecutable. La migración completa del catálogo sigue en los carriles de contenido; no se considera cerrada. |
| Docker y servidor dedicado opcional | Pendiente. Un contenedor no añade valor al HTTP que debe seguir siendo loopback del navegador; un host dedicado necesita antes un contrato de arranque, persistencia y healthcheck nativos. No se entrega un Dockerfile vacío ni se marca este criterio como cumplido. |
| Más sincronización / Foundry remoto / prueba real | Pendiente. Fichas Actor, inventario, herramientas GM y relé hacia navegadores de otras máquinas requieren contratos propios de privacidad y autoridad. |

Este PR usa `Refs #5`: no cierra Docker, pruebas reales ni toda sincronización posible. El standalone permanece completo sin instalar ninguna de estas integraciones.
