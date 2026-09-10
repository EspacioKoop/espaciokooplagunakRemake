import {LagunakClient, FoundryClient, COMMANDS, newEvents, eventsHtml} from "./client.mjs";

const ID = "espaciokoop-lagunak";
let panel;
const element = (tag, text, className) => {
  const node = document.createElement(tag);
  if (text) node.textContent = text;
  if (className) node.className = className;
  return node;
};
const fieldLabels = {target: "Contacto", system: "Sistema", value: "Potencia (0–4)", heading: "Rumbo (0–359°)", throttle: "Impulso (−1 a 1)", level: "Alerta", enabled: "Escudos"};

export class LagunakPanel extends foundry.applications.api.ApplicationV2 {
  static DEFAULT_OPTIONS = {id: "lagunak-bridge", classes: ["lagunak-panel"], position: {width: 700, height: 740}, window: {title: "Espaciokoop Lagunak · Puesto y bitácora", resizable: true}};
  client = null;
  timer = null;
  busy = false;
  importing = false;
  lastState = null;
  orderKey = "";

  async _renderHTML() {
    this.stop();
    const root = element("div", "", "lagunak-content");
    root.append(element("h2", "La Itsaso, en tu mesa"));
    root.append(element("p", "El anfitrión de Lagunak concede el acceso y resuelve las órdenes. Tu ficha se consulta aquí; la campaña permanece en el juego independiente."));
    root.append(element("p", "Origen que debes autorizar en Lagunak: " + window.location.origin, "lagunak-origin"));
    root.append(element("p", "Tu ID de usuario: " + game.user.id + ". Entrégalo al anfitrión para recibir un token personal.", "lagunak-origin"));
    const modeLabel = element("label", "Tipo de acceso");
    const mode = element("select");
    for (const [value, label] of [["personal", "Acceso personal: ficha y puesto concedido"], ["public", "Consulta pública: token de Sesión"]]) {
      const option = element("option", label); option.value = value; mode.append(option);
    }
    modeLabel.append(mode); root.append(modeLabel);
    const label = element("label", "Token temporal");
    const input = element("input");
    input.type = "password"; input.autocomplete = "off"; input.spellcheck = false;
    input.placeholder = "Pega el token que te ha concedido el anfitrión";
    label.append(input); root.append(label);
    const controls = element("div", "", "lagunak-actions");
    const connect = element("button", "Conectar");
    const disconnect = element("button", "Desconectar");
    this.importButton = element("button", "Importar nuevos eventos a un diario");
    this.importButton.disabled = true;
    this.importButton.hidden = !game.user.isGM;
    controls.append(connect, disconnect); root.append(controls, this.importButton);
    this.status = element("p", "Sin conexión.", "lagunak-status");
    this.status.setAttribute("role", "status");
    this.ship = element("div", "", "lagunak-ship");
    this.crew = element("div", "", "lagunak-crew");
    this.orders = element("div", "", "lagunak-orders");
    this.events = element("div", "", "lagunak-events");
    root.append(this.status, this.ship, this.crew, this.orders, this.events);
    connect.addEventListener("click", async () => {
      this.stop();
      try {
        this.client = mode.value === "personal" ? new FoundryClient(input.value.trim(), game.user.id) : new LagunakClient(input.value.trim());
        input.value = "";
        this.timer = setInterval(() => void this.poll(), 2000);
        await this.poll();
      } catch (error) { this.status.textContent = error.message; }
    });
    disconnect.addEventListener("click", () => { this.stop(); input.value = ""; this.status.textContent = "Desconectado."; });
    this.importButton.addEventListener("click", async () => {
      if (this.importing || !this.client || !this.lastState || !game.user.isGM) return;
      this.importing = true; this.importButton.disabled = true;
      try { await this.importJournal(); }
      catch (error) { this.status.textContent = error.message; }
      finally { this.importing = false; this.importButton.disabled = !this.lastState; }
    });
    return root;
  }
  _replaceHTML(result, content) { content.replaceChildren(result); }

  async poll() {
    if (this.busy || !this.client) return;
    this.busy = true;
    const client = this.client;
    try {
      const state = client instanceof FoundryClient ? await client.view() : await client.state();
      const log = client instanceof FoundryClient ? state.log : await client.events(0);
      if (this.client !== client) return;
      this.lastState = state;
      this.importButton.disabled = this.importing || !game.user.isGM;
      this.status.textContent = state.mission.title + " · " + ({active: "En curso", won: "Completada", lost: "Nave perdida"}[state.status] ?? state.status) + (state.identity ? " · " + state.identity.role : " · Consulta pública");
      this.ship.replaceChildren();
      for (const [label, value] of [["Integridad", `${Math.round(state.ship.hull)} / ${Math.round(state.ship.max_hull)}`], ["Escudos", `${Math.round(state.ship.shield)} %`], ["Energía", `${Math.round(state.ship.energy)} %`], ["Combustible", `${Math.round(state.ship.fuel)} %`]]) {
        const item = element("div"); item.append(element("span", label), element("strong", value)); this.ship.append(item);
      }
      this.crew.replaceChildren();
      if (state.crew) {
        this.crew.append(element("h3", state.crew.name || "Ficha aún no creada en el juego"));
        if (state.crew.name) {
          this.crew.append(element("p", `Nivel ${state.crew.level} · XP ${state.crew.xp} · Concentración ${state.crew.focus} · Condición ${state.crew.condition}% · Enfoque ${state.crew.approach}`));
          this.crew.append(element("p", Object.entries(state.crew.skills).map(([skill, value]) => `${skill}: ${value}`).join(" · ")));
          this.crew.append(element("p", "Rasgos: " + (state.crew.traits.join(", ") || "ninguno")));
        }
      }
      this.renderOrders(state);
      this.orders.inert = false;
      this.events.replaceChildren();
      for (const event of log.events.slice(-12).reverse()) {
        const item = element("p"); item.append(element("strong", event.source + " · "), document.createTextNode(event.text)); this.events.append(item);
      }
    } catch (error) {
      if (this.client === client) {
        this.lastState = null; this.orders.inert = true; this.importButton.disabled = true;
        this.crew.replaceChildren(); this.ship.replaceChildren(); this.events.replaceChildren();
        this.status.textContent = "No se pudo consultar la nave. " + error.message;
      }
    } finally { if (this.client === client) this.busy = false; }
  }

