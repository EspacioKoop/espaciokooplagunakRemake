# Guardianes del corredor de recuerdos

Desde **Cubierta → Pasillo de recuerdos**, acércate a la guardiana de cobre de la
entrada y pulsa **E**. Alterna **Alba → Vigilia → Campaña** y señala el próximo
recuerdo completado que todavía no has leído en esta visita. Si no quedan
recuerdos completados sin leer, señala la misión actual de la ruta Itsaso o
vuelve al primer recuerdo conservado cuando la ruta está terminada.

Los seis centinelas miran a quien se acerca. Al interactuar, orientan su mirada
hacia el prisma de su propio recuerdo, en el lado opuesto del corredor. Las
señales ámbar indican el recorrido y la cartela de destino. Acércate al prisma y
pulsa **E** para abrir el lector habitual; **Volver al recorrido** lo cierra.
La cabina de regreso a la cantina sigue disponible en cualquier estado.

![Guardiana, centinelas y guía hacia la misión actual en el ejecutable Linux](images/memory-guardians.png)

Captura real de Linux a 1600×900, producida por
[Actions 34503084258](https://github.com/VaroTv7/espaciokooplagunakRemake/actions/runs/34503084258)
en el commit `b4e9bdf835fe1260d1735a348bc9d5890a492dcf`.

Cada relato se abre por el identificador de su misión completada en la campaña.
Los títulos se muestran desde el principio; el contenido futuro permanece
cerrado. Las memorias de rescate indican el total acumulado de personas
rescatadas en esa campaña. Las misiones personalizadas no se hacen pasar por
los seis hitos de la ruta Itsaso.

| Ambiente automático | Condición |
| --- | --- |
| Vigilia azul | Ninguna misión de la ruta completada |
| Travesía turquesa | Entre una y cinco misiones completadas |
| Alba ámbar | Las seis misiones completadas |

Los ambientes manuales, la guía y la lista de lecturas son preferencias de
presentación de esta ejecución. No conceden recompensas ni escriben en el
guardado. En cooperativo, los desbloqueos proceden exclusivamente de la
proyección pública `Session.view.campaign` que envía el anfitrión. No se añaden
RPC, campos al protocolo ni una segunda autoridad de progreso. La opción de
movimiento reducido inmoviliza la mirada sin impedir lectura o guía.

## Integración y modelos editables

`MemoryGuardians` entra como hijo de `main.tscn` y conecta cada `WorldDeck` en su
señal `ready`, antes del lector que registra la aplicación. Reutiliza las
entradas de `LeisurePlaces` y la señal `interaction_requested`; el lector recibe
el resultado de la interacción en el mismo diccionario. Una prueba comprueba
el orden de señales y que sólo se abre una ventana. Al salir de Cubierta, la
galería comparte la liberación de la sala; al regresar se conecta una nueva.

Fuente: `art/blender/memory_guardians.blend` (Blender 4.5.3 LTS). Incluye tres
raíces: `memory_keeper`, `memory_sentinel` y `memory_prism`. Las dos primeras
conservan pivotes `Gaze` para orientar la lente. Son autómatas de brújula y
cerámica diseñados para este remake, con mallas y materiales propios MIT.

Para exportar una edición sin regenerar la fuente:

```sh
blender --background art/blender/memory_guardians.blend --python art/blender/export_memory_guardians.py
```

Para reconstruir el diseño inicial:

```sh
blender --background --python art/blender/build_memory_guardians.py
```

El manifiesto propio `game/assets/models/memory_guardians.manifest.json` contiene
SHA-256 de la fuente y del GLB. El verificador comprueba ambas huellas, las tres
raíces y los dos pivotes. Los volúmenes de colisión son cajas simples
dimensionadas para estos modelos, independientes de la mirada animada. La
ruta central completa y cada punto de lectura se comprueban con física real.

Referencia funcional consultada: catálogo y escena del corredor en
[`EspacioKoop/espaciokooplagunak@fecd074`](https://github.com/EspacioKoop/espaciokooplagunak/blob/fecd0740545f485d2402c6dfe4b47d5a859cb96c/foundry-module/scripts/pasillo-recuerdos-escena.mjs).
La referencia presenta guardianes y piezas de museo en un corredor recorrible.
Aquí se reimplementan el papel de guía y dos tamaños de guardián con un diseño
visual diferente; se añade la lectura vinculada a la campaña standalone. No se
copian código, geometría, iconografía ni textos de la referencia.

## Validación reproducible

```sh
python3 tests/run_memory_guardians.py
.toolchain/godot --headless --path game --script ../tests/test_leisure.gd -- --test
.toolchain/godot --headless --path game --script ../tests/test_ui.gd -- --test
.toolchain/godot --headless --path game --script ../tests/test_core.gd -- --test
```

La suite propia contiene 72 comprobaciones: entradas inválidas, lecturas cerradas, progreso por ID,
proyección sin mutación, guía, variantes, colisiones, lector, movimiento
reducido, retorno y recreación de la cubierta. Las regresiones cubren 102
comprobaciones de ocio, 62 de interfaz y 136 del núcleo.

La plantilla release de Godot ignora el inicio por `--script` externo. Por eso
la verificación del ejecutable usa el driver `memory_capture.gd`, activado
exclusivamente con `--test` y `--memory-smoke` o `--memory-capture`. Arranca una
campaña temporal con guardados suprimidos y comprueba interacción y retorno.
No modifica un guardado existente. Para probar un Linux ya exportado:

```sh
python3 tests/run_memory_guardians.py --binary "$PWD/build/memory/EspaciokoopLagunak.x86_64"
xvfb-run -a python3 tests/run_memory_guardians.py --binary "$PWD/build/memory/EspaciokoopLagunak.x86_64" --capture "$PWD/build/memory/memory-guardians.png"
```

El workflow `memory-guardians.yml` importa, prueba, exporta Linux y captura ese
ejecutable con un renderizador real mediante Xvfb. El PNG debe medir 1600×900;
un servidor headless no se acepta como captura. El artefacto de Actions es
`memory-guardians-evidence`.

Este subcarril avanza #6. No declara terminado el catálogo artístico, mobiliario
o audio restante del issue.
