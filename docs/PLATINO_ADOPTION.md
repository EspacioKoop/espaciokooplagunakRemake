# Adopción de Normas Platino

[Inicio](../README.md) · [Instrucciones](../AGENTS.md) · [Roadmap](ROADMAP.md) · [Copia y procedencia](platino/README.md)

## Identidad, revisión y autoridad

| Campo | Decisión local |
| --- | --- |
| Repositorio | `EspacioKoop/espaciokooplagunakRemake` |
| Fuente adoptada | [normas_platino@b5e01a2b2060a31268507797708a92a7d14ffc52](https://github.com/EspacioKoop/normas_platino/commit/b5e01a2b2060a31268507797708a92a7d14ffc52) |
| Copia reproducible | Los 13 archivos originales, sin modificaciones, en `docs/platino/upstream/`; inventario SHA-256 y blobs Git en `upstream-lock.json` |
| Revisión de adopción | 11/09/2026, agente `astra-platino-adoption-s11`, por encargo expreso de Varo; [tarea y PR enlazado #72](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/72) |
| Plan maestro | [#1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1); aceptación y análisis transversal en [#32](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32) |
| Único registro de reservas | [#7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7); CLAIM de adopción [5637906650](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7#issuecomment-5637906650) |
| Base y ramas | `main`; `agent/<issue>-<slug>` y checkout propio. Ningún push directo a main, force-push o permiso derivado de una autorización histórica |
| Instrucciones locales | `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md` y esta ficha; el motor, contratos y aceptación siguen siendo los del juego |
| Mantenimiento del roadmap | Sesión coordinadora autorizada por Varo, con reserva de `docs/ROADMAP.md` y decisiones enlazadas a #1/#72. No se inventa un responsable nominal permanente |
| Merge y publicación | Usuario o sesión coordinadora expresamente autorizada, con alcance registrado en issue/PR y controles del SHA exacto. La adopción, PR_READY y milestones no conceden esos permisos |
| Prioridad y dependencias | #1 prioriza; issue y decisiones definen aceptación; #7 concede titularidad. Una contradicción detiene sólo el alcance afectado y se resuelve de forma registrada |
| Archivos/metadatos compartidos | AGENTS, README, guías, manifiesto, herramientas, workflows y milestones requieren reserva y un único escritor; no basta separar párrafos o asignar personas distintas |
| Autonomía y parada | Sólo el trabajo expresamente encargado y libre. Pausa o bloqueo conservan la reserva; abandono/completado requieren checkpoint y RELEASE explícito. Sin permiso no hay merge, publicación, reasignación ni despliegue en otros repositorios |

La implementación se entrega por PR; **la presencia de esta ficha en una rama no significa que esté integrada en main**. El estado efectivo de integración, CI y sincronización se registra en #72, sobre el SHA correspondiente.

## Qué se adopta y cómo se adapta

| Norma central | Aplicación verificable en el remake |
| --- | --- |
| Cooperación autónoma y arranque | AGENTS §§0–4 y 8–10: leer todas las páginas, CLAIM y relectura, prioridad por fecha/ID, ampliaciones, escritor único, PR y checkpoint |
| Esperas y liberación | PAUSE/WAITING_ON no caducan por silencio; PR_READY no libera; RELEASE menciona CLAIM/SHA y no publica una GitHub Release |
| Arquitectura, pruebas y datos | Se conservan standalone-first, host autoritativo, privacidad de proyecciones, compatibilidad, recursos propios y recorridos seamless; AGENTS §§5–7 y SECURITY |
| Planificación y entregas | Roadmap con alcance incluido/excluido, dependencias y salida; separación plan/reservas/issue/milestone/PR/release; gates G0–G3 sin porcentaje ficticio |
| Automatización | Copia exacta del CLI y pruebas centrales; `.platino.json` adaptado; `tools/platino.py` sólo abre la copia local revisada |
| Plantillas centrales | Conservadas intactas para consulta. Esta ficha, el roadmap y la plantilla local de PR son las adaptaciones; los ejemplos de otro repositorio no se ejecutan |
| Actualización y trazabilidad | SHA completo, hashes y prueba de integridad; cambios centrales se revisan y proponen mediante PR, nunca por descarga/ejecución automática |
| Trampas conocidas | AGENTS §12 enlaza fallos y regresiones reales de guardados, red, terminales exportadas, evidencias y biblioteca |
| Privacidad y autonomía | Datos públicos del código y fixtures sintéticos. No subir partidas, preferencias, credenciales, registros privados ni capturas de personas; no llamar a servicios de IA ni escanear directorios personales |

Los números #1/#2 de la copia central pertenecen a **normas_platino**. No crean un segundo registro: en este juego siempre se utiliza #7. La reserva histórica de Atlas fue liberada; cualquier reserva posterior sigue prevaleciendo.

## Controles y límites

Desde la raíz, Python 3.11 o posterior:

```sh
python3 tools/platino.py check .platino.json
python3 -m unittest discover -s docs/platino/upstream/tests -v
python3 -m unittest discover -s tests/platino -v
git diff --check
```

El workflow [Validate Platino adoption](../.github/workflows/platino.yml) utiliza `contents: read`, acciones fijadas, checkout sin credenciales persistidas y pruebas locales. No escribe issues, milestones, releases ni ramas. No demuestra lectura o comprensión de normas por parte de un agente.

La referencia del juego continúa siendo [Verify and package standalone](../.github/workflows/release.yml), más sus workflows por área. Godot y exportadores se fijan en las herramientas del repositorio, no en las normas genéricas. La validación del juego usa `--test` y datos sintéticos. La CI gráfica Linux, el arranque Windows, una instalación real de Foundry y un playtest humano son evidencias distintas; no se sustituyen entre sí.

La [release v0.9.2](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/tag/v0.9.2) tiene como referencia histórica `f2015279bb7a8c307352a9526d1942a9df047ac4`. La adopción no modifica esos paquetes ni convierte un main posterior en una release. Para una publicación nueva se requiere alcance aceptado, candidato exacto, controles exigidos, paquetes/hashes, instalación y recorrido requeridos, limitaciones y autorización.

## Sincronizar milestones

Configuración: [`.platino.json`](../.platino.json). Las asignaciones y exclusiones se explican en el [roadmap](ROADMAP.md). El plan inicial de tres hitos se sustituyó al detectar cuatro milestones creadas por otra sesión: se conservan sus metadatos y asignaciones, y sólo se añaden gobernanza y debates aún sin hito. Las cuatro existentes siguen siendo manuales; la herramienta no añade su marcador ni toma su propiedad. La sincronización sólo escribe en este repositorio. El único escritor es quien tenga el CLAIM vigente para esos metadatos en #7; no se crea un propietario perpetuo.

```sh
# Validación sin red ni gh.
python3 tools/platino.py check .platino.json

# Consulta con la autenticación existente de gh; no escribe.
python3 tools/platino.py sync .platino.json --repo EspacioKoop/espaciokooplagunakRemake

# Después de revisar actions, before, issues y approval del resultado anterior.
# HUELLA es la aprobación de 64 caracteres, no un SHA de commit.
python3 tools/platino.py sync .platino.json --repo EspacioKoop/espaciokooplagunakRemake --apply --approve HUELLA
```

El [workflow manual](../.github/workflows/platino-sync.yml) exige `workflow_dispatch` desde `main`, repositorio exacto y `expected_sha` coincidente. Preview sólo dispone de lectura; apply necesita una huella revisada y `issues: write`, no administración ni escritura de código. Los inputs pasan por variables de entorno, no se interpolan como comandos. Hay exclusión mutua entre ejecuciones, pero la API no ofrece una transacción frente a ediciones humanas: la reserva de escritor único sigue siendo obligatoria.

No se ejecuta por PR, cron, cierre de issue ni porcentaje del milestone. No mueve asignaciones existentes, no borra ni cierra/reabre hitos, no toca issues cerrados para darles otra versión y no sobrescribe metadatos manuales incompatibles. Los errores parciales se inspeccionan antes de otra vista previa; no hay rollback destructivo. Quitar una entrada del manifiesto no la elimina del remoto. Cada aplicación verifica el resultado con una nueva lectura.

La primera aplicación de #72, cuando se registre, se distingue de la instalación permanente del workflow: un procedimiento temporal de rama propia debe fijar código revisado y aprobación literal, y retirarse del diff final. No se otorga permiso a futuras ramas para ejecutar escrituras.

## Projects

**No adoptado.** No hay esquema de propietario/ID/campos/opciones verificado para este proyecto ni automatización autorizada de Projects. No se inventan columnas o estados y no se solicitan permisos de administración. Su futura adopción necesita ficha con datos reales y PR separado; #7 seguirá siendo la fuente de reservas.

## Actualizar o revertir

Al iniciar una sesión con acceso se comparan novedades centrales con la revisión fijada. El cambio necesita reserva, lectura del diff completo, adaptación local y PR con ambas suites. Se renuevan juntos copia, lock y ficha. Sin acceso, se usa la copia disponible indicando que no se comprobaron novedades. No se ejecuta una actualización obtenida de `main` sin revisión.

La reversión del código se hace por otro PR. **No revierte automáticamente los milestones ya creados o las asignaciones**: esos efectos se inventariarán y se deciden aparte. No se borran metadatos ni releases como efecto lateral de desinstalar la herramienta.
