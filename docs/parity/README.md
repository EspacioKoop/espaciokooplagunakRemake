# Registro de evidencias de paridad

Herramienta de trabajo para [#32](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32), complementaria a [FEATURE_PARITY](../FEATURE_PARITY.md) y al [plan #1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1). No los reemplaza, no declara la 1.0 y no cambia las reservas de [#7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7).

## Usar el inventario

Desde la raíz del repositorio, con Python 3.11 o posterior y sin instalar dependencias:

```sh
python3 tools/check_parity_evidence.py
python3 tools/check_parity_evidence.py --markdown informe-paridad.md
python3 -m unittest discover -s tests -p test_parity_evidence.py -v
```

El informe contiene una fila por bloque explícito del registro y por declaración ya examinada del catálogo de naves: original y enlace inmutable, equivalente, estado, decisión, issue responsable, criterio de aceptación, límites y evidencias. El workflow **Validate parity evidence register** lo añade al resumen de su ejecución. El archivo local generado no se publica automáticamente.

**Un check verde aquí significa que el registro es coherente, no que todas las funciones estén terminadas.** El registro inicial deja `coverage.complete = false`, no contiene ejecuciones inventadas y distingue pruebas presentes de pruebas ejecutadas. `partial` describe la evidencia/paridad incompleta del alcance de la fila: no revoca pruebas históricas ni afirma que todo el sistema esté averiado.

La lectura inicial del remake está fijada a `8b1dcf27683a00972b03d5203606eab12f31fe2d`; la referencia original, a `fecd0740545f485d2402c6dfe4b47d5a859cb96c`. Son referencias de auditoría, no afirmaciones de CI verde. El último checkpoint validado lo mantiene #1.

## Una sola autoridad por dato

[`issue32_inventory.json`](issue32_inventory.json) conserva decisiones y bloques de trabajo. El adaptador lee directamente [`game/data/ship_templates.json`](../../game/data/ship_templates.json): no copia casco, armas ni otra configuración de nave a un segundo catálogo.

Las entradas `templates` generan filas `ship:<id>` inicialmente parciales; las entradas `excluded` generan `ship-excluded:<archivo>:<línea>` pendientes. Una exclusión por limitación del modelo **no es una renuncia de producto**. Aunque `unsupported` esté vacío, siguen aplicándose los límites comunes de [SHIP_TEMPLATES](../SHIP_TEMPLATES.md). Las configuraciones dinámicas y los demás catálogos aún no enumerados mantienen abierto el alcance global.

Los campos `source` que empiezan por `issue:` remiten a un issue del remake: indican que el requisito está planteado allí, no que su presencia en el original haya quedado demostrada. El resto son rutas de la referencia original. Antes del cierre hay que contrastar esos requisitos con consumidores reales; no basta una propuesta histórica.

`owner_issue` señala el carril responsable de resolver el punto, **no asigna una persona ni reserva archivos**. Los agentes siguen necesitando CLAIM en #7. `scope: proposal` separa mejoras nuevas de paridad; su prioridad no amplía automáticamente #1.

## Cómo registrar un cierre

Cada fila exige ID estable, gate G0–G3, prioridad, alcance, fuente, equivalente, estado, decisión, issue responsable, aceptación, nota y evidencias. Los estados son `pending`, `partial`, `verified` y `waived`. Las decisiones son `reimplement`, `replace`, `review` y `waive`.

Para `verified`, se requieren una implementación local, una prueba bajo `tests/` y al menos una ejecución enlazada con resultado `passed`, SHA completo y descripción de checks. Todas las ejecuciones de una fila deben pertenecer al mismo `remake_revision`. Un documento no puede sustituir a la implementación o a la prueba. Una ejecución pendiente/fallida o un SHA distinto impiden ese estado.

Las filas generadas pueden resolverse mediante `overrides` por ID. Sólo se permiten estado, decisión, aceptación, nota, evidencias y aprobación: no cambiar la identidad o convertir a escondidas un requisito en propuesta. Si desaparece su declaración original, el override huérfano falla y obliga a revisar el cambio.

Una renuncia necesita `status: waived`, `decision: waive`, motivos y un enlace `approval` a la decisión en issue/PR. Marcar el inventario completo requiere además `coverage.review`. **El validador no autentica la aprobación, la independencia del revisor ni el resultado remoto del run**: valida el registro y los enlaces; corresponde a la revisión comprobar su contenido y autoridad. No autoriza renuncias por sí mismo.

Para evaluar las condiciones registradas de cierre:

```sh
python3 tools/check_parity_evidence.py --require-complete --candidate SHA_COMPLETO_DE_40_CARACTERES
```

Sustituir el último argumento por el SHA real. Códigos de salida: `0`, registro válido y, en modo estricto, condiciones registradas satisfechas; `1`, estructura/archivo/argumento inválido; `2`, cierre aún bloqueado. En modo estricto, faltas de cobertura, filas de paridad abiertas y candidato distinto de la revisión auditada bloquean. Las propuestas no se cuentan como requisitos de paridad.

Ni siquiera un `0` estricto sustituye la revisión funcional, la CI canónica, la validación física o el playtest humano. Tampoco comprueba automáticamente los hashes de todos los archivos del checkout contra la revisión anotada. Para publicar hay que ejecutar/revisar esas pruebas sobre el candidato exacto y comprobar los enlaces registrados. Este workflow aditivo **no está conectado al publicador como autorización de release**.

## Seguridad y mantenimiento

El comprobador funciona sin red, no ejecuta comandos del manifiesto ni interpreta Lua. Lee únicamente el registro y los archivos locales referenciados, con límites de tamaño, rechazo de JSON ambiguo/no finito, rutas relativas y contención de enlaces simbólicos. Escapa textos del informe y restringe los enlaces de ejecución/aprobación al repositorio correcto. Los fixtures de pruebas son sintéticos y temporales.

No introducir partidas, fichas personales, tokens, credenciales ni logs privados en el registro. La CI sólo procesa el contenido versionado y publica el informe funcional en su resumen. Los logs reales enlazados deben revisarse y redactarse antes de publicarlos.

[Balance inicial y criterios pendientes de #32](ISSUE32_EVIDENCE.md).
