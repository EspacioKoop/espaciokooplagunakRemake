# Triggers de interior para dirección GM

## Alcance

Esta rebanada conecta una entrada real de `WorldDeck` con `GMLiveActions`, ya usado por la consola **Puente → Dirección en vivo**. El trigger mínimo está ligado a la llegada a **Cantina** y publica una única nota de dirección por ejecución de misión.

## Recorrido ejecutable

```text
WorldDeck.teleport_zone() / detección de corredor
  → zone_changed("Cantina")
  → GMInteriorTrigger.enter_zone()
  → GMLiveActions.dispatch("message", ...)
  → Simulation.log_event() + auditoría GM
  → Session._refresh_view()
  → App._refresh() / pie de la shell
```

La entrada no abre una segunda consola ni mantiene una copia paralela del estado GM. La consecuencia usa el evento público existente, por lo que también aparece en la bitácora autorizada de la sesión.

La API general `InteriorTriggers` permite además registrar, modificar, listar, evaluar y retirar hasta 64 triggers host-only para `enter_zone`, `exit_zone`, `interact` y `sit`. Las consecuencias admitidas pasan por `GMLiveActions` y el estado se valida antes de aceptar un guardado.

## Reglas y seguridad

- Sólo se enlaza el nombre de zona exacto `Cantina`; otras zonas no producen efectos.
- `GMLiveActions.can_direct()` exige sesión `offline` o `host`, simulación activa y misión en estado `active`.
- Se exige el `run_id` actual y se pasa como guardia de carrera a `dispatch`.
- El trigger es idempotente por `run_id`: volver a entrar no añade otra nota; una ejecución nueva vuelve a armarlo.
- La consecuencia es exclusivamente pública: `La dirección registra la entrada de la tripulación en la cantina.` No se publican IDs de contactos ni información privada.
- Un cliente o una sesión inválida recibe rechazo sin mutar el estado autoritativo.
- `Simulation.snapshot()` elimina `interior_triggers` antes de enviarlo a cualquier cliente; la edición y la auditoría permanecen en el host.

## Límites deliberados

Esto no completa el bloque GM de #32. Siguen fuera los eventos configurables por zona, espectadores sin puesto, cámaras/modo foto, Parlamento, dirección remota del dedicado, replay y el flujo GM completo. El trigger es una integración mínima de una zona, no un editor de escenas ni un sistema de scripting general.

Las regresiones `tests/test_gm_interior_trigger.gd` y `tests/test_interior_triggers.gd` cubren respectivamente la cadena de producción y el contrato general, incluida validación de guardado y redacción del snapshot. `tests/run_gm_interior_trigger.py` y `tests/run_interior_triggers.py` las ejecutan con perfiles temporales.
