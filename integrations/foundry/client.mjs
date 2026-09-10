/** Credentials never leave the explicitly selected loopback endpoint. */
export class LagunakClient {
  constructor(token, {base = "http://127.0.0.1:27841", fetcher = globalThis.fetch, timeout = 3000} = {}) {
    const url = new URL(base);
    if (url.protocol !== "http:" || !["127.0.0.1", "localhost"].includes(url.hostname) || url.username || url.password || url.search || url.hash || !["", "/"].includes(url.pathname)) {
      throw new Error("La consulta solo admite una dirección local, sin rutas ni credenciales en la URL.");
    }
    if (typeof token !== "string" || token.length < 8 || token.length > 128) throw new Error("Introduce el token de consulta de Lagunak.");
    this.base = url.origin;
    this.token = token;
    this.fetcher = fetcher;
    this.timeout = timeout;
    this.pending = new Set();
  }
  async request(path, {method = "GET", payload} = {}) {
    if (!this.token) throw new Error("El cliente está desconectado.");
    if (!/^\/v[12]\/[a-z]+(?:\?after=\d+)?$/.test(path)) throw new Error("Ruta inválida.");
    const controller = new AbortController();
    this.pending.add(controller);
    const timer = setTimeout(() => controller.abort(), this.timeout);
    try {
      const headers = {Authorization: "Bearer " + this.token};
      if (this.userId) headers["X-Lagunak-User"] = this.userId;
      if (payload !== undefined) headers["Content-Type"] = "application/json";
      const response = await this.fetcher(this.base + path, {method, headers, ...(payload === undefined ? {} : {body: JSON.stringify(payload)}), signal: controller.signal, credentials: "omit", cache: "no-store", redirect: "error"});
      if (!response.ok) throw new Error(({401: "El token no coincide con este usuario, ha caducado o se ha revocado.", 403: "El origen, el acceso o el puesto no están autorizados.", 409: "La misión o secuencia ha cambiado; actualiza antes de volver a ordenar.", 429: "Demasiadas órdenes; espera un segundo."})[response.status] ?? "La consulta devolvió HTTP " + response.status + ".");
      const text = await response.text();
      if (text.length > 1024 * 1024) throw new Error("Respuesta demasiado grande.");
      return JSON.parse(text);
    } finally {
      clearTimeout(timer);
      this.pending.delete(controller);
    }
  }
  async state() {
    const value = await this.request("/v1/state");
    if (!value || typeof value.mission?.title !== "string" || !value.ship || !Array.isArray(value.contacts)) throw new Error("Lagunak todavía no tiene una partida activa.");
    return value;
  }
  async events(after = 0) {
    if (!Number.isSafeInteger(after) || after < 0) throw new Error("Cursor de bitácora inválido.");
    const value = await this.request("/v1/events?after=" + after);
    if (!Array.isArray(value?.events) || value.events.length > 200 || !Number.isSafeInteger(value.cursor)) throw new Error("Bitácora inválida.");
    for (const event of value.events) {
      if (!Number.isSafeInteger(event.seq) || typeof event.source !== "string" || typeof event.text !== "string" || !Number.isFinite(event.time)) throw new Error("Evento inválido.");
    }
    return value;
  }
  close() {
    for (const controller of this.pending) controller.abort();
    this.pending.clear();
    this.token = "";
  }
}

export const COMMANDS = Object.freeze({
  alert: {label: "Cambiar alerta", fields: {level: ["verde", "ambar", "roja"]}},
  helm: {label: "Aplicar rumbo e impulso", fields: {heading: "heading", throttle: "throttle"}},
  autopilot: {label: "Piloto automático", fields: {target: "target"}},
  dock: {label: "Atracar", fields: {target: "target"}},
  undock: {label: "Desatracar", fields: {}},
  power: {label: "Asignar potencia", fields: {system: "system", value: "power"}},
  coolant: {label: "Refrigerar sistema", fields: {system: "system"}},
  shields: {label: "Cambiar escudos", fields: {enabled: [true, false]}},
  fire: {label: "Disparar haces", fields: {target: "target"}},
  scan: {label: "Analizar contacto", fields: {target: "target"}},
  hail: {label: "Abrir canal", fields: {target: "target"}},
  probe: {label: "Lanzar sonda", fields: {target: "target"}},
  repair: {label: "Reparar sistema", fields: {system: "system"}}
});

export class FoundryClient extends LagunakClient {
  lastView = null;
  commandBusy = false;
  viewSerial = 0;
  constructor(token, userId, options = {}) {
    super(token, options);
    if (!/^[a-f0-9]{64}$/.test(token) || !/^[A-Za-z0-9_-]{1,64}$/.test(userId)) throw new Error("Introduce el token personal emitido para tu ID de usuario.");
    this.userId = userId;
  }
  async view() {
    const serial = ++this.viewSerial;
    const value = await this.request("/v2/view");
    if (value?.protocol !== 2 || value.identity?.user_id !== this.userId || typeof value.identity.role !== "string" || typeof value.run_id !== "string" || typeof value.mission?.title !== "string" || !value.ship || !Array.isArray(value.contacts) || value.contacts.length > 48 || !value.crew || !Array.isArray(value.commands) || value.commands.some(op => !Object.hasOwn(COMMANDS, op)) || !Number.isSafeInteger(value.sequence) || value.sequence < 1 || !Array.isArray(value.log?.events) || value.log.events.length > 200 || !Number.isSafeInteger(value.log.cursor)) throw new Error("Proyección personal incompatible o inválida.");
    for (const event of value.log.events) {
      if (!Number.isSafeInteger(event.seq) || typeof event.source !== "string" || typeof event.text !== "string" || !Number.isFinite(event.time)) throw new Error("Evento inválido.");
    }
    if (this.token && this.viewSerial === serial) this.lastView = value;
    return value;
  }
  async command(operation, args = {}) {
    if (this.commandBusy) throw new Error("Ya hay una orden en curso.");
    const view = this.lastView;
    if (!view || !view.commands.includes(operation)) throw new Error("Actualiza la vista; este acceso no permite esa orden.");
    this.commandBusy = true;
    ++this.viewSerial;
    try {
      const value = await this.request("/v2/command", {method: "POST", payload: {run_id: view.run_id, sequence: view.sequence, operation, args}});
      if (typeof value?.ok !== "boolean" || typeof value.message !== "string" || !Number.isSafeInteger(value.sequence)) throw new Error("Resultado de orden inválido.");
      return value;
    } finally {
      // An ambiguous timeout must never trigger a blind retry of a mutation.
      this.commandBusy = false;
      this.lastView = null;
      ++this.viewSerial;
    }
  }
  close() { super.close(); this.lastView = null; ++this.viewSerial; }
}

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}[c]));
}
export function newEvents(events, cursor) {
  const seen = new Set();
  return events.filter(event => event.seq > cursor && !seen.has(event.seq) && seen.add(event.seq)).sort((a, b) => a.seq - b.seq);
}
export function eventsHtml(events) {
  return events.map(event => `<p><strong>${escapeHtml(event.source)}</strong> · ${Math.floor(event.time / 60)}:${String(Math.floor(event.time % 60)).padStart(2, "0")}<br>${escapeHtml(event.text)}</p>`).join("");
}
