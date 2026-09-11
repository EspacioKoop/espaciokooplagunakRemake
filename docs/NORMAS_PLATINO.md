# Adopción de Normas Platino

Esta ficha adapta las Normas Platino al remake de Espaciokoop Lagunak. No sustituye `AGENTS.md`, la matriz de paridad ni las decisiones del equipo: añade un protocolo común de coordinación, entregas y evidencia.

| Campo | Decisión del proyecto |
| --- | --- |
| Proyecto | `EspacioKoop/espaciokooplagunakRemake` |
| Normas adoptadas | `EspacioKoop/normas_platino@b5e01a2b2060a31268507797708a92a7d14ffc52` (revisión 2026-09-11) |
| Copia reproducible | `docs/normas-platino/`, `scripts/platino.py`, `tests/test_platino.py` |
| Instrucciones locales | `AGENTS.md`, `CONTRIBUTING.md`, `docs/FEATURE_PARITY.md` |
| Plan maestro | [Issue #1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1) |
| Registro de reservas | [Issue #7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7) |
| Roadmap | [`docs/ROADMAP.md`](ROADMAP.md) |
| Milestones | `.platino.json`; activas en GitHub: 1.0 — Paridad funcional (#29, #32), Cosmografía y navegación (#56, #59), Contenido y catálogo (#2, #3, #6, #52), Plataforma y publicación (#4, #5, #30) |
| Rama base | `main`; las entregas ordinarias llegan mediante PR |
| Pruebas canónicas | `release.yml`, `python3 -m unittest discover -s tests -v`, `git diff --check` |
| Merge y publicación | según autorización registrada en el issue #7 y revisión del PR |
| Fronteras de datos | no incluir secretos, credenciales, tokens, cookies ni datos personales; preferencias y guardados del juego permanecen locales |

## Adaptaciones propias del remake

- Se conserva el protocolo de reservas y PR de `AGENTS.md`; las Normas Platino no autorizan a saltárselo.
- Godot, el host autoritativo, Foundry opcional, Atlas y las rutas del juego siguen siendo decisiones locales, no obligaciones generales.
- La sincronización de milestones es opt-in y sólo se ejecuta de forma explícita con un manifiesto revisado. No borra, cierra ni reasigna automáticamente trabajo existente.
- Un release o milestone sólo se considera cerrado con la evidencia definida en sus criterios; un botón, un documento o un porcentaje no bastan.
