# Espaciokoop Lagunak 0.9.2

Actualización standalone para pruebas de jugadores en **Linux y Windows x86_64**.
Incluye las entregas posteriores a 0.9.1 descritas a continuación. **No es la
certificación de paridad total 1.0**: el plan #1 y la auditoría #32 siguen abiertos.

## Descargar y arrancar

Descargar el ZIP de la plataforma, descomprimirlo en una carpeta nueva y ejecutar
`EspaciokoopLagunak.x86_64` o `EspaciokoopLagunak.exe`. En Linux, dar permiso de
ejecución con `chmod +x EspaciokoopLagunak.x86_64` cuando sea necesario.
No hace falta instalar Godot, Foundry ni Docker para jugar.

`SHA256SUMS` permite comprobar los paquetes. En Linux: `sha256sum --ignore-missing -c
SHA256SUMS`, desde la carpeta de descargas. Foundry es un adaptador opcional y se
entrega en su ZIP separado.

## Novedades que se pueden probar en el juego

- **Terminales e interiores:** correcciones de consumo de entrada y transición
  diferida (#35/#42), con apertura, uso, cierre y reapertura comprobables. Se
  conservan pasillos y escotillas de los siete compartimentos conectados, museo,
  playa y espacios sociales. El reporte #29 conserva pendiente la confirmación
  en el equipo afectado; no se afirma haber eliminado cualquier posible crash.
- **Escuela de tripulación (#62):** primera misión guiada y ocho recorridos de
  puesto desde Puente → Asistencia entre puestos → Escuela de tripulación.
  El entrenamiento seguro de asistencia (#46) se mantiene. Usa una sesión
  desechable y no altera la campaña real.
- **Combate táctico 3D (#64):** F6 → Expedición táctica incorpora los modelos de
  tripulantes, enemigos, armas y coberturas de la biblioteca. Cámaras táctica,
  tercera persona y POV; giro, zoom, recentrado y alternativa 2D. Las reglas,
  turnos y recursos siguen siendo los existentes. Los recogibles espaciales
  también usan los modelos de caja y mineral, sin cambiar sus recompensas.
- **Dirección y autoría:** consola GM conectada al juego y selección de modelos
  espaciales (#63); taller de NPC con ficha y exportación local (#50); comparadores
  de estructura y montajes al importar diseños (#44/#49); formato y validador de
  misiones documentados (#43).
- **Dossier local de sesión (#37/#38):** exportación de crónica y resumen en
  F2 → Crónica y bestiario → Exportar sesión…, y briefing de misión desde F4.
  No es replay ni historia ilimitada.
- **Legibilidad y avisos:** tamaño de texto persistente (#39) y subtítulos de las
  cinco señales sonoras locales desde Ajustes → Subtítulos de avisos sonoros…
  (#66). Funcionan con el sonido silenciado, tienen duración configurable y no
  graban voz ni conversaciones.
- **Campaña y cooperación:** validación y migración de guardados reforzadas (#48),
  comprobaciones adicionales de identidad/privacidad (#45), alerta para entradas
  tardías y reconexiones (#40), y barrera de preparación de las pruebas ENet (#65).
  Esto no añade cifrado a ENet ni certifica redes hostiles.
- **Foundry opcional (#53):** resumen operativo y mapa relativo en su panel, con
  limpieza al desconectar. La validación manual con una instalación licenciada,
  la equivalencia completa de puestos y los modificadores dnd5e siguen pendientes.

## Biblioteca y recursos de desarrollo

Se conservan las colecciones Frontera, Órbita y Fieldkit y se incorporan **Itsasargi
con Bizi (#57)**, **ocho entornos Portu (#60)** y el **catálogo visual de 99 fichas
con foto (#61)**. Las revisiones fijas del catálogo son un corte documental, no un
recuento de todos los recursos futuros. Las fuentes Blender y sus fotografías
permanecen en el repositorio.

Los planetas Bizi y las salas Portu tienen visores/laboratorios locales; **no son
nuevos destinos de campaña con vuelo, aterrizaje o desembarco seamless**. Las
herramientas artísticas no añaden por sí solas inventario, curación o daño.

## Verificación de esta publicación

La publicación sólo se habilita tras la CI canónica del commit de `main`, con
exportación Linux/Windows, sus comprobaciones existentes y arranque Windows.
Además, la aceptación Linux **extrae el ejecutable del ZIP descargable** y ejecuta
con gráficos reales la regresión de terminales y la suite de ocio/pasillos.
No utiliza un proyecto suelto como respaldo; comprueba versión y recursos
embebidos, guarda capturas y registra el SHA-256 del paquete y del ejecutable.
Las suites se derivan de las pruebas existentes y se incorporan al mismo PCK,
verificadas por hash. Un despachador de lista cerrada sólo se activa con
`--test --release-acceptance=<fase>`; el juego normal no ejecuta las pruebas
y no se habilita la carga de scripts externos de la plantilla.

Las pruebas emplean perfiles sintéticos aislados. El posicionamiento de las
pruebas de terminales es una fixture, no un paseo humano continuo por todo el
juego. La suite de ocio sí recorre los seis enlaces físicos en ambos sentidos y
comprueba los trece destinos. Estas pruebas no sustituyen un playtest humano.

## Partidas y límites

Conservar una copia local de la partida antes de probar una actualización; no
sobrescribir la carpeta de 0.9.1. Los guardados válidos anteriores conservan las
migraciones soportadas. Los slots con nombre que aún están en desarrollo no
forman parte de este corte. No hace falta subir partidas, contraseñas o registros
personales para comunicar un fallo.

No se publican APK Android ni paquete macOS en esta versión. Continúan pendientes
catálogo y formatos originales completos, cosmografía, localización/accesibilidad
integrales, validaciones de plataformas y otros criterios de paridad. Tampoco se
anuncian vuelo 6DOF, aterrizaje seamless o rendimiento certificado por hardware.

## Qué probar primero

Caminar por la nave, abrir/usar/cerrar/reabrir terminales; después visitar museo y
playa, completar una lección, probar F6 y guardar/reabrir una campaña. En
cooperativo, comprobar entrada tardía, alerta compartida y reconexión. Ajustar los
subtítulos con el sonido silenciado. La guía detallada está en
[docs/RELEASE_0_9_2.md](https://github.com/EspacioKoop/espaciokooplagunakRemake/blob/v0.9.2/docs/RELEASE_0_9_2.md).

Para un reporte: **versión 0.9.2, sistema operativo, solo/host/cliente, pasos,
resultado esperado y observado**. Revisar las capturas antes de compartirlas para
no incluir información privada.
