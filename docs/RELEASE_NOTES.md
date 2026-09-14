# Espaciokoop Lagunak 0.9.3

**Cooperativo con acceso guiado por Hamachi**, para Linux y Windows x86_64.
Actualización del juego standalone; no es la certificación de paridad total 1.0.

## Jugar juntos en pocos pasos

1. Instalad y encended **Hamachi** en cada equipo; entrad en la misma red privada.
2. En Lagunak, pulsad **Inicio → Jugar por Hamachi** o abrid la misma opción desde
   **Sesión**.
3. El anfitrión comprueba su IPv4 de Hamachi, pulsa **Crear partida** y comparte
   **Copiar invitación** por un canal privado.
4. Los demás abren **Tripulante**, pulsan **Pegar invitación**, eligen un puesto
   libre y pulsan **Unirse**. No necesitan copiar puerto y clave por separado.

[Guía de Hamachi y resolución de problemas](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/v0.9.3/docs/HAMACHI.md).

## Qué cambia

- Asistente nativo con pestañas para anfitrión y tripulante, portapapeles explícito
  y mensajes sobre conexión, errores y puestos ocupados.
- Detección conservadora de interfaces identificadas como Hamachi, con alternativa
  manual cuando la tarjeta no aparece o tiene un nombre personalizado. No se
  presupone que una dirección pertenezca a Hamachi por su prefijo.
- Invitación privada con dirección IPv4, puerto real del anfitrión y clave. Se
  valida su formato y sus límites antes de conectar; no es una URL ni ejecuta
  instrucciones. La contraseña de la red Hamachi no se pide ni se almacena.
- Se evita reemplazar una sesión activa inadvertidamente y se confirma su cierre.
  Cerrar la ventana del asistente no cierra la partida.
- La entrada al puente espera a la primera vista de la nave tras la autenticación:
  «Conectando» no se confunde con una entrada ya completada.
- Se conserva el formulario manual de red y el protocolo de autenticación existente,
  la autoridad del anfitrión, los puestos y los guardados compatibles.

## Descargar y ejecutar

Descomprime el ZIP completo **en una carpeta nueva**, sin sobrescribir la instalación
0.9.2. Ejecuta `EspaciokoopLagunak.exe` en Windows o `EspaciokoopLagunak.x86_64` en Linux.
En Linux puede hacer falta dar permiso de ejecución al archivo.

El juego y sus recursos van incluidos: no necesitas instalar Godot, Blender,
Docker o Foundry. **Hamachi sí debe estar instalado y conectado para usar esa VPN**;
el juego local y la conexión manual no lo requieren.

La release incluye `SHA256SUMS` para comprobar las descargas. El adaptador Foundry
sigue siendo un ZIP opcional separado: **conserva su versión 0.9.2, sin cambios de
código, metadatos o compatibilidad**. Esta función pertenece al juego, no al módulo.

## Seguridad y límites

- La invitación contiene una credencial de acceso. Su formato compacto **no la
  cifra**; no la publiques ni la incluyas en capturas. El portapapeles puede
  conservarla después de cerrar el asistente.
- Lagunak no instala ni configura Hamachi, no modifica el firewall/router, no
  habilita UPnP y no abre el adaptador Foundry en la VPN. No se deben desactivar
  protecciones para resolver una conexión fallida.
- ENet autentica, pero no cifra por sí mismo. Utiliza una VPN conectada y una red
  de confianza. La detección de la interfaz no demuestra que el túnel del proveedor
  esté operativo; se mantienen las condiciones y límites de Hamachi.
- No hay migración de host. Conserva una copia local de la campaña antes de
  actualizar y usad todos la misma compilación para jugar juntos.

## Verificación y alcance real

La publicación depende de la CI canónica del commit final de `main`, las
exportaciones Linux/Windows, la aceptación gráfica del ZIP Linux y el arranque
real del ejecutable Windows. Se conservan las comprobaciones de campaña,
autenticación, privacidad, red, terminales, pasillos, ocio y el adaptador opcional.

Se añaden pruebas del asistente nativo, validación positiva/negativa de invitaciones
y controles del ejecutor. Cuatro procesos Godot reales comprueban crear/unirse,
clave incorrecta, puesto ocupado, recepción autorizada de estado y reconexión,
con perfiles sintéticos aislados y sin registrar credenciales.

**Estas conexiones automatizadas se realizan en el mismo equipo: no certifican
un túnel Hamachi entre dos ordenadores ni sustituyen un playtest humano.** La
instalación del proveedor y las reglas de red de los jugadores necesitan
comprobarse en sus equipos. La validación con una instalación licenciada de
Foundry sigue pendiente.

No se incluyen guardados con nombre ni las PR de cosmografía/accesibilidad que
siguen fuera del corte. El corpus de escenarios continúa siendo un inventario,
no escenarios jugables nuevos. No se publican paquetes macOS o Android ni se
anuncian vuelo 6DOF, aterrizaje seamless o rendimiento certificado por hardware.
#1/#32 mantienen sus pendientes; #29 conserva la confirmación en el equipo afectado.

Para informar de un fallo, indica **0.9.3, sistema operativo, anfitrión/tripulante,
pasos y resultado observado**, sin enviar invitaciones, claves ni partidas completas.
