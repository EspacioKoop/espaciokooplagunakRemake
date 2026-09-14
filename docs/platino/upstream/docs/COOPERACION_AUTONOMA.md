# Guía de cooperación autónoma

[Inicio y adaptación](../README.md) · [Instrucciones de este repositorio](../AGENTS.md)

## 1. Un plan y un registro por proyecto

El **plan maestro** contiene objetivo, prioridades ordenadas, dependencias, criterios de aceptación, responsables, estado integrado/pendiente y último SHA completamente validado con enlaces a pruebas. HEAD no significa automáticamente checkpoint verde. Sólo marca terminado lo integrado y verificado; separa límites y defectos conocidos.

El **registro único de reservas** conserva mediante comentarios nuevos CLAIM, acuerdos, bloqueos, pausas, PR_READY y RELEASE. Sus resúmenes ayudan, pero no sustituyen el historial completo. Issue asignado, rama existente o encargo en chat no equivalen a reserva. Los issues de tarea describen alcance, exclusiones y aceptación; los PR contienen cambios y evidencia. La coordinación mantiene el plan sin crear una segunda autoridad contradictoria.

## 2. Selección y reserva antes de editar

1. Lee instrucciones locales, plan, registro completo —incluida paginación—, issue elegido, PR y revisiones vigentes. Comprueba el checkout y los cambios locales.
2. Elige el pendiente de mayor prioridad que tenga dependencias satisfechas y archivos/criterios libres. No adelantes preferencias personales a la prioridad del plan.
3. Publica en el registro, no sólo en el issue de tarea:

```text
CLAIM issue=#N agent=<nombre> branch=agent/N-slug files=<rutas> goal=<objetivo>
```

4. **Relee inmediatamente las reservas después de publicar y antes de editar.** Gana el CLAIM activo anterior por `created_at` de GitHub; si empatan, el ID de comentario menor. Conserva el enlace/ID como identidad de la reserva. Si la lectura falla o es incompleta, no des por adquirido el bloque.
5. Si pierdes una colisión, no empieces: publica RELEASE y elige otro bloque, o acuerda una reducción y publica una reserva nueva sin solape. No borres ni edites el comentario antiguo para aparentar prioridad.

Ejemplo concreto ilustrativo —sustituye los valores por los de tu proyecto—:

```text
CLAIM issue=#42 agent=agente-a branch=agent/42-validacion files=src/validation.py,tests/test_validation.py goal=Rechazar documentos inválidos con regresiones negativas; sin cambiar API ni configuración compartida.
```

Una ampliación requiere otro CLAIM y relectura: los archivos nuevos reciben la prioridad del comentario nuevo, no la antigüedad del alcance original. Referencia la reserva anterior y detalla qué se conserva, añade o libera. Si hay ambigüedad, mantén el bloqueo hasta acuerdo explícito. La reserva limita edición, no concede permisos externos.

## 3. Subdivisión y archivos compartidos

Un issue grande se subdivide únicamente cuando **archivos y criterios de aceptación son independientes**. Publica propuesta, exclusiones, dependencias y responsable de cada subbloque; cada uno necesita CLAIM y PR propios. Si el padre ya está reservado, su propietario debe liberar explícitamente el alcance que cede antes de una nueva reserva. No implementes el mismo sistema dos veces.

Dos nombres de issue distintos no hacen independiente un archivo común. Declara rutas concretas; evita comodines amplios. Inventaría archivos calientes como README, manifiestos, puntos de entrada, esquemas y workflows.

Para un archivo compartido, prioriza que su propietario haga el cambio mínimo y permita transportar el commit exacto. Alternativamente acuerda una secuencia de edición con un único escritor activo, secciones delimitadas, SHA de partida y orden de integración. Un acuerdo sobre un punto de conexión no autoriza cambios generales. Las áreas funcionales y sus pruebas deben seguir siendo independientes; si no lo son, trabaja secuencialmente.

```text
COORDINATION issue=#42 agent=agente-a claim=<URL> files=src/app.py owner=<propietario> agreement=<confirmación del propietario> action=<cambio mínimo o transporte del commit exacto> order=<secuencia> exclusions=<resto del archivo>
WAITING_ON issue=#42 agent=agente-a branch=agent/42-validacion claim=<URL> reason=<solape o dependencia> needs=<decisión concreta> reservation=retained
```

No resuelvas conflictos aceptando un archivo entero de un lado sin comparación. Conserva las aportaciones y regresiones de ambos; si el conflicto excede la reserva, documenta WAITING_ON y coordina. Si todos los bloques están ocupados, revisa PR sin editar sus ramas o propón trabajo independiente con evidencia. No fabriques ocupación ni dupliques reservas para acelerar.

