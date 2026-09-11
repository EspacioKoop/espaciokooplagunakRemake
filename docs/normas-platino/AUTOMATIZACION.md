# Automatización de milestones

[Inicio](../README.md) · [Planificación y entregas](PLANIFICACION_Y_ENTREGAS.md)

## Qué se entrega

`scripts/platino.py` utiliza sólo la biblioteca estándar de Python 3.11 o posterior. `check` valida JSON localmente, sin red. `sync` consulta exclusivamente el repositorio indicado en github.com mediante la autenticación **ya existente** de GitHub CLI (`gh`); no lee ni imprime tokens ni configura credenciales.

La configuración es una lista explícita de versiones o hitos. No se interpreta texto libre de issues para decidir prioridades. No se escanean otros repositorios, carpetas personales, correos ni archivos de configuración ajenos. La herramienta no contacta servicios de IA ni envía telemetría propia.

## Adopción por repositorio

Con autorización y reserva previas, toma la herramienta de un commit revisado de normas_platino; registra ese SHA en la ficha de adopción. Copia `scripts/platino.py`, sus pruebas y una configuración adaptada por PR. No descargues y ejecutes automáticamente lo que haya en `main`, ni sobrescribas archivos existentes. El script puede usarse desde una copia local de este repositorio pasando la ruta de la configuración del proyecto.

El [ejemplo JSON](../templates/platino.json) usa un repositorio **ficticio**. Cambia `repository`, `title`, `description` e `issues` por decisiones aprobadas. `issues` admite sólo números positivos de issues de ese mismo repositorio; no números de PR ni los del plan/registro usados como sustitutos de tareas. Un issue no puede pertenecer a dos hitos del manifiesto.

`due_on` es opcional y acepta una fecha real UTC `YYYY-MM-DDTHH:MM:SSZ`. Omitirla conserva la fecha existente; no la borra. No se admiten `null`, fechas inventadas ni claves desconocidas. Los hitos sin tareas pueden usar `issues: []`; una adopción sin versiones comprometidas puede usar `milestones: []`.

Ejemplo de uso, tras guardar la configuración revisada como `.platino.json` en el proyecto:

```bash
# Todo local; no requiere gh ni autenticación.
python3 scripts/platino.py check .platino.json

# Lectura remota y vista previa; sustituye el destino de ejemplo.
python3 scripts/platino.py sync .platino.json --repo ORGANIZACION/REPOSITORIO

# Sólo después de revisar actions, before, issues y approval de la vista previa.
# HUELLA es el valor SHA-256 completo de approval, no el SHA de un commit.
python3 scripts/platino.py sync .platino.json --repo ORGANIZACION/REPOSITORIO \
  --apply --approve HUELLA
```

`--repo` es obligatorio y debe coincidir con el manifiesto. La herramienta comprueba además la identidad remota y que el repositorio no esté archivado. La aplicación vuelve a leer el estado: una huella diferente detiene la operación antes de escribir y exige una nueva revisión. No automatices la aprobación copiando la huella sin examinar el plan.

## Cambios permitidos y conflictos

Puede crear milestones abiertos ausentes y asignarles los issues abiertos, sin versión previa, enumerados en la configuración. Los creados por ella llevan un marcador HTML en su descripción; sólo los que conservan ese marcador pueden actualizarse automáticamente. Si un milestone manual coincide exactamente con la descripción y los campos declarados, puede reutilizarse sin apropiarse de él. Una discrepancia con metadatos manuales detiene el plan.

No borra ni cierra milestones, no reabre hitos, no altera issues cerrados para asignarlos a otra versión y no mueve issues que ya tengan otro milestone. Un cambio de título crea un hito distinto: **no** se interpreta como renombrado. Quitar un issue o hito del JSON no lo elimina del remoto. La desasignación, el cambio de versión, la adopción de metadatos manuales y el borrado de una fecha requieren decisión y operación manuales aparte.

