# Créditos y procedencia

Dirección del proyecto y encargo: **VaroTv7 y Eloy (eGurucharri), conjuntamente**. Ambos han contribuido en todas las áreas del remake: diseño, programación, misiones, interfaz, modelado procedural original en Blender y síntesis de audio. El trabajo se ha realizado con asistencia de Codex.

Los veinte modelos proceden de `art/blender/lagunak_assets.blend`, editable con Blender 4.5.3 LTS. `art/blender/export_assets.py` produce las exportaciones GLB y su manifiesto de integridad. La segunda fuente, `art/blender/leisure_assets.blend`, contiene los seis espacios de ocio y dieciocho esculturas estilizadas originales; no se han importado escaneos del catálogo de referencia. `export_leisure.py` permite exportar sus cambios manuales. Los seis archivos WAV se sintetizaron para el proyecto. Las diecinueve imágenes de `docs/images/` son capturas directas del ejecutable de Linux; no son ilustraciones ni maquetas.

Se estudió [EspacioKoop/espaciokooplagunak](https://github.com/EspacioKoop/espaciokooplagunak) como referencia funcional. Se reconoce el trabajo de Varo, Eloy (eGurucharri) y los colaboradores de ese proyecto. Su código C++, Lua y JavaScript, sus recursos heredados y su historial de EmptyEpsilon no se han incorporado a este repositorio. El inventario y las decisiones del remake se describen en `docs/SOURCE_REVIEW.md`.

El código, las misiones, los modelos y el audio propios de este repositorio se distribuyen con la [licencia MIT](LICENSE). Godot Engine y sus componentes conservan sus licencias: los avisos oficiales se incluyen en `third_party/` y en las descargas. Blender y Foundry VTT son herramientas externas y pertenecen a sus titulares; Foundry no se incluye en los paquetes ni es necesario para jugar.
