# Montajes de nave desde el astillero

En **Taller de misiones → Diseñar nave → Montajes** puedes configurar entre uno
y ocho montajes. Selecciona un montaje en la lista para editarlo, añade otro,
duplica uno existente, elimínalo o cambia su orden. Cada identificador debe ser
único. Las cuatro plantillas existentes de `ShipArmaments` sirven como punto de
partida; «Reemplazar por plantilla» sustituye el borrador completo de montajes.

| Parámetro | Efecto al jugar |
| --- | --- |
| Tipo | Haz, torreta, cañón de riel o EMP; conserva los efectos de `ShipArmaments`. |
| Orientación | Centro del arco relativo a la proa: 0° delante, −90° babor, +90° estribor, ±180° detrás. |
| Arco | Apertura de disparo, mayor que 0° y hasta 360°. |
| Alcance | Distancia máxima al blanco, entre 50 y 3000 m. |
| Daño | Daño base por disparo, entre 0 y 100; la eficiencia de armas modifica el resultado. |
| Ciclo | Tiempo base entre disparos, entre 0,1 y 30 s. |
| Energía | Consumo por disparo, entre 0 y 40. |

La vista de arcos representa los alcances relativos y resalta el montaje
seleccionado. **Aplicar diseño a la misión** confirma estructura y montajes
juntos; **Cancelar** los descarta. **Deshacer** en el taller recupera ambos con
una sola acción. Editar el borrador no modifica la nave de una partida activa.

Guarda la misión o pulsa **Probar misión** para usar ese diseño. Desde el puesto
de Armas, **F7** abre la consola de los montajes, que conserva sus reglas de
alcance, arco, energía, recarga y autorización. El anfitrión inicia la misión y
resuelve los disparos; un cliente no puede instalar el borrador sobre su partida.

## Archivos y compatibilidad

**Exportar nave** escribe un documento JSON `lagunak-ship` versión **2** con dos
secciones: `design` (estructura) y `loadout` (plantilla y lista de montajes).
**Importar nave** valida ambas antes de cambiar el borrador. Se admiten archivos
de hasta 64 KiB y se conservan parámetros fraccionarios.

Los diseños versión **1** siguen abriéndose: como sólo contenían estructura,
reciben los montajes de exploración Itsaso que usaba el runtime. Las misiones
antiguas sin `ship_loadout` mantienen ese mismo comportamiento. Al guardar una
misión editada, `ship_design` y `ship_loadout` permanecen en el formato existente
de misión; no se cambia la versión del guardado ni del protocolo de red.

El documento de diseño excluye blancos automáticos y recargas en curso. Una
partida guardada sigue conservando su estado operativo mediante `LocalStorage`;
el editor no reinicia ese estado ni introduce una segunda implementación de las
reglas de armamento. `Catalog` rechaza un `ship_loadout` inválido al importar,
probar o validar una partida.

## Comprobación reproducible

```sh
python3 tools/bootstrap.py
.toolchain/godot --headless --editor --path game --quit
.toolchain/godot --headless --path game --script ../tests/test_loadout_editor.gd -- --test
```

La prueba cubre formato v1/v2, importación y exportación, límites y entradas
inválidas, controles nativos, cancelación, deshacer, guardado de misión y de
partida, permisos y disparo real de un EMP personalizado. El workflow
`loadout-editor.yml` añade estas comprobaciones sin modificar el workflow de
distribución del proyecto.

Bloque de **#2**: edición detallada de montajes. El catálogo completo de plantillas
y el resto de editores conservan su seguimiento independiente. Como referencia
funcional se estudiaron los parámetros `setBeamWeapon`, `setBeamWeaponTurret`
y `setBeamWeaponEnergyPerFire` de `scripts/api/shipTemplate.lua` en el original
`fecd0740545f485d2402c6dfe4b47d5a859cb96c`; esta interfaz usa exclusivamente los
tipos y reglas propios que ya implementa el remake.
