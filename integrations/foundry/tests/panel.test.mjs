// Contract tests with a small DOM/ApplicationV2 fixture, NOT a licensed Foundry runtime.
import {test} from "node:test";
import assert from "node:assert/strict";
import {FoundryClient, LagunakClient} from "../client.mjs";
class Element {
  children = []; listeners = {}; value = ""; disabled = false;
  constructor(tag, text = "") { this.tagName = tag; this.textContent = text; }
  append(...nodes) { this.children.push(...nodes); if (this.tagName === "select" && !this.value) this.value = this.children[0]?.value ?? ""; }
  replaceChildren(...nodes) { this.children = nodes; }
  setAttribute(name, value) { this[name] = value; }
  addEventListener(name, fn) { this.listeners[name] = fn; }
}
globalThis.document = {createElement: tag => new Element(tag), createTextNode: text => new Element("#text", text)};
globalThis.window = {location: {origin: "http://localhost:30000"}};
globalThis.foundry = {applications: {api: {ApplicationV2: class {async close() {}}}}};
const hooks = {};
globalThis.Hooks = {once: (name, fn) => {hooks[name] = fn;}, on: (name, fn) => {hooks[name] = fn;}};
globalThis.game = {user: {id: "testUser", isGM: false}, journal: []};
const {LagunakPanel} = await import("../main.mjs");
const fixture = () => ({protocol: 2, identity: {user_id: "testUser", role: "mando"}, run_id: "run1", status: "active", mission: {title: "Test mission"}, ship: {hull: 90, max_hull: 100, shield: 50, energy: 80, fuel: 60, systems: {}}, contacts: [], crew: {name: "Own crew", level: 1, xp: 0, focus: 3, condition: 100, approach: "ingenio", skills: {ciencia: 1}, traits: []}, commands: ["alert"], sequence: 1, log: {cursor: 1, events: [{seq: 1, time: 0, source: "Public", text: "<script>public log</script>"}]}});
const response = value => ({ok: true, status: 200, text: async () => JSON.stringify(value)});
const walk = node => [node, ...node.children.flatMap(walk)];

test("player panel opens, shows own crew and submits a real station form", async () => {
  const panel = new LagunakPanel();
  await panel._renderHTML();
  let payload;
  panel.client = new FoundryClient("a".repeat(64), "testUser", {fetcher: async (_url, options) => {
    if (options.method === "GET") return response(fixture());
    payload = JSON.parse(options.body); return response({ok: true, message: "Alerta aplicada", sequence: 2});
  }});
  await panel.poll();
  assert.equal(panel.importButton.hidden, true);
  assert.ok(walk(panel.crew).some(n => n.textContent === "Own crew"));
  const form = walk(panel.orders).find(n => n.tagName === "form");
  assert.ok(form);
  const select = walk(form).find(n => n.tagName === "select"); select.value = "ambar";
  await form.listeners.submit({preventDefault() {}});
  assert.deepEqual(payload.args, {level: "ambar"});
  assert.equal(payload.operation, "alert");
  assert.equal(panel.status.textContent, "Alerta aplicada");
  panel.stop();
  assert.equal(panel.crew.children.length, 0);
  assert.equal(panel.orders.children.length, 0);
});
test("revocation clears private displays and disables order handlers", async () => {
  const panel = new LagunakPanel(); await panel._renderHTML();
  let revoked = false;
  panel.client = new FoundryClient("a".repeat(64), "testUser", {fetcher: async () => revoked ? {ok: false, status: 401} : response(fixture())});
  await panel.poll(); revoked = true; await panel.poll();
  assert.equal(panel.lastState, null);
  assert.equal(panel.orders.inert, true);
  assert.equal(panel.crew.children.length, 0);
  assert.equal(panel.importButton.disabled, true);
  panel.stop();
});
test("legacy public access exposes no controls", async () => {
  const panel = new LagunakPanel(); await panel._renderHTML();
  panel.client = new LagunakClient("legacy-test-token", {fetcher: async url => response(url.includes("events") ? {events: [], cursor: 0} : {mission: {title: "Public"}, ship: {}, contacts: []})});
  await panel.poll();
  assert.equal(panel.orders.children.length, 0);
  assert.equal(panel.crew.children.length, 0);
  panel.stop();
});
test("journal imports only escaped public events, privately by default", async () => {
  game.user.isGM = true;
  let created;
  globalThis.JournalEntry = {create: async data => {created = data; return {name: data.name};}};
  const panel = new LagunakPanel(); await panel._renderHTML();
  panel.client = new FoundryClient("a".repeat(64), "testUser", {fetcher: async () => response(fixture())});
  await panel.importJournal();
  assert.deepEqual(created.ownership, {default: 0});
  assert.ok(!JSON.stringify(created).includes("Own crew"));
  assert.ok(created.pages[0].text.content.includes("&lt;script&gt;"));
  game.user.isGM = false;
  await assert.rejects(panel.importJournal(), /Sólo/);
  panel.stop();
});
test("scene button is available to players without granting HTTP authority", () => {
  const controls = {tokens: {tools: {}}}; hooks.getSceneControlButtons(controls);
  assert.equal(controls.tokens.tools.lagunak.visible, true);
});
