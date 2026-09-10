# Espaciokoop Lagunak 0.9

Primera release pública del remake standalone. La paridad completa con el original continúa hacia 1.0; el seguimiento está en el [plan maestro](https://github.com/VaroTv7/espaciokooplagunakRemake/issues/1).

## Descargas

- **Linux x86_64:** descomprimir y ejecutar `EspaciokoopLagunak.x86_64` (dar permiso de ejecución si el descompresor lo pierde).
- **Windows x86_64:** descomprimir y ejecutar `EspaciokoopLagunak.exe`.
- **Foundry opcional:** `espaciokoop-lagunak-foundry.zip`; no hace falta para jugar ni alojar partidas.
- `SHA256SUMS` permite comprobar la integridad de los paquetes: `sha256sum -c SHA256SUMS` desde su carpeta.

Ambos ejecutables contienen los recursos y no necesitan instalar Godot. Cada paquete incluye instrucciones y licencias. La publicación requiere CI canónica completa verde, incluida ejecución Linux, pruebas de red, exportaciones y arranque automatizado Windows.

## Incluye

- Campaña y partidas locales; ocho puestos cooperativos con autoridad del anfitrión y privacidad por jugador.
- Nave recorrible sin cargas entre compartimentos, escotillas, museo, playa, cantina, terraza, estudio y galería de recuerdos.
- Física espacial, cuatro cuadrantes de escudo, armas modulares, maniobra lateral, sensores y combate táctico.
- Póker, blackjack y dados de faroleo compartidos; asientos humanos exclusivos y poses sincronizadas.
- Editores nativos de misiones, campañas, montajes de nave y fichas de personajes.
- Editor de avatar, retratos, variantes persistentes, guardianes interactivos y música procedural reactiva.
- Remapeo de controles, mando, ajustes de sensibilidad y panel de configuración ES/EN.
- Adaptador Foundry opcional con permisos por usuario y puesto.

## Límites de 0.9

El catálogo y varias funciones del original siguen pendientes; esta release no se presenta como paridad total. Android, controles táctiles, despliegue Docker, catálogo completo, funciones restantes de NPC/avatar, traducción completa y validación con Foundry real tienen seguimiento separado. macOS tiene exportador disponible, pero esta release distribuye únicamente los ejecutables Linux y Windows verificados por la CI canónica. No incluye cambios de formato incompatibles deliberados en partidas existentes.
