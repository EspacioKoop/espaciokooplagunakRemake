# Editor nativo de personajes — bloque de #2

## Uso y alcance

**F4 → Editar ficha** abre una ventana de 1040×740, comprobada sobre un viewport de
1600×900. Se edita únicamente la ficha propia de la sesión actual:

- Nombre: 1–32 caracteres Unicode, sin controles ni espacios en los extremos.
- Enfoque: Ingenio, Temple, Empatía o Técnica.
- Pilotaje, Ciencia, Ingeniería, Negociación y Combate: enteros de 0 a 4.
- Presupuesto compartido: **como máximo 12 puntos**; gastar menos es válido.

El presupuesto y los errores se muestran antes de aplicar. Los controles se
construyen una vez; las actualizaciones periódicas no reemplazan el formulario ni
su foco. El cuerpo tiene desplazamiento vertical y las acciones quedan fuera de
él para seguir accesibles al reducir la ventana (mínimo 900×640).

**Aplicar a mi ficha** modifica el personaje real, no una biblioteca paralela.
**Importar JSON** carga solo un borrador; no cambia la partida. Una importación
válida que sustituiría cambios locales pide confirmación. Cancelarla o importar un
archivo inválido conserva el borrador completo. **Exportar plantilla** guarda lo
visible y editable, pero no aplica cambios ni marca el borrador como aplicado.

Cerrar mediante la X, Cerrar, Escape o F4 sigue la misma confirmación de descarte
cuando hay cambios. Exportar no elimina esa confirmación. La ventana del editor
pertenece a la raíz del SceneTree, no a `CrewConsole.body` ni a la propia consola:
reconstruir o cerrar la consola de F4 no destruye el borrador. Volver a pulsar
Editar ficha enfoca la instancia existente. Tras cerrar el editor y reabrirlo se
lee la ficha vigente, sin resucitar cambios descartados.

## Una sola autoridad y progresión preservada

`CharacterDocument` es un adaptador de datos editables, no un sistema de
personajes. Sus referencias válidas proceden de `ExpeditionSystems.SKILLS` y
`ExpeditionSystems.APPROACHES`. La autoridad persistente sigue siendo
`ExpeditionSystems`; `CrewSystem` conserva las reglas y progresión existentes.

El único envío de producción es:

```gdscript
expedition.command("profile_set", {
    "name": name, "approach": approach,
    "pilotaje": pilotaje, "ciencia": ciencia,
    "ingenieria": ingenieria, "negociacion": negociacion, "combate": combate
})
```

No se asigna `data.profiles`, no se manda un actor de destino y no se restaura una
copia antigua del perfil. XP, nivel, rasgos, condición, concentración e hitos
quedan fuera del borrador y del comando. Aunque cambien mientras se edita, el
`profile_set` existente modifica solo nombre/enfoque/habilidades y conserva su
valor **vigente en el anfitrión**. El guardado sigue su ruta existente; no cambia
el formato de partidas ni el protocolo de red.

La proyección normaliza habilidades integrales a `int`, porque JSON vuelve a
cargar números como `float`. Esto evita detectar cambios inexistentes al reabrir
una partida y permite comparar snapshots con el borrador de forma canónica.

### Confirmación de aplicación

- Antes de llamar al comando se entra en estado `pending`; así también se trata
  correctamente el `updated` síncrono del modo local/anfitrión.
- «Orden enviada al anfitrión» **no es una confirmación**. La UI no declara éxito
  hasta recibir un `Expedition.updated` posterior cuyo perfil propio coincida
  exactamente en los siete campos enviados.
- Los `notice` actuales carecen de ID de petición/operación. Se muestran durante
  la espera, pero ni un aviso positivo ni un rechazo de otra orden demuestran por
  sí solos qué ficha se aplicó. Un fallo síncrono del comando sí termina como
  rechazado. No se añade un protocolo paralelo para resolver esta limitación.
- Durante la espera se bloquean edición/importación y nuevos envíos. A los
  **8 segundos** se informa de timeout, se conserva el borrador y se permite
  esperar/exportar/reintentar. Un snapshot concordante tardío se reconoce como
  confirmación tardía; no borra cambios posteriores del borrador.
