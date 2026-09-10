# Taller de NPC standalone

Refs #32 §2.1. Esta entrega cubre el **motor de fichas y su herramienta de autoría**,
no el catálogo completo ni toda la incidencia #32.

## Uso desde el juego

Abre **Taller de misiones → Taller de NPC…**, en la columna izquierda.
Introduce una semilla de `0` a `2147483647`, selecciona el valor de desafío (VD)
y pulsa **Generar ficha**. El taller muestra características, modificadores,
competencia, CA, PG, dados de golpe, velocidad, línea, naturaleza, etapa,
afinidades y acciones separadas por economía de turno. La ficha se puede usar
como referencia para dirigir una escena y exportar a **JSON** o **texto plano**.

**Abrir ficha JSON…** recupera una ficha exportada por este taller. Importar,
generar y exportar no cambian la misión, la campaña ni los personajes de la
tripulación. Cambiar los parámetros deshabilita la exportación hasta generar de
nuevo: nunca se exporta una ficha antigua bajo una receta nueva. El selector de
archivo pide confirmación al sobrescribir; si el sistema operativo falla durante
la escritura, el taller lo comunica y el archivo podría quedar incompleto.

No existe envío automático, consulta remota, acceso a Foundry ni lectura del
guardado. Los archivos se leen o escriben solo por una acción explícita del
usuario. No se guarda una copia automática al cerrar el taller.

## Equivalencia y límites

Referencia funcional estudiada: `docs/NPC_GENERADOR.md` del original en
`fecd0740545f485d2402c6dfe4b47d5a859cb96c`. No se ha copiado su implementación,
tablas, nombres o recursos. Ese documento separa expresamente el motor de la
aparición en salas, conversaciones y memoria de campaña. Esta entrega conserva
esa frontera y añade una interfaz nativa para usar las fichas.

| Capacidad del motor de referencia | Implementación nueva |
| --- | --- |
| Semilla + VD reproducibles | SHA-256 por canales estables, algoritmo `sha256-v1` |
| Características, modificadores, CA, PG y competencia | Fórmulas explícitas y parámetros acotados |
| Seis grados de afinidad | `debil`, `neutral`, `resiste`, `nulo`, `absorbe`, `repele` |
| Siete elementos y cuatro naturalezas | Tabla propia; cada elemento declara tipo de daño SRD y naturaleza fuerte/débil |
| Tres etapas por línea | Cuatro líneas propias; etapa por VD, no por azar |
| Acción, adicional, reacción, movimiento | Ficha con reglas y parámetros legibles en cada categoría |
| Procedencia en la ficha | Atribución y licencia en `procedencia_reglas`, JSON y texto |

Las estadísticas son una propuesta de autoría. **El VD no certifica un encuentro
equilibrado** ni una ficha de monstruo oficial. Este taller no es un importador de
actores dnd5e de Foundry, ni convierte las fichas en perfiles del combate táctico.
Tampoco coloca NPC en la nave, ejecuta sus acciones, modifica contactos espaciales
ni añade memoria de bestiario. Esas integraciones necesitan su propio contrato
con el anfitrión y no se declaran hechas por existir esta ficha.

## Contrato reproducible v1

Un documento contiene exactamente `format`, `version`, `algorithm`, `recipe` y
`sheet`. `format` vale `lagunak-npc`; `version`, `1`; `algorithm`, `sha256-v1`.
La receta contiene exactamente `seed` y `challenge`. Se admite VD `0`, `0.125`,
`0.25`, `0.5` o un entero entre `1` y `30`; no se aceptan booleanos, cadenas,
fracciones distintas, valores no finitos o números fuera de rango.

El canal aleatorio calcula SHA-256 de `lagunak-npc-v1|<semilla>|<canal>`, interpreta
los primeros ocho dígitos hexadecimales y toma el módulo del tamaño de la tabla.
No usa el generador aleatorio global ni su estado. Las tablas/algoritmo v1 deben
mantenerse inmutables una vez publicadas: un cambio que altere fichas requiere
otro identificador y una decisión explícita de compatibilidad.

