# Paquete base de accesibilidad

Este bloque de #32 añade componentes runtime independientes para:

- emitir subtítulos de avisos con origen y duración;
- representar información con etiqueta, icono y patrón además del color;
- eliminar duraciones de transición cuando se activa movimiento reducido.

No toca red, guardados ni persistencia de preferencias. La aplicación que los consuma debe decidir cómo presentar y, si procede, persistir las opciones localmente.

Esto **no declara traducción completa**, certificación de todas las pantallas, modo daltónico global ni cumplimiento total de accesibilidad. Son los siguientes trabajos del carril.

Prueba aislada:

`godot --headless --path game --script res://../tests/test_accessibility_baseline.gd`
