# Fronteras de red: amenazas y regresiones

Subbloque de #32 §4.3. Revisión inicial del código de
`8b1dcf27683a00972b03d5203606eab12f31fe2d`; los resultados ejecutados deben citar el
SHA del PR y el enlace a su CI. No modifica protocolo, simulación ni guardados.

## Qué se confía y qué se protege

El host y su sistema operativo son de confianza. Los clientes, sus nombres y los
argumentos de sus órdenes no lo son. La LAN no se presupone confidencial. Los
activos son la autoridad de la simulación, los puestos, las fichas/tareas/cartas
privadas, las credenciales y los documentos de campaña que sólo necesita el host.

| Frontera | Implementación revisada | Garantía acotada y riesgo restante |
|---|---|---|
| Conexión → miembro | `Session._peer_connected`, `_challenge`, `_authenticate` | Nonce aleatorio de 24 bytes, reto de 8 segundos, HMAC-SHA256 y comparación de tiempo constante. Consume el reto antes de aceptar/rechazar. No es cifrado de transporte ni autenticación del servidor por certificado. |
| Miembro → puesto | `Session._authenticate`, `_request_role`, `_assign_role` | Asiento exclusivo; se resuelve usando el peer del transporte y el roster. El nombre no confiere derechos. Conocer la clave compartida permite pedir un puesto libre: no es una cuenta individual ni una lista de GM autorizados. |
| Orden → simulación | `_receive_order` y `Simulation.command` | Puesto/principal obtenidos del servidor, permisos y entradas acotadas. Un `role`, `actor` o `principal` declarado en args no sustituye esa identidad. El límite nativo de órdenes es por peer y ventana, no protección integral frente a DoS. |
| Simulación → cliente | `Simulation.snapshot`, `ShipOperations.redact`, `Cooperation.redact` | Documento de autoría, códigos ajenos y retos ajenos no deben viajar al cliente. Las garantías son por campo/sistema: no se deduce privacidad de todos los futuros campos por esta prueba. |
| Mesas y reconexión | `Session._receive_table`, tickets y `ShipLounge` | El servidor resuelve identidad y permisos; el ticket es secreto al portador. Las pruebas específicas de mesas siguen en `test_tables.gd` y `run_table_network.py`; esta suite no las sustituye. |
| Presencia | `Session._receive_pose` | Requiere miembro y coordenadas/yaw finitos con límites. No demuestra recorrido físico legítimo, antiteletransporte ni prevención de trampas gráficas. |
| Paquete → vista local | `Session._snapshot` | Límites de 256 KiB y validación de estructura mínima. Las llamadas locales de esta suite prueban el parser, no la autenticidad del remitente RPC ni resistencia exhaustiva a fuzzing. |
| HTTP opcional → juego | `Telemetry` y adaptador de autoridad Foundry | Loopback, tokens y proyección explícita. El contrato detallado, límites, revocación y pruebas HTTP están en `FOUNDRY_AUTHORITY.md`; CORS no reemplaza autenticación ni cifra el tráfico. |

### Riesgos que no quedan resueltos

El código de Session no configura DTLS. El reto de acceso no cifra snapshots ni
tickets de reconexión y no protege por sí solo frente a un intermediario. Una
clave humana débil tampoco debe considerarse resistente a adivinación offline de
un reto observado. Las pruebas de loopback no capturan, alteran ni auditan el
tráfico en una red hostil. No añaden TLS/DTLS, VPN ni negociación criptográfica.

Tampoco cubren saturación de UDP, agotamiento previo a autenticar, todas las
superficies RPC de otros autoloads, compromiso del host, malware local, versiones
vulnerables del motor, seguridad física ni cifrado de archivos en disco. La
limitación de órdenes no equivale a limitar todo el tráfico recibido. Se requiere
un análisis propio antes de anunciar exposición pública segura.

## Suite nueva reproducible

```sh
python3 tools/bootstrap.py
.toolchain/godot --headless --editor --path game --quit -- --test
python3 -m unittest discover -s tests -p test_network_boundary_runner.py -v
python3 tests/run_network_boundary.py
```

`--godot /ruta/al/motor` permite reutilizar el motor verificado; `--timeout` admite
15–120 segundos y vale 60 por defecto. El bootstrap descarga herramientas; la
suite nueva sólo conecta clientes a `127.0.0.1`, usa una clave aleatoria sintética
y no solicita cuentas, partidas ni credenciales reales. El host utiliza el método
real de apertura de sesión (puede escuchar en otras interfaces); ejecútala en un
entorno de pruebas aislado, no como servicio en una máquina expuesta.

