# Exportar Linux, Windows, macOS y Android

El exportador reproducible usa Linux x86_64, Python 3.11+ y Godot **4.7.1**.
El juego exportado sigue siendo standalone. No necesita Foundry, Docker ni el editor.
Los comandos sin opciones siguen creando Linux y Windows, con los mismos nombres
que consume `release.yml`. Los destinos adicionales se solicitan explícitamente:

```sh
python3 tools/bootstrap.py --templates --targets linux windows macos android
.toolchain/godot --headless --editor --path game --quit
python3 tools/build.py --targets linux windows macos
python3 tools/package_downloads.py --targets linux windows macos
(cd dist && sha256sum -c SHA256SUMS)
```

`GODOT=/ruta/al/editor` permite usar otro binario de la misma versión. El bootstrap
verifica SHA-512 oficial y extrae sólo las plantillas seleccionadas. Con
`--templates-only` conserva el editor existente. `build.py --check --targets macos`
comprueba configuración y toolchain sin descargar ni exportar. Un fallo no publica
un nuevo ejecutable ni sustituye el último paquete válido. El código de salida es
no cero si Godot informa errores, falta un requisito o el artefacto es inválido.

| Destino | Exportación en `build/` | ZIP descargable en `dist/` |
|---|---|---|
| Linux x86_64 | `linux/EspaciokoopLagunak.x86_64` | `EspaciokoopLagunak-1.0.0-linux-x86_64.zip` |
| Windows x86_64 | `windows/EspaciokoopLagunak.exe` | `EspaciokoopLagunak-1.0.0-windows-x86_64.zip` |
| macOS Universal 2 | `macos/EspaciokoopLagunak.zip` | `EspaciokoopLagunak-1.0.0-macos-universal.zip` |
| Android release | `android/EspaciokoopLagunak.apk` | `EspaciokoopLagunak-1.0.0-android-arm64-x86_64.zip` |
| Android debug | `android/EspaciokoopLagunak-debug.apk` | `EspaciokoopLagunak-1.0.0-android-arm64-x86_64-debug.zip` |

Cada ZIP incluye licencia, créditos y guía. El paquete macOS contiene directamente
la `.app` con sus permisos y firma conservados. `SHA256SUMS` describe exclusivamente
los paquetes de la última invocación; no anuncia archivos anteriores de `dist/`.
`--skip-foundry` omite el adaptador opcional. Empaquetar nunca escribe sus fuentes.

## macOS

El preset incluye Intel x86_64 (macOS 11+) y Apple Silicon arm64 (macOS 13+), ID
`org.espaciokoop.lagunak`, recursos del juego y firma **ad-hoc** integrada de Godot.
El validador comprueba plist, ambos CPU, permiso de ejecución, PCK y firma de recursos.
La firma ad-hoc no es Developer ID ni notarización. Este paquete es para pruebas y
distribución manual: Gatekeeper puede bloquear una descarga. Una publicación de
confianza requiere certificado Developer ID, notarización y validación en macOS,
como explica [Godot](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html).
No se incluyen certificados ni se declara el paquete apto para App Store.

Tras descomprimir en un Mac, ejecutar la `.app` prueba la UI. Para una comprobación
reproducible del motor, desde el directorio descomprimido:

```sh
codesign --verify --deep --strict --verbose=2 EspaciokoopLagunak.app
EspaciokoopLagunak.app/Contents/MacOS/EspaciokoopLagunak --headless --audio-driver Dummy --quit-after 60 -- --test
```

Una exportación válida desde Linux no demuestra por sí sola arranque en macOS.

## Android

Se exporta APK firmado para instalación directa, ARM64 y x86_64, Android 7/API 24+
con target API 35, permiso de Internet para ENet/HTTP y copia de datos desactivada.
El preset usa plantillas APK oficiales sin Gradle; no genera AAB ni anuncia una
publicación en Google Play. No presupone que el resto de la interfaz ya tenga
paridad táctil: los controles y su validación de dispositivo pertenecen al otro
subcarril de #4.

Instalar OpenJDK 17 y el SDK oficial según [Godot](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html).
Para este flujo de APK sin Gradle son necesarios:

```sh
export JAVA_HOME=/ruta/al/jdk-17
export ANDROID_HOME=/ruta/al/android-sdk
sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" "build-tools;35.0.1" "platforms;android-35"
python3 tools/build.py --targets android --android-debug --check
python3 tools/build.py --targets android --android-debug
python3 tools/package_downloads.py --targets android --android-debug --skip-foundry
"$ANDROID_HOME/platform-tools/adb" install -r build/android/EspaciokoopLagunak-debug.apk
"$ANDROID_HOME/platform-tools/adb" shell am start -n org.espaciokoop.lagunak/com.godot.game.GodotApp
```

`ANDROID_SDK_ROOT` también se acepta si no se define `ANDROID_HOME`. Los ajustes de
exportación se aíslan para no sustituir los del editor del usuario. Godot genera su
clave de debug local sólo para `--android-debug`; ese APK tiene nombre distinto.
Para release, configurar fuera del repositorio estas tres variables y omitir
`--android-debug` tanto al compilar como al empaquetar:

- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`: ruta absoluta a un keystore existente.
- `GODOT_ANDROID_KEYSTORE_RELEASE_USER`: alias de su clave.
- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`: contraseña suministrada mediante un
  gestor de secretos o entorno seguro; no escribirla en comandos, presets ni logs.

La contraseña del almacén y la clave debe coincidir. `keytool` comprueba el alias
antes de exportar; `apksigner verify` verifica cada APK resultante. La validación de
estructura comprueba manifiesto, código Java, las dos bibliotecas nativas y datos
Godot. El release nunca se degrada silenciosamente a debug si falta la firma.
Instalar un APK con otra firma sobre el mismo ID requiere desinstalar el anterior;
conservar antes los guardados que se necesiten.

## Pruebas y límites

```sh
python3 tests/test_platform_exports.py
python3 tools/build.py --targets macos --check
python3 tools/build.py --targets android --android-debug --check
```

Las pruebas de Python cubren selección/defaults, presets, SDK/JDK/firma ausentes,
secretos fuera de argumentos, rechazo de archivos inválidos, permisos del bundle,
ZIPs inseguros y empaquetado con checksums sin modificar Foundry. Las fixtures son
pruebas del validador, no pruebas de que esos ficheros sean aplicaciones ejecutables.
`build.py` ejecuta esa suite antes de exportar: también queda dentro de la CI
canónica que ya llama al comando, sin modificar `release.yml`.
Los exportadores reales y su smoke de cada plataforma se registran por separado en
el PR. Sin SDK, Mac o dispositivo/emulador no se declara comprobado su arranque.
