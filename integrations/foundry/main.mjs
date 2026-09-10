import {LagunakClient, newEvents, eventsHtml} from "./client.mjs";

const ID = "espaciokoop-lagunak";
let panel;
const element = (tag, text, className) => {
  const node = document.createElement(tag);
  if (text) node.textContent = text;
  if (className) node.className = className;
  return node;
};

class LagunakPanel extends foundry.applications.api.ApplicationV2 {
  static DEFAULT_OPTIONS = {id: "lagunak-bridge", classes: ["lagunak-panel"], position: {width: 660, height: 650}, window: {title: "Espaciokoop Lagunak · Bitácora", resizable: true}};
  client = null;
  timer = null;
  busy = false;
  importing = false;
  lastState = null;

  async _renderHTML() {
    const root = element("div", "", "lagunak-content");
    root.append(element("h2", "La Itsaso, en tu mesa"));
    root.append(element("p", "Consulta el estado del juego independiente. La importación de la bitácora es manual; este módulo no envía órdenes a la nave."));
    root.append(element("p", "Origen que debes autorizar en Lagunak: " + window.location.origin, "lagunak-origin"));
    const label = element("label", "Token de consulta");
    const input = element("input");
    input.type = "password";
    input.autocomplete = "off";
    input.spellcheck = false;
    input.placeholder = "Pega el token de Sesión → Enlace con Foundry";
    label.append(input);
    root.append(label);
    const controls = element("div", "", "lagunak-actions");
    const connect = element("button", "Conectar");
    const disconnect = element("button", "Desconectar");
    const importButton = element("button", "Importar nuevos eventos a un diario");
    importButton.disabled = true;
    controls.append(connect, disconnect);
    root.append(controls, importButton);
    this.status = element("p", "Sin conexión.", "lagunak-status");
    this.ship = element("div", "", "lagunak-ship");
    this.events = element("div", "", "lagunak-events");
    root.append(this.status, this.ship, this.events);
    connect.addEventListener("click", async () => {
      this.stop();
      try {
        this.client = new LagunakClient(input.value.trim());
        input.value = "";
        await this.poll();
        if (this.lastState) {
          importButton.disabled = false;
          this.timer = setInterval(() => void this.poll(), 2000);
        }
      } catch (error) { this.status.textContent = error.message; }
    });
    disconnect.addEventListener("click", () => { this.stop(); this.status.textContent = "Desconectado."; importButton.disabled = true; });
    importButton.addEventListener("click", async () => {
      if (this.importing || !this.client || !this.lastState || !game.user.isGM) return;
      this.importing = true;
      importButton.disabled = true;
      try { await this.importJournal(); }
      catch (error) { this.status.textContent = error.message; }
      finally { this.importing = false; importButton.disabled = !this.client; }
    });
    return root;
  }
  _replaceHTML(result, content) { content.replaceChildren(result); }

  async poll() {
    if (this.busy || !this.client) return;
    this.busy = true;
    const client = this.client;
    try {
      const state = await client.state();
      const log = await client.events(0);
      if (this.client !== client) return;
      this.lastState = state;
      this.status.textContent = state.mission.title + " · " + ({active: "En curso", won: "Completada", lost: "Nave perdida"}[state.status] ?? state.status);
      this.ship.replaceChildren();
      for (const [label, value] of [["Integridad", `${Math.round(state.ship.hull)} / ${Math.round(state.ship.max_hull)}`], ["Escudos", `${Math.round(state.ship.shield)} %`], ["Energía", `${Math.round(state.ship.energy)} %`], ["Combustible", `${Math.round(state.ship.fuel)} %`]]) {
        const item = element("div");
        item.append(element("span", label), element("strong", value));
        this.ship.append(item);
      }
      this.events.replaceChildren();
      for (const event of log.events.slice(-12).reverse()) {
        const item = element("p");
        item.append(element("strong", event.source + " · "), document.createTextNode(event.text));
        this.events.append(item);
      }
    } catch (error) {
      if (this.client === client) this.status.textContent = "No se pudo consultar la nave. " + error.message;
    } finally { this.busy = false; }
  }

  async importJournal() {
    const client = this.client;
    const state = await client.state();
    const runId = state.run_id || state.mission.id;
    const log = await client.events(0);
    // A mission may change between the two HTTP requests. Never mix two flights.
    const current = await client.state();
    if ((current.run_id || current.mission.id) !== runId) throw new Error("La misión ha cambiado. Vuelve a importar la nueva bitácora.");
    let journal = game.journal.find(entry => entry.getFlag(ID, "runId") === runId);
    const cursor = journal?.getFlag(ID, "cursor") ?? 0;
    const fresh = newEvents(log.events, cursor);
    if (!fresh.length) { this.status.textContent = "La bitácora ya está al día."; return; }
    const html = eventsHtml(fresh);
    if (!journal) {
      journal = await JournalEntry.create({name: "Lagunak · " + state.mission.title, flags: {[ID]: {runId, cursor: fresh.at(-1).seq}}, pages: [{name: "Bitácora", type: "text", text: {format: 1, content: html}}]});
    } else {
      const page = journal.pages.find(page => page.type === "text");
      if (page) await journal.updateEmbeddedDocuments("JournalEntryPage", [{_id: page.id, "text.content": (page.text.content || "") + html}]);
      else await journal.createEmbeddedDocuments("JournalEntryPage", [{name: "Bitácora", type: "text", text: {format: 1, content: html}}]);
      await journal.setFlag(ID, "cursor", fresh.at(-1).seq);
    }
    this.status.textContent = `${fresh.length} eventos importados en «${journal.name}».`;
  }
  stop() {
    clearInterval(this.timer);
    this.timer = null;
    this.client?.close();
    this.client = null;
    this.lastState = null;
  }
  async close(options) { this.stop(); return super.close(options); }
}

function openPanel() {
  if (!game.user.isGM) return ui.notifications.warn("El enlace de Lagunak está reservado a la dirección de juego.");
  panel ??= new LagunakPanel();
  return panel.render({force: true});
}
Hooks.once("ready", () => { game.modules.get(ID).api = Object.freeze({open: openPanel}); });
Hooks.on("getSceneControlButtons", controls => {
  if (game.user.isGM && controls.tokens) controls.tokens.tools.lagunak = {name: "lagunak", title: "Espaciokoop Lagunak", icon: "fa-solid fa-shuttle-space", order: 90, button: true, visible: true, onChange: openPanel};
});
