# Paridad funcional con el original

Referencia: [EspacioKoop/espaciokooplagunak](https://github.com/EspacioKoop/espaciokooplagunak), commit `fecd0740545f485d2402c6dfe4b47d5a859cb96c`.

**Criterio de cierre: todas las características existentes reimplementadas con código y recursos propios, accesibles desde el ejecutable autónomo. Foundry es un adaptador opcional.**

La revisión completa sigue abierta. El inventario de archivos no equivale a revisar toda la lógica. Ninguna fila pendiente es una exclusión del encargo. Esta matriz diferencia la implementación comprobada de la equivalencia todavía incompleta.

## Sistemas comprobados en esta ampliación

Las órdenes siguientes tienen controles nativos en **Puente → Operaciones** y se resuelven en el anfitrión. `tests/test_operations.gd` contiene 79 comprobaciones; las de cooperación y privacidad también se ejecutan con procesos ENet reales.

| Función observada en el original | Implementación nativa | Comprobación / alcance |
|---|---|---|
| Impulso, rumbo y warp | `simulation.gd`, `ship_operations.gd` | Movimiento, consumo, límites y niveles warp |
| Salto y maniobra lateral | `ship_operations.gd` | Carga temporal, coste, dirección y rechazo sin recursos |
| Aproximación, atraque, cancelación y desatraque | `ship_operations.gd`, `simulation.gd` | Llegada simulada a la estación y cancelación antes de amarrar |
| Potencia y distribución de refrigerante | `simulation.gd`, `ship_operations.gd` | Presupuesto compartido, calor y enfriamiento |
| Reparación automática | `ship_operations.gd` | Elección del sistema dañado y desplazamiento de equipos |
| Frecuencia y activación de escudos | `ship_operations.gd`, `simulation.gd` | Recalibración con escudos bajos y resistencia por frecuencia |
| Frecuencia de haces y blanco automático | `ship_operations.gd`, `simulation.gd` | Pulsos con gasto real, recarga, alcance e identificación |
| Tubos: guiado, nuclear, mina, EMP y HVLI | `ship_operations.gd` | Carga, descarga, inventario, daño de área, inhibición y proximidad |
| Autodestrucción coordinada | `ship_operations.gd`, `session.gd` | Tres códigos, identidad por conexión, cancelación y cuenta atrás |
| Escaneo y cancelación | `simulation.gd`, `ship_operations.gd` | Alcance, interferencias, potencia y finalización temporal |
| Base científica y descubrimientos | `ship_operations.gd` | Registro persistente de contactos identificados |
| Canal, mensajes, respuestas y cierre de comunicaciones | `ship_operations.gd` | Conversación mantenida y tregua condicionada |
| Puntos de ruta: añadir, mover, borrar y seguir | `ship_operations.gd`, `radar.gd` | Posición compartida, navegación y frenado al llegar |
| Sonda enlazada con Sensores | `simulation.gd`, `ship_operations.gd` | El origen del alcance de análisis cambia a la sonda |
| Alerta de Enlace | `simulation.gd`, `session.gd` | Orden autorizada y estado compartido |
| Equipos móviles de reparación | `ship_operations.gd` | Viaje hasta el sistema, tiempo de trabajo y consumo de repuestos |
| Asistencia de temporización | `cooperation.gd`, `assistance_console.gd` | La autoridad calcula el resultado con el reloj de simulación |
| Asistencia de secuencia | `cooperation.gd`, `assistance_console.gd` | Memorización, retirada del patrón de la vista y entradas ordenadas |
| Asistencia de precisión | `cooperation.gd`, `assistance_console.gd` | Un intento y distancia real a la diana |
| Asistencia de puzle | `cooperation.gd`, `assistance_console.gd` | Circuito generado resoluble y evaluación del patrón |
| Propuesta de asistencia consumible | `cooperation.gd` | Sin acción automática; titular, límite, caducidad y uso único |
| Ayuda narrativa | `cooperation.gd` | Bitácora sin modificar los sistemas de la nave |

Las reglas, escalas y recursos son de esta implementación nueva. Esta tabla no afirma compatibilidad de escenarios, formatos antiguos o todas las variantes del motor original. Las fuentes contrastadas para los puestos incluyen `station-actions.mjs`, `PERMISOS_PUESTO.md`, componentes nativos de escaneo y los módulos de asistencia de la referencia.

## Funciones que siguen pendientes o parciales

| Área original | Estado comprobado en el remake | Trabajo necesario para paridad completa |
|---|---|---|
| Modelo de nave | Cuatro sistemas, casco y escudo agregado | Nueve subsistemas originales, escudos segmentados, arcos de tiro, capacidades por plantilla y todas sus interacciones |
| Movimiento espacial | Impulso, warp, salto, maniobra y rutas | Marcha atrás, viraje limitado, colisiones, gravedad, agujeros de gusano y demás objetos con física |
| Inteligencia artificial y facciones | Hostiles de combate, aliados y negociación | Facciones, relaciones, órdenes de flota, comercio y comportamientos completos de IA |
| Sensores | Identificación, sondas, archivo científico y cancelación | Bandas corta/larga con filtrado completo, niveles de análisis, vista remota de sonda y minijuegos nativos de análisis/hackeo |
| Asistencia de personajes | Cuatro retos y propuestas nativas | Fichas, enfoques de habilidad, probabilidades, conjuros, rasgos y gasto de recursos de personaje |
| Mesas de ocio | Sin implementar | Póker completo, blackjack, dados de faroleo, NPC automáticos, espectadores, abandono y reconexión |
| Edición de contenido | Editor visual de misiones, JSON y prueba jugable | Editor de campañas, mapas, naves y personajes; dependencias, migraciones de formatos y catálogo completo |
| Atlas | Radar de misión y descubrimientos persistentes | Cosmografía jerárquica, HYG/Spelljammer, importación, conexiones, marcadores, mapas y navegación entre sectores |
| Dirección de juego | Editor de misiones y pausa local | Tempo del anfitrión, reposición, encuentros, convocatoria, parlamento, iniciativas, consola GM y control de escenas |
| Interiores | Siete salas recorribles, colisiones, escotillas y presencia | Geografía del original, minimapa interior, asientos, mobiliario y terminales, museo, playa, cantina, terraza, estudio y pasillo de recuerdos |
| Avatar y animación | Modelo de tripulante visible en red | Editor/asignación de avatar, retratos, poses, retargeting, mirada y progresión visual |
| Combate de personajes | Sin implementar | Arena, combate por rejilla, armas, iniciativas y cámaras POV/tercera persona/táctica |
| Campaña y contenido | Seis misiones nuevas, reputación, supervivientes, decisiones y casco | Todos los escenarios y capacidades del catálogo original, bestiario, inventario, libros, hitos y cronista |
| Arte y sonido | Veinte modelos Blender y seis sonidos propios | Recursos equivalentes del contenido pendiente, estilos de representación, registro musical procedural y gestión de audio |
| Foundry opcional | Lectura HTTP y Journal | Control por puestos, autoridad por usuario, fichas y sincronización de las demás funciones; prueba en Foundry real |
| Distribución | Linux ejecutado; Windows comprobado por CI en el primer checkpoint | macOS, Android, controles adicionales, servidor Docker y herramientas periféricas equivalentes |
| Herramientas externas | No son necesarias para la campaña nueva | Funciones del bot de Discord, netboot, gestión de packs y demás herramientas presentes en la referencia |
| Accesibilidad y configuración | Teclado, ajustes de texto/audio y movimiento reducido | Reasignación completa, mandos/táctil, idiomas y demás opciones del original |

Las variantes pendientes de una función no se consideran cubiertas por el mero hecho de tener un botón con un nombre parecido. La publicación de código y los tests de la campaña nueva tampoco cierran esta matriz.