  renderOrders(state) {
    const key = JSON.stringify([state.run_id, state.identity, state.commands, state.contacts.map(c => [c.id, c.name]), Object.keys(state.ship.systems ?? {})]);
    if (key === this.orderKey) return;
    this.orderKey = key; this.orders.replaceChildren();
    if (!(this.client instanceof FoundryClient)) return;
    this.orders.append(element("h3", state.commands.length ? "Órdenes del puesto" : "Acceso de lectura"));
    for (const operation of state.commands) {
      const definition = COMMANDS[operation];
      const form = element("form", "", "lagunak-order");
      const inputs = {};
      for (const [name, kind] of Object.entries(definition.fields)) {
        const label = element("label", fieldLabels[name]);
        let input;
        if (Array.isArray(kind) || kind === "target" || kind === "system") {
          input = element("select");
          const choices = Array.isArray(kind) ? kind.map(x => [String(x), typeof x === "boolean" ? (x ? "Activar" : "Desactivar") : x]) : kind === "target" ? state.contacts.map(c => [c.id, c.name]) : Object.keys(state.ship.systems).map(x => [x, x]);
          for (const [value, text] of choices) { const option = element("option", text); option.value = value; input.append(option); }
        } else {
          input = element("input"); input.type = "number"; input.required = true;
          [input.min, input.max, input.step, input.value] = kind === "heading" ? [0, 359, 1, Math.floor(state.ship.heading)] : kind === "throttle" ? [-1, 1, .1, 0] : [0, 4, 1, 1];
        }
        label.append(input); form.append(label); inputs[name] = input;
      }
      const button = element("button", definition.label); button.type = "submit"; form.append(button);
      form.addEventListener("submit", async event => {
        event.preventDefault();
        if (!this.lastState || !this.client || this.client.commandBusy) return;
        const client = this.client;
        const args = Object.fromEntries(Object.entries(inputs).map(([name, input]) => [name, name === "enabled" ? input.value === "true" : input.type === "number" ? Number(input.value) : input.value]));
        button.disabled = true;
        let message;
        try { message = (await client.command(operation, args)).message; }
        catch (error) { message = error.message; }
        finally {
          if (this.client === client) {
            await this.poll();
            this.status.textContent = message;
            button.disabled = false;
          }
        }
      });
      this.orders.append(form);
    }
  }

  async importJournal() {
    if (!game.user.isGM) throw new Error("Sólo la dirección puede crear el diario.");
    const client = this.client;
    const state = client instanceof FoundryClient ? await client.view() : await client.state();
    const runId = state.run_id || state.mission.id;
    const log = client instanceof FoundryClient ? state.log : await client.events(0);
    if (!(client instanceof FoundryClient)) {
      const current = await client.state();
      if ((current.run_id || current.mission.id) !== runId) throw new Error("La misión ha cambiado. Vuelve a importar la nueva bitácora.");
    }
    if (this.client !== client || !this.client) throw new Error("Conexión cerrada.");
    let journal = game.journal.find(entry => entry.getFlag(ID, "runId") === runId);
    const cursor = journal?.getFlag(ID, "cursor") ?? 0;
    const fresh = newEvents(log.events, cursor);
    if (!fresh.length) { this.status.textContent = "La bitácora ya está al día."; return; }
    const html = eventsHtml(fresh);
    if (!journal) {
      journal = await JournalEntry.create({name: "Lagunak · " + state.mission.title, ownership: {default: 0}, flags: {[ID]: {runId, cursor: fresh.at(-1).seq}}, pages: [{name: "Bitácora", type: "text", text: {format: 1, content: html}}]});
    } else {
      const page = journal.pages.find(page => page.type === "text");
      if (page) await journal.updateEmbeddedDocuments("JournalEntryPage", [{_id: page.id, "text.content": (page.text.content || "") + html}]);
      else await journal.createEmbeddedDocuments("JournalEntryPage", [{name: "Bitácora", type: "text", text: {format: 1, content: html}}]);
      await journal.setFlag(ID, "cursor", fresh.at(-1).seq);
    }
    this.status.textContent = `${fresh.length} eventos importados en «${journal.name}».`;
  }
  stop() {
    clearInterval(this.timer); this.timer = null;
    this.client?.close(); this.client = null; this.lastState = null;
    this.busy = false; this.orderKey = "";
    this.orders?.replaceChildren(); this.crew?.replaceChildren(); this.ship?.replaceChildren(); this.events?.replaceChildren();
    if (this.importButton) this.importButton.disabled = true;
  }
  async close(options) { this.stop(); return super.close(options); }
}

function openPanel() {
  panel ??= new LagunakPanel();
  return panel.render({force: true});
}
Hooks.once("ready", () => { game.modules.get(ID).api = Object.freeze({open: openPanel}); });
Hooks.on("getSceneControlButtons", controls => {
  if (controls.tokens) controls.tokens.tools.lagunak = {name: "lagunak", title: "Espaciokoop Lagunak", icon: "fa-solid fa-shuttle-space", order: 90, button: true, visible: true, onChange: openPanel};
});
