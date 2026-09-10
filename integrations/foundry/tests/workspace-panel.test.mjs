// Synthetic DOM/ApplicationV2 contracts, not a licensed Foundry installation.
import {test} from "node:test";
import assert from "node:assert/strict";
import {FoundryClient, LagunakClient} from "../client.mjs";
import {CrewWorkspace} from "../workspace.mjs";
class Element {
  children = []; listeners = {}; value = ""; disabled = false; hidden = false; writes = 0;
  constructor(tag) { this.tagName = tag; this._text = ""; }
  set textContent(value) { this._text = String(value); this.children = []; this.writes++; }
  get textContent() { return this._text + this.children.map(c => c.textContent).join(""); }
  set innerHTML(_value) { throw new Error("HTML injection sink must not be used"); }
  append(...nodes) { this.children.push(...nodes); if (this.tagName === "select" && !this.value) this.value = this.children[0]?.value ?? ""; }
  replaceChildren(...nodes) { this._text = ""; this.children = nodes; }
  setAttribute(name, value) { this[name] = String(value); }
  addEventListener(name, fn) { this.listeners[name] = fn; }
}
globalThis.document = {createElement: tag => new Element(tag), createTextNode: value => {const n = new Element("#text"); n.textContent = value; return n;}};
globalThis.window = {location: {origin: "http://localhost:30000"}};
globalThis.foundry = {applications: {api: {ApplicationV2: class {async close() {}}}}};
globalThis.Hooks = {once() {}, on() {}};
globalThis.game = {user: {id: "testUser", isGM: false}, journal: []};
const {LagunakPanel} = await import("../main.mjs");
const response = value => ({ok: true, status: 200, text: async () => JSON.stringify(value)});
const fixture = () => ({protocol: 2, identity: {user_id: "testUser", role: "mando"}, run_id: "one", status: "active", mission: {title: "Mission", sector: "Argi"}, ship: {hull: 90, max_hull: 100, shield: 80, energy: 70, fuel: 60, systems: {}, alert: "roja", position: [0, 0], heading: 0, target_heading: 90, speed: 2, autopilot: "faro", docked: ""}, contacts: [{id: "faro", name: "Faro Argi", identified: true, position: [3, 4]}], crew: {}, commands: ["alert"], sequence: 1, log: {events: [], cursor: 0}});
const client = fetcher => new FoundryClient("a".repeat(64), "testUser", {fetcher});
const walk = n => [n, ...n.children.flatMap(walk)];
const deferred = () => {let resolve; const promise = new Promise(r => {resolve = r;}); return {promise, resolve};};

async function panelWith(fetcher) {
  const panel = new LagunakPanel(); await panel._renderHTML(); panel.client = client(fetcher); return panel;
}

