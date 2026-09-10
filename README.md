# Espaciokoop Lagunak

**Una nave. Ocho puestos. Un mismo destino.**

[![Verificación y descargas](https://github.com/VaroTv7/espaciokooplagunakRemake/actions/workflows/release.yml/badge.svg)](https://github.com/VaroTv7/espaciokooplagunakRemake/actions/workflows/release.yml)
[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-62ddcc)](LICENSE)

Una aplicación nativa de exploración espacial cooperativa: navega con la Itsaso, cuida sus sistemas y completa una campaña de seis misiones. Juega en solitario cambiando de puesto o reúne una tripulación por red. La campaña, el guardado, los interiores y el editor funcionan sin Foundry.

![Inicio del ejecutable de Linux](docs/images/01_inicio.png)

## Estado y ejecución

El trabajo recuperado está conservado en este repositorio. La paridad completa con
el original sigue en implementación; no se considera una entrega final mientras
queden funciones pendientes en [la matriz de paridad](docs/FEATURE_PARITY.md).
La autonomía respecto a Foundry es obligatoria para todos los sistemas.

Abre `game/project.godot` con Godot 4.7.1 y ejecuta el proyecto. El flujo de
[Actions](https://github.com/VaroTv7/espaciokooplagunakRemake/actions) comprueba el
código y prepara ejecutables Linux y Windows. Las descargas solo se anuncian
cuando están publicadas y verificadas.

Pulsa **Comenzar expedición**, selecciona Faro Argi en Navegación y activa el piloto
automático. **F1** abre la ayuda; **F5** guarda; **F11** alterna pantalla completa.

## A bordo de la Itsaso

- **Ocho puestos:** mando, navegación, ingeniería, armas, sensores, comunicaciones, enlace y control de daños. Cada orden tiene permisos, requisitos y consecuencias.
- **Seis misiones nuevas:** exploración, interferencias, rescate, combate, reparación y diplomacia. Recompensas, supervivientes, reputación y refuerzos de casco persisten entre misiones.
- **Sistemas conectados:** potencia, temperatura, refrigeración, daños, combustible, escudos, energía, sondas, torpedos y repuestos.
- **Cooperación:** sesiones ENet con clave de acceso, puestos exclusivos, órdenes validadas por el anfitrión y presencia de otros tripulantes en cubierta.
- **Interiores recorribles:** puente, pasillo central, ingeniería, camarotes, bodega, comedor y enfermería. WASD, ratón, Mayús y E para moverse e interactuar.
- **Editor integrado:** coloca contactos sobre el mapa, ordena objetivos, deshaz cambios, guarda JSON y prueba la misión con las reglas reales del juego.
- **Guardado local:** autoguardado y copia anterior, con comprobaciones de estructura e integridad.

## Capturas del juego

Estas ocho imágenes se capturaron directamente desde el ejecutable autónomo de Linux a 1600 × 900. Muestran esta implementación en ejecución.

### Puente y navegación

![Navegación, radar, objetivo y estado real de la nave](docs/images/02_puente.png)

### Ingeniería

![Potencia, refrigeración y daño causado por temperatura](docs/images/03_ingenieria.png)

### Cubierta y reactor

![Puente 3D recorrible con consolas](docs/images/04_cubierta.png)

![Sala de ingeniería modelada en Blender](docs/images/05_reactor.png)

### Atlas y campaña

![Mapa del sector y contactos identificados](docs/images/06_atlas.png)

![Las seis misiones y las mejoras de campaña](docs/images/07_campana.png)

### Taller de misiones

![Editor visual y JSON integrado](docs/images/08_editor.png)

## Modelos en Blender

Los **20 modelos** tienen [fuente editable en Blender](art/blender/lagunak_assets.blend), exportaciones GLB incluidas y [manifiesto SHA-256](game/assets/models/manifest.json). El archivo se trabaja con Blender 4.5.3 LTS. Incluye Itsaso, estación, otras naves, tripulante, mobiliario, reactor, salas y objetos del sector.

```sh
blender --background art/blender/lagunak_assets.blend --python art/blender/export_assets.py
```

[Guía de modelos, sonido y misiones](docs/AUTHORING.md).

## Foundry es un complemento

El [módulo opcional para Foundry 13](integrations/foundry/README.md) permite consultar la nave e importar su bitácora a Journal. Se activa desde Sesión con un origen permitido y un token temporal. No es necesario para jugar y no guarda la campaña.

[Manifiesto de instalación](https://raw.githubusercontent.com/VaroTv7/espaciokooplagunakRemake/main/integrations/foundry/module.json).

El servidor HTTP y el cliente tienen pruebas automatizadas; la ventana y la creación de Journal dentro de una instalación real de Foundry 13 requieren esa comprobación adicional. [Alcance de la validación](docs/VALIDATION.md).

## Ejecutar desde el código

Abre `game/project.godot` en **Godot 4.7.1** y pulsa F6 sobre `main.tscn` o F5 para ejecutar el proyecto. No hacen falta Blender ni Node para jugar: los recursos ya están exportados.

Para compilar en Linux, con Python 3.11 o posterior:

```sh
python3 tools/bootstrap.py --templates
.toolchain/godot --headless --editor --path game --quit
python3 tools/build.py
python3 tools/package_downloads.py
```

El bootstrap verifica las descargas oficiales de Godot mediante SHA-512. Los ZIP aparecen en `dist/`. CI ejecuta las pruebas de campaña, guardado, interfaz, cooperación y HTTP, exporta ambos sistemas, captura Linux y comprueba el arranque en Windows antes de publicar una versión.

Comprobaciones locales: **136 del núcleo, 39 de interfaz, 14 HTTP y 10 del cliente**, más una sesión de red con **cinco procesos reales**. [Comandos y límites](docs/VALIDATION.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Contribuir](CONTRIBUTING.md).

## Un proyecto independiente

Este repositorio tiene su propio historial y una implementación nueva en Godot. No es un fork de EmptyEpsilon y no incorpora su código, SeriousProton, escenarios Lua ni recursos heredados. Se estudió el proyecto EspacioKoop como referencia funcional: [análisis y decisiones](docs/SOURCE_REVIEW.md)..

La campaña recuperada aporta seis misiones nuevas. La cobertura de todos los sistemas y del catálogo original es un requisito pendiente, no una exclusión del proyecto. Código y recursos propios bajo [MIT](LICENSE). [Créditos y procedencia](CREDITS.md). Los avisos de Godot y sus componentes se incluyen en `third_party/` y en los paquetes descargables.