La importación admite un máximo de 64 KiB y valida UTF-8 antes de decodificar.
Recalcula la ficha completa y compara todos sus campos con la receta; rechaza
campos añadidos, estadísticas editadas, textos sustituidos y atribución alterada.
El resultado importado es siempre la ficha recalculada, nunca un objeto de autoría
no validado. El orden de claves JSON no importa y los números enteros decodificados
como flotantes son equivalentes; los booleanos no lo son. Los errores conservan
el borrador anterior. La vista es texto plano, no HTML ni BBCode ejecutable.

## Reglas de cálculo propias y de referencia

`modifier` implementa `floor((score - 10) / 2)` para características de 1 a 30.
La competencia es `2 + max(0, floor((VD - 1) / 4))`. Los PG usan la media de los
dados de golpe más Constitución por dado, redondeados hacia abajo con mínimo 1.
La asignación concreta de puntuaciones, dados y CA es propia. Las etapas son
1 por debajo de VD 5, 2 desde VD 5 y 3 desde VD 11. La misma semilla conserva su
nombre, línea y afinidades al cambiar el VD; sus PG y etapa no disminuyen.

`effectiveness` devuelve ×2 contra la naturaleza fuerte, ×0,5 contra la débil
y ×1 en el resto. `resolve_damage` aplica después afinidad débil ×2, resistente
×0,5 o neutral ×1 y redondea **una vez al final**. Nulo cancela el resultado;
absorber lo convierte en curación y repeler en daño devuelto. No aplica ese daño
a ningún actor ni inicia un bucle de reflexiones. La ficha enumera la matriz para
poder resolverlo manualmente. Un elemento/naturaleza/afinidad desconocido falla,
no se interpreta silenciosamente como neutral. Toda ficha tiene una debilidad.

Las fórmulas 5e toman como referencia **System Reference Document 5.1**, de
**Wizards of the Coast LLC**, bajo **CC BY 4.0**. Fuente:
<https://www.dndbeyond.com/srd>. Licencia:
<https://creativecommons.org/licenses/by/4.0/>. Código, nombres, tablas, líneas y
textos de acciones de esta implementación son propios; las afinidades, etapas y
asignación de VD son modificaciones, no contenido SRD. No implica patrocinio.
Esta atribución también viaja en cada documento y exportación legible.

## Verificación reproducible

```sh
python3 -m unittest discover -s tests -p test_npc_workbench_runner.py -v
python3 tools/bootstrap.py
python3 tests/run_npc_workbench.py
# Con una pantalla real o virtual disponible:
xvfb-run -a python3 tests/run_npc_workbench.py --graphics
```

El runner importa el proyecto real, ejecuta `test_npc_generator.gd` y abre el
`MissionEditor` real para `test_npc_workbench.gd`. Aísla HOME/XDG/AppData en una
carpeta temporal; no reutiliza guardados del usuario. No descarga herramientas
implícitamente. Exige salida cero, ausencia de `SCRIPT ERROR`/`ERROR` y marcadores
finales con un número positivo de comprobaciones. Tiene timeout por proceso y
límite de salida. La CI aditiva `npc-workbench.yml` usa Godot del bootstrap del
repositorio y una pantalla Xvfb; no modifica ni sustituye los controles de release.

La suite del motor recorre 512 semillas, todos los VD admitidos, umbrales de
crecimiento y competencia, 28 combinaciones elemento/naturaleza, seis afinidades,
ida/vuelta JSON, aislamiento de datos, rechazo de entradas y UTF-8 incorrectos.
La suite de UI comprueba acceso, abrir/cerrar/reabrir, generación, exportación
JSON/texto, importación, errores y conservación de la misión. Las pruebas Python
comprueban **el runner**, no sustituyen la ejecución real de Godot. La evidencia
válida de ejecución del juego es la salida de esas suites/CI, no este documento.

No hay comprobación física de Windows/macOS/Android específica de este taller,
ni calibración de equilibrio por partidas. No se cierra #32 globalmente.
