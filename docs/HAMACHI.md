# Jugar por Hamachi

Acceso guiado de cooperativo de **0.9.3**. **No está incluido en los ZIP de 0.9.2.**
Consulta [Releases](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/tag/v0.9.3)
para descargar la versión adecuada.

Hamachi conecta los equipos como una red local a través de Internet. Lagunak utiliza
esa conexión, pero **no instala Hamachi, no crea redes del proveedor y no cambia el
firewall ni el router**. La conexión manual de **Sesión** sigue disponible.

## Preparar la red una vez

1. Instala Hamachi desde su proveedor y actívalo en cada equipo.
2. Crea una red privada en malla (*mesh*) y comunica su identificador y contraseña
   únicamente a las personas con las que vas a jugar.
3. El resto entra desde **Red → Unirse a una red existente** en Hamachi. Comprobad
   que el anfitrión y los demás aparezcan conectados en la misma red.
4. Todos deben abrir la misma versión de Lagunak.

La cuenta, la aprobación de miembros y los límites de participantes dependen del
proveedor. La contraseña de la red Hamachi **no se introduce en Lagunak**.
[Documentación oficial de Hamachi](https://support.goto.com/hamachi) ·
[Unirse a una red existente](https://support.goto.com/hamachi/help/beitritt-zu-einem-bestehenden-netzwerk-hamachi-t-hamachi-client-join-nw).

## Anfitrión: abrir la nave y compartir una invitación

1. En **Inicio** o **Sesión**, pulsa **Jugar por Hamachi**.
2. En la pestaña del anfitrión, comprueba la dirección detectada. La detección sólo
   reconoce interfaces identificadas como Hamachi; no elige otra tarjeta porque
   su dirección se parezca. Si falta, abre Hamachi, copia su **IPv4** y pégala en
   el campo de dirección. No uses el identificador de la red ni una IPv6.
3. Pulsa **Crear partida**. El puerto predeterminado es UDP `27840`.
4. Pulsa **Copiar invitación** y envíala por un canal privado a la tripulación.
   Cierra esta ventana para volver al juego; **cerrar la ventana no cierra la partida**.

No hace falta escribir el puerto ni la clave por separado en los demás equipos.
La invitación toma el puerto del anfitrión real: si la partida se creó desde el
formulario manual con otro puerto, no anuncia el predeterminado por error.

## Tripulante: pegar y entrar

1. Pulsa **Jugar por Hamachi** y abre la pestaña del tripulante.
2. Usa **Pegar invitación**, escribe tu nombre para la partida y elige un puesto libre.
3. Pulsa **Unirse**. «Conectando» no significa que el anfitrión te haya aceptado:
   la entrada se confirma cuando finaliza la autenticación y aparece el puente.

El juego comprueba la estructura de la invitación antes de intentar conectar.
No abre enlaces ni ejecuta instrucciones que se hayan pegado en el campo.

## Si no conecta

- **No se detecta Hamachi:** comprueba que esté encendido. Si la interfaz tiene un
  nombre personalizado o no puede identificarse, pega manualmente su IPv4. La
  detección de la tarjeta por sí sola no certifica que el túnel esté operativo.
- **Invitación inválida:** pide una copia completa al anfitrión. No pegues el nombre
  de la red, su contraseña, una dirección IPv6 o una URL.
- **Clave incorrecta:** pide una invitación nueva; crear otra sesión renueva la clave.
  La clave de Lagunak y la contraseña de Hamachi son credenciales distintas.
- **Puesto ocupado:** selecciona otro puesto; no se expulsa a su ocupante.
- **Conexión fallida:** comprueba que ambos equipos estén en la misma red Hamachi,
  que la partida siga abierta y que se pueda alcanzar al anfitrión desde el cliente
  Hamachi. Revisa la autorización específica del ejecutable de Lagunak/UDP en el
  firewall del anfitrión. **No desactives el firewall ni abras puertos del router
  indiscriminadamente.** Si la política de red impide la conexión, consulta con su administrador.
- **Puerto ocupado:** cierra explícitamente la partida anterior o utiliza el
  formulario manual de Sesión para otro puerto. Reabre el asistente para generar
  la invitación correspondiente al puerto activo.

## Privacidad y límites

- La invitación **contiene la dirección, el puerto y la clave de acceso**. Es una
  credencial: su formato compacto no la cifra. No la publiques en issues, capturas,
  vídeos, repositorios o canales abiertos.
- Copiar y pegar sólo ocurre al pulsar el botón correspondiente. El portapapeles
  pertenece al sistema y puede conservar la invitación después de cerrar la ventana;
  sustituye su contenido si el equipo es compartido.
- Los campos se limpian al cerrar la ventana. El asistente no guarda invitaciones
  en disco ni recibe la contraseña de Hamachi. La clave permanece en la sesión
  activa porque hace falta para autenticar a la tripulación.
- ENet sigue usando la autenticación existente y **no cifra el tráfico por sí
  mismo**. Hamachi debe proporcionar el túnel adecuado. No se cambia el servidor
  para escuchar exclusivamente en esa interfaz; se conserva su comportamiento
  de red anterior, sus permisos y su autoridad sobre la campaña.
- La consulta Foundry sigue siendo opcional y local; este botón no la activa ni
  la expone a la red de Hamachi. Tampoco habilita reenvíos, UPnP o migración de host.

## Comprobación reproducible

Las pruebas del componente validan las invitaciones, la detección conservadora y
los botones de la interfaz real. El ejecutor `tests/run_hamachi_network.py` arranca
cuatro procesos Godot reales en **el mismo equipo**, con una dirección local, un
puerto temporal y perfiles desechables. Comprueba crear/unirse desde la ventana,
clave incorrecta, puesto ocupado, estado autorizado y reconexión.

```sh
python3 tests/test_hamachi_runner.py
python3 tests/run_hamachi_network.py
```

La CI canónica ejecuta ambas comprobaciones a través de `tests/run_network.py` y
la regresión del asistente mediante `tests/test_ui.gd`; conserva las pruebas de
red, campaña y UI anteriores. Los registros no incluyen la invitación ni su clave.

**Una prueba local ENet no equivale a una prueba de Hamachi entre dos equipos.**
La comprobación final de la instalación del proveedor, su túnel y las reglas del
firewall de los jugadores requiere esos equipos; no se presenta la automatización
local como un playtest humano ni como certificación del servicio externo.
