# Probar Espaciokoop Lagunak 0.9.2

[Notas de la versión](RELEASE_NOTES.md) · [Descargas y sumas de comprobación](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/tag/v0.9.2)

## Antes de empezar

Descomprimir el ZIP en una carpeta nueva, sin sustituir la de 0.9.1. Conservar
localmente una copia de la partida antes de cargarla con una versión nueva.
Foundry, Docker, Godot y Blender no son requisitos del juego descargable.
No subir la partida, credenciales o registros personales para una prueba inicial.

## Recorrido sugerido

| Prueba | Acciones | Resultado esperado |
| --- | --- | --- |
| Arranque | Abrir el ejecutable de 0.9.2; comenzar una expedición | Menús y partida accesibles sin servicios externos |
| Terminales | Recorrer cubierta; abrir una terminal con E, operar, regresar y reabrir; repetir en otra sala | Sin cierre del juego, pantalla retirada ni controles bloqueados |
| Escotillas | Atravesar los seis enlaces entre compartimentos, ida y vuelta, abriendo sus puertas | Movimiento continuo, sin bloqueos, caídas o teletransporte correctivo |
| Ocio | Visitar cantina, museo, playa, terraza, estudio y recuerdos; usar libro y asientos | Interacciones y regreso accesibles |
| Aprendizaje | Puente → Asistencia entre puestos → Escuela de tripulación | Lección guiada utilizable sin modificar la campaña real |
| Táctica | F6 → Expedición táctica; iniciar encuentro, seleccionar unidad/casilla, cambiar cámaras y alternar 2D/3D | Modelos visibles; se conservan turno, selección y coste de movimiento |
| Avisos | Ajustes → Subtítulos de avisos sonoros…; silenciar sonido y emitir una orden; cerrar/reabrir el juego | Texto correspondiente al aviso y preferencia local conservada |
| Guardado | Guardar, salir y reabrir la campaña | Progreso válido conservado; comunicar cualquier rechazo sin enviar la partida completa |
| Cooperativo | Host y cliente con la misma versión; cambiar alerta, incorporar un cliente tarde y reconectar | Estado autorizado y alerta vigentes; sin duplicar puestos o revelar datos privados |

La sincronización de avisos sonoros no transforma una confirmación local de envío
en aceptación nueva del anfitrión. No interpretar el subtítulo como una regla de
red distinta del sonido al que acompaña.

## Biblioteca y laboratorios

La [biblioteca visual](ASSET_LIBRARY.md) conserva fuentes Blender, fichas y fotos
por revisión. Los planetas Bizi y los entornos Portu son recursos con laboratorios
locales, no nuevos viajes de campaña. La navegación 6DOF y el descenso/atraque
seamless siguen siendo trabajos separados.

## Evidencia automatizada de la descarga

La CI conserva el artefacto `exported-release-acceptance`: `report.json`, logs y
dos capturas de las terminales. El informe identifica versión, SHA-256 del ZIP y
del ejecutable y hashes de los tests. Se ejecuta el binario extraído del ZIP con
un directorio de trabajo vacío y perfiles locales desechables.

```sh
python3 -m unittest discover -s tests/release_092 -p test_runner.py -v
python3 tests/release_092/run.py \
  --package dist/EspaciokoopLagunak-0.9.2-linux-x86_64.zip
```

Hace falta una pantalla Linux o Xvfb. Se comprueban metadatos/recursos embebidos,
terminales y la suite existente de ocio/pasillos. Sólo se reubican las referencias
entre fixtures de test; las rutas de código/recursos `res://` continúan apuntando
al PCK embebido. No se copia el proyecto para suplir recursos ausentes.

Las terminales usan posicionamiento sintético controlado; no se presenta como un
paseo humano continuo. Los tests existentes recorren físicamente los seis enlaces
en ambos sentidos e inspeccionan los trece destinos. El test usa el ritmo
acelerado de física ya existente, no certifica rendimiento en hardware concreto.
La confirmación del reporte original #29 en el equipo del jugador sigue pendiente.

## Comunicar un fallo

Indicar **0.9.2**, sistema operativo, modo solo/host/cliente, pantalla o sala,
pasos, frecuencia, resultado esperado y observado. Comprobar primero que se está
abriendo la carpeta nueva y no el ejecutable de 0.9.1.

Una captura puede ayudar, revisada antes para eliminar nombres, conversaciones,
rutas o datos privados. El crash de terminales se sigue en #29; para otro problema,
abrir un issue específico. No hace falta enviar contraseñas ni partidas completas.
