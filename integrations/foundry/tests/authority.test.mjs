import {test} from "node:test";
import assert from "node:assert/strict";
import {FoundryClient, COMMANDS} from "../client.mjs";
const token = "a".repeat(64), user = "testUser";
const view = () => ({protocol: 2, identity: {user_id: user, role: "mando"}, run_id: "run", mission: {title: "Fixture"}, ship: {}, contacts: [], crew: {}, commands: ["alert"], sequence: 1, log: {events: [], cursor: 0}});
const response = value => ({ok: true, status: 200, text: async () => JSON.stringify(value)});

test("personal identity and credential validated", () => {
  for (const id of ["", "../other", "name\nheader", "a".repeat(65)]) assert.throws(() => new FoundryClient(token, id));
  assert.throws(() => new FoundryClient("legacy-token", user));
});
test("closed DTO version, owner, sequence and commands checked", async () => {
  for (const patch of [{protocol: 1}, {identity: {user_id: "other"}}, {sequence: 0}, {commands: ["self_destruct"]}, {log: {events: [{seq: 1}], cursor: 1}}]) {
    const client = new FoundryClient(token, user, {fetcher: async () => response({...view(), ...patch})});
    await assert.rejects(client.view(), /inválid|incompatible/);
  }
});
test("authenticated POST sends no client role or principal and no cookies", async () => {
  let captured;
  const client = new FoundryClient(token, user, {fetcher: async (url, options) => {captured = {url, options}; return response(options.method === "GET" ? view() : {ok: true, message: "Applied", sequence: 2});}});
  await client.view();
  await client.command("alert", {level: "ambar"});
  assert.equal(captured.options.method, "POST");
  assert.equal(captured.options.headers["X-Lagunak-User"], user);
  assert.equal(captured.options.headers["Content-Type"], "application/json");
  assert.deepEqual(JSON.parse(captured.options.body), {run_id: "run", sequence: 1, operation: "alert", args: {level: "ambar"}});
  assert.equal(captured.options.credentials, "omit");
  assert.equal(captured.options.redirect, "error");
  assert.equal(client.lastView, null);
});
test("disallowed operations do not send HTTP", async () => {
  let calls = 0;
  const client = new FoundryClient(token, user, {fetcher: async () => {calls++; return response(view());}});
  await client.view();
  await assert.rejects(client.command("power", {}), /permite/);
  assert.equal(calls, 1);
});
test("ambiguous timeout invalidates sequence and never retries mutation", async () => {
  let posts = 0;
  const client = new FoundryClient(token, user, {timeout: 10, fetcher: async (_url, options) => {
    if (options.method === "GET") return response(view());
    posts++;
    return new Promise((_resolve, reject) => options.signal.addEventListener("abort", () => reject(new Error("timeout"))));
  }});
  await client.view();
  const pending = client.command("alert", {level: "roja"});
  await assert.rejects(client.command("alert", {level: "verde"}), /curso/);
  await assert.rejects(pending, /timeout/);
  await assert.rejects(client.command("alert", {level: "roja"}), /Actualiza/);
  assert.equal(posts, 1);
});
test("revocation and throttling are actionable", async () => {
  for (const [status, message] of [[401, /revocado/], [403, /autorizados/], [409, /secuencia/], [429, /segundo/]]) {
    const client = new FoundryClient(token, user, {fetcher: async () => ({ok: false, status})});
    await assert.rejects(client.view(), message);
  }
});
test("all offered controls have real field schemas", () => {
  assert.equal(Object.keys(COMMANDS).length, 13);
  for (const definition of Object.values(COMMANDS)) assert.equal(typeof definition.fields, "object");
});
