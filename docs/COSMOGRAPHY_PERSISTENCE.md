# Contrato de persistencia cosmográfica standalone

Este subcarril añade \`CosmographyPersistence\`, un componente puro que conecta un catálogo \`espaciokoop-cosmography\` v1 validado con una posición cosmográfica persistible.

## Alcance

- Registra catálogos validados por \`CosmographyCatalog\`.
- Conserva \`catalog_id\`, \`current_system_id\` y \`current_planet_id\`.
- Permite seleccionar únicamente sistemas existentes y planetas cuyo padre sea ese sistema.
- Serializa y restaura el estado sin Foundry, red, UI global ni vuelo 6DOF.
- Rechaza catálogos inválidos, ubicaciones inexistentes, padres incompatibles, estados corruptos y estados de otro catálogo.
- No escribe en \`ExpeditionSystems\`: su propietario puede integrar la API en una entrega posterior sin mezclar fuentes de verdad.

## Contrato de estado

    {
      "format": "lagunak-cosmography-state",
      "version": 1,
      "catalog_id": "fixture-v1",
      "current_system_id": "sol",
      "current_planet_id": "tierra"
    }

Un estado restaurado inválido no muta el estado anterior. La selección de sistema/planeta es atómica desde la perspectiva del consumidor.

## Verificación

    python3 tests/run_cosmography_persistence.py

La prueba cubre round-trip positivo, IDs inexistentes, tipo incorrecto, padre incompatible, \`map_ref\` inválido, corrupción, catálogo ajeno y ausencia de mutación tras un restore rechazado.
