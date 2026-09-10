# Variantes de nave en el astillero

En el editor de misiones, abre **Diseñar nave**, elige una variante y pulsa **Cargar variante**. Esto reemplaza estructura y montajes del borrador; **Aplicar diseño a la misión** confirma ambos. Se pueden modificar, exportar/importar como nave JSON v2 y guardar con la misión. Al jugar, Session y ShipArmaments aplican las capacidades, alcance, arco, daño y recarga; el guardado conserva también las recargas activas.

## Fuente y alcance

Datos numéricos contrastados con `EspacioKoop/espaciokooplagunak@fecd0740545f485d2402c6dfe4b47d5a859cb96c`, `scripts/shipTemplates.lua` y `scripts/shiptemplates/*.lua`. El cargador también incluye `OLD.lua`. No se incorporan código Lua, textos descriptivos, mallas ni otros recursos originales.

`game/data/ship_templates.json` registra archivo, línea de declaración, variante base y valores efectivos tras las copias. Son 38 configuraciones adaptadas, no paridad íntegra de esas naves:

- Hornet: MT52, MU52, MP52; Adder MK3–MK9; ANT 615.
- Phobos T3, M3, M3P; Elara P2; Nirvana R3, R5, R5A; Storm, Hathcock; Stalker Q5, R7; Flavia Falcon y P.Falcon.
- Atlantis, Crucible; Dagger, Blade, Gunner, Shooter, Jagger, Racer, Hunter, Strike, Dash.
- Karnack, Adv. Striker y Blockade Runner del catálogo antiguo visible.

## Correspondencia y límites concretos

| Dato original | Aplicación actual |
| --- | --- |
| Casco, impulso, viraje, aceleración | Valores originales, sin escalar ni recortar. |
| Dos sectores de escudo | Proa y popa con sus capacidades originales. |
| Un escudo omnidireccional | Se conserva capacidad total dividiéndola por igual entre proa y popa; su geometría y absorción direccional cambian. |
| `setBeam` / `setBeamWeapon` | Un montaje por índice activo, con arco, dirección, alcance, daño y ciclo originales. Las bajas con arco/alcance cero eliminan ese montaje heredado. |
| Munición | Capacidades declaradas y heredadas para los cinco tipos actuales; tipos ausentes empiezan en cero. Los tubos originales no se reproducen. |
| Warp declarado | Velocidad original; sin declaración se desactiva. |
| Haz frontal antiguo del remake | Desactivado para evitar añadir un arma extra a los montajes de la variante. |

Los valores nativos auxiliares **no son datos de paridad**: marcha atrás 0,5, radio 22 m, alcance de misiles 1600 m y gasto de energía 10 por montaje. No hay equivalencia completa de consumo, calor, energía máxima o regeneración. El salto se desactiva: estas declaraciones no proporcionan una distancia directamente representable por el diseño actual. Se mantienen los interiores y sistemas comunes del remake.

No se representan número/dirección/tamaño/exclusividad/recarga de tubos, giro de torretas independiente de su cono de disparo, habitaciones/puertas/reparadores originales, depósitos de energía distintos, impulso lateral y maniobra por plantilla, clases/capacidad de atraque o transporte, sensores/radar por plantilla, ni geometría/modelos. `unsupported` identifica los métodos adicionales presentes en cada variante, incluida su herencia. Los valores de capacidades auxiliares no se deducen de descripciones.

El catálogo excluye configuraciones ocultas, sin capacidades base explícitas, sin haces, con más de ocho montajes, torretas orientables, más de dos escudos o prestaciones fuera de los límites actuales; `excluded` lista las 60 declaraciones nominales examinadas que no se ofrecen y sus motivos. Tampoco se incluyen los cargueros generados mediante bucles/expresiones dinámicas ni se afirma que ese listado sea el total de plantillas del original. No se agregan montajes ficticios ni se recortan rangos para admitir una nave.

## Prueba esencial

`godot --headless --path game --script ../tests/test_armaments.gd -- --test`

La suite canónica existente ejecuta además `test_ship_templates.gd`: las 38 configuraciones y sus documentos JSON, herencia numérica conocida, límites negativos, selector y aplicación conjunta, disparo real, autorización y guardado/recarga con cooldown activo.