## 4. Ramas, checkouts y persistencia

Usa un clon o worktree separado por agente y rama. Crear un worktree no cambia el directorio de la siguiente orden: comprueba siempre raíz, rama, HEAD y estado antes de actuar.

Ejemplo Bash, ejecutado desde un clon limpio y **después** de ganar la reserva:

```bash
set -euo pipefail
git fetch origin
git status --short
# Comprueba manualmente que no hay cambios desconocidos.
# Cambia main si la rama base de tu proyecto tiene otro nombre.
git worktree add ../tarea-42 -b agent/42-validacion origin/main
cd ../tarea-42
git branch --show-current
git status --short
```

Haz commits pequeños, coherentes y recuperables; publica al completar cada bloque estable y antes de pausar. Primero revisa diff y secretos. Antes de cada push, relee la rama/PR remotos: si otro integró y eliminó la rama, no la recrees accidentalmente; prepara un seguimiento desde la base vigente. No uses force-push, reset destructivo, limpieza ajena ni push directo a main.

Antes del PR incorpora la base actual mediante un merge ordinario cuando haga falta, sin reescribir commits publicados. Resuelve únicamente dentro del alcance acordado y repite las pruebas afectadas. No publiques artefactos privados para facilitar una reanudación.

## 5. Calidad proporcional y funcionalidad real

La prueba debe corresponder al riesgo y al criterio pedido:

- Documentación: enlaces, formato, ejemplos, consistencia, referencias y privacidad.
- Lógica: casos positivos, negativos, límites y regresión del defecto.
- Integración: recorrido desde la entrada real del producto; un helper aislado no demuestra que la función sea utilizable.
- Red, permisos, privacidad, persistencia o formatos: negativos de autorización, datos y compatibilidad; migración explícita cuando proceda.
- Interfaz o juego: interacción y ejecución reales si el criterio lo exige. Un smoke automatizado no acredita playtest humano.

No entregues botones sin mecánica, placeholders o resultados inventados. Enumera las pruebas ejecutadas, resultado, SHA, evidencia y límites. La CI canónica **exigida debe estar verde en el candidato actual**; no basta una prueba local ni el verde de un SHA anterior. No desactives controles para obtener aprobación. Un fallo intermitente sigue siendo un hallazgo aunque una repetición pase.

Si falta herramienta o CI, declara el bloqueo o la ausencia con precisión; nunca los conviertas en éxito. En un repositorio puramente documental sin CI establecida, la validación local puede ser la evidencia acordada: se registra como local, no como CI verde. Esto no exime ningún check o aceptación ya exigidos por el proyecto.

## 6. PR, revisión e integración

Abre PR hacia la base del proyecto y completa una descripción como esta:

```markdown
## Alcance
Refs #42
Objetivo y archivos: ...
Exclusiones y dependencias: ...
Reserva canónica: <URL del CLAIM>

## Resultado y aceptación
- [ ] Criterios completos y funcionalidad/documentación utilizable
- [ ] Pruebas proporcionales y controles exigidos satisfechos
- [ ] Privacidad y compatibilidad revisadas

## Evidencia
SHA: <commit completo>
Pruebas ejecutadas y resultado real: ...
CI: <enlace y estado, o ausencia explícita>
Pendiente/no probado: ...

## Integración y reversión
Autorización: <responsable y referencia>
Orden/dependencias: ...
Reversión: <PR que revierta esta entrega sin reescribir historia>
```

Usa `Closes #N` sólo si el PR satisface el issue completo; `Refs #N` si es parcial. Después publica en el registro:

```text
PR_READY issue=#N branch=<rama> pr=#M tests=<resumen real> agent=<nombre> claim=<URL> sha=<SHA completo> ci=<estado y enlace o ausencia explícita> pending=<límites>
```

**PR_READY no es aprobación, permiso de merge ni liberación.** Si faltan checks o revisiones, queda pendiente de integración. Mantén la reserva para correcciones hasta RELEASE explícito. Un nuevo commit exige actualizar la evidencia afectada y el registro.

Merge únicamente por autoridad expresamente habilitada y dentro de su alcance. Inmediatamente antes, relee cabeza/base del PR, comentarios, revisiones completas, solicitudes de cambios, conflictos y checks. Las revisiones pendientes o los bloqueos no resueltos impiden el merge; protege la operación contra un cambio del SHA revisado. Sin bypass, force-push ni push directo a main. No copies la excepción histórica del coordinador del juego.

