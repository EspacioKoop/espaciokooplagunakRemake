# Contribuir

Este repositorio desarrolla la aplicación independiente Espaciokoop Lagunak. La simulación y el progreso deben seguir funcionando con Foundry desactivado.

Abre `game/project.godot` con Godot 4.7.1. Mantén las reglas y permisos en `game/core/`, las decisiones de sesión en `game/net/` y la presentación en `game/ui/` y `game/world/`. Un botón debe emitir una orden; no debe modificar directamente la simulación. Las misiones se validan con `Catalog.validate_mission`.

Consulta [la arquitectura](docs/ARCHITECTURE.md), [la autoría de contenido](docs/AUTHORING.md) y [los comandos de validación](docs/VALIDATION.md). Para la coordinación, reservas, roadmap y evidencia, consulta también [la adopción de Normas Platino](docs/NORMAS_PLATINO.md), [AGENTS.md](AGENTS.md), el [roadmap](docs/ROADMAP.md), el [plan maestro #1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1) y el [registro único #7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7). Las pruebas del núcleo se usan para cambios de reglas o persistencia; las de red para autenticación y réplica; las de interfaz para pantallas y controles. CI ejecuta todas antes de publicar descargas.

Trabaja en una rama, describe el problema, el comportamiento resultante y las comprobaciones ejecutadas. Incluye capturas del juego cuando cambie la interfaz. Los modelos deben conservar su fuente Blender y actualizar el manifiesto GLB mediante el exportador. No incluyas partidas, preferencias, claves de sesión, credenciales, cachés o herramientas descargadas. Antes de asignar milestones, revisa `.platino.json` y usa el validador en modo de vista previa; su aplicación remota requiere una aprobación explícita por huella y no debe mover asignaciones existentes.

Las versiones publicadas son inmutables. Para una nueva versión, actualiza el identificador visible, el módulo, los nombres de los paquetes, las notas y el tag del flujo de publicación de forma coherente. Las contribuciones propias se incorporan bajo la licencia MIT del repositorio; cualquier recurso externo necesita procedencia y licencia explícitas.