- Cerrar con una petición sin confirmar exige confirmación y avisa de que **no
  cancela la orden enviada**. Cambiar de modo/identidad de sesión bloquea la
  aplicación a una ficha distinta; se debe cerrar y reabrir.

«Aplicada» confirma el estado autoritativo observado. No es una afirmación de
`fsync` ni una garantía adicional sobre el guardado de campaña existente, cuya
API no devuelve resultado de escritura. En red, el anfitrión sigue validando
identidad y límites por la infraestructura existente.

## Formato portable, versión 1

Ejemplo válido completo:

```json
{
  "format": "lagunak-character-template",
  "version": 1,
  "character": {
    "name": "Ane Itsaso",
    "approach": "tecnica",
    "skills": {
      "pilotaje": 2,
      "ciencia": 3,
      "ingenieria": 3,
      "negociacion": 2,
      "combate": 2
    }
  }
}
```

El sobre contiene exactamente `format`, `version`, `character`; `character`,
exactamente `name`, `approach`, `skills`; `skills`, las cinco claves actuales.
Todas son obligatorias. No se aceptan claves extra, IDs/referencias de actor,
barco o campaña, campos runtime, progresión, inventario ni metadatos externos.
No se cargan recursos Godot, scripts o referencias `$ref` desde el documento.

Solo se admite el formato y versión indicados. `1.0` es equivalente al numeral
integral `1`, pero `true`, `"1"`, versiones anteriores/futuras y versiones
fraccionarias se rechazan. Las habilidades integrales se normalizan a `int`;
booleanos, números no finitos, cadenas y fracciones se rechazan. No hay
migración implícita. Un cambio incompatible futuro deberá aportar una migración
explícita y sus pruebas; las partidas `lagunak-expedition` no son plantillas.

Antes del parser de Godot se comprueba gramática JSON estricta: sin comentarios,
comas finales, numerales incompletos, contenido sobrante ni **claves repetidas**,
también cuando las claves equivalentes usan escapes Unicode. Se valida UTF-8
antes de decodificar y se rechazan sustitutos Unicode escapados sin pareja. El
anidamiento se limita a 16 niveles. No se usa la permisividad del parser del
motor como sustituto del contrato.

### Archivos y fallos

- Límite de **32 KiB (32768 bytes UTF-8)** tanto en entrada como en salida. Se
  comprueba la longitud antes de leer y se lee como máximo el límite más un byte
  centinela para detectar crecimiento concurrente; no se carga un archivo grande
  y se recorta después.
- Exportación a una ruta absoluta o `user://`, con extensión `.json` y carpeta
  existente. Se rechazan `res://`, rutas al árbol de recursos del proyecto,
  enlaces simbólicos en cualquier componente, directorios como destino y rutas
  relativas/esquemas externos. No se crean carpetas por una ruta importada.
- Las rutas de `user://campaign.json`, `user://expedition-systems.json` y sus
  sufijos de respaldo/temporales están protegidas contra exportación accidental.
- Se valida todo antes de abrir un temporal de nombre aleatorio en la misma
  carpeta. Se escribe, se vacía el buffer y se relee/valida el temporal; solo
  entonces se sustituye el destino mediante `DirAccess.rename_absolute` y se
  verifica el archivo final. El código no elimina ni mueve el destino anterior
  para intentar arreglar un fallo de renombrado. Los temporales propios se limpian
  al fallar; la UI informa del fallo, no inventa una exportación correcta.
- La sustitución real y conservación del anterior ante fallos de entrada/I/O se
  prueban en Linux. No se promete durabilidad frente a corte eléctrico, protección
  contra otro proceso local que cambie las rutas simultáneamente, ni validación
  gráfica/física en Windows por el mero hecho de exportar para Windows.

## Trazabilidad funcional y compatibilidad con el original

