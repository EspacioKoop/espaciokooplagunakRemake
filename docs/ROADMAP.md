# Roadmap de Espaciokoop Lagunak Remake

[Inicio](../README.md) · [Normas adoptadas](PLATINO_ADOPTION.md) · [Paridad](FEATURE_PARITY.md) · [Evidencias](parity/README.md)

**Planificación del 11/09/2026, #72, a petición de Varo.** [#1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1) prioriza, [#7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7) reserva y cada issue conserva su aceptación. El roadmap no es una segunda cola ni un porcentaje de calidad.

## Reconciliación con los hitos existentes

La lectura inicial estaba vacía. Durante esta adopción otra sesión creó cuatro milestones y asignó issues. La [vista previa](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/runs/34628977620) abortó sin escrituras ante ese cambio. La [lectura posterior](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/runs/34629465154) permitió conservar sus títulos, descripciones y asignaciones, sin imponer la propuesta anterior de `v1.0.0` ni duplicar hitos.

[`.platino.json`](../.platino.json) reproduce las cuatro descripciones manuales exactamente; no añade marcador ni toma su propiedad. Sólo añade dos hitos faltantes y asignaciones aún vacías. Otros issues ya asociados a los hitos permanecen intactos aunque no estén enumerados en el manifiesto. El estado efectivo y la aplicación verificada se registran en [#72](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/72).

| Milestone | Ámbito y asignaciones contempladas por el manifiesto | Exclusiones y salida |
| --- | --- | --- |
| **1.0 — Paridad funcional** (existente #1) | Objetivo global, aceptación del conjunto y regresión de terminales #29. Los issues #1/#32 siguen siendo las referencias transversales. | No basta cerrar estos issues ni ver una barra al 100 %. Salida G0–G3, candidato exacto, aceptación y publicación autorizada. |
| **Cosmografía y navegación** (existente #2) | Catálogo jerárquico, persistencia, navegación y decisiones de #59; conserva su asignación. | Un parser, modelo o laboratorio no demuestra navegación integrada. Salida: contratos aprobados, integración y pruebas; la discusión 6DOF no aprueba todas sus propuestas. |
| **Contenido y catálogo** (existente #3) | #2: edición, dependencias, formatos y migración; #3: avatar, poses, presencia y mesas; #6: interiores/social/arte/audio. | No rehacer funciones ya integradas ni dar por migrado todo el original. Salida: aceptación de cada issue, recursos utilizables y evidencia de consumo desde el ejecutable. |
| **Plataforma y publicación** (existente #4) | #4: controles, localización, accesibilidad y plataformas; #5: integraciones opcionales; #30: decisiones de segunda pantalla Android. | Foundry no se convierte en núcleo. APK/preset/segunda pantalla no equivalen a port validado. Salida por alcance aprobado, paquetes y validación física exigida; #30 no impone una release. |
| **Adopción Normas Platino** (nuevo) | #72: copia revisada, instrucciones, roadmap, sincronización explícita, pruebas e inventario. | Sin cambios de juego, release ni Projects. Salida: PR revisado e integrado, validación del candidato y sincronización remota verificada. |
| **Diseño futuro — decisiones sin release** (nuevo) | #33: Big Walk; #71: PULSAR. Son debates aún sin hito, no compromisos de implementación. | Sin fecha/versiones, copia de recursos ajenos ni requisitos nuevos impuestos a 1.0. Salida: decisiones explícitas, riesgos/dependencias y tareas de seguimiento aprobadas o aplazadas. |

Los números de milestone e issue son espacios distintos: «milestone #1» no significa «issue #1». Los dos hitos nuevos no reciben número supuesto antes de crearse. La asignación de #30/#59 a hitos temáticos se respeta y **no convierte sus ideas en funciones aprobadas**.

## Base publicada y secuencia

[v0.9.2](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/tag/v0.9.2), commit `f2015279bb7a8c307352a9526d1942a9df047ac4`, es el corte estudiado. Su entrega está registrada en [#67](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/67), con CI canónica [34615686998](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/runs/34615686998). Esa ejecución no acredita un candidato posterior; main y release pueden diferir.

Primero se completa el inventario original→remake y se resuelven decisiones de modelo/contenido. Después se integran capacidades jugables con evidencia; finalmente se acepta y distribuye el conjunto. Se permite avanzar en paralelo sólo con archivos y contratos independientes. Cosmografía depende de catálogo, persistencia, navegación y proyecciones; plataformas e integraciones pueden validarse en paralelo sin declarar completo el núcleo. Gobernanza no bloquea esos carriles independientes.

Linux/Windows tienen líneas de empaquetado existentes. macOS/Android y Foundry real conservan sus criterios físicos. La capacidad de exportar debe estar preparada antes de comprometer la primera release de una plataforma. No se crean hitos retrospectivos vacíos, una 0.9.3 ficticia ni fechas para completar el tablero. Las releases publicadas son inmutables.

## Criterios de salida de la 1.0: G0–G3

| Gate | Evidencia del candidato exacto |
| --- | --- |
| G0 — Integridad de plataforma | Build, importación, suites, red, guardados y paquetes de cada plataforma comprometida; ningún fallo ocultado. |
| G1 — Paridad de modelo | Inventario completo del original, equivalencias y decisiones autorizadas; esquemas, dependencias, migraciones y round-trip. |
| G2 — Paridad jugable | Capacidades utilizables de punta a punta desde el standalone; positivos y negativos reproducibles, no sólo botones, modelos o pruebas de un parser. |
| G3 — Paridad de producto | Contenido/arte/audio, localización/accesibilidad, integraciones opcionales reales y validaciones físicas/humanas exigidas. |

Los gates proceden de [la revisión de #1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1#issuecomment-5622983070) y #32. No se sustituyen por las agrupaciones temáticas de milestones. La aceptación íntegra de #2–#6 y los requisitos transversales siguen vigentes; esta adopción no concede renuncias.

```sh
python3 tools/check_parity_evidence.py --require-complete --candidate SHA_COMPLETO_DEL_CANDIDATO
```

Se comprueba la cobertura y también las evidencias reales, no sólo la forma de los enlaces. `coverage.complete=false` bloquea el cierre global. Una salida estructural correcta no sustituye CI, instalación ni playtest. #29 conserva la confirmación del informante aunque pase la aceptación automatizada del ZIP.

Después de G0–G3 se revisan alcance y exclusiones, autorización de publicación, artefactos/hashes, notas y compatibilidad, instalación/recorrido y la release realmente publicada. **Ni una barra al 100 %, ni un tag, ni una suma de PRs autoriza cerrar la paridad.**

## Referencias permanentes, triaje y mantenimiento

#1/#32 conservan plan y análisis transversales; #7 sigue siendo el registro único; [#52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52) es la biblioteca permanente. No se cierran ni reasignan por esta adopción. [#56](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/56) necesita reconciliar su aceptación con los packs/laboratorios; no se declara terminado ni se le inventa versión. Los PR #69/#70 no se tratan como issues de planificación ni se atribuyen al corte 0.9.2.

La [ficha de adopción](PLATINO_ADOPTION.md) explica preview, aprobación por huella y escritor único. Cambiar alcance requiere reserva y decisión registrada. Cambiar una asignación existente se resuelve de forma explícita, no mediante heurísticas; quitarla del manifiesto no la elimina del remoto. Las fechas sólo se añaden cuando exista un compromiso real. Revertir archivos no revierte automáticamente los metadatos.
