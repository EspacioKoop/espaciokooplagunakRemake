# Estado del remake

Trabajo recuperado y ampliado; paridad completa con el original todavía pendiente.

Aplicación nativa Godot, ocho puestos, seis misiones, campaña persistente, cooperación por red, trece espacios recorribles, dos fuentes de Blender y editor de misiones.

La ampliación añade operaciones de puestos y cuatro minijuegos de asistencia con propuestas consumibles. El README incluye diecinueve capturas reales del ejecutable. Las pruebas de núcleo, operaciones y asistencia suman 320 comprobaciones; también se prueban interfaz, HTTP y cinco procesos de red.

Los paquetes de Actions permiten ejecutar el estado de ese commit. No equivalen a una versión final con paridad total. Consulte `docs/FEATURE_PARITY.md` y `docs/VALIDATION.md`.

Ampliación de nave: diez sistemas independientes, escudos direccionales, astillero nativo, capacidades configurables, marcha atrás y giro gradual, colisiones barridas, gravedad, portales y nebulosas. Los guardados de cuatro sistemas se migran; la red pasa al protocolo 3.

Museo y ocio: dieciocho esculturas nuevas y cartelas, cinco cuadros, libro de cinco páginas, playa con paseo continuo, reloj y aerogeneradores animados, cabina de regreso, cantina, terraza con asientos locales, estudio con focos y corredor de recuerdos. La red pasa al protocolo 4 para admitir la presencia en los nuevos destinos.

Mesas standalone: póker con botes secundarios, blackjack con pagos 3:2 y dados de faroleo; NPC, espectadores, apuestas, partidas sucesivas sin recompras y cancelación. El protocolo 5 incorpora recuperación privada de asiento y mano al reconectar durante la misma ejecución. El README añade una captura real del póker. La representación animada de cartas/dados sobre las mesas 3D sigue pendiente.
