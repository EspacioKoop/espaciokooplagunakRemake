# Espaciokoop Lagunak

**Una nave. Ocho puestos. Un mismo destino.**

[![Verificación y empaquetado](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions/workflows/release.yml)
[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-62ddcc)](LICENSE)

Juego nativo de exploración espacial cooperativa construido en **Godot**, con gestión de nave, campaña, combate táctico y espacios 3D recorribles. En solitario puedes alternar entre los ocho puestos de la **Itsaso**; en red, cada tripulante se ocupa de su estación y el anfitrión resuelve la simulación.

**Standalone-first:** jugar, guardar, editar contenido y alojar partidas no requiere Foundry, una cuenta externa ni servicios de nube. Foundry es un adaptador opcional.

[Descargar](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/latest) · [Primeros pasos](#primeros-pasos) · [Capturas](#capturas-reales) · [Documentación](#documentación) · [Plan de desarrollo](docs/ROADMAP.md) · [Normas Platino](docs/NORMAS_PLATINO.md)

![Puente tridimensional de la Itsaso, con puestos de control y espacio recorrible](docs/images/04_cubierta.png)

## Estado del proyecto

**Versión preparada: [v0.9.2](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/tag/v0.9.2), 11 de septiembre de 2026.** La publicación de los paquetes Linux/Windows está condicionada a la CI del commit final; la sección [Releases](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases) es la autoridad sobre su disponibilidad. Es una entrega para pruebas de jugadores; **la paridad funcional completa de la 1.0 sigue abierta**.

La 0.9.2 reúne correcciones de terminales, escuela de tripulación, combate táctico con modelos 3D, consola GM, taller de NPC, dossier local de sesión, subtítulos de avisos y mejoras de guardados/validación. Incluye también los recursos Itsasargi/Bizi/Portu y el catálogo visual, sin presentarlos como vuelo o aterrizaje de campaña. [Novedades y límites](docs/RELEASE_NOTES.md) · [Guía para probar la 0.9.2](docs/RELEASE_0_9_2.md).

`main` es la rama de desarrollo y puede contener cambios posteriores a los paquetes publicados. Un PR abierto, una captura o una prueba aislada no convierten una función en parte de una release. Consulta las [notas de publicación](docs/RELEASE_NOTES.md), la [matriz de paridad](docs/FEATURE_PARITY.md) y el [plan maestro](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1) para distinguir entregas, avances y pendientes.

> **Seguimiento de terminales:** las correcciones de transición de #35/#42 están incluidas, pero [#29](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/29) conserva pendiente la confirmación en el equipo afectado. La aceptación del ZIP usa pruebas gráficas y perfiles sintéticos; no sustituye esa comprobación humana.

## Descargar y ejecutar

Los paquetes incluyen el juego, sus recursos e instrucciones. **No necesitas instalar Godot, Blender ni Node.js para jugar.** Descomprime el ZIP completo antes de ejecutarlo.

| Plataforma | Paquete v0.9.2 | Ejecutable |
| --- | --- | --- |
| Linux x86_64 | [Descargar ZIP](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/download/v0.9.2/EspaciokoopLagunak-0.9.2-linux-x86_64.zip) | `EspaciokoopLagunak.x86_64` |
| Windows x86_64 | [Descargar ZIP](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/download/v0.9.2/EspaciokoopLagunak-0.9.2-windows-x86_64.zip) | `EspaciokoopLagunak.exe` |

En Linux, si se ha perdido el permiso de ejecución, abre una terminal en la carpeta descomprimida:

```sh
chmod +x EspaciokoopLagunak.x86_64
./EspaciokoopLagunak.x86_64
```

Las sumas de comprobación están en [SHA256SUMS](https://github.com/EspacioKoop/espaciokooplagunakRemake/releases/download/v0.9.2/SHA256SUMS). En Linux, desde la carpeta que contiene ese archivo y los ZIP descargados:

```sh
sha256sum --check --ignore-missing SHA256SUMS
```

Comprueba que cada paquete que vayas a utilizar aparezca como correcto; los archivos no descargados se omiten. **macOS y Android no tienen paquete en esta release**: existen herramientas de exportación y preparación, pero no deben confundirse con una distribución validada en esos dispositivos. [Estado de plataformas](docs/PLATFORM_EXPORTS.md).

## Primeros pasos

1. Pulsa **Comenzar expedición**. En **Navegación**, selecciona **Faro Argi** y activa el **Piloto automático**.
2. Cambia a **Sensores** y analiza el faro cuando estés a menos de 900 metros. Sigue el objetivo resaltado sobre la vista exterior.
3. En **Comunicaciones**, abre un canal con **Puerto Kaia**. Acércate desde Navegación y atraca a menos de 190 metros y por debajo de 35 m/s.
4. Desde **Campaña** puedes instalar mejoras y elegir la siguiente misión. **Cubierta** permite recorrer la nave; **Ajustes → Guardar partida ahora** guarda manualmente.

### Controles esenciales

| Entrada predeterminada | Acción |
| --- | --- |
| `1`–`8` | Cambiar de puesto en el puente o el atlas, sujeto a los permisos de la sesión. |
| Clic en la vista de cubierta o `C` | Controlar al personaje. |
| `WASD` + ratón | Caminar y mirar. |
| `Mayús` / `E` | Correr / interactuar con escotillas, consolas y asientos. |
| `Esc` | Liberar el ratón para volver a los menús. |
| `F1` | Abrir la guía de tripulación. |
| `F9` | Abrir controles, remapeo, sensibilidad y opciones de mando. |
| `Alt+A` | Abrir el editor de avatar. |
| `F11` | Alternar pantalla completa. |

Hay movimiento analógico con mando, navegación de menús y controles táctiles de cubierta. El panel de controles dispone de español e inglés; **esto no supone una traducción completa del juego**. [Guía de la tripulación](docs/PLAYER_GUIDE.md) · [Teclado y mando](docs/INPUT_CONTROLS.md) · [Controles táctiles](docs/TOUCH_CONTROLS.md).

## Qué puedes hacer

### Compartir el mando de la Itsaso

Ocho puestos —mando, navegación, ingeniería, armas, sensores, comunicaciones, enlace y control de daños— operan sobre una misma simulación. Gestiona potencia, calor, refrigeración, combustible, escudos y reparaciones; coordina warp, salto, rutas, atraque y equipos móviles desde **Puente → Operaciones**.

La nave dispone de **cuatro cuadrantes de escudo**, montajes y torretas configurables, distintos tipos de munición y maniobra lateral continua. La física incluye colisiones por trayectoria, gravedad, agujeros de gusano, nebulosas y objetos recogibles. Los retos cooperativos de temporización, secuencia, precisión y puzle generan propuestas de asistencia para otros puestos.

### Explorar, combatir y progresar

La campaña incorporada ofrece **seis misiones propias** de exploración, rescate, combate, reparación y diplomacia. El progreso conserva recompensas, supervivientes, reputación y mejoras. Sensores avanzados, sondas, análisis y hackeo se complementan con facciones, comercio y comportamientos estratégicos de flotas.

Las fichas de tripulación incorporan habilidades, enfoques, concentración, rasgos y progresión. El combate táctico de personajes cuenta con iniciativa, movimiento, cobertura, armas, asistencia, IA enemiga y cámaras táctica, en tercera persona y subjetiva. La cobertura detallada, incluidas las limitaciones de cada sistema, está en la [matriz de paridad](docs/FEATURE_PARITY.md).

### Recorrer la nave y sus espacios sociales

Los **siete compartimentos principales** —puente, pasillo central, ingeniería, camarotes, bodega, comedor y enfermería— se conectan físicamente mediante corredores y escotillas, sin pantallas de carga al caminar entre ellos. La cubierta dispone de un plano vivo.

Los destinos de ocio incluyen museo, playa, cantina, terraza, estudio y corredor de recuerdos. Hay esculturas propias, cuadros, un libro físico navegable, asientos interactivos, iluminación de estudio y guardianes ligados al progreso de campaña. La playa incorpora paseo, dunas y mar animado.

Las mesas ofrecen **póker Texas Hold’em, blackjack y dados de faroleo**, con NPC, espectadores, manos privadas y recuperación de asientos tras reconectar. El [editor de avatar](docs/AVATAR_CUSTOMIZATION.md) permite personalizar traje, visor y accesorios cosméticos; no concede habilidades ni permisos.

### Crear contenido desde el juego

| Herramienta | Acceso y alcance |
| --- | --- |
| Editor de misiones | **Editor**: mapa, contactos, objetivos, deshacer, JSON y prueba de la misión con las reglas del juego. |
| Taller de campañas | **Campaña → Taller de campañas**: de 1 a 24 misiones, orden, requisitos, importación/exportación y progreso persistente. [Guía](docs/CAMPAIGN_EDITOR.md). |
| Editor de personajes | Desde la ficha de tripulación: edición e importación/exportación de plantillas sin sustituir la progresión. [Guía](docs/CHARACTER_EDITOR.md). |
| Astillero y montajes | **Editor → Diseñar nave**: estructura, capacidades, variantes y configuración del armamento. [Montajes](docs/LOADOUT_EDITOR.md) · [Plantillas](docs/SHIP_TEMPLATES.md). |

Estos editores usan formatos nativos del remake. **No se anuncia compatibilidad general con todos los formatos ni con el catálogo del proyecto original.**

## Capturas reales

Selección de imágenes ya versionadas del juego y sus herramientas. Se obtuvieron en distintas revisiones durante el desarrollo: **no son renders promocionales ni capturas nuevas de esta actualización documental**. La interfaz, los textos de versión y la distribución pueden diferir de la revisión que estés ejecutando.

La galería incorpora ahora las capturas de los editores de campañas, personajes y avatar, además de los guardianes del corredor, que no figuraban en el README anterior. Su contexto se conserva en las guías de cada función.

| Puente y navegación | Ingeniería |
| --- | --- |
| ![Consola de navegación con radar, objetivos y estado de la nave](docs/images/02_puente.png) | ![Panel de ingeniería con potencia, refrigeración y temperatura](docs/images/03_ingenieria.png) |

| Museo | Playa |
| --- | --- |
| ![Sala del museo con esculturas originales del remake](docs/images/12_museo.png) | ![Paseo de la playa, dunas, mar y aerogeneradores](docs/images/14_playa.png) |

| Taller de campañas | Editor de personajes |
| --- | --- |
| ![Editor nativo de campañas con organización de misiones](docs/images/campaign-editor.png) | ![Editor nativo de la ficha de tripulación](docs/images/character-editor.png) |
| [Campañas y dependencias](docs/CAMPAIGN_EDITOR.md) | [Edición e importación de fichas](docs/CHARACTER_EDITOR.md) |

| Personalización del avatar | Guardianes y recuerdos |
| --- | --- |
| ![Editor de apariencia con retrato tridimensional del tripulante](docs/images/avatar-editor.png) | ![Guardiana y centinelas del corredor de recuerdos](docs/images/memory-guardians.png) |
| [Apariencia y persistencia](docs/AVATAR_CUSTOMIZATION.md) | [Galería ligada a la campaña](docs/MEMORY_GUARDIANS.md) |

<details>
<summary>Ver más capturas: reactor, atlas, editores, asistencia y espacios de ocio</summary>

| Reactor | Atlas del sector |
| --- | --- |
| ![Interior de la sala de ingeniería y reactor](docs/images/05_reactor.png) | ![Mapa sectorial con contactos](docs/images/06_atlas.png) |

| Campaña incorporada | Editor de misiones |
| --- | --- |
| ![Selección de misiones y mejoras de campaña](docs/images/07_campana.png) | ![Editor visual de misión con documento JSON](docs/images/08_editor.png) |

| Operaciones | Asistencia cooperativa |
| --- | --- |
| ![Consola de operaciones de ingeniería](docs/images/09_operaciones.png) | ![Puzle nativo de asistencia entre puestos](docs/images/10_asistencia.png) |

| Astillero | Libro del museo |
| --- | --- |
| ![Editor de capacidades de nave](docs/images/11_astillero.png) | ![Lectura del libro tridimensional del museo](docs/images/13_libro.png) |

| Cantina | Terraza |
| --- | --- |
| ![Cantina y acceso a las zonas sociales](docs/images/15_cantina.png) | ![Terraza con mesas y asientos](docs/images/16_terraza.png) |

| Estudio | Corredor de recuerdos |
| --- | --- |
| ![Escenario del estudio con focos de colores](docs/images/17_estudio.png) | ![Recorrido por el corredor de recuerdos](docs/images/18_recuerdos.png) |

| Mesa de póker | Inicio |
| --- | --- |
| ![Mesa de póker con mano privada y apuestas](docs/images/19_poker.png) | ![Pantalla inicial del ejecutable standalone](docs/images/01_inicio.png) |

</details>

## Cooperativo, guardado e integración opcional

**Partidas en red.** El anfitrión abre **Sesión → Crear sesión** y comparte dirección, puerto UDP —`27840` por defecto— y clave por un canal privado. Los participantes eligen un puesto libre. La campaña permanece en el equipo anfitrión; no hay migración automática del host. La aplicación autentica la entrada con una clave, pero **ENet no cifra el transporte**: no trates la clave de acceso como una garantía de confidencialidad del tráfico. Para jugar fuera de una red de confianza, utiliza una VPN adecuada. [Guía de red](docs/PLAYER_GUIDE.md).

**Guardado local.** Hay autoguardado de campaña, guardado manual y copia anterior `campaign.json.bak`. Las preferencias y el avatar se mantienen localmente. Para comunicar un fallo, comparte únicamente la información necesaria y revisa capturas y registros antes de publicarlos.

**Servidor dedicado.** El repositorio incluye un anfitrión sin interfaz y despliegue opcional con Docker/Compose, autenticación y almacenamiento persistente. Sigue la [guía de servidor dedicado](docs/DEDICATED_SERVER.md) para configurar la clave fuera del repositorio y el volumen de datos.

**Foundry 13.** El [adaptador opcional](integrations/foundry/README.md) ofrece consulta de nave y bitácora, ficha propia y órdenes básicas según los permisos concedidos por el anfitrión. No sustituye la simulación ni el guardado. El navegador debe ejecutarse en el mismo equipo que el host de Lagunak; no hay un relé remoto incorporado. La validación dentro de una instalación real de Foundry sigue pendiente y se distingue de las pruebas automatizadas de cliente, HTTP y autoridad. [Instalación y límites](integrations/foundry/README.md) · [Contrato de permisos](docs/FOUNDRY_AUTHORITY.md).

## Desarrollar y crear recursos

### Ejecutar desde el código

La versión de herramientas fijada por el proyecto es **Godot 4.7.1**; [export_targets.py](tools/export_targets.py) es la referencia para versiones y destinos. Abre `game/project.godot` con el editor y ejecuta el proyecto. Los recursos necesarios ya están exportados.

En un equipo de desarrollo **Linux x86_64**, con Git y **Python 3.11 o posterior**:

```sh
git clone https://github.com/EspacioKoop/espaciokooplagunakRemake.git
cd espaciokooplagunakRemake
python3 tools/bootstrap.py
.toolchain/godot --headless --editor --path game --quit
.toolchain/godot --path game
```

El bootstrap descarga el editor oficial fijado y comprueba su SHA-512. Para exportar y empaquetar los destinos predeterminados, Linux y Windows:

```sh
python3 tools/bootstrap.py --templates
python3 tools/build.py
python3 tools/package_downloads.py
python3 tools/verify_artifacts.py
```

Los paquetes se generan en `dist/`. El bootstrap del editor está orientado a Linux x86_64; los demás destinos y requisitos específicos se describen en [Exportación por plataforma](docs/PLATFORM_EXPORTS.md).

### Modelos editables en Blender

Las fuentes propias están preparadas en **Blender 4.5.3 LTS**. El repositorio incluye tres conjuntos editables: [nave, tripulante y salas base](art/blender/lagunak_assets.blend), [museo, playa y ocio](art/blender/leisure_assets.blend) y [guardianes del corredor](art/blender/memory_guardians.blend). Blender sólo es necesario para modificar o reexportar esos recursos, no para jugar.

```sh
blender --background art/blender/lagunak_assets.blend --python art/blender/export_assets.py
blender --background art/blender/leisure_assets.blend --python art/blender/export_leisure.py
blender --background art/blender/memory_guardians.blend --python art/blender/export_memory_guardians.py
```

Las esculturas son interpretaciones estilizadas originales, no escaneos ni reconstrucciones arqueológicas fieles. [Autoría de modelos, sonido y misiones](docs/AUTHORING.md) · [Audio reactivo](docs/REACTIVE_AUDIO.md) · [Créditos](CREDITS.md).

### Pruebas y contribución

El [workflow canónico](.github/workflows/release.yml) comprueba campaña, guardados, operaciones, física, sensores, tripulación, combate, flotas, red con procesos reales, HTTP, interfaz, interiores y mesas. También exporta aplicaciones, captura el ejecutable Linux y comprueba el arranque de Windows. Otros workflows cubren áreas específicas.

Los resultados se consultan **por commit** en [Actions](https://github.com/EspacioKoop/espaciokooplagunakRemake/actions); esta página no sustituye los registros de CI ni da por aprobada una revisión nueva. [Comandos y límites de validación](docs/VALIDATION.md).

Antes de contribuir, lee [CONTRIBUTING.md](CONTRIBUTING.md) y [AGENTS.md](AGENTS.md). El trabajo paralelo se coordina mediante reservas en [#7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7), ramas propias y PR hacia `main`.

## Documentación

| Para… | Referencias |
| --- | --- |
| Jugar y configurar controles | [Guía de tripulación](docs/PLAYER_GUIDE.md) · [Teclado y mando](docs/INPUT_CONTROLS.md) · [Táctil](docs/TOUCH_CONTROLS.md) |
| Crear misiones, campañas y naves | [Autoría](docs/AUTHORING.md) · [Campañas](docs/CAMPAIGN_EDITOR.md) · [Montajes](docs/LOADOUT_EDITOR.md) · [Plantillas](docs/SHIP_TEMPLATES.md) |
| Editar tripulación y apariencia | [Personajes](docs/CHARACTER_EDITOR.md) · [Avatares](docs/AVATAR_CUSTOMIZATION.md) |
| Alojar o integrar una partida | [Servidor dedicado](docs/DEDICATED_SERVER.md) · [Foundry](integrations/foundry/README.md) |
| Entender y verificar el proyecto | [Arquitectura](docs/ARCHITECTURE.md) · [Validación](docs/VALIDATION.md) · [Plataformas](docs/PLATFORM_EXPORTS.md) |
| Seguir las entregas y lo pendiente | [Notas de versión](docs/RELEASE_NOTES.md) · [Paridad](docs/FEATURE_PARITY.md) · [Plan maestro](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1) |

### Hacia la 1.0

Permanecen abiertos bloques de cosmografía y navegación entre sistemas, catálogo y formatos originales, funciones restantes de dirección y personajes, variantes de NPC y arte, integración remota y validación real de Foundry, traducción completa, accesibilidad y validación de plataformas adicionales. El seguimiento técnico vive en [#1](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/1), [#32](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32) y la [matriz de paridad](docs/FEATURE_PARITY.md), no en una promesa de cobertura total.

Para [informar de un fallo](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues), indica versión o SHA, sistema operativo, modo local/anfitrión/cliente, pasos de reproducción y resultado esperado y observado. No publiques contraseñas, tokens, partidas completas ni datos personales para un primer diagnóstico.

## Independencia, licencia y procedencia

Implementación nueva en Godot, con historial, código y recursos propios. **No es un fork de EmptyEpsilon** y no incorpora su código, SeriousProton, escenarios Lua ni recursos heredados. El proyecto original EspacioKoop se estudia como referencia funcional: [análisis y decisiones](docs/SOURCE_REVIEW.md).

Código y recursos propios bajo [licencia MIT](LICENSE). Consulta [CREDITS.md](CREDITS.md) para la procedencia y los avisos de terceros incluidos en los paquetes. La independencia técnica no elimina el objetivo de paridad: las capacidades pendientes siguen formando parte del plan de trabajo.

<!-- Revisión documental: 2026-09-10. Fuentes: release v0.9.1 (cddb1d63d3f5022bceec156f183489092019add7), main 8b1dcf27683a00972b03d5203606eab12f31fe2d, AGENTS.md, issues #1/#7/#29, código de app, herramientas y guías enlazadas. Las 23 capturas ya existían en docs/images; esta revisión no genera capturas ni declara nuevas pruebas de ejecución. -->
