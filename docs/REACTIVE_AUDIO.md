# Música de a bordo

En **Ajustes → Música de a bordo**, o con **F12**, activa la música, ajusta su
volumen y elige un tema. El modo **Automática** sigue la situación visible de la
nave y la zona de cubierta. El volumen general continúa regulando toda la mezcla;
apagar la música conserva los efectos y avisos existentes.

| Tema | Selección automática |
| --- | --- |
| La guardia | Inicio, navegación y compartimentos de la nave |
| Alerta a bordo | Casco inferior al 30 % o contacto hostil identificado y vivo durante una misión activa |
| Itsasoa | Playa |
| Lo que vuelve | Museo y pasillo de recuerdos |
| Mesa compartida | Cantina, terraza y estudio |

Los cambios normales esperan un segundo de estabilidad y mezclan ambos temas
durante dos segundos. La alerta se solicita inmediatamente. Los ecos sin
identificar no influyen en la música. La presentación consulta `Session.view`
sin leer ni cambiar secretos, reglas de simulación o campaña.

`ScoreComposer` sintetiza cuatro voces estéreo deterministas a 11025 Hz con
envolventes suaves y margen antes de saturación. No contiene grabaciones,
partituras ni muestras ajenas. El contenido musical es propio, generado por
motivos, armonía y pausas; no reproduce las composiciones del proyecto original.
La síntesis se alimenta por bloques acotados sin hilo ni descarga y se detiene al
desactivar la música. No arranca en servidor dedicado, headless, capturas ni
`--test`; las pruebas pueden activar explícitamente el búfer Dummy.

La preferencia versionada se guarda separadamente en `user://reactive_music.json`.
No modifica partidas ni se envía por red. Un archivo corrupto, demasiado grande
o con valores no finitos no bloquea el inicio.

## Validación

```sh
.toolchain/godot --headless --editor --path game --quit
.toolchain/godot --headless --path game --script ../tests/test_reactive_score.gd -- --test
.toolchain/godot --headless --path game --script ../tests/test_ui.gd -- --test
```

La suite nueva también se ejecuta desde `test_ui.gd` en la CI canónica. Comprueba
señal PCM audible, determinismo, límites, transitorios, selección desde la vista
pública, privacidad de ecos, preferencias dañadas, acceso desde Ajustes y
reproducción/parada real con búfer de audio. La escucha humana y el rendimiento
en dispositivos móviles requieren comprobación adicional; esta entrega no cierra
las restantes variantes de arte/audio del issue #6.
