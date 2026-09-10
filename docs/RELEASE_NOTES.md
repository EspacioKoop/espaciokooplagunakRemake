# Espaciokoop Lagunak 0.9.1

Actualización standalone para pruebas de jugadores. **La paridad total de 1.0 sigue en desarrollo** y se documenta en el [plan maestro](https://github.com/VaroTv7/espaciokooplagunakRemake/issues/1).

## Descargas y arranque

- Linux x86_64: descomprimir y ejecutar `EspaciokoopLagunak.x86_64`; si hace falta, `chmod +x EspaciokoopLagunak.x86_64`.
- Windows x86_64: descomprimir y ejecutar `EspaciokoopLagunak.exe`.
- Foundry es opcional; no se necesita para jugar ni alojar partidas.
- Verificación: descargar también `SHA256SUMS` y ejecutar `sha256sum -c SHA256SUMS` desde la carpeta de los paquetes.

Los paquetes incluyen recursos, instrucciones y licencias; no requieren instalar Godot. La publicación exige la CI conjunta verde, incluida exportación y arranque Linux/Windows.

## Cambios desde 0.9

- Controles táctiles de movimiento, cámara, interacción y menús. Se activan automáticamente en dispositivo táctil o desde el panel F9 para pruebas en escritorio.
- Servidor dedicado opcional con Docker/Compose, anfitrión observador, autenticación y guardado persistente. Instrucciones reproducibles en `docs/DEDICATED_SERVER.md` del repositorio.
- Suministros y artefactos recogibles por colisión, con recursos limitados, objetivos y consumo persistente, también en red.
- Selector de 38 variantes adaptadas de nave en el astillero; aplica diseño y montajes. Las conversiones y atributos originales todavía no representables se detallan en `docs/SHIP_TEMPLATES.md`.

## Qué probar y cómo comunicar un fallo

Prueba los desplazamientos entre compartimentos y las escotillas, los editores, una partida guardada y una sesión cooperativa. Anota **versión0.9.1, sistema operativo, modo solo/host/cliente, pasos, resultado esperado y resultado observado**. Una captura del fallo ayuda; revisa antes que no incluya datos privados. No hace falta compartir contraseñas ni partidas completas para un primer informe.

Los cambios conservan las partidas anteriores cuando su contenido sigue siendo válido. La validación física en Android/macOS, el catálogo completo y formatos originales, idiomas y otros apartados de la paridad permanecen pendientes. No se anuncian APK ni paquete macOS en esta release.
