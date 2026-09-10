# Consola caliente del GM

La consola caliente es una herramienta nativa para dirigir una misión ya iniciada sin depender de Foundry. Su núcleo vive en `GMLiveActions` y aplica cambios sobre la `Simulation` autoritativa del host.

## Acciones disponibles

- Crear contactos con ID, nombre, tipo y posición validados.
- Renombrar y mover contactos existentes.
- Retirar contactos y limpiar referencias activas de autopiloto, atraque o escaneo.
- Cambiar el nivel de alerta.
- Publicar mensajes de escena en la bitácora.
- Aplicar daño o reparación de escena con límites.
- Introducir refuerzos hostiles alrededor de la nave.

Todas las operaciones se rechazan si la misión no está activa. Los cambios relevantes quedan registrados mediante `Simulation.log_event()` con origen `Dirección`.

## Autoridad e integración

`GMLiveActions` no abre sockets ni duplica estado. Recibe una instancia de `Simulation`, valida parámetros y modifica únicamente el estado autoritativo existente. La ventana `GMHotConsole` es una vista delgada sobre ese núcleo.

La integración visible desde la shell principal se mantiene separada de este subcarril para no tocar `app.gd` sin una reserva explícita adicional. El sistema puede probarse directamente con `tests/test_gm_hot_console.gd` y queda preparado para conectarse a una entrada exclusiva del host/GM.
