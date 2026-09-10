# Seguridad y comunicación de vulnerabilidades

## Alcance y límites actuales

Lagunak es standalone: no necesita Foundry ni servicios externos para jugar o
conservar la campaña. Eso no convierte una sesión de red en un canal privado.

**La clave de sesión autentica pertenencia al grupo, no cifra ENet.** La
implementación de `game/net/session.gd` usa un reto HMAC-SHA256 y resuelve el puesto
y el principal en el anfitrión. No configura DTLS ni autenticación del servidor
mediante certificado. No ofrece resistencia demostrada frente a escucha,
manipulación del tráfico o un intermediario en una red hostil.

El anfitrión y su sistema operativo son parte de la base de confianza: poseen la
simulación completa, los resultados y los secretos necesarios para dirigirla.
Las proyecciones por destinatario no ocultan esa información al administrador del
host. Los nombres de pantalla no son identidades verificadas. Quien conoce la
clave compartida puede solicitar cualquier puesto libre permitido por el juego;
no existe por ello una autorización individual de cuentas para cada puesto.

Para partidas con datos privados, utiliza una red controlada o un túnel cifrado
con equipos autorizados y limita el puerto UDP mediante el cortafuegos. No
expongas el puerto de juego indiscriminadamente a Internet. Usa una clave
aleatoria distinta de tus contraseñas personales y cámbiala al cambiar el grupo.
Estas son medidas de despliegue, no funcionalidades de cifrado añadidas al juego.

El adaptador Foundry es opcional y su HTTP se limita a loopback. Un token personal
es una credencial al portador: `X-Lagunak-User` es una etiqueta vinculada a esa
credencial, no una prueba independiente de identidad de Foundry. No publiques
claves, tokens, tickets de reconexión, guardados, fichas ni capturas que los
contengan. No abras el HTTP mediante un proxy público ni desactives las
protecciones del navegador para hacerlo funcionar.

Consulta [el modelo de amenazas y sus pruebas](docs/NETWORK_BOUNDARY.md) y
[el contrato del adaptador opcional](docs/FOUNDRY_AUTHORITY.md). Las verificaciones
se atribuyen a un SHA y una ejecución concretos; no constituyen una certificación
ni una promesa de ausencia de vulnerabilidades en todas las versiones.

## Comunicar un problema

Si GitHub muestra **Security → Advisories → Report a vulnerability** para este
repositorio, utiliza ese canal privado. Su disponibilidad depende de la
configuración del repositorio; este documento no afirma que esté activado.

Si no aparece, solicita al mantenedor un canal privado mediante un mensaje mínimo
sin detalles explotables. No publiques una prueba de explotación, datos de una
mesa real ni credenciales en un issue abierto. No se define aquí una dirección de
contacto no verificada ni un plazo de respuesta garantizado.

En el canal privado, incluye versión/SHA, sistema operativo, componente afectado,
impacto observado, pasos mínimos con datos sintéticos y si el fallo requiere
conocer la clave o ser anfitrión. Elimina datos personales antes de adjuntar logs.
Ante una credencial expuesta, cierra la sesión o revoca el acceso correspondiente;
retirar el texto público no revoca por sí solo una credencial ya copiada.

## Criterio para cambios de seguridad

Una corrección debe incluir un caso negativo que falle antes del arreglo y un
control positivo que conserve el uso autorizado. Si afecta a red, guardados o
proyecciones, debe respetar `AGENTS.md`, la compatibilidad y las reservas de #7.
Ni una suite parcial verde ni la existencia de este documento cierran la paridad
#1/#32. La revisión y la CI canónica siguen siendo necesarias antes de integrar.
