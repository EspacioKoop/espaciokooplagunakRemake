# Asientos físicos compartidos

En **Cubierta → Cantina/Terraza**, camina hasta el frente de un asiento y pulsa
**E** (o la acción Interactuar configurada). El anfitrión confirma la reserva;
un asiento ocupado muestra ese estado y rechaza otra persona. Vuelve a
interactuar para levantarte. El ratón o stick derecho permite mirar alrededor
sin girar ni desplazar el cuerpo anclado.

Los ocho puntos físicos se obtienen de `LeisurePlaces.interactions`, junto con
las posiciones de zona de `WorldDeck`. La interacción requiere estar a un
máximo de 1,25 m del acceso y dentro de 0,75 m de su altura. Levantarse recupera
la posición accesible anterior y la colisión. Cambiar de zona, cerrar Cubierta,
cerrar la sesión o desconectarse libera la reserva. Reconectar comienza de pie.
Esto no altera los asientos ni las manos privadas de los juegos de mesa.

## Autoridad e integración

`SeatPresence` arranca como autoload incluso si el anfitrión nunca abre Cubierta.
Es la única autoridad de **ocupación física**; `Session` mantiene autenticación,
roster, posición y yaw. Los clientes no suministran otro peer ni coordenadas a
una reserva: el RPC usa el emisor autenticado y la posición ya recibida por
`Session`. Se comprueban asiento, alcance, exclusividad, versión, secuencia
creciente y frecuencia de peticiones.

El host añade únicamente su campo público opcional `roster[1].seat_protocol = 1`.
El cliente espera ese anuncio antes de negociar el componente. Un anfitrión
anterior que no lo anuncia conserva sus posiciones/yaw sin recibir RPC hacia un
nodo inexistente; los clientes anteriores ignoran el campo adicional. El
protocolo base de `Session` y los guardados no cambian.

Tras negociar, cada snapshot público de asientos contiene sólo versión,
revisión y un diccionario `seat_id → peer_id`. No hay fichas, cartas, dados,
tickets, claves ni datos de `ShipLounge`. Al cambiar el transporte se vacían
ocupantes, suscripciones, contadores y estado negociado. La retirada del
componente elimina su clave de capacidad, sin modificar otras claves del roster.

API del nodo `/root/SeatPresence`:

- `request_sit(seat_id)` / `request_stand()`: respuesta local inmediata o
  `{ok: true, pending: true}` mientras decide el host.
- `seat_for(peer_id)`: metadatos físicos canónicos del asiento, o `{}` de pie.
- `occupant(seat_id)`: peer propietario, o `0` libre.
- `changed` y `result_received(ok, message)`: proyección y feedback de UI.

`WorldDeck` presenta la posición canónica mientras alguien está sentado y vuelve
al canal original al levantarse. La malla propia `crew.glb` recibe una flexión de
cadera/rodillas generada en memoria; se conservan las superficies/materiales y se
restaura la malla original al levantarse. Los enlaces opcionales `Controls` y
`Avatars.bind_avatar` mantienen compatibilidad con los PR independientes de
controles y apariencia.

## Comprobación reproducible

```sh
.toolchain/godot --headless --editor --path game --quit
GODOT="$PWD/.toolchain/godot" python3 tests/run_shared_seats.py
GODOT="$PWD/.toolchain/godot" python3 tests/run_table_network.py
```

`run_shared_seats.py` comprueba el ejecutable/UI y seis procesos ENet reales en
dos grupos: host, dos clientes que compiten y una conexión no autenticada; después,
un host sin componente de asientos y un cliente nuevo. Incluye exclusividad,
postura/anclaje visible en la escena, rechazo de identidad falsificada, replay,
versión desconocida, posición lejana, cambio de zona, desconexión, reconexión,
descubrimiento ausente/malformado y compatibilidad de posición/yaw.

La CI canónica ya invoca `run_table_network.py`, que ejecuta primero sus pruebas
de privacidad/reconexión de mesas y después esta suite; no requiere un workflow
adicional. Las comprobaciones locales usan Godot headless. La inspección gráfica
mediante capturas necesita el runtime de pantalla de CI.

Este bloque resuelve reservas **humanas** y poses sentado/de pie. No cierra el
issue #3 completo: personalidades/NPC, gestos y edición/progresión del avatar son
subcarriles distintos. No asigna NPC a estos ocho asientos ni cambia las reservas
lógicas de póker, blackjack o dados.
