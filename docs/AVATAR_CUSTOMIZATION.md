# Avatar de tripulación

![Editor y retrato renderizados desde Godot](images/avatar-editor.png)

Captura real del editor en CI, ejecución `34502779934` (commit `c9ab0648`).

Desde Inicio o Puente, pulsa **Mi avatar** sobre la vista 3D; **Alt+A** abre el
mismo editor desde otras pantallas. Elige entre cuatro trajes, tres visores y
tres opciones de equipo cosmético. El retrato y la vista giratoria usan el mismo
`crew.glb` que se ve en cubierta. Arrastra sobre la vista o usa los dos botones
de giro para inspeccionar la espalda.

**Guardar avatar** aplica y conserva la selección. **Restablecer Itsaso** prepara
la apariencia original para guardar; **Cancelar** descarta los cambios de la
vista previa. El equipo es visual: no concede inventario, habilidades ni permisos.

## Persistencia y renderizado

`user://avatar.json` contiene exclusivamente `format`, `version`, `suit`, `visor`
y `gear`. El formato `lagunak-avatar` v1 acepta únicamente opciones del catálogo
cerrado y un máximo de 512 bytes; no permite rutas a modelos ni imágenes. La
escritura temporal se verifica antes del reemplazo. Un archivo ausente o dañado
usa Itsaso; un fallo de escritura se informa y conserva el avatar activo.

Los cambios de color duplican materiales por instancia. El recurso `crew.glb`,
sus superficies y el transform de movimiento permanecen intactos. El escáner y
la mochila son geometría procedural propia. El traje Itsaso sin equipo y visor
Aguamarina conserva los materiales originales. La apariencia respeta las poses
que aplique el componente independiente de asientos.

## Cooperación

`Avatars` es un componente separado de `Session`. Envía perfiles cosméticos v1
en RPC fiable; sólo el anfitrión acepta cambios y sólo para el remitente que ya
figure en el roster autenticado de `Session`. El cliente nunca proporciona el
ID del avatar que quiere cambiar. Solicitudes inválidas, sobredimensionadas o
más frecuentes que una por 250 ms se descartan.

El anfitrión replica exclusivamente perfiles cosméticos a conexiones que hayan
enviado un perfil válido; una conexión sin autenticar no recibe esta proyección.
La configuración local se vuelve a enviar al reconectar. Los perfiles de peers
desconectados se eliminan, sin modificar la campaña ni las poses de `Session`.
La integración de cubierta llama `Avatars.bind_avatar(avatar, peer_id)` al crear
un tripulante remoto y actualiza su apariencia aunque el objeto ya exista.
El host anuncia `avatar_protocol=1` en su entrada pública del roster. El cliente
espera ese marcador antes de enviar RPC: con anfitriones anteriores sin
`Avatars` conserva el avatar local y los remotos originales sin enviar mensajes
a nodos inexistentes. Clientes anteriores ignoran el campo adicional. El
formato de posición/yaw permanece intacto.

## Referencia funcional y alcance

Se estudiaron `avatar/avatar-assignment.mjs`, `avatar/retrato-tripulante.mjs` y
`avatar/avatar-porte.mjs` de
`EspacioKoop/espaciokooplagunak@fecd0740545f485d2402c6dfe4b47d5a859cb96c`:
elección propia separada de la partida, retrato que no acredita permisos y
equipamiento separado de la pose. Esta implementación y sus accesorios son
nuevos; no se han copiado código ni assets de la referencia.

Este subcarril cubre editor/asignación propia, retrato, variantes visibles,
persistencia y replicación autenticada. No cierra #3 completo: asientos y NPC
pertenecen a otros subcarriles, y retargeting esquelético, mirada, gestos y
progresión visual siguen fuera de esta entrega. El `crew.glb` actual tiene una
malla estática, sin esqueleto.

## Pruebas

```sh
.toolchain/godot --headless --editor --path game --quit
python3 tests/run_avatar_customization.py
```

El runner aísla los datos de usuario y ejecuta formato/persistencia/materiales/UI
y cuatro procesos ENet reales: anfitrión, dos clientes autenticados y una
conexión que nunca se autentica. Una segunda sesión prueba un host sin nodo
`Avatars` con un cliente nuevo. Comprueba entradas dañadas, suplantación,
límites de frecuencia, actualización de geometría, desconexión y reconexión.
`tests/test_ui.gd` y `tests/test_leisure.gd` cubren las pantallas y recorridos
existentes. La CI completa canónica sigue siendo necesaria antes de integrar.
