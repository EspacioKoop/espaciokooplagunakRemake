# Resumen operativo en Foundry

Entrega acotada de [#32, §2.3](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32).
La aplicación standalone continúa siendo la única autoridad. Este cambio añade
presentación de sólo lectura al panel opcional existente, no otro sistema de
navegación, un Atlas ni un protocolo nuevo.

## Uso

Abre el panel **Espaciokoop Lagunak** desde el control de escena de Foundry y
conecta con el acceso público o personal ya concedido por el anfitrión. Debajo
de los indicadores de nave aparece **Resumen operativo**: alerta escrita,
sector, posición, rumbo actual/ordenado, velocidad, destino del piloto
automático y atraque. El mapa centra la nave y numera los contactos de la lista
textual inferior; X aumenta a la derecha e Y hacia abajo. No representa una
orientación astronómica ni calcula un trayecto.

Se reutiliza la consulta existente cada dos segundos. No hay suscripción
adicional, envío al pulsar el mapa, caché persistente ni almacenamiento de
credenciales nuevo. Los formularios de órdenes siguen separados y sólo ofrecen
las operaciones concedidas por el anfitrión. El cliente continúa restringido al
endpoint HTTP local ya documentado en [la integración](../integrations/foundry/README.md).

La alerta también se muestra al conectar cuando ya estaba activa. Sus palabras
no dependen del color; el lector de pantalla recibe cambios mediante una región
`status` estable, no una nueva notificación por cada consulta idéntica. El mapa
tiene alternativa textual y no añade animaciones ni controles que capturen foco.
Esto no equivale a una auditoría completa de accesibilidad de Foundry.

## Datos y límites

Los campos proceden exclusivamente de `FoundryProjection.state` y de la vista
que los clientes existentes entregan al panel. `workspace.mjs` construye otra
lista positiva para presentación; no conserva la respuesta original.

| Presentación | Campo autorizado | Ausencia o dato no válido |
|---|---|---|
| Alerta | `ship.alert`: `verde`, `ambar`, `roja` | «Alerta no publicada», nunca verde por defecto |
| Sector | `mission.sector` | «No publicado» |
| Posición y rumbo | `ship.position`, `heading`, `target_heading` | Sin mapa si falta la posición; rumbo no publicado |
| Velocidad | `ship.speed` | «No publicado», sin inventar km/h ni ETA |
| Piloto automático y atraque | `ship.autopilot`, `ship.docked` | Destino resuelto sólo contra los contactos recibidos; nunca muestra el ID bruto |
| Contactos | `contacts`, máximo 48 | Sin contacto recibido no hay marcador ni nombre recuperado de otra consulta |
| Distancia | Posiciones autorizadas de nave/contacto | Distancia geométrica local, no distancia de ruta ni tiempo de llegada |

Un contacto sólo usa el nombre recibido cuando `identified === true`; los demás
son **Eco 01**, **Eco 02**, etc., aunque una entrada malformada incluya nombre o
tipo. Un ID de destino ausente o ambiguo se presenta como «destino no visible».
No se consultan `hidden_contacts`, inventarios, fichas ajenas, secretos de misión,
bitácora ni campos adicionales para enriquecer ese nombre.

La presentación limita textos a 160 caracteres e IDs de búsqueda a 128. Acepta
sólo pares numéricos finitos con valor absoluto máximo de `1e9`; no convierte
cadenas ni `null` en cero. Los rumbos deben estar en `[0, 360)`. Son límites de
presentación defensiva, no cambios en las reglas de la simulación. Los puntos
inválidos pueden figurar en la lista como posición no publicada, sin marcador.

La escala es automática e isotrópica: el contacto más alejado en cualquiera de
los ejes queda dentro del margen punteado. El centro representa la nave; los
números remiten a la lista. Marcadores coincidentes pueden solaparse: la lista
conserva todos los contactos recibidos. La posición y la velocidad cambian con
las consultas; no se extrapolan ni interpolan entre ellas.

Los nombres se insertan con `textContent`, nunca `innerHTML`; sólo números
calculados y acotados entran en los estilos de posición. La revocación, un error
de consulta, desconectar o cerrar vacían resumen, alerta, mapa, lista y firma
temporal de presentación. Una respuesta de una conexión anterior no puede
repoblarlos tras desconectar o reconectar.

## Correspondencia con lo solicitado en #32

Esta tabla relaciona la petición del issue con su superficie de implementación;
no es un inventario exhaustivo del repositorio original.

| Capacidad solicitada en §2.3 | Implementación y estado de esta entrega |
|---|---|
| Puestos y permisos | Existentes: `FoundryClient`, autoridad por usuario del host y 13 operaciones; sin cambios |
| Estado de nave y ficha propia | Existentes en `main.mjs`; sin cambios de proyección o propiedad |
| Alerta compartida visible | Añadida en el panel; consume la alerta del host, no la decide |
| Destino y navegación | Añadidos rumbo, velocidad, posición, piloto automático y atraque publicados |
| Mapa | Añadido mapa relativo de contactos autorizados; no sustituye Atlas/cosmografía |
| Bitácora deduplicada | Existente en `newEvents` / `importJournal`; no modificada |
| ETA y objetivos detallados | Pendientes: esta proyección no proporciona esos datos; no se fabrican |
| Paridad completa de estaciones, dnd5e y efectos | Fuera de este cambio; siguen pendientes de la auditoría y de sus respectivos trabajos |
| Validación contra Foundry real | Procedimiento abajo; no se declara completada por pruebas de un DOM simulado |

El bloque de alerta ENet para entrada tardía/reconexión y el inventario global de
paridad pertenecen a otros subcarriles de #32. Esta PR no duplica sus pruebas,
no edita el núcleo Godot ni cierra #32 o #5.

## Pruebas reproducibles

Desde la raíz, con Node.js 22:

```sh
node --check integrations/foundry/main.mjs
node --check integrations/foundry/workspace.mjs
node --test integrations/foundry/tests/*.test.mjs
python3 tests/test_foundry_workspace_package.py
```

Resultado local de esta entrega con Node **v22.16.0**: **47 tests, 47 correctos,
0 fallos** (22 existentes y 25 nuevos). Los tres archivos de pruebas existentes
y `client.mjs` se verificaron contra sus blobs originales sin modificarlos.
Además pasan **2 pruebas Python de empaquetado** con los archivos reales del
módulo: dependencias, licencia, checksum, exclusión de archivos locales extra y
fallo sin sustituir paquetes anteriores cuando falta `workspace.mjs`. Son
**49 pruebas focales locales** en total; no una prueba del ejecutable del juego.

Las 25 pruebas nuevas cubren los tres niveles de alerta; datos opcionales,
malformados y no finitos; límites; ausencia de mutación; exclusión de datos
extra; ecos sin identificar; IDs ocultos/duplicados; coordenadas y alternativa
textual; inyección HTML/CSS; permisos públicos; continuidad de los formularios;
notificaciones sin repetición; cambio de misión; revocación y fallo de red;
cierre, respuesta tardía y reconexión entre dos clientes.

El workflow aditivo `foundry-workspace.yml` ejecuta todos los archivos
`*.test.mjs`, las dos pruebas del ZIP y los contratos de exportación existentes.
El empaquetador y el fixture de exportación sólo añaden `workspace.mjs` a sus
listas explícitas; no se amplía la selección a archivos locales arbitrarios.
No sustituye las pruebas HTTP/Godot ni la verificación y el
empaquetado standalone existentes.

**Límite de evidencia:** son contratos Node con `fetch` y DOM/ApplicationV2
simulados. No se han ejecutado localmente Godot, una instalación licenciada de
Foundry ni un lector de pantalla real. La prueba `live-client.mjs` existente no
forma parte del patrón `*.test.mjs` y requiere su servidor de integración.

### Comprobación manual en Foundry 13

Con una instalación autorizada y una partida standalone activa en el mismo
equipo del cliente HTTP, conceder los accesos desde el juego según la guía de
integración. Usar sólo datos de prueba, sin adjuntar tokens ni partidas privadas.

1. Cambiar la alerta en el juego antes de abrir Foundry; conectar como lector y
   comprobar que aparece el nivel actual sin enviar órdenes ni recibir permisos.
2. Con un usuario autorizado de navegación, fijar un contacto visible como
   destino; comprobar rumbo, destino, posición, marcador y lista. Confirmar que
   un eco no identificado carece de nombre real y que un destino que desaparece
   deja de mostrar su nombre en la siguiente consulta.
3. Mantener un formulario seleccionado mientras cambia la alerta o se mueve la
   nave; verificar que no pierde la selección. Redimensionar el panel y revisar
   lectura de la alerta y lista con teclado/lector de pantalla.
4. Revocar el acceso y comprobar que el resumen se vacía cuando falla la próxima
   consulta. Desconectar/reconectar y cerrar/reabrir sin conservar contactos viejos.
   Confirmar que el juego continúa funcionando sin el módulo.

Registrar por separado versión, resultado y pasos de cualquier fallo. Hasta
hacer esta comprobación no se afirma paridad de experiencia en Foundry real.
