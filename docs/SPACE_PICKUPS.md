# Suministros y artefactos

En **Taller de misiones**, selecciona **Suministro** o **Artefacto** y pulsa en el
mapa. Añade el objetivo **Recoger objeto**; **Tocar objeto** también permite un
artefacto que permanece en el espacio. **Probar misión** usa la simulación real:
pilota hasta atravesar el objeto. El contacto no causa daño.

El suministro creado desde el mapa aporta 25 de energía y 2 misiles guiados.
La pestaña JSON existente permite configurar `supply_energy` entre 0 y 100,
`supply_ammo` con cantidades enteras entre 0 y 1000 por tipo
(`homing`, `nuke`, `mine`, `emp`, `hvli`) y `radius` entre 5 y 2000 m.
La reposición respeta la energía máxima y la capacidad de munición del diseño,
incluidos los tubos cargados. El excedente se pierde al consumir el suministro.

Un artefacto creado desde el mapa tiene `allow_pickup: true`. Cambia este campo
a `false` para conservarlo tras el contacto y utiliza **Tocar objeto** como
objetivo. En JSON, omitir `allow_pickup` equivale a `false`. Los artefactos no
aportan suministros: su interacción registra hechos que completan los objetivos
y recompensas existentes. No ejecutan código ni callbacks importados.

Sólo el anfitrión resuelve la colisión barrida. Un obstáculo corta la trayectoria;
un portal comprueba su llegada sin recoger objetos en la línea de teletransporte.
Los hechos `touch:<id>` y `pickup:<id>` y la desaparición persisten en el guardado
normal. Reanudar no repite la entrega. Clientes anteriores necesitan actualizar
el juego para representar estos dos nuevos tipos de contacto.

Prueba reproducible, incluidos host y cliente ENet reales:

```sh
python3 tests/run_space_pickups.py --godot /ruta/a/godot
```

Referencia funcional estudiada: `scripts/api/entity/artifact.lua` y
`supplydrop.lua` del original fijado `fecd074`. Implementación y geometría propias.
