# Trofeos de campaña en el Museo

Subcarril de #32. Esta entrega conecta una primera vitrina jugable con el Museo
existente; **no cierra la casilla compuesta de trofeos en museo y camarotes**.

## Uso

1. Inicia o continúa una expedición desde el ejecutable standalone.
2. Entra físicamente al Museo y abre el libro.
3. Pulsa **Vitrinas de campaña**.
4. La galería muestra cinco cartelas: estado expuesto o pendiente y progreso
   público hasta desbloquearlas.

Al volver a abrir el libro, la galería se deriva otra vez del progreso de la
campaña que la sesión ya ha cargado. No existe una segunda partida ni una
colección paralela que pueda divergir del guardado.

## Contrato de datos

`CampaignTrophyCatalog.project(campaign)` recibe sólo el resumen público de
`Session.view.campaign` en el cliente o el estado de campaña del guardado local
en offline. Devuelve `format = "lagunak-campaign-trophies"`, `version = 1`, un
`scope`, un `summary` y una lista cerrada de `trophies`.

La autoridad sigue siendo el anfitrión en red y `LocalStorage` en offline. La
proyección no ejecuta órdenes, concede recompensas, muta la simulación ni
escribe archivos. En red, el cliente no consulta `Session.sim.state`: sólo usa
el resumen que ya recibió mediante la vista pública.

Las cinco cartelas son:

| ID | Desbloqueo público | Ubicación actual |
| --- | --- | --- |
| `first_route` | Una misión completada | Museo |
| `three_routes` | Tres misiones completadas | Museo |
| `survivor_manifest` | Un superviviente o más | Museo |
| `reinforced_itsaso` | Una mejora de campaña o más | Museo |
| `veteran_route` | Seis misiones completadas | Museo |

La entrega no inventa un inventario de artefactos: el estado de campaña actual
no expone un contador persistente de artefactos recuperados. La cartela de
supervivientes usa únicamente el contador público existente; un sistema de
artefactos y su diseño de producto requieren un subcarril posterior.

## Privacidad y límites

- Se aceptan identificadores de misión de hasta 64 caracteres y como máximo 256
  entradas, sin coerción de tipos ni duplicados.
- Los contadores se validan como enteros finitos y acotados. Valores inválidos
  bloquean la proyección, no se convierten silenciosamente en cero.
- No se copian contactos, inventario, perfiles, identidades de red, claves,
  cartas, dados, objetivos futuros ni campos desconocidos.
- `history_complete` permanece en `false`: el catálogo deriva el estado actual
  retenido por la campaña y no reconstruye una historia ilimitada.
- El cliente puede ver solamente la proyección pública del anfitrión; esta
  vertical es de lectura y no añade RPC ni un canal externo.

## Verificación reproducible

Con la toolchain del repositorio:

```sh
python3 tests/run_campaign_trophy_catalog.py --self-test
python3 tests/run_campaign_trophy_catalog.py
xvfb-run -a python3 tests/run_campaign_trophy_catalog.py --graphics
```

La suite usa fixtures sintéticas y comprueba catálogo cerrado, determinismo,
round-trip textual, no mutación, privacidad, tipos/límites negativos y el
recorrido real `MuseumReader → Vitrinas de campaña → ventana de galería`.
El runner falla ante salida no nula, `SCRIPT ERROR`, `ERROR`, marcador ausente o
cero comprobaciones. La ejecución gráfica automatizada no sustituye el
playtest humano de una misión completada, guardado/reapertura y recorrido
físico hasta el Museo.

## Pendiente y rollback

Esta rebanada no añade vitrinas 3D físicas, objetos de artefacto, cartelas en
camarotes, editor de trofeos, sincronización con Foundry, replay/debriefing,
agenda de NPC, canales de voz/texto, espectador, modo foto ni Parlamento.
Tampoco modifica la autoridad, el protocolo de red o el formato de guardado.

Rollback: revertir el commit de esta entrega. El código anterior conserva el
libro del Museo y las partidas existentes; no hay migración porque los trofeos
son una proyección derivada y no se escribe un campo nuevo.
