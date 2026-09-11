# Contribuir

Este repositorio desarrolla la aplicación independiente Espaciokoop Lagunak. La simulación y el progreso deben seguir funcionando con Foundry desactivado.

Abre `game/project.godot` con Godot 4.7.1. Mantén las reglas y permisos en `game/core/`, las decisiones de sesión en `game/net/` y la presentación en `game/ui/` y `game/world/`. Un botón debe emitir una orden; no debe modificar directamente la simulación. Las misiones se validan con `Catalog.validate_mission`.

Consulta [la arquitectura](docs/ARCHITECTURE.md), [la autoría de contenido](docs/AUTHORING.md) y [los comandos de validación](docs/VALIDATION.md). Las pruebas del núcleo se usan para cambios de reglas o persistencia; las de red para autenticación y réplica; las de interfaz para pantallas y controles. CI ejecuta todas antes de publicar descargas.

Trabaja en una rama, describe el problema, el comportamiento resultante y las comprobaciones ejecutadas. Incluye capturas del juego cuando cambie la interfaz. Los modelos deben conservar su fuente Blender y actualizar el manifiesto GLB mediante el exportador. No incluyas partidas, preferencias, claves de sesión, credenciales, cachés o herramientas descargadas.

Las versiones publicadas son inmutables. Para una nueva versión, actualiza el identificador visible, el módulo, los nombres de los paquetes, las notas y el tag del flujo de publicación de forma coherente. Las contribuciones propias se incorporan bajo la licencia MIT del repositorio; cualquier recurso externo necesita procedencia y licencia explícitas.

## Coordinación, normas y entregas

Lee [AGENTS.md](AGENTS.md), [adopción de Normas Platino](docs/PLATINO_ADOPTION.md) y [roadmap](docs/ROADMAP.md). Conservamos el [plan #1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1) y el [registro único #7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7): CLAIM antes de editar, relectura inmediata y respeto a la reserva anterior. Los metadatos de milestones también necesitan un único escritor.

No hagas push directo a main ni force-push. Abre PR con issue, reserva, SHA, pruebas, límites y reversión; una autorización de merge es explícita y no se deduce de un check verde. PR_READY no libera la reserva: termina con RELEASE o conserva un checkpoint PAUSE/WAITING_ON sin caducidad por silencio.

Para validar únicamente la adopción, ejecuta `python3 tools/platino.py check .platino.json`, `python3 -m unittest discover -s docs/platino/upstream/tests -v` y `python3 -m unittest discover -s tests/platino -v`. No requieren red ni credenciales. El [procedimiento de milestones](docs/PLATINO_ADOPTION.md#sincronizar-milestones) exige preview y aprobación independiente; no modifica versiones por leer títulos ni convierte las ideas futuras en compromisos de implementación.
