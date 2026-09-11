# Normas Platino

**Cooperación autónoma entre agentes, sin colisiones ni pérdida de trabajo.**

Este repositorio contiene un protocolo reutilizable: los agentes eligen trabajo prioritario, reservan un alcance independiente, producen una entrega comprobada y la presentan mediante PR. Autonomía no significa permiso ilimitado ni integración sin autorización.

Incluye también planificación de versiones, criterios de publicación y una herramienta opcional para sincronizar milestones con vista previa. No es un coordinador permanente ni un permiso para modificar todos los repositorios de una organización.

## Empieza aquí

1. Lee este README para conocer el mapa y la adaptación.
2. Lee [AGENTS.md](AGENTS.md): instrucciones para contribuir **a este repositorio**.
3. Consulta la [guía de cooperación](docs/COOPERACION_AUTONOMA.md) y las [normas de planificación y entrega](docs/PLANIFICACION_Y_ENTREGAS.md).
4. En el proyecto donde vayas a trabajar, localiza su plan maestro, registro único de reservas, instrucciones locales, roadmap y pruebas canónicas **antes de editar**.

## Mapa del repositorio

| Fuente | Para qué sirve |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Contrato operativo para contribuir aquí |
| [Cooperación autónoma](docs/COOPERACION_AUTONOMA.md) | Reservas, estados, coordinación y plantillas de entrega |
| [Planificación y entregas](docs/PLANIFICACION_Y_ENTREGAS.md) | Roadmap, milestones, Projects, releases y evidencia |
| [Automatización](docs/AUTOMATIZACION.md) | Instalación, comandos, permisos y límites reales |
| [Ficha de adopción](templates/ADOPCION.md) | Adaptación y revisión de normas por proyecto |
| [Plantilla de roadmap](templates/ROADMAP.md) | Fases, dependencias y criterios de salida |
| [Configuración de ejemplo](templates/platino.json) | Milestones explícitos; repositorio ficticio, no un destino real |
| [Herramienta](scripts/platino.py) y [pruebas](tests/test_platino.py) | Validación local y sincronización opcional mediante GitHub CLI |
| [Plan maestro #1](https://github.com/EspacioKoop/normas_platino/issues/1) | Prioridad, alcance y checkpoint de este proyecto |
| [Registro único #2](https://github.com/EspacioKoop/normas_platino/issues/2) | Reservas, coordinación, pausas y liberaciones |
| [Issues](https://github.com/EspacioKoop/normas_platino/issues) y [PR](https://github.com/EspacioKoop/normas_platino/pulls) | Tareas, aceptación, revisión y evidencia |

El plan determina **qué va primero**; el registro determina **quién puede editar qué**. Los issues concretan el trabajo y los PR acreditan su entrega. No mantengas una segunda cola o registro contradictorios en un chat. Un Project refleja hechos; no sustituye la aceptación ni concede autorización de merge.

## Adoptarlo en otro repositorio

1. Conserva y lee su documentación, licencias e instrucciones existentes. Integra estas normas; no reemplaces contratos locales a ciegas.
2. Identifica o crea, con autorización, **un plan maestro y un único registro de reservas por proyecto**. Enlázalos desde su README y AGENTS.md. No reutilices los números de este repositorio ni los del juego.
3. Define responsables, prioridad, dependencias, aceptación, rama base, pruebas, archivos compartidos, autoridad de merge y publicación.
4. Adapta la [ficha de adopción](templates/ADOPCION.md) y el [roadmap](templates/ROADMAP.md). Sustituye todos los campos antes de publicarlos y registra el SHA completo de las normas adoptadas.
5. Incorpora el ciclo de las guías mediante PR y comprueba su aplicación con una tarea pequeña. No hace falta implantar un bot ni un servicio. La automatización de milestones es opcional y se habilita por repositorio.

Ficha mínima —la plantilla amplía las evidencias, Projects y trampas conocidas—:

```text
Proyecto: <organización/repositorio>
Instrucciones: <AGENTS.md y documentos locales>
Normas adoptadas: <SHA completo, fecha de revisión y copia/enlace reproducible>
Plan maestro: <URL canónica>
Registro único de reservas: <URL canónica>
Roadmap: <ruta y alcance de cada fase>
Coordinación: <responsable y límites de autoridad>
Rama base: <rama protegida>
Prioridad y aceptación: <regla y ubicación>
Archivos compartidos: <rutas y propietario/secuencia de edición>
Pruebas canónicas: <comandos y workflows reales>
Autorización de merge y publicación: <quién autoriza y dónde se registra>
Fronteras de datos: <qué puede publicarse y qué queda privado>
Límites de autonomía: <objetivos, recursos, duración y condiciones de parada>
```

Los proyectos concretan su arquitectura y controles adicionales. No pueden interpretar una reserva como autorización para publicar secretos, ignorar una denegación, sobrescribir a otros o saltarse pruebas. Si dos instrucciones son incompatibles, detén el alcance afectado y pide resolución a la autoridad del proyecto.

Cada sesión comienza leyendo el AGENTS local y las fuentes adoptadas. Las novedades centrales se comparan y adaptan mediante PR; no sobrescriben silenciosamente las reglas locales. Tener un enlace o un check verde no demuestra que un agente haya leído las normas.

## Automatización utilizable, no una promesa

Con Python 3.11 o posterior, este comando valida el ejemplo **sin red ni credenciales**:

```bash
python3 scripts/platino.py check templates/platino.json
python3 -m unittest discover -s tests -v
```

Para un repositorio adoptante se copia la herramienta revisada, se adapta una configuración propia y se ejecuta primero `sync` en modo de vista previa. Sólo `--apply --approve HUELLA` permite aplicar exactamente el plan revisado, con destino explícito coincidente. Consulta el [procedimiento completo](docs/AUTOMATIZACION.md).

La herramienta crea milestones ausentes, actualiza metadatos gestionados por ella y asigna issues abiertos sin milestone cuando están enumerados en la configuración. No borra ni cierra hitos, no mueve issues de otra versión, no publica releases, no fusiona PR, no modifica Projects ni caduca reservas. No hay despliegue automático en otros repositorios.

## Reglas esenciales

- Escoge el pendiente prioritario libre y reserva **antes** de editar.
- Publica `CLAIM`, relee inmediatamente: gana la reserva activa anterior.
- Subdivide sólo con archivos y criterios independientes; coordina archivos compartidos.
- Trabaja en rama y checkout propios; commits pequeños y pushes frecuentes.
- Entrega funcionalidad real, pruebas proporcionales y CI exigida verde sobre el candidato actual.
- Abre PR, registra `PR_READY` y espera autorización para integrar.
- Pausa con estado, SHA y próximos pasos; libera explícitamente con `RELEASE` al abandonar. El silencio no hace caducar reservas.
- Al acabar, relee plan/reservas y escoge otro bloque libre dentro del mandato vigente.
- Sin force-push, push directo a `main`, pérdida de trabajo ajeno ni filtración de secretos.

## Procedencia y alcance

El protocolo de cooperación se basa en las fuentes públicas de **espaciokooplagunakRemake**:

- [AGENTS.md](https://github.com/VaroTv7/espaciokooplagunakRemake/blob/main/AGENTS.md): contrato de colaboración.
- [Issue #1](https://github.com/VaroTv7/espaciokooplagunakRemake/issues/1): plan maestro y checkpoint validado.
- [Issue #7](https://github.com/VaroTv7/espaciokooplagunakRemake/issues/7): registro y acuerdos reales de reservas.
- [Conjunto de issues](https://github.com/VaroTv7/espaciokooplagunakRemake/issues): contexto público del trabajo.

La planificación incorpora aprendizajes del [PR expediente-legado #183](https://github.com/EspacioKoop/expediente-legado/pull/183), contrastando su descripción con los archivos. La [guía de entregas](docs/PLANIFICACION_Y_ENTREGAS.md) detalla qué se generaliza y qué no.

Se generaliza el método, no las decisiones de los juegos: **Atlas/cosmografía es una reserva específica**, no una norma comunitaria. Tampoco se imponen Godot, Foundry, arquitecturas, rutas, números de issue, personas, estados concretos de Project ni excepciones históricas de integración directa. La integración ordinaria pasa por PR autorizado.

## Estado y contribuciones

El protocolo no es un sistema de bloqueo técnico: requiere comprobar y respetar el registro. El [workflow de validación](.github/workflows/validar.yml) define pruebas sin escrituras en GitHub; su mera existencia no significa que una ejecución haya pasado. La evidencia de CI se consulta por SHA en [Actions](https://github.com/EspacioKoop/normas_platino/actions). Una ejecución local no equivale a CI verde ni prueba una sincronización real con credenciales.

Las mejoras se proponen mediante issue, reserva y PR conforme a [AGENTS.md](AGENTS.md). No se cambia la licencia ni la autoría de proyectos que adopten estas normas.
