// Invoked by the Python harness with synthetic, temporary credentials only.
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {FoundryClient} from "../client.mjs";
const fixture = JSON.parse(await readFile(process.env.FOUNDRY_TEST_READY, "utf8"));
const grant = fixture.users.mando;
const client = new FoundryClient(grant.token, grant.user, {base: process.env.FOUNDRY_TEST_BASE});
const view = await client.view();
assert.equal(view.identity.role, "mando");
assert.equal(view.crew.name, "Crew mando");
const result = await client.command("alert", {level: "ambar"});
assert.equal(result.ok, true);
assert.equal((await client.view()).ship.alert, "ambar");
await assert.rejects(client.command("helm", {heading: 45, throttle: 0}), /permite/);
client.close();
await assert.rejects(client.view(), /desconectado/);
console.log("FOUNDRY_NODE_LIVE_OK");
