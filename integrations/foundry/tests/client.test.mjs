import {test} from "node:test";
import assert from "node:assert/strict";
import {LagunakClient, escapeHtml, newEvents, eventsHtml} from "../client.mjs";
const token = "synthetic-test-token";
const response = value => ({ok: true, status: 200, text: async () => JSON.stringify(value)});

test("only loopback URLs without credentials, paths or redirects", () => {
  for (const base of ["https://example.com", "http://192.168.1.4", "http://localhost/other", "http://name:pass@localhost", "http://localhost?key=x"]) assert.throws(() => new LagunakClient(token, {base}));
});
test("token is required", () => assert.throws(() => new LagunakClient("")));
test("requests are authenticated GET without cookies and redirects", async () => {
  let captured;
  const client = new LagunakClient(token, {fetcher: async (url, options) => {captured = {url, options}; return response({mission: {title: "Test"}, ship: {}, contacts: []});}});
  await client.state();
  assert.equal(captured.url, "http://127.0.0.1:27841/v1/state");
  assert.equal(captured.options.method, "GET");
  assert.equal(captured.options.headers.Authorization, "Bearer " + token);
  assert.equal(captured.options.credentials, "omit");
  assert.equal(captured.options.redirect, "error");
});
test("unauthorized response is actionable", async () => {
  const client = new LagunakClient(token, {fetcher: async () => ({ok: false, status: 401})});
  await assert.rejects(client.state(), /token/);
});
test("invalid state is rejected", async () => {
  const client = new LagunakClient(token, {fetcher: async () => response({})});
  await assert.rejects(client.state(), /partida/);
});
test("invalid event payload and cursor rejected", async () => {
  const client = new LagunakClient(token, {fetcher: async () => response({events: [{seq: 1, source: 4}], cursor: 1})});
  await assert.rejects(client.events(-1), /Cursor/);
  await assert.rejects(client.events(0), /Evento/);
});
test("slow request is aborted", async () => {
  const client = new LagunakClient(token, {timeout: 10, fetcher: (_url, {signal}) => new Promise((_resolve, reject) => signal.addEventListener("abort", () => reject(new Error("aborted"))))});
  await assert.rejects(client.state(), /aborted/);
});
test("closing clears credentials and pending requests", () => {
  const client = new LagunakClient(token);
  client.close();
  assert.equal(client.token, "");
  assert.equal(client.pending.size, 0);
});
test("journal content is escaped", () => {
  assert.equal(escapeHtml('<script>"&'), "&lt;script&gt;&quot;&amp;");
  assert.ok(!eventsHtml([{seq: 1, source: "<img>", text: "<script>x</script>", time: 3}]).includes("<script>"));
});
test("event import is ordered and idempotent", () => {
  const events = [{seq: 3}, {seq: 1}, {seq: 3}, {seq: 2}];
  assert.deepEqual(newEvents(events, 1), [{seq: 2}, {seq: 3}]);
  assert.deepEqual(newEvents(events, 3), []);
});
