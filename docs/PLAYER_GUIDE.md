# Guía de la tripulación

Espaciokoop Lagunak es un juego independiente de exploración espacial. Puedes controlar los ocho puestos en un solo equipo o compartirlos con otras personas por red. Foundry es un complemento opcional.

## Empezar

Descomprime el paquete de tu sistema y ejecuta `EspaciokoopLagunak.x86_64` en Linux o `EspaciokoopLagunak.exe` en Windows. No necesitas instalar Godot. Si tu gestor de archivos de Linux no conserva el permiso de ejecución, usa `chmod +x EspaciokoopLagunak.x86_64` en la carpeta del juego.

Pulsa **Comenzar expedición**. La primera misión explica los pasos básicos:

1. En Navegación, selecciona **Faro Argi** y activa **Piloto automático**. La nave frena al aproximarse.
2. Cambia a Sensores y analiza el faro a menos de 900 metros.
3. En Comunicaciones, selecciona **Puerto Kaia** y abre un canal.
4. En Navegación, acércate a Kaia. Atraca a menos de 190 metros y por debajo de 35 m/s.
5. Abre Campaña para instalar un refuerzo de casco o embarcar en la siguiente misión.

Lee el objetivo resaltado sobre la vista exterior. Los objetivos se completan por orden, pero las acciones realizadas previamente quedan registradas. En local puedes cambiar de puesto cuando lo necesites. Cada misión puede repetirse; sus recompensas de campaña se conceden una sola vez.

## Los ocho puestos

| Puesto | Qué hace | Coordinación útil |
| --- | --- | --- |
| Mando | Alerta y decisiones diplomáticas. | Comunicaciones debe negociar antes de una decisión. |
| Navegación | Rumbo, impulso, piloto automático, atraque y sobrealimentación. | La potencia y la integridad de motores afectan a la velocidad. |
| Ingeniería | Distribuye 8 unidades de potencia, dirige refrigeración y gestiona escudos. | Sobrepasar 95 °C daña el sistema. Reduce potencia antes de repartirla. |
| Armas | Pulsos de energía y torpedos. | Necesita un hostil identificado por Sensores. |
| Sensores | Identifica contactos en un radio de 900 m. | Un canal abierto compensa interferencias; una sonda acelera el análisis. |
| Comunicaciones | Contacta y negocia. | Negociar requiere identificación, canal abierto, escudos bajos y alcance. |
| Enlace | Sondas, rescate y recuperación de materiales. | Rescatar y recuperar requieren identificación y menos de 300 m. |
| Control de daños | Repara sistemas y estaciones. | Los drones usan 2 repuestos; reparar una estación usa 5. |

La asistencia consume 15 de energía, devuelve 15 puntos de escudo y refuerza la recarga del reactor durante ocho segundos. El casco puede reforzarse cuatro veces, por 120 créditos cada vez, tras completar una misión y atracar.

## Controles

| Entrada | Acción |
| --- | --- |
| 1–8 | Cambiar de puesto en el puente o el atlas. |
| F1 | Guía de la tripulación. |
| F5 | Guardar la campaña local. |
| F11 | Pantalla completa. |
| Rueda sobre el radar | Cambiar escala. |
| Botón derecho y ratón sobre la vista exterior | Orbitar alrededor de la nave. |
| Clic en la cubierta | Activar vista en primera persona. |
| WASD / ratón / Mayús | Caminar / mirar / correr. |
| E en cubierta | Acceder a una escotilla u operar una consola cercana. |
| Esc | Liberar el ratón o volver al inicio. |

Las escotillas del pasillo conectan los seis compartimentos. También hay traslado rápido en la lista de salas. Desde Ajustes puedes cambiar volumen, tamaño de texto, pantalla completa y movimiento decorativo.

## Jugar por red

El anfitrión abre **Sesión → Crear sesión** y comparte su dirección local, puerto UDP y clave por el medio que prefiera. Cada participante introduce esos datos, un alias y un puesto libre. La clave autentica la entrada y el anfitrión valida todas las órdenes. La conexión ENet no cifra el tráfico; para jugar a través de Internet utiliza una VPN de confianza. No se configura automáticamente el router.

La partida continúa mientras el anfitrión está conectado, incluso si abre un menú. La pausa solo está disponible en local. El anfitrión conserva el guardado y decide las misiones y mejoras. Un puesto se libera al desconectarse su ocupante. Si se cierra el anfitrión, los participantes deben volver a conectar; no hay migración automática de anfitrión.

## Guardado y datos

La campaña se guarda cada 30 segundos, al terminar una misión y al salir. El archivo anterior se conserva en `campaign.json.bak`. Continuar intenta esa copia si el guardado principal está dañado. Una nueva expedición reinicia la campaña local tras una confirmación.

Ubicación habitual de los datos:

- Linux: `~/.local/share/godot/app_userdata/Espaciokoop Lagunak/`
- Windows: `%APPDATA%\Godot\app_userdata\Espaciokoop Lagunak\`

Allí están la campaña, las preferencias y las misiones del editor. Estos archivos no se envían a servicios de nube. La red y el servidor de consulta local solo se activan desde Sesión. Las claves y los tokens no forman parte del guardado de campaña ni de las preferencias.

## Servidor sin interfaz

En Linux: `./EspaciokoopLagunak.x86_64 --headless -- --server --port 27840`.

El servidor recupera la campaña guardada o inicia una nueva. Escribe una clave nueva en `server-access.txt`, dentro del directorio local de datos; en Linux el archivo solo admite lectura y escritura de su propietario. Conserva ese archivo fuera del repositorio y comparte la clave únicamente con la tripulación.