Se leen todas las páginas, incluidos hitos cerrados; duplicados o respuestas incompletas producen error, no una falsa lista vacía. Una segunda ejecución sobre un estado ya sincronizado no debe producir escrituras. Cada aplicación se verifica mediante relectura remota.

## Seguridad, fallos y privacidad

La API no ofrece en esta herramienta una transacción entre milestone e issues ni un cerrojo atómico. Hay una ventana entre lectura y escritura: reserva también los metadatos y mantén **un único escritor**. No ejecutes dos sincronizadores a la vez. El script detecta cambios observables antes de aplicar, pero no garantiza excluir una edición humana simultánea.

Un error intermedio devuelve código distinto de cero y advierte de cambios parciales. No reintenta escrituras ni hace rollback destructivo. Revisa lo que se aplicó y genera un nuevo plan: la idempotencia permite completar lo que falta sin duplicar lo ya creado. Ante un timeout, no supongas que el servidor no aplicó la petición.

Los errores no vuelcan respuestas, cabeceras ni credenciales. Se desactiva `GH_DEBUG` para el subproceso y los datos se envían como JSON por entrada estándar, no como comandos de shell. La vista previa incluye descripciones de milestones y asignaciones: consérvala local si contiene información privada. Sólo debe enviarse a GitHub la configuración expresamente autorizada para ese repositorio. No incluyas secretos en sus descripciones.

## CI y despliegue común

El [workflow de este repositorio](../.github/workflows/validar.yml) valida documentación, configuración y pruebas con `contents: read`, sin sincronizaciones remotas. Usa `pull_request` y `push` a la base, no `pull_request_target`, cron, auto-merge ni publicación automática. Checkout se fija a un SHA revisado y no conserva credenciales en Git. Consulta la ejecución para el SHA concreto antes de afirmar éxito.

En repositorios adoptantes, añade `python3 scripts/platino.py check .platino.json` al workflow de validación existente mediante PR. No copies ciegamente nuestros comandos de tests: integra las pruebas con las suyas. La sincronización con escritura sigue siendo una operación explícita tras aprobar el alcance; no se ejecuta como efecto de un PR no revisado.

Para actualizar varios proyectos, cada uno declara su adopción y revisión del script. Se puede repetir el mismo procedimiento para una lista **autorizada** de repositorios, pero esta entrega no instala un bot de organización ni despliega nada en otros proyectos. Un workflow de escritura futuro necesitará autorización, permisos mínimos, código y configuración confiables, exclusión mutua y registro de acciones. No solicites permisos de administración para gestionar milestones.

Projects usa un modelo y permisos distintos: sus automatizaciones nativas pueden reducir trabajo manual, pero esta herramienta **no sincroniza Projects**. Tampoco crea planes maestros, reservas, releases o PR automáticamente.

## Verificación y referencias

```bash
python3 -m unittest discover -s tests -v
python3 scripts/platino.py check templates/platino.json
git diff --check
```

La suite usa dobles locales y datos ficticios. Prueba éxito, idempotencia, paginación, fechas, duplicados, destino incorrecto, aprobaciones, cambios concurrentes observables, conflictos manuales, fallos parciales y ausencia de escrituras sin autorización. **No es una prueba end-to-end de GitHub con credenciales**. La validación del esquema tampoco demuestra que el roadmap esté completo o que un agente haya leído las normas.

Fuentes primarias consultadas para el contrato técnico:

- [API de milestones](https://docs.github.com/en/rest/issues/milestones): listado paginado, creación y actualización; permisos de Issues o Pull requests según la operación. Este script usa endpoints de Issues, no requiere modificar permisos de organización.
- [GitHub CLI: gh api](https://cli.github.com/manual/gh_api): método explícito, hostname y JSON por `--input`.
- [Automatizaciones nativas de Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations): alternativas para reflejar estados reales sin inventar campos.

La versión REST fijada en el script es `2026-03-10`. Los cambios de API o de autenticación se revisan y prueban; no se amplían credenciales automáticamente al encontrar un error.
