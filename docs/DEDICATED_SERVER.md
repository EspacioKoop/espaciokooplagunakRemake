# Servidor dedicado opcional

El servicio ejecuta la misma `Session` y simulación del juego standalone, sin ventana,
como anfitrión observador. Los ocho puestos quedan disponibles para clientes nativos
de la misma versión. Docker y Foundry siguen siendo opcionales: este despliegue no
requiere Foundry, no activa telemetría ni publica HTTP. La campaña vive en el servidor.

## Arranque con Docker Compose

Requiere Docker Engine con Compose v2 y un host Linux x86_64 (la imagen es
`linux/amd64`). Ejecuta desde la raíz del repositorio:

```sh
mkdir -m 700 "$HOME/lagunak-server-secrets"
python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > "$HOME/lagunak-server-secrets/session-key"
chmod 444 "$HOME/lagunak-server-secrets/session-key"
export LAGUNAK_KEY_FILE="$HOME/lagunak-server-secrets/session-key"
docker compose up --build -d --wait
docker compose logs --tail 20
```

Conserva el directorio de claves con permiso **0700**: protege el archivo en el host
mientras el archivo montado es legible para el UID 10001 del contenedor. Compose
monta los secretos basados en archivos sin remapear su propietario o permisos;
un archivo 0600 de otro UID no sería legible. No guardes la clave en el repositorio
ni la pegues en comandos, imágenes o configuración versionada. Entrégala a los
participantes por un canal privado para introducirla en «Unirse».

Por defecto sólo publica `127.0.0.1:27840/udp`. Para clientes de la LAN, establece
`LAGUNAK_BIND_ADDRESS` a la IP LAN del host y permite ese puerto UDP en el firewall.
`LAGUNAK_HOST_PORT` cambia el puerto exterior; el interior permanece en 27840.
El protocolo ENet existente autentica con clave compartida; no ofrece cifrado del
tráfico. Para acceso por Internet utiliza una red privada/VPN y comparte la clave
sólo con los jugadores autorizados.

## Campaña y parada

El volumen nombrado `lagunak-data` contiene todo `user://` bajo `/var/lib/lagunak`:
campaña, copia de recuperación y datos de expedición. El servicio usa UID/GID
10001, raíz de sólo lectura y `/tmp` efímero. La salud comprueba un latido interno
del proceso anfitrión; no abre otro puerto ni devuelve fichas o secretos.

```sh
docker compose stop
docker compose up -d --wait
```

SIGTERM solicita guardado de campaña y expedición antes de salir. Compose espera
20 segundos; el supervisor limita la espera limpia a 12 segundos y devuelve error
si no termina. Session conserva su autoguardado existente. `docker compose down`
mantiene el volumen; **`down --volumes` elimina la partida**. Haz las copias del
volumen con el servidor detenido. Si la campaña y su respaldo están dañados o la
expedición no es válida, se rechaza el arranque y se conservan los archivos para
restaurar una copia. No se crea silenciosamente una campaña sustitutiva.

| Variable | Valor por defecto | Comportamiento |
| --- | --- | --- |
| `LAGUNAK_KEY_FILE` | Obligatoria en Compose | Ruta absoluta al archivo externo, 16–128 caracteres ASCII visibles; admite salto final. |
| `LAGUNAK_LOAD_MODE` | `auto` | Reanuda si hay guardado; crea si no existe. `resume` exige guardado; `new` exige volumen sin campaña. |
| `LAGUNAK_MISSION_INDEX` | `-1` | Conserva la misión. Un índice de catálogo 0–255 selecciona sólo una misión desbloqueada al arrancar. |
| `LAGUNAK_BIND_ADDRESS` | `127.0.0.1` | Interfaz de publicación UDP en el host Docker. |
| `LAGUNAK_HOST_PORT` | `27840` | Puerto UDP exterior. |

Para pasar a otra misión desbloqueada, detén el servicio, cambia
`LAGUNAK_MISSION_INDEX` y recrea con `docker compose up -d --wait`. La numeración es
la del catálogo de campaña, empezando por 0. Este adaptador no añade administración
remota, selección de campaña desde clientes ni avance automático entre misiones.
La pertenencia de fichas conserva las identidades de conexión del protocolo nativo;
no introduce cuentas persistentes. Foundry remoto y su autenticación entre máquinas
quedan fuera de este servicio; no publiques el HTTP de loopback mediante un proxy.

## Sin contenedor y comprobaciones

Con Python 3.11+ y el Godot indicado por `tools/bootstrap.py`, importa `game` y usa:

```sh
export GODOT="$PWD/.toolchain/godot"
export XDG_DATA_HOME="$PWD/server-data"
export LAGUNAK_RUNTIME_DIR="/tmp/lagunak-runtime"
export LAGUNAK_KEY_FILE="$HOME/lagunak-server-secrets/session-key"
python3 server/launch.py
```

Los directorios deben ser absolutos y escribibles. `LAGUNAK_PORT` configura el
puerto de este arranque directo (1024–65535). No ejecutes dos servidores sobre el
mismo directorio de datos o ejecución.

Pruebas: `python3 -m unittest discover -s tests -p test_server_config.py`,
`python3 tests/run_dedicated_server.py` y, con Docker instalado,
`python3 tests/smoke_docker.py`. La última construye y arranca Compose realmente,
conecta clientes Godot, comprueba credencial incorrecta, autoridad, cierre y
reanudación del mismo estado, configuración inválida y aislamiento básico.
La CI `Dedicated server Docker` ejecuta las tres. El entorno de desarrollo del
autor no tiene Docker; la prueba del contenedor se ejecuta en CI Linux. No se ha
probado Docker Desktop, ARM ni un servidor Foundry licenciado.

Referencia de permisos de secretos:
https://docs.docker.com/reference/compose-file/services/#secrets
