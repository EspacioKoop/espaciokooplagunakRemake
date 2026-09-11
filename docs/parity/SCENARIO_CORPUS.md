# Corpus acotado de escenarios original → remake

Este documento acompaña a [`scenario_corpus.json`](scenario_corpus.json), un inventario P0 acotado para [#32](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/32).

## Qué queda registrado

- **Fuente original:** `EspacioKoop/espaciokooplagunak` en `fecd0740545f485d2402c6dfe4b47d5a859cb96c`.
- **Alcance:** los 38 `scripts/scenario_*.lua` presentes en ese árbol, conservando número, nombre, tipo declarado cuando estaba disponible, ruta y blob SHA-1.
- **Remake contrastado:** `game/data/campaign.json` en la lectura fijada `8b1dcf27683a00972b03d5203606eab12f31fe2d`, con las seis IDs de campaña presentes (`itsasoratu`, `oihartzuna`, `aterpe`, `zaindari`, `berpiztu`, `elkarlana`).
- **Resultado honesto:** 37 escenarios quedan sin correspondencia acreditada en el catálogo actual y `scenario:90` sólo queda como candidato nominal frente a `itsasoratu`. El nombre compartido no prueba objetivos, fases, dependencias, desenlaces, recompensas ni equivalencia jugable.

El archivo no copia código Lua, recursos ni descripciones extensas del original. Es una tabla de procedencia y estado de contraste. Todas las filas mantienen `decision: human_review`; no se marca ninguna como `verified`.

`coverage.complete` permanece explícitamente en `false`: este bloque no inventaría paridad ni cierra el inventario global de escenarios, libros, hitos, bestiario o recursos. Los siguientes elementos a decidir son el desglose por objetivos/fases/dependencias/recompensas y la auditoría de los catálogos no cubiertos por este slice.

## Verificación local

Desde la raíz del repositorio, sin dependencias externas:

```sh
python3 tools/check_scenario_corpus.py
python3 tools/check_scenario_corpus.py --require-complete  # debe bloquear con salida 2
python3 -m unittest discover -s tests -p 'test_scenario_corpus.py' -v
```

El verificador comprueba el esquema, el conjunto exacto de 38 entradas, IDs/nombres/rutas, SHA-1 de cada blob, catálogo local y la conservación de `coverage.complete=false`. También rechaza duplicados, entradas fuera del alcance, IDs de misión inexistentes y el intento de convertir este corpus parcial en un cierre exhaustivo. No usa red, no ejecuta Lua y no afirma paridad funcional.

## Exclusiones

- No se modifica `game/data/campaign.json`: el catálogo del remake es la evidencia contrastada, no un destino que este inventario pueda alterar.
- No se reabre ni se replica el inventario estructural de [#36](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/36); este archivo añade el nivel de corpus por escenario que el registro inicial deja abierto.
- No se tocan Atlas, cosmografía, navegación sectorial ni archivos calientes.
- No se afirma que los escenarios originales deban copiarse: cualquier futura implementación debe usar código, datos y recursos propios y pasar la decisión humana correspondiente.

La reserva de este subcarril está registrada en [#7](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/7). Para retirar el bloque sin reescribir historia, revertir el commit que añade este documento, el JSON, el checker y sus pruebas.
