# Briefing de misión por puesto

Subcarril de [#32, apartado 3.1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32): preparar un documento de la misión actual para cada uno de los ocho puestos. Es una herramienta de lectura y exportación local, no un cambio de autoridad, un guardado ni un registro de sesión.

## Uso desde el juego

Con una misión iniciada, abre **F4 → Briefing de misión**. Elige un puesto y un formato. El selector prepara una guía genérica para ese puesto: **no cambia tu puesto real ni accede a su información privada**. La vista previa siempre muestra la versión Markdown legible, aunque el archivo seleccionado sea HTML o JSON.

Pulsa **Actualizar** para recoger el progreso más reciente. **Guardar briefing…** abre un selector de archivo local. El archivo recibe la instantánea que se estaba revisando al pulsar Guardar, aunque la misión cambie mientras el selector está abierto. Cancelar no escribe nada. Un archivo existente no se sobrescribe: elige otro nombre incluso si el selector del sistema ofrece confirmar su sustitución.

Para imprimir, selecciona **HTML imprimible (.html)**, guarda el archivo y ábrelo tú en un navegador local. Usa su orden de impresión. El HTML contiene estilos de impresión A4 y todos sus recursos están embebidos. La aplicación no abre automáticamente el navegador ni envía datos a un servicio de impresión.

La ventana es independiente de F4: cerrar o reconstruir la consola de tripulación no destruye el documento que estás revisando. Abrirla de nuevo enfoca la misma ventana, sin duplicarla.

## Contenido y formato

Incluye título, sector, briefing público de la misión, texto y progreso de los objetivos compartidos, descripción del puesto y tres comprobaciones de coordinación. La guía se basa en las operaciones nativas existentes; no es una misión tutorial, no ejecuta órdenes y no aplica cambios al juego.

Se puede exportar como Markdown, HTML o JSON. El JSON declara `format: espaciokoop-mission-briefing` y `version: 1`. Sus únicos campos raíz son `format`, `version`, `mission`, `station`, `objectives` y `notice`. Cada objetivo contiene `number`, `text` y `status` (`completed`, `current` o `pending`). El formato no tiene importador: no debe confundirse con un documento de campaña o un guardado.

Los encabezados admiten hasta 4.000 caracteres por campo, los objetivos hasta 500 caracteres y 24 entradas. Se validan tipos, estados y progreso entero finito. El límite del archivo es 256 KiB. Una entrada inválida no produce un documento parcial ni habilita Guardar.

## Frontera de privacidad

`MissionBriefingWindow` lee únicamente `Session.view`, la vista que ya recibe ese participante. `MissionBriefing` construye un documento nuevo mediante lista blanca; no copia el estado global ni documentos arbitrarios. No utiliza `sim.state` ni realiza llamadas de red.

Se excluyen contactos (identificados o no), identificadores de objetivo, futuros escenarios, notas extra del GM, bitácora, fichas, identidades, posiciones, cartas, dados, tickets, claves y códigos de operaciones. El selector de puesto solo cambia el contenido orientativo estático de la guía.

**La lista blanca no es un detector de secretos dentro del texto.** Si quien crea una misión escribe información confidencial en su briefing público o en los objetivos compartidos, ese texto se incluirá igual que aparece en el juego. Revisa el documento antes de distribuirlo. Un archivo ya exportado queda bajo el control de quien lo guarda; el juego no puede revocarlo.

El texto de autoría se escapa antes de renderizar Markdown y HTML para que imágenes, enlaces de imagen o etiquetas HTML incrustadas no se conviertan en recursos activos. El HTML incorpora una política CSP que deniega recursos externos, scripts y formularios. El JSON conserva el texto como datos. La función de escritura exige ubicación de sistema de archivos y extensión compatible, rechaza URI de servicios y `res://`, y no sobrescribe archivos existentes. No crea directorios arbitrarios ni exporta automáticamente.

## Verificación reproducible

```sh
python3 tools/bootstrap.py
python3 tests/run_mission_briefing.py
# En Linux con Xvfb y Mesa instalados:
xvfb-run -a python3 tests/run_mission_briefing.py --graphical
# Solo el contrato del ejecutor Python, sin afirmar que se ejecutó Godot:
python3 tests/run_mission_briefing.py --self-test
```

El ejecutor crea directorios XDG temporales y pasa `--test`. No usa partidas de una instalación real. Importa el proyecto, ejecuta las pruebas sin pantalla y, con `--graphical`, repite el flujo con ventanas reales bajo Xvfb. Falla ante salida no cero, timeout, errores del motor o ausencia de un único marcador positivo. Se conserva únicamente la excepción de importación ya acotada en el proyecto por mensaje exacto y SHA del archivo de cosmografía; nunca se admite ese aviso durante los tests de juego.

La suite recorre las misiones reales del catálogo en los ocho puestos y los tres formatos; comprueba la no mutación de estado, JSON round-trip, canarios en campos privados anidados, texto malicioso, límites y tipos inválidos, archivos locales, negativa a sobrescribir, cancelar y guardar exactamente la instantánea revisada. La integración abre el briefing desde el botón de `CrewConsole` y verifica reutilización, cierre y cambio de puesto sin cambiar autoridad. Los eventos de los controles se activan desde la prueba: esto no se presenta como una sesión ENet, una interacción humana con una impresora o un smoke del ejecutable exportado.

La CI aditiva es `.github/workflows/mission-briefing.yml`; conserva `mission-briefing-test-log` como evidencia sintética. Los resultados concretos y el SHA probado se anotan en el PR. La CI canónica `release.yml` sigue siendo necesaria antes de integrar/publicar; este workflow no la sustituye.

## Alcance separado

No implementa replay, dossier retrospectivo, crónica/bitácora exportada, briefing de misiones futuras ni importación/exportación de guardados. La exportación de crónica tiene un subcarril independiente registrado en #7. Este cambio no cierra globalmente #32 ni declara paridad 1.0. No modifica Atlas, consola GM, interiores, protocolo ni guardados.
