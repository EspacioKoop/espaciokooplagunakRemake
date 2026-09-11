# Roadmap de Espaciokoop Lagunak Remake

[Inicio](../README.md) · [Normas adoptadas](PLATINO_ADOPTION.md) · [Paridad](FEATURE_PARITY.md) · [Registro de evidencias](parity/README.md)

**Decisión de planificación: 11/09/2026, #72, a petición de Varo.** No es una segunda cola diaria ni un porcentaje de calidad. [#1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1) prioriza, [#7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7) reserva y cada issue mantiene su aceptación íntegra. La asignación de una tarea a un hito no cambia su estado ni autoriza editarla.

## Base publicada, no una promesa de paridad

[v0.9.2](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/tag/v0.9.2), commit `f2015279bb7a8c307352a9526d1942a9df047ac4`, es el checkpoint utilizado por esta revisión. La publicación del 11/09/2026 y sus comprobaciones se registran en [#67](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/67). La CI canónica de ese main es [34615686998](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/runs/34615686998); no acredita una revisión posterior.

Linux y Windows son líneas de empaquetado existentes. macOS/Android y Foundry real conservan sus criterios de validación física. La capacidad de exportar debe estar lista **antes** de comprometer la primera release de una plataforma; no se promete un APK por existir un preset.

No se crean milestones retrospectivos vacíos para simular seguimiento histórico. Las releases previas se conservan sin reetiquetar. Una siguiente versión de pruebas requiere su propio corte y decisión: este roadmap no inventa una 0.9.3 ni fecha para la 1.0.

## Fase A — Adopción Normas Platino

**Milestone:** `Adopción Normas Platino`. **Tipo:** gobernanza, sin release del juego. **Issue:** [#72](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/72).

Incluye revisión central fijada, copia local íntegra, instrucciones coherentes para humanos/agentes, este roadmap, configuración explícita, sincronizador con aprobación, pruebas y mapa/inventario del repositorio. Depende de las reservas y del examen de fuentes; no bloquea el trabajo independiente de jugabilidad.

Excluye cambiar mecánicas, renunciar a requisitos del original, modificar paquetes publicados, activar Projects o otorgar autorización de merge/publicación.

**Salida observable:** PR revisado e integrado, pruebas identificadas sobre el candidato, normas y rutas accesibles, plan de milestones revisado y aplicación remota verificada. Una rama con archivos preparados es una entrega propuesta, no la finalización de la adopción.

## Fase B — v1.0.0: paridad funcional demostrable

**Milestone:** `v1.0.0`. **Tipo:** objetivo de producto/release, sin fecha comprometida.

La asignación inicial usa los carriles que ya describen aceptación de paridad, no búsquedas por palabras en títulos:

| Issue | Trabajo que aporta al objetivo, conservando lo ya integrado |
| --- | --- |
| [#2](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/2) | Edición, contenido, dependencias, importación/exportación y migración pendiente |
| [#3](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/3) | Avatar, poses, presencia y mesas; no rehacer asientos/autenticación ya integrados |
| [#4](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/4) | Controles y remapeo restantes, localización, accesibilidad y plataformas con validación real |
| [#5](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/5) | Integraciones opcionales y sus criterios pendientes; Foundry nunca es el núcleo |
| [#6](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/6) | Interiores/social/arte/audio restantes, interacción real y recursos editables |
| [#29](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/29) | Regresión de terminales y confirmación humana pendiente; la CI de #68 no inventa el playtest del informante |

**No es un inventario exhaustivo de paridad.** #1 y #32 conservan los pendientes transversales de cosmografía, navegación, dirección, contenido y modelo. Al subdividirlos se añaden tareas independientes a la versión mediante decisión registrada, sin mover una tarea previamente asignada a escondidas. El porcentaje de estas seis asignaciones no mide el estado completo de la 1.0.

La secuencia técnica prioriza inventario original→remake y decisiones de contenido/modelo; después, integración jugable y su evidencia; por último, aceptación del conjunto y distribución. Se puede avanzar en paralelo sólo con archivos y contratos independientes. La cosmografía enlaza persistencia, catálogo y navegación; un parser aislado no completa esos contratos. Las plataformas e integraciones se pueden validar en paralelo sin declarar terminado el núcleo.

### Criterios de salida G0–G3

| Gate | Evidencia necesaria en el candidato exacto |
| --- | --- |
| G0 — Integridad de plataforma | Build, importación, suites, red, guardados, paquetes y validaciones de cada plataforma comprometida, sin ocultar fallos |
| G1 — Paridad de modelo | Inventario completo del original, equivalencias y decisiones autorizadas, esquemas/dependencias/migraciones y round-trip |
| G2 — Paridad jugable | Capacidades accesibles y utilizables de punta a punta desde el standalone; interacciones y negativos reproducibles, no sólo botones o modelos |
| G3 — Paridad de producto | Contenido/arte/audio, localización/accesibilidad, integraciones opcionales reales y validaciones físicas/humanas exigidas |

Los gates proceden de [la revisión de #1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1#issuecomment-5622983070) y del seguimiento #32. El verificador existente se usa así:

```sh
python3 tools/check_parity_evidence.py --require-complete --candidate SHA_COMPLETO_DEL_CANDIDATO
```

El registro debe tener cobertura completa y evidencia consistente; además se comprueban los resultados reales de las pruebas, no sólo la forma de sus enlaces. Un `0` estructural no reemplaza CI, revisión, instalación o playtest. `coverage.complete=false` bloquea el cierre global.

Después de G0–G3: revisión del alcance/exclusiones, autorización de publicación, artefactos identificados y verificables, notas/compatibilidad y comprobación de la release realmente publicada. **No se cierra #1, #32 o el milestone por suma de PRs, una barra al 100 % o la existencia de un tag.** Una renuncia de producto necesita aprobación explícita; esta adopción no concede ninguna.

## Fase C — Diseño futuro: decisiones sin release

**Milestone:** `Diseño futuro — decisiones sin release`. **Tipo:** investigación y decisiones, no compromiso de implementar todas las ideas ni de publicar una versión.

Incluye [#30](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/30) (segunda pantalla Android), [#33](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/33) (ideas de cooperación de Big Walk), [#59](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/59) (navegación 3D/6DOF) y [#71](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/71) (inspiración PULSAR). Sus cuerpos separan propuestas y funcionalidades aprobadas; esta agrupación conserva esa distinción.

Dependencias: decisiones de arquitectura/autoridad/UX de cada debate, límites actuales del juego y compatibilidad con la paridad. La navegación 6DOF requiere revisar el modelo planar, persistencia, proyecciones y colisiones; modelos 3D o laboratorios planetarios no aportan por sí solos ese sistema. Android de segunda pantalla tampoco equivale al port completo.

Excluye imponer estas mecánicas a 1.0, copiar recursos ajenos, cambiar los ocho puestos por los de otro juego, crear fechas o ejecutar cambios sin un issue de implementación y su reserva.

**Salida observable:** cada debate deja decisión explícita (aceptar alcance concreto, posponer o descartar con motivo), riesgos/dependencias y seguimiento enlazado. Cerrar un debate de diseño no acredita implementación. Una idea aprobada pasa a una tarea y entrega decididas aparte.

## Referencias permanentes y triaje pendiente

#1 y #32 son plan/análisis transversales; #7 es el registro; [#52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52) es el índice permanente de biblioteca. No se utilizan para inflar milestones ni se cierran por esta adopción.

[#56](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/56), laboratorio/pack planetario, necesita reconciliar su aceptación con las entregas ya publicadas. Se deja sin versión nueva, no descartado ni declarado terminado. Los PR #69/#70 no se asignan como si fueran issues de planificación y no se atribuyen al corte 0.9.2. Cualquier estado posterior se consulta en GitHub.

## Mantenimiento

[`.platino.json`](../.platino.json) es la lista técnica de estas decisiones; las reglas de aplicación viven en [la ficha](PLATINO_ADOPTION.md). Añadir/cambiar alcance necesita reserva y una justificación en el issue; un cambio de versión ya asignada se resuelve manualmente, no por heurísticas. Las fechas son opcionales y sólo se añaden si se han comprometido. La coherencia entre fuentes importa más que rellenar todo el tablero.
