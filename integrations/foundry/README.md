# Enlace opcional con Foundry

Módulo para Foundry VTT 13. El juego funciona de forma independiente; este módulo añade un panel de consulta para la dirección de juego e importación manual de la bitácora a un diario.

## Instalación y conexión

1. Instala el módulo con la URL de `module.json` publicada en el README principal, o descomprime el ZIP de la publicación en `Data/modules/espaciokoop-lagunak/`.
2. Actívalo en tu mundo. Abre el panel desde el botón de nave en las herramientas de fichas, con una cuenta de dirección de juego.
3. Ejecuta Lagunak y abre una campaña. En **Sesión → Enlace con Foundry**, introduce el origen exacto de tu página de Foundry, por ejemplo `http://localhost:30000`, sin ruta ni barra final.
4. Activa la consulta local, copia el token y pégalo en el panel de Foundry. Pulsa Conectar.

El navegador que muestra Foundry debe estar en el mismo equipo que la instancia de Lagunak a la que consulta. El servidor de Foundry puede estar alojado en otro equipo: la consulta la realiza el navegador hacia `127.0.0.1:27841`. Si el navegador pide autorización de acceso a la red local, debe concederse para esta conexión elegida por el usuario.

El panel también puede abrirse con una macro de script:

```js
game.modules.get("espaciokoop-lagunak").api.open();
```

## Comportamiento

El cliente consulta estado y eventos cada dos segundos tras conectarlo. El token se mantiene en memoria, se elimina al desconectar y debe volver a introducirse después de cerrar el panel. No se guarda en ajustes de Foundry ni se añade a una URL.

**Importar nuevos eventos a un diario** crea una entrada por ejecución de misión y añade los eventos todavía no importados. La aplicación conserva los últimos 200 eventos; importa periódicamente si quieres archivar una sesión con muchas órdenes. El texto del juego se escapa antes de incorporarlo al diario. Solo la dirección de juego puede usar el panel.

La API admite GET `/v1/state` y GET `/v1/events?after=0`, con cabecera `Authorization: Bearer <token>`. No dispone de rutas para controlar la nave. Cambiar de misión durante una importación cancela esa importación para evitar mezclar dos bitácoras.

## Comprobaciones

Las pruebas automatizadas ejercitan el servidor HTTP real de Godot y el cliente JavaScript, incluidas autenticación, origen, límites, abortos y escape de texto. El panel y la escritura de diarios utilizan la API documentada de Foundry 13. No se ha ejecutado una instalación de Foundry VTT en el entorno de construcción; esa comprobación manual queda documentada en `docs/VALIDATION.md`.
