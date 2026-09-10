import {test} from "node:test";
import assert from "node:assert/strict";
import {buildWorkspace} from "../workspace.mjs";
const fixture = () => ({mission: {sector: "Argi"}, ship: {alert: "roja", position: [0, 0], heading: 0, target_heading: 90, speed: 0, autopilot: "faro", docked: ""}, contacts: [{id: "faro", identified: true, name: "Faro Argi", position: [3, 4]}]});

test("all three host alert levels are explicit, including a first red snapshot", () => {
  for (const [level, label] of [["verde", "Alerta verde"], ["ambar", "Alerta ámbar"], ["roja", "Alerta roja"]]) {
    const value = fixture(); value.ship.alert = level;
    assert.deepEqual(buildWorkspace(value).alert, {level, label});
  }
});
test("unknown alerts never become green or prototype lookups", () => {
  for (const level of [null, undefined, 0, {}, [], "constructor", "toString", "__proto__", "amarilla", "roja onclick=x"]) {
    assert.deepEqual(buildWorkspace({ship: {alert: level}}).alert, {level: "unknown", label: "Alerta no publicada"});
  }
});
test("zero position, heading and speed remain real values; distance is geometric", () => {
  const view = buildWorkspace(fixture());
  assert.deepEqual(view.position, [0, 0]); assert.equal(view.heading, 0); assert.equal(view.speed, 0);
  assert.equal(view.targetHeading, 90); assert.equal(view.contacts[0].distance, 5); assert.equal(view.extent, 4);
  assert.equal(view.autopilot, "Activo · Faro Argi"); assert.equal(view.docked, "Sin atraque");
});
test("unidentified contacts never use supplied names or kinds", () => {
  const source = fixture(); source.contacts[0].identified = false;
  source.contacts[0].name = "HIDDEN_NAME"; source.contacts[0].kind = "HIDDEN_KIND";
  const view = buildWorkspace(source);
  assert.equal(view.contacts[0].name, "Eco 01"); assert.equal(view.autopilot, "Activo · Eco 01");
  assert.doesNotMatch(JSON.stringify(view), /HIDDEN_|faro/);
  for (const value of ["true", 1, null, undefined]) {
    source.contacts[0].identified = value;
    assert.equal(buildWorkspace(source).contacts[0].name, "Eco 01");
  }
});
test("targets missing from this projection never reveal raw ids or cached names", () => {
  const source = fixture(); source.ship.autopilot = "SECRET_TARGET_ID"; source.ship.docked = "SECRET_DOCK_ID";
  source.hidden_contacts = [{id: "SECRET_TARGET_ID", name: "SECRET_NAME"}];
  const view = buildWorkspace(source);
  assert.equal(view.autopilot, "Activo · destino no visible"); assert.equal(view.docked, "Atracada · destino no visible");
  assert.doesNotMatch(JSON.stringify(view), /SECRET/);
});
test("destinations handle off, absent and boolean flags without inventing a target", () => {
  for (const value of [false, ""]) {
    const view = buildWorkspace({ship: {autopilot: value, docked: value}});
    assert.equal(view.autopilot, "Desactivado"); assert.equal(view.docked, "Sin atraque");
  }
  assert.equal(buildWorkspace({ship: {autopilot: true}}).autopilot, "Activo · destino no publicado");
  for (const value of [null, undefined, [], {}, 0]) assert.equal(buildWorkspace({ship: {autopilot: value}}).autopilot, "No publicado");
});
test("duplicate ids cannot resolve an ambiguous destination, including a third duplicate", () => {
  const source = fixture(); source.contacts.push({...source.contacts[0], name: "Other"}, {...source.contacts[0], name: "Third"});
  assert.equal(buildWorkspace(source).autopilot, "Activo · destino no visible");
});
test("malformed coordinates and non-finite data are missing, never coerced to zero", () => {
  for (const point of [null, {}, [], [0], [0, 0, 0], ["0", 0], [null, 0], [NaN, 0], [Infinity, 0], [1e10, 0]]) {
    const source = fixture(); source.ship.position = point; source.contacts[0].position = point;
    const view = buildWorkspace(source);
    assert.equal(view.position, null); assert.equal(view.contacts[0].position, null); assert.equal(view.contacts[0].distance, null);
  }
  for (const value of ["0", null, {}, NaN, Infinity, -1, 360, 1e10]) assert.equal(buildWorkspace({ship: {heading: value}}).heading, null);
});
test("negative velocity and finite coordinate boundaries are preserved without overflow", () => {
  const view = buildWorkspace({ship: {position: [-1e9, -1e9], speed: -8.5}, contacts: [{position: [1e9, 1e9]}]});
  assert.equal(view.speed, -8.5); assert.equal(view.extent, 2e9); assert.ok(Number.isFinite(view.contacts[0].distance));
});
test("contact and text limits prevent unbounded presentation", () => {
  const source = fixture(); source.mission.sector = "S".repeat(1000);
  source.contacts = Array.from({length: 1000}, (_, i) => ({id: `${i}`, identified: true, name: "N".repeat(1000), position: [i, 0]}));
  const view = buildWorkspace(source);
  assert.equal(view.contacts.length, 48); assert.equal(view.sector.length, 160); assert.equal(view.contacts[0].name.length, 160);
});
test("malformed records are skipped and names receive safe fallbacks", () => {
  const view = buildWorkspace({contacts: [null, [], "bad", {identified: true, name: "\u0000\n"}, {identified: false}]});
  assert.deepEqual(view.contacts.map(c => c.name), ["Contacto 1", "Eco 02"]);
  for (const value of [null, undefined, [], 0, "bad", {ship: [], mission: false, contacts: {}}]) assert.doesNotThrow(() => buildWorkspace(value));
});
test("positive view model excludes credentials, identity, logs, inventories and objective secrets", () => {
  const source = fixture();
  Object.assign(source, {token: "SECRET_TOKEN", identity: {user_id: "SECRET_USER"}, crew: {inventory: ["SECRET_ITEM"]}, log: {events: ["SECRET_LOG"]}, objective: "SECRET_OBJECTIVE", eta: "SECRET_ETA"});
  source.ship.private = "SECRET_SHIP"; source.contacts[0].notes = "SECRET_NOTES";
  assert.doesNotMatch(JSON.stringify(buildWorkspace(source)), /SECRET/);
});
test("presentation does not mutate inputs or retain their arrays", () => {
  const source = fixture(), before = JSON.stringify(source);
  function freeze(value) { if (value && typeof value === "object") { Object.values(value).forEach(freeze); Object.freeze(value); } }
  freeze(source);
  const view = buildWorkspace(source);
  assert.equal(JSON.stringify(source), before);
  view.position[0] = 17; view.contacts[0].position[0] = 99;
  assert.equal(JSON.stringify(source), before);
});
