# Enlace opcional con Foundry 13

Consulta la nave, tu ficha de tripulación y las órdenes básicas que te conceda el anfitrión de Lagunak. Foundry nunca guarda ni resuelve la campaña: la simulación nativa conserva toda la autoridad.

## Instalar y conectar

1. Instala el ZIP del módulo o copia `module.json`, `main.mjs`, `client.mjs`, `style.css`, `README.md` y `LICENSE` a `Data/modules/espaciokoop-lagunak/`. Activa el módulo en tu mundo Foundry 13.
2. Abre el botón de nave en las herramientas de fichas. Está disponible para GM y jugadores. El panel muestra tu ID de usuario y el origen exacto que debes autorizar.
3. En el ejecutable Lagunak, inicia una campaña local o una sesión como anfitrión. Abre **Sesión → Enlace con Foundry**, introduce el origen de tu página (por ejemplo `http://localhost:30000`, sin ruta ni barra final) y activa la consulta.
4. Se abre la ventana nativa **Accesos por usuario**. El anfitrión escribe tu ID de Foundry, selecciona tu tripulante nativo activo y concede lectura de ficha o también órdenes del puesto. Copia el nuevo token y pégalo en Foundry con **Acceso personal** seleccionado.
5. Para la consulta anterior de nave/bitácora, selecciona **Consulta pública** y utiliza el token de Sesión. Ese token no permite controlar la nave ni leer fichas.

El navegador debe estar en el **mismo equipo que el host de Lagunak**: consulta `127.0.0.1:27841`. El servidor de Foundry puede estar alojado en otra máquina. Un navegador en otro equipo no puede usar ese loopback del host; esta versión no incorpora un relé remoto. El navegador puede solicitar permiso para acceder a la red local.

También puedes abrir el panel mediante una macro:

```js
game.modules.get("espaciokoop-lagunak").api.open();
```

## Qué se comparte

La ficha muestra sólo tu nombre, enfoque, habilidades, rasgos, nivel/XP, condición y concentración existentes en el juego. No contiene inventario, hitos narrativos, cartas, dados, fichas de otras personas ni información interna de campaña. Los contactos sin identificar permanecen como ecos.

El acceso de control ofrece únicamente operaciones básicas del puesto nativo concedido: alerta, rumbo/impulso/autopiloto/atraque, potencia/refrigeración/escudos, haces, escaneo, canal, sonda o reparación. Cada orden la verifica Godot; un rol de Foundry o una edición del formulario no concede autoridad adicional. Los recursos, alcances y requisitos del juego pueden rechazar una orden válida.

Los tokens personales duran una hora, permanecen en memoria y se eliminan al desconectar/cerrar. No se guardan en ajustes, flags, URL ni documentos. Cambiar de misión/puesto/conexión nativa, emitir otro acceso para la misma identidad o desactivar el enlace los revoca. Para reabrir la ventana nativa de accesos, reactiva el enlace; esto también rota y revoca los tokens previos. Nunca compartas un token con otra persona: la credencial es el token, no el ID visible de Foundry.

El panel sondea cada dos segundos y borra su vista cuando falla la autorización. Las órdenes tienen secuencia y no se reintentan automáticamente tras un timeout; consulta de nuevo el estado antes de repetir una acción.

**Importar nuevos eventos a un diario** está disponible sólo para GM. Crea un diario privado por ejecución de misión e incorpora los eventos públicos aún no importados; nunca copia tu ficha. El juego conserva los últimos 200 eventos, así que importa periódicamente si quieres archivarlos. No se modifica ningún Actor ni ficha de personaje de Foundry.

## Alcance comprobado

Hay pruebas de autoridad Godot, servidor HTTP real con tres procesos ENet, cliente Node contra el host y fixtures de los formularios/Journal. No se ha ejecutado una instalación licenciada de Foundry en este entorno. No se declara validación real de su ventana, políticas del navegador o documentos hasta completar la guía reproducible de `docs/FOUNDRY_AUTHORITY.md` en el repositorio.

La API v1 conserva consulta pública; v2 añade GET `/v2/view` y POST `/v2/command` con token personal y cabecera `X-Lagunak-User`. El host decide la identidad nativa y el puesto. Docker, relé remoto, fichas Actor y más sincronización permanecen fuera de este subbloque.