test("opening after red alert shows current host state using only the existing GET", async () => {
  const methods = [];
  const panel = await panelWith(async (_url, options) => {methods.push(options.method); return response(fixture());});
  await panel.poll();
  assert.equal(panel.workspace.element.hidden, false); assert.equal(panel.workspace.alert.textContent, "Alerta roja");
  assert.match(panel.workspace.summary.textContent, /Activo · Faro Argi/);
  assert.equal(panel.workspace.map.children.length, 2); assert.deepEqual(methods, ["GET"]);
  panel.stop();
});
test("alert changes do not rebuild permitted order forms or overwrite keyboard selection", async () => {
  const state = fixture(); const panel = await panelWith(async () => response(state));
  await panel.poll();
  const form = walk(panel.orders).find(n => n.tagName === "form");
  const select = walk(form).find(n => n.tagName === "select"); select.value = "verde";
  state.ship.alert = "ambar"; await panel.poll();
  assert.equal(panel.workspace.alert.textContent, "Alerta ámbar");
  assert.equal(walk(panel.orders).find(n => n.tagName === "form"), form); assert.equal(select.value, "verde");
  panel.stop();
});
test("unchanged alert is not re-announced when navigation changes", () => {
  const workspace = new CrewWorkspace(document), state = fixture(); workspace.update(state);
  const writes = workspace.alert.writes, list = workspace.contacts.children[0];
  workspace.update(state); assert.equal(workspace.contacts.children[0], list);
  state.ship.speed++; workspace.update(state);
  assert.equal(workspace.alert.writes, writes); assert.equal(workspace.alert["aria-live"], "polite");
});
test("HTML-like contact names stay text, unknown names are discarded, marker CSS is numeric", () => {
  const workspace = new CrewWorkspace(document), state = fixture();
  state.contacts[0].name = '<img src=x onerror="evil()">';
  state.contacts.push({id: "private", identified: false, name: "SECRET_NAME", position: [-3, -4]});
  workspace.update(state);
  assert.match(workspace.contacts.textContent, /<img/); assert.doesNotMatch(workspace.element.textContent, /SECRET_NAME/);
  assert.ok(!walk(workspace.element).some(n => n.tagName === "img" || n.tagName === "script"));
  for (const marker of workspace.map.children) {
    assert.match(marker.style, /^left:\d+\.\d{3}%;top:\d+\.\d{3}%$/);
    assert.equal(marker["aria-hidden"], "true");
  }
});
test("public access gains no commands, crew data or identity from the workspace", async () => {
  const panel = new LagunakPanel(); await panel._renderHTML();
  const state = fixture(); delete state.crew; delete state.identity; delete state.commands;
  panel.client = new LagunakClient("public-test-token", {fetcher: async url => response(url.includes("events") ? state.log : state)});
  await panel.poll();
  assert.equal(panel.orders.children.length, 0); assert.equal(panel.crew.children.length, 0);
  assert.equal(panel.workspace.alert.textContent, "Alerta roja"); panel.stop();
});
test("missing optional navigation data does not invent green alert, zero coordinates or ETA", async () => {
  const state = fixture(); state.ship = {}; state.contacts = [];
  const panel = await panelWith(async () => response(state)); await panel.poll();
  assert.equal(panel.workspace.alert.textContent, "Alerta no publicada"); assert.equal(panel.workspace.map.hidden, true);
  assert.match(panel.workspace.summary.textContent, /Posición no publicada/);
  assert.doesNotMatch(panel.workspace.element.textContent, /ETA|X 0/); panel.stop();
});
test("revocation and network failure clear all new displays instead of showing stale data", async () => {
  for (const failure of [401, 403, "network"]) {
    let fail = false;
    const panel = await panelWith(async () => {
      if (!fail) return response(fixture());
      if (failure === "network") throw new Error("network unavailable");
      return {ok: false, status: failure};
    });
    await panel.poll(); fail = true; await panel.poll();
    assert.equal(panel.lastState, null); assert.equal(panel.workspace.element.hidden, true);
    assert.equal(panel.workspace.summary.children.length, 0); assert.equal(panel.workspace.contacts.children.length, 0);
    assert.equal(panel.workspace.map.children.length, 0); assert.equal(panel.workspace.signature, null);
    assert.doesNotMatch(panel.workspace.element.textContent, /Faro Argi|Alerta roja/); panel.stop();
  }
});
test("a late response after disconnect cannot resurrect the workspace", async () => {
  const wait = deferred(), panel = await panelWith(() => wait.promise);
  const pending = panel.poll(); panel.stop(); wait.resolve(response(fixture())); await pending;
  assert.equal(panel.workspace.element.hidden, true); assert.equal(panel.workspace.map.children.length, 0);
  assert.equal(panel.lastState, null);
});
test("an old connection cannot overwrite a reconnected client's current workspace", async () => {
  const wait = deferred(), panel = await panelWith(() => wait.promise);
  const pending = panel.poll(); panel.stop();
  const next = fixture(); next.ship.alert = "verde"; next.mission.sector = "Berri";
  panel.client = client(async () => response(next)); await panel.poll();
  wait.resolve(response(fixture())); await pending;
  assert.equal(panel.workspace.alert.textContent, "Alerta verde"); assert.match(panel.workspace.summary.textContent, /Berri/);
  assert.equal(panel.busy, false); panel.stop();
});
test("new mission, disappearing contacts and reacquisition replace the view without cached identities", async () => {
  const state = fixture(), panel = await panelWith(async () => response(state)); await panel.poll();
  state.run_id = "two"; state.contacts = []; await panel.poll();
  assert.doesNotMatch(panel.workspace.element.textContent, /Faro Argi/);
  assert.match(panel.workspace.summary.textContent, /destino no visible/); assert.equal(panel.workspace.map.children.length, 1);
  state.contacts = [{id: "faro", identified: false, position: [5, 0], name: "SECRET_NAME"}]; await panel.poll();
  assert.match(panel.workspace.summary.textContent, /Eco 01/); assert.doesNotMatch(panel.workspace.element.textContent, /SECRET_NAME/);
  panel.stop();
});
test("map stays bounded, supports absent positions and retains a full textual alternative", () => {
  const workspace = new CrewWorkspace(document), state = fixture();
  state.ship.position = [-1e9, -1e9]; state.contacts[0].position = [1e9, 1e9];
  state.contacts.push({id: "no-position", identified: false}); workspace.update(state);
  assert.equal(workspace.contacts.children.length, 2); assert.equal(workspace.map.children.length, 2);
  assert.match(workspace.map.children[1].style, /left:90\.000%;top:90\.000%/);
  assert.match(workspace.contacts.textContent, /Posición no publicada/);
  assert.equal(workspace.map.role, "img"); assert.match(workspace.map["aria-label"], /X crece/);
});
test("closing and rendering again clear the old workspace and await a fresh connection", async () => {
  const panel = await panelWith(async () => response(fixture())); await panel.poll();
  const old = panel.workspace; await panel.close(); await panel._renderHTML();
  assert.equal(old.element.hidden, true); assert.equal(old.map.children.length, 0);
  assert.equal(panel.workspace.element.hidden, true); assert.notEqual(panel.workspace, old); panel.stop();
});
