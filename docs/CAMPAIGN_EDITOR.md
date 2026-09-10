# Taller de campañas standalone

Desde **Campaña → Taller de campañas**, el anfitrión puede crear una expedición de
1 a 24 misiones. No hacen falta Foundry, conexión a Internet ni archivos externos
para jugar o continuar una campaña ya guardada.

## Recorrido completo

1. Crea una campaña y escribe su identificador, título y presentación.
2. **Añadir misión** incorpora una etapa jugable de navegación. **Importar misión
   JSON** incorpora una misión compatible con el editor existente.
3. **Editar misión seleccionada** abre el mismo taller de mapas, contactos,
   objetivos y diseño de nave. **Aplicar a la campaña** confirma la edición;
   **Cancelar edición** permite descartarla sin alterar las demás etapas.
4. **Subir**, **Bajar** y **Eliminar** organizan la expedición. **Deshacer** recupera
   cambios, incluida una misión eliminada. No se puede quitar la última misión ni
   una misión de la que dependa explícitamente otra.
5. Cada etapa sigue por defecto una ruta lineal. Para crear bifurcaciones, desmarca
   **Ruta lineal**, marca las misiones previas que se deban completar y pulsa
   **Aplicar requisitos**. Sin ninguna marcada, la etapa estará disponible desde
   el principio. Renombrar un identificador actualiza sus referencias; reordenar
   nunca deja referencias rotas o ciclos.
6. **Guardar copia local** conserva el documento en la biblioteca de campañas.
   **Exportar JSON** permite elegir otro destino. **Abrir JSON** recupera ambos.
   Las escrituras válidas conservan la copia anterior y se finalizan mediante un
   archivo temporal. Un documento inválido no sustituye el anterior.
7. **Jugar campaña** pide confirmación antes de sustituir la partida actual. En
   **Campaña** aparecen sus propias etapas, bloqueos y progreso. Las recompensas
   pasan a la siguiente etapa y repetir una misión no las concede de nuevo.
8. Guarda la partida normalmente y usa **Continuar** tras volver a abrir el juego.
   El guardado contiene la campaña completa: no necesita volver a importar JSON.

**Probar misión** abre una partida independiente, no una etapa de la campaña. El
borrador permanece abierto y se recupera con **Volver al taller de campañas** o
abriendo de nuevo el taller desde Campaña, incluso después de visitar otra página.
Empezar otra campaña no mezcla los créditos o desbloqueos de la anterior.

![Taller de campañas en el ejecutable Linux](images/campaign-editor.png)

## Formato y autoridad

- Formato propio `lagunak-campaign`, versión `1`, campos `id`, `title`,
  `description` y `missions`. Límite de 512 KiB y 24 misiones.
- Cada misión conserva el contrato de `Catalog.validate_mission`, incluidos
  objetivos, contactos y componentes de nave opcionales. No hay otro simulador ni
  otro editor de mapas, personajes o armamento.
- El campo opcional `requires` contiene identificadores de **misiones anteriores**.
  Ausente: requiere la etapa anterior; `[]`: disponible desde el inicio. Todos los
  requisitos explícitos deben estar completados.
- Los identificadores de autoría no cambian al exportar. Al jugar se genera un ID
  determinista propio de campaña y misión, separado de las misiones incorporadas
  y sin colisiones por recortar nombres largos.
- El documento es contenido, no progreso. `Simulation.campaign` sigue siendo la
  única autoridad sobre completadas, recompensas, decisiones y mejoras.
- Sólo el anfitrión puede iniciar o cambiar campañas. El documento completo vive
  en `state.campaign_document` y en el guardado, **nunca en snapshots ENet o HTTP**.
  El cliente sólo lista la misión activa con la proyección ya autorizada.
- Guardados anteriores, sin ese campo opcional, conservan su comportamiento.
  No cambia el protocolo de red. El validador comprueba la campaña incrustada y
  la correspondencia de la misión activa antes de restaurar.

## Referencia y límites de este bloque

Se ha estudiado la referencia fija
[`EspacioKoop/espaciokooplagunak@fecd0740545f485d2402c6dfe4b47d5a859cb96c`](https://github.com/EspacioKoop/espaciokooplagunak/tree/fecd0740545f485d2402c6dfe4b47d5a859cb96c):
`docs/CONTENT_EDITOR.md`, `src/content/contentResource.cpp`,
`src/content/campaignGraph.cpp` y `src/screens/gm/contentEditor.cpp`. La referencia
separa autoría, relaciones y validación del estado de juego. Esta implementación
es propia y no incorpora código, assets ni escenarios del original.

Este bloque cubre autoría y ejecución multi-misión con dependencias locales. No
importa automáticamente recursos C++/Lua, mapas, bibliotecas o grafos del formato
original, ni añade su catálogo completo. Tampoco cierra los subcarriles de
personajes o loadouts, que reutiliza a través de los componentes existentes.
**Es un avance parcial de #2, no el cierre de todo #2 ni de la paridad del juego.**

## Verificación reproducible

```sh
.toolchain/godot --headless --editor --path game --quit
python3 tests/run_campaign_editor.py
python3 tests/run_network.py
```

El runner usa datos temporales, rechaza errores de Godot incluso con salida cero y
exige marcadores de finalización. Cubre documentos válidos/hostiles, dependencias,
renombrado, importación/exportación, guardado, tres etapas completadas con la
simulación real, recompensa única, compatibilidad, UI y host/cliente ENet reales.
`tests/run_network.py` lo ejecuta obligatoriamente desde la CI de publicación
existente, sin sustituir ni desactivar sus cinco procesos de red.

Captura opcional del **ejecutable exportado**, mediante el pipeline integrado:

```sh
python3 tools/build.py
build/linux/EspaciokoopLagunak.x86_64 --audio-driver Dummy -- \
  --test --capture --capture-campaign-editor --capture-dir /tmp/lagunak-capture
```

Requiere pantalla gráfica, o un Xvfb temporal. Produce la galería habitual y
`campaign-editor.png`; debe terminar con `LAGUNAK_CAMPAIGN_CAPTURE_OK` y sin errores
de script. El modo de captura no escribe la partida del jugador. Las pruebas
headless y la captura automatizada no sustituyen un playtest humano cooperativo.

— OTACON Astra