Referencia funcional fijada del producto original:
[`docs/CONTENT_EDITOR.md` en `fecd0740545f485d2402c6dfe4b47d5a859cb96c`](https://github.com/EspacioKoop/espaciokooplagunak/blob/fecd0740545f485d2402c6dfe4b47d5a859cb96c/docs/CONTENT_EDITOR.md).
De ahí se retienen las capacidades de edición/importación/exportación de un
personaje, validación de datos, exportación del recurso visible y confirmación
antes de perder un borrador. Esta es una implementación nueva en GDScript,
construida contra las autoridades nativas actuales, sin copiar código ni assets
del original y sin necesitar Foundry.

El recurso `character` de aquel editor también contempla `crew_position_id`,
`callsign`, `tags`, `ship_id`, `legacy_role` y vínculos de campaña. **Este bloque no
implementa esa biblioteca de metadatos/dependencias ni migra sus documentos v7**;
se rechazan en vez de ignorarlos silenciosamente. El consumidor
[`ficha-dnd5e.mjs`](https://github.com/EspacioKoop/espaciokooplagunak/blob/fecd0740545f485d2402c6dfe4b47d5a859cb96c/foundry-module/scripts/asistencia/ficha-dnd5e.mjs)
usa `Actor.system` de D&D5e/Foundry, no este esquema nativo. Clases, conjuros,
recursos D&D, avatares/retratos, campañas y loadouts no se añaden aquí.

Por tanto, este bloque **Refs #2**, no cierra todo #2 ni declara paridad completa
con el original. La equivalencia garantizada es el round-trip de los campos
editables nativos enumerados, no la conversión de una ficha externa completa.

## API y pruebas

- `CharacterDocument.document(fields)` crea el sobre (sin prometer validación).
- `validate(value)`, `parse_text(text)` y `load_file(path)` devuelven
  `{ok, message, document}` si son válidos; en fallo, `{ok: false, message}`.
- `editable_from_profile(profile)` proyecta y copia únicamente campos editables;
  `command_args(fields)` valida y produce los siete argumentos planos.
- `save_file(path, fields)` valida, exporta y relee; devuelve un resultado explícito.
- `CharacterEditor.fields`: `name` (LineEdit), `approach` (OptionButton con los IDs
  nativos como metadatos) y las cinco habilidades (SpinBox).
- `read_document()` obtiene el borrador; `apply_changes()` aplica mediante el
  comando existente. `pending`, `last_apply_state` y `status` permiten observar
  la transición sin confundir envío con confirmación.
- `import_document(value)`/`import_file(path)` validan y, si corresponde, abren la
  confirmación; un `true` significa documento aceptado para ese flujo, **no** que
  se haya confirmado sustituir el borrador ni aplicado la ficha.

Ejecutar desde la raíz con el runner aislado preparado para este carril:

```sh
python3 tests/run_character_editor.py
python3 tests/run_character_editor.py --capture-only --capture-to /tmp/character-editor.png
```

El runner crea directorios temporales separados para `XDG_DATA_HOME`,
`XDG_CONFIG_HOME` y `XDG_CACHE_HOME`. **No ejecutar estas pruebas contra partidas
reales**: los autoloads leen datos al arrancar y `profile_set` guarda incluso con
`--test`. El test SceneTree además rechaza una ejecución sin `XDG_DATA_HOME`.
El runner considera fallo los mensajes `SCRIPT ERROR`/`ERROR`, la ausencia de
marcadores y salidas no cero; no basta que Godot termine con código cero.

`tests/test_character_editor.gd` cubre límites, schema/JSON/UTF-8 negativos,
privacidad, copias profundas, I/O real acotado, rutas protegidas, round-trip,
entrada F4 y controles reales, presupuesto, foco tras actualizaciones periódicas,
confirmaciones de importación/descarte, cambios autoritativos del perfil propio,
progresión que cambia durante la edición, guardado/recarga/reapertura y cierre de
la consola sin perder borrador. Una **fixture de transporte demorado** prueba
no-éxito-al-enviar, avisos no correlacionados, timeout, confirmación tardía y
cambio de sesión; no se presenta como sustituto de ENet real. El runner del carril
añade por separado host y dos clientes autenticados reales y regresiones de
Crew/Expedition/combate.

Con renderizador gráfico, `--capture-to <ruta_png>` captura el editor ejercitado,
emite `CHARACTER_EDITOR_CAPTURE_OK` y continúa su cierre normal. La comprobación
gráfica exige exactamente 1040×740 a 1600×900; el display dummy headless puede
reducir el popup a su mínimo y ahí se verifican los límites reales de todos los
controles, sin presentar esa pasada como validación visual.