Cada proceso recibe directorios HOME/XDG/APPDATA temporales distintos y `--test`
para desactivar guardados. Es aislamiento de datos de prueba, **no un sandbox del
sistema operativo**. El lanzador elige un puerto UDP libre observado; si otro
proceso lo ocupa antes del host, la prueba falla en vez de reutilizar un servidor.
No se pasan claves por argumentos de línea de comandos ni se imprimen a propósito.

Se lanzan cinco procesos: uno de parser/límites y cuatro que usan ENet (host,
cliente sin autenticar, Ingeniería y Navegación). Los clientes no están todos
conectados a la vez. La coordinación por archivos temporales evita depender de
esperas fijas para el orden de las fases. El host verifica independientemente los
efectos de los paquetes, además de las respuestas que ve el cliente.

| Caso | Evidencia exigida por `tests/test_network_boundary.gd` |
|---|---|
| `unit` | 20 órdenes permitidas, exceso rechazado, ventanas y peers independientes; tamaños/longitudes y tipos obligatorios de snapshot rechazados; un paquete válido sí se acepta. |
| `unauthenticated` + host | Se envían órdenes de timón/potencia, solicitud de puesto y pose antes de resolver una clave incorrecta. No se obtiene puesto ni snapshot útil y no cambia la nave; la conexión sí entrega el rechazo. No es una prueba de entrega garantizada del datagrama de pose, que usa canal no fiable. |
| `victim` | Ingeniería recibe un reto privado real y exclusivamente su código de confirmación; conserva su puesto pese a un nombre de pantalla duplicado. |
| `navigation` + host | El mismo nombre no comparte identidad; argumentos falsos de puesto/principal no permiten cambiar potencia ni jugar/cancelar el reto ajeno. Una segunda llamada a autenticación, ya consumido el reto, no eleva el puesto. No se prueba aquí un replay de HMAC capturado entre conexiones. |
| Control positivo | Navegación autorizada modifica realmente el impulso a 0,33. Evita un falso verde causado por rechazar todas las órdenes o por una conexión que no funciona. |
| Privacidad | La vista real de Navegación excluye documento de campaña, marcador oculto, tareas/códigos ajenos, clave y ticket. La proyección interna de telemetría excluye documento, lounge, códigos y tareas; no se presenta esa llamada local como una petición HTTP real. |

El runner exige salida cero, exactamente un resultado final con comprobaciones
positivas y cero fallos, y ausencia de `SCRIPT ERROR`, `ERROR` o `FATAL`, incluso
con códigos ANSI. Impone plazo global, watchdog Godot y límite de logs observado;
termina los procesos restantes al salir. Sus pruebas Python incluyen resultados
incompletos, falsos éxitos, errores, aislamiento y terminación/escalado.

El workflow aditivo `network-boundary.yml` conserva los logs sintéticos dentro de
la salida de Actions. No crea artefactos con campañas ni modifica `release.yml`.
Una prueba verde demuestra los casos de su tabla, no todos los riesgos del modelo.

## Evidencias complementarias, sin duplicar sus pruebas

La CI canónica mantiene `tests/run_network.py`, `tests/run_telemetry.py` y las
pruebas de mesas. El workflow `foundry-authority.yml` conserva la frontera HTTP
personal con ENet y sockets reales. [FOUNDRY_AUTHORITY.md](FOUNDRY_AUTHORITY.md)
explica qué queda pendiente de comprobar dentro de Foundry real.

Antes de cerrar un hallazgo, registrar SHA, versión del motor, comando, resultado
y enlace a la ejecución. No atribuir resultados de `main` a una release anterior
ni cerrar #32 por sumar estas comprobaciones. Ante un fallo de producción,
reservar primero sus archivos en #7 y añadir una regresión específica.

## Fuentes primarias

- Código: [Session](../game/net/session.gd),
  [Simulation](../game/core/simulation.gd),
  [Cooperation](../game/core/cooperation.gd),
  [pruebas ENet existentes](../tests/test_network.gd).
- [Godot 4.7: multiplayer de alto nivel](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html).
- [Godot: ENet y activación explícita de DTLS](https://godotengine.org/article/multiplayer-changes-godot-4-0-report-3/).
- [GitHub: informes privados de vulnerabilidades](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/fix-reported-vulnerabilities/manage-vulnerability-reports).
