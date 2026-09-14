# AGENTS.md — instrucciones para agentes

## Fuentes y alcance

Lee [README.md](README.md), la [guía de cooperación](docs/COOPERACION_AUTONOMA.md), [planificación y entregas](docs/PLANIFICACION_Y_ENTREGAS.md), el [plan maestro #1](https://github.com/EspacioKoop/normas_platino/issues/1), el [registro único #2](https://github.com/EspacioKoop/normas_platino/issues/2), sus comentarios y el issue concreto antes de editar. Estos números pertenecen exclusivamente a normas_platino.

Este repositorio mantiene reglas comunitarias y herramientas opcionales de adopción. Conserva lo existente, usa español de España y ejemplos adaptables. No conviertas Atlas, motores, personas ni contratos de los juegos de referencia en obligaciones generales. El README debe permitir encontrar todas las fuentes y adaptar las normas sin memoria de chat. Para cambiar la herramienta, lee también [AUTOMATIZACION.md](docs/AUTOMATIZACION.md).

## Ciclo obligatorio

1. Comprueba rama, checkout, cambios locales, plan, reservas y PR existentes. Elige el pendiente prioritario libre dentro del alcance autorizado.
2. Publica en #2, antes de modificar archivos:

   `CLAIM issue=#N agent=<nombre> branch=agent/N-slug files=<rutas> goal=<objetivo>`

3. Relee inmediatamente todas las reservas. La activa anterior por fecha de GitHub gana; en empate, el ID de comentario menor. Si hay solape, no edites: coordina o libera y reclama otro bloque.
4. Usa rama `agent/N-slug` y checkout propios desde la base actual. No alteres cambios desconocidos ni ramas ajenas. Commits pequeños y pushes frecuentes, previa revisión de privacidad y estado remoto.
5. Subdivide únicamente si archivos y criterios son independientes. README.md, AGENTS.md, guías, configuración y workflows son archivos compartidos: reserva sus rutas y acuerda un único escritor o una secuencia explícita. No sobrescribas trabajo ajeno al resolver conflictos.
6. Ejecuta los controles de abajo. Ninguna afirmación de estado puede exceder la evidencia. La referencia de CI es la ejecución para el SHA candidato; no su definición ni un verde anterior.
7. Abre PR hacia `main`, enlaza el issue y registra `PR_READY` en #2 con PR, SHA, pruebas y límites. No libera la reserva ni autoriza merge.
8. Integra sólo con autorización explícita y controles satisfechos. Prohibidos force-push, reescritura compartida y push directo a `main`. La inicialización vacía autorizada y la autorización histórica del issue #3 no son excepciones reutilizables.
9. Verifica el resultado remoto; actualiza el plan coordinadamente y publica `RELEASE`. Al abandonar, deja checkpoint antes de liberar. Al pausar, publica estado, SHA, próximos pasos y reserva explícita: no caduca por silencio.
10. Relee plan y reservas y selecciona otro bloque libre si el mandato sigue vigente. Si no hay trabajo autorizado, informa del cierre sin inventar tareas ni crear automatización persistente.

## Controles canónicos

Desde la raíz, con Python 3.11 o posterior:

```bash
python3 -m unittest discover -s tests -v
python3 scripts/platino.py check templates/platino.json
git diff --check
```

Las pruebas son locales, sin red, y usan datos ficticios. Comprueban lógica, negativos de escritura, configuración y documentación. Revisa además coherencia normativa, ejemplos y privacidad. El workflow `.github/workflows/validar.yml` ejecuta controles sin permisos de escritura; si falta una ejecución, falla o no es accesible, decláralo. No inventes CI verde ni rebajes checks exigidos.

## Trampas conocidas

- El protocolo `RELEASE` libera una reserva; **no** publica una GitHub Release.
- `templates/platino.json` contiene un repositorio ficticio. No es la configuración de producción de esta organización.
- `sync` sin opciones de aplicación consulta GitHub pero no escribe; `check` no usa red. No ejecutes pruebas de escritura sobre proyectos reales para validar el script.
- La huella de aprobación y la relectura detectan cambios observables, pero la API no proporciona aquí una transacción entre recursos. Sigue siendo obligatorio un único escritor para los metadatos reservados.
- El PR de referencia contiene una discrepancia entre la descripción y los estados de Project asumidos en su ROADMAP. Comprueba archivos y esquema real, no sólo el resumen del PR.

## Seguridad y entrega

No publiques tokens, cookies, claves, contraseñas, datos personales, infraestructura privada ni información de otros dominios. Revisa también diffs, logs, capturas, adjuntos y descripciones de PR. Una autorización para este repositorio no permite modificar otros ni ampliar credenciales o permisos.

La sincronización es opcional, explícita y limitada al destino validado. No añadas telemetría, servicios de IA, ejecución de comandos procedentes de issues, auto-merge, publicación de releases ni reasignación por silencio. No ejecutes código no revisado de PR con tokens de escritura ni utilices `pull_request_target` para probarlo. Un despliegue en otro repositorio requiere su propia adopción y autorización.

El PR incluye alcance, documentos y código modificados, requisitos cumplidos, comprobaciones reales, limitaciones y reversión mediante otro PR. `Closes #N` sólo para cierre completo; `Refs #N` para entrega parcial. No cierres criterios por una intención, un placeholder o una revisión pendiente. Revertir el código no revierte automáticamente los metadatos que alguien haya sincronizado: inventaría cualquier efecto remoto.
