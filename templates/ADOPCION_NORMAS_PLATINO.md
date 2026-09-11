# Ficha de adopción de Normas Platino

Plantilla: copiar y adaptar por PR, sin sustituir instrucciones existentes. Los campos entre `<...>` se rellenan o se declaran no aplicables con motivo antes de publicar la ficha del proyecto.

## Identidad y autoridad

| Campo | Valor del proyecto |
| --- | --- |
| Repositorio | `<organización/repositorio>` |
| Instrucciones locales y contribución humana | `<AGENTS.md, CONTRIBUTING.md u otras rutas existentes>` |
| Normas adoptadas | `<URL del commit completo de normas_platino y copia/referencia reproducible>` |
| Revisión de adopción | `<fecha, responsable y PR de adaptación>` |
| Plan maestro | `<URL del issue de ESTE repositorio>` |
| Registro único de reservas | `<URL del issue de ESTE repositorio>` |
| Roadmap | `<ruta y responsable de mantenerla>` |
| Rama base y convención de ramas | `<valores reales>` |
| Coordinación y límites de autoridad | `<responsable, alcance y registro de decisiones>` |
| Autoridad de merge | `<quién, condiciones y dónde registra la autorización>` |
| Autoridad de publicación | `<quién, productos/canales y registro de aprobación>` |
| Prioridad, dependencias y aceptación | `<regla y fuentes canónicas>` |
| Archivos y metadatos compartidos | `<rutas, milestones, propietario y secuencia de edición>` |
| Fronteras de datos | `<información publicable, información local y destinos autorizados>` |
| Límites de autonomía | `<objetivos, recursos, duración y condiciones de parada>` |

## Pruebas y publicación

Comandos canónicos: `<comandos reales desde el directorio indicado>`.
Workflows y checks exigidos: `<nombres/enlaces o ausencia explícita; no afirmar verde>`.
Entorno: `<versiones de herramientas, plataforma, fixtures sin datos privados>`.
Criterio de release: `<artefactos, recorrido, evidencia, autorización y limitaciones>`.
Estado publicado frente a integrado: `<release disponible, SHA candidato y pruebas correspondientes>`.

## Projects, sólo cuando se adopten

| Tablero | Identidad y contenido | Campo y opciones reales | Regla de transición |
| --- | --- | --- | --- |
| Backlog | `<propietario/ID/URL; issues admitidos>` | `<IDs/nombres verificados>` | `<hecho y evidencia que cambian el estado>` |
| Cola de entrega | `<propietario/ID/URL; PR admitidos>` | `<IDs/nombres verificados>` | `<CI, conflictos, decisión, integración>` |

No aplicable: `<motivo si no se usan Projects>`. Permisos/automatizaciones autorizados: `<alcance o ninguno>`. El registro de reservas sigue siendo la única fuente de titularidad.

## Trampas conocidas

| Archivo o contrato | Invariante y fallo conocido | Prueba de regresión y referencia |
| --- | --- | --- |
| `<ruta o contrato local>` | `<qué debe conservarse y qué lo rompe>` | `<comando/test e issue o PR>` |

No copiar las peculiaridades de otro proyecto como si fueran nuestras. Si aún no hay incidencias documentadas, indicarlo sin inventar ejemplos reales.

## Rutina de arranque y actualización

El AGENTS local exige leer las instrucciones, normas adoptadas, plan, reservas e issue con comentarios antes de editar. Registra la revisión usada con el CLAIM o checkpoint cuando cambie. Consulta las novedades centrales al iniciar una sesión con acceso y propón su adaptación mediante PR, conservando reglas locales y excepciones justificadas. Sin acceso, declara qué revisión local usas y qué no se pudo contrastar.

Configuración opcional de milestones: `<ruta del JSON o no habilitada>`.
Revisión del script: `<SHA completo que contiene la herramienta revisada o no habilitada>`.
Responsable único de sincronización y reserva de metadatos: `<responsable y registro>`.
CI de validación: `<comando check incorporado o no habilitada>`.

Un agente no recibe nuevos permisos por leer esta ficha. La copia de plantillas no instala automatizaciones ni demuestra cumplimiento.
