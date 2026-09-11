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

## Reglas y seguridad

- Sólo se enlaza el nombre de zona exacto `Cantina`; otras zonas no producen efectos.
- `GMLiveActions.can_direct()` exige sesión `offline` o `host`, simulación activa y misión en estado `active`.
- Se exige el `run_id` actual y se pasa como guardia de carrera a `dispatch`.
- El trigger es idempotente por `run_id`: volver a entrar no añade otra nota; una ejecución nueva vuelve a armarlo.
- La consecuencia es exclusivamente pública: `La dirección registra la entrada de la tripulación en la cantina.` No se publican IDs de contactos ni información privada.
- Un cliente o una sesión inválida recibe rechazo sin mutar el estado autoritativo.

## Límites deliberados

Esto no completa el bloque GM de #32. Siguen fuera los eventos configurables por zona, espectadores sin puesto, cámaras/modo foto, Parlamento, dirección remota del dedicado, replay y el flujo GM completo. El trigger es una integración mínima de una zona, no un editor de escenas ni un sistema de scripting general.

La regresión `tests/test_gm_interior_trigger.gd` instancia la escena principal, crea una partida, abre la cubierta y verifica el recorrido completo hasta el evento visible en la shell. `tests/run_gm_interior_trigger.py` ejecuta esa regresión con perfiles temporales.