Después, lee el PR remoto y la rama base: verifica estado fusionado, commit y presencia de la entrega. Actualiza el plan con el SHA final y evidencia aplicable. Integrado, probado localmente, CI verde, desplegado y playtest humano son estados diferentes.

## 7. Pausa, reanudación y abandono

Toda interrupción deja un checkpoint recuperable: issue, agente, reserva, rama/PR, estado, último SHA publicado, cambios locales no publicados, pruebas, bloqueos y próximos pasos. Si no existe commit, escribe `sha=none` y explica la ausencia; no inventes un SHA.

```text
PAUSE issue=#N agent=<nombre> branch=<rama> claim=<URL> sha=<SHA publicado> state=<estado> next=<pasos concretos> reservation=retained
PR: <URL o ninguno>
Pruebas/evidencia: <resultado y enlaces>
Cambios no publicados: <detalle saneado o ninguno>
Bloqueo y condición de vuelta: <detalle>
```

**PAUSE y WAITING_ON conservan la reserva; no caduca por silencio ni por tiempo.** Antes de reanudar, relee plan, registro, issue, PR y remoto; comprueba que conservas titularidad y que nadie autorizó una transferencia. Comprueba checkout/SHA y cambios locales sin sobrescribirlos.

```text
RESUME issue=#N agent=<nombre> branch=<rama> claim=<URL> sha=<SHA comprobado> state=<estado> next=<siguiente paso> reservation=retained
```

Si liberaste o cediste la reserva, RESUME no la recupera: publica un **nuevo CLAIM**, relee y gana la prioridad de la nueva reserva. No reaproveches su antigüedad.

Al abandonar, guarda el checkpoint y publica explícitamente:

```text
RELEASE issue=#N branch=<rama> reason=<motivo> agent=<nombre> claim=<URL> sha=<último SHA> files=<alcance liberado> next=<pasos para quien retome>
```

RELEASE libera el alcance identificado, no borra commits ni cierra automáticamente issue/PR. Indica qué sucede con un PR abierto. Una transferencia necesita acuerdo registrado y nueva reserva del receptor; nadie toma archivos ajenos por falta de respuesta. Si el propietario no vuelve, la autoridad del proyecto debe resolver y registrar expresamente la reasignación; no se deduce del silencio.

## 8. Cierre y siguiente bloque

Tras integración verificada, actualiza coordinadamente el plan, registra evidencia y RELEASE con motivo de entrega integrada. **Relee de nuevo plan y reservas y escoge el siguiente pendiente prioritario libre.** Repite CLAIM y relectura: no heredas permiso de edición de la tarea anterior.

El ciclo continúa sólo dentro de objetivos, recursos, duración y permisos autorizados. Si la orden se limita a una entrega y ya está terminada, no amplíes el mandato: informa del cierre. Si no queda un bloque independiente autorizado, no edites; deja un estado recuperable o ayuda con revisión permitida. Este protocolo no crea crons ni turnos persistentes por sí solo.

## 9. Privacidad, secretos y límites

Una reserva no permite mover información entre proyectos o dominios privados. Publica únicamente datos autorizados para el destino. Protege tokens, claves, cookies, credenciales, partidas/datos personales, infraestructura privada, logs y capturas; revisa también historial y adjuntos antes del push. Usa referencias y evidencia saneadas, nunca secretos como ejemplo.

No introduzcas credenciales en remotos, comandos públicos o archivos. Si detectas exposición, detén la publicación comprometida, avisa por canal autorizado sin reproducir el secreto y coordina revocación/limpieza con la autoridad competente. No amplíes permisos ni cambies de mecanismo para eludir una denegación.

## 10. Qué se hereda y qué se adapta

De [AGENTS.md del remake](https://github.com/VaroTv7/espaciokooplagunakRemake/blob/main/AGENTS.md), su [plan #1](https://github.com/VaroTv7/espaciokooplagunakRemake/issues/1) y su [registro #7](https://github.com/VaroTv7/espaciokooplagunakRemake/issues/7) se heredan reserva pública previa, precedencia, independencia, coordinación, calidad y contexto recuperable.

Aquí se explicitan pausa/reanudación, no caducidad por silencio, continuidad acotada y que PR_READY no libera. Los nombres, rutas, arquitectura y **Atlas/cosmografía** pertenecen al juego y no se exportan como normas comunitarias. Cada repositorio publica su propia ficha de adaptación enlazada desde README/AGENTS, preserva sus documentos y mantiene un solo registro por proyecto.
