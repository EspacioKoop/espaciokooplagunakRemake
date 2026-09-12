# Comprobar las descargas realmente publicadas

Complemento de sólo lectura para #67. **No publica, no integra PR, no ejecuta el juego y no sustituye las pruebas de terminales de la exportación.** Contrasta los ZIP que descarga una persona con los archivos del artefacto `standalone-downloads` de la CI canónica aprobada.

## Uso

Ejecutar desde un checkout de la misma versión que se desea comprobar. Se requieren Python 3.11 o posterior y `gh` con acceso de lectura a los artefactos de Actions. En el workflow se usa exclusivamente el token efímero de GitHub con `contents: read` y `actions: read`; no introducir credenciales en el repositorio o en los argumentos.

```sh
python3 tools/release_download_audit.py \
  --repository EspacioKoop/espaciokooplagunakRemake \
  --tag v0.9.2 \
  --expected-commit SHA_COMPLETO_APROBADO \
  --run-id ID_CI_CANONICA \
  --output release-download-audit.json
```

Sustituir SHA e ID por el candidato final y su ejecución **push/main** de `release.yml`, no por la prueba previa del PR. El comando rechaza la versión si no coincide con `tools/export_targets.py`. El workflow **Audit published release downloads** permite introducir esos tres valores mediante ejecución manual una vez integrado en la rama predeterminada. Los parámetros pasan por variables de entorno y argumentos, no por interpolación dentro del código del shell.

## Qué se comprueba

- Release publicada, no borrador; etiqueta ligera apuntando exactamente al SHA aprobado. `target_commitish` no se considera prueba suficiente.
- Ejecución canónica finalizada correctamente para ese SHA, rama `main`, evento `push` y repositorio propio. Jobs `build` y `windows-smoke` presentes, únicos y correctos.
- Un artefacto `standalone-downloads` no caducado y asociado a ese mismo run/SHA. La retención de Actions limita la ventana en que puede comprobarse esta procedencia.
- Cuatro descargas exactas: ZIP Linux, ZIP Windows, adaptador Foundry y `SHA256SUMS`. Tamaño/digest publicados por GitHub, checksum local y **comparación byte a byte mediante SHA-256 con la CI canónica**, incluido el fichero de sumas.
- Reutilización del validador `verified_assets` del publicador y del contrato `checked_zip`. Límites previos de ZIP, enlaces simbólicos rechazados, licencias/instrucciones, cabeceras de ejecutables e identidad/versión del manifiesto Foundry.
- Segunda lectura de identidad de release, activos, etiqueta, intento de CI y artefacto para rechazar sustituciones durante la comprobación.

Los ZIP públicos y el artefacto se descargan a un directorio temporal y se eliminan al finalizar. **No se extraen ni ejecutan los ZIP de juego.** `gh` descomprime el contenedor de Actions verificado por procedencia para comparar sus archivos. No se buscan partidas, HOME de jugadores, registros, fotos, tokens ni datos locales ajenos. El informe sólo contiene identificadores públicos, tamaños, hashes y límites del ensayo. No se publican los registros privados de la herramienta de autenticación.

## Resultado y límites

El marcador `RELEASE_DOWNLOAD_AUDIT_OK` y código 0 aparecen sólo después de todas las comprobaciones. El JSON se escribe únicamente tras éxito. Error de acceso, caducidad, ausencia de versión o discrepancia produce código 1, no una aprobación parcial. El límite es 1 GiB por archivo descargado y 2 GiB de contenido descomprimido por ZIP; revisar explícitamente estos límites si el producto los supera.

Este control demuestra correspondencia de las descargas en el momento de la consulta; no certifica inmutabilidad futura, autenticidad criptográfica independiente de GitHub, calidad de juego, privacidad del protocolo, pruebas humanas ni funcionamiento en un equipo concreto. Requiere que el publicador y la CI de origen hayan sido revisados. La compilación/arranque y la interacción real con terminales pertenecen al workflow canónico, no a este auditor.

```sh
python3 -m unittest discover -s tests -p test_release_download_audit.py -v
```

Las pruebas son sintéticas y sin red: releases/ZIP válidos e inválidos, checksum recalculado sobre un paquete distinto de la CI, jobs ausentes/duplicados, cambios durante descarga, versiones, límites y fallo cerrado del CLI. No atribuir esas fixtures a un playtest.
