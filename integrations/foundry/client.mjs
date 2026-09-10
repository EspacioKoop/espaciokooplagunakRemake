/** Read-only client. Credentials never leave the explicitly selected loopback endpoint. */
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
  async #read(path) {
    const controller = new AbortController();
    this.pending.add(controller);
    const timer = setTimeout(() => controller.abort(), this.timeout);
    try {
      const response = await this.fetcher(this.base + path, {method: "GET", headers: {Authorization: "Bearer " + this.token}, signal: controller.signal, credentials: "omit", cache: "no-store", redirect: "error"});
      if (!response.ok) throw new Error(response.status === 401 ? "El token no coincide o ha caducado." : response.status === 403 ? "El origen de Foundry no está autorizado en Lagunak." : "La consulta devolvió HTTP " + response.status + ".");
      const text = await response.text();
      if (text.length > 1024 * 1024) throw new Error("Respuesta demasiado grande.");
      return JSON.parse(text);
    } finally {
      clearTimeout(timer);
      this.pending.delete(controller);
    }
  }
  async state() {
    const value = await this.#read("/v1/state");
    if (!value || typeof value.mission?.title !== "string" || !value.ship || !Array.isArray(value.contacts)) throw new Error("Lagunak todavía no tiene una partida activa.");
    return value;
  }
  async events(after = 0) {
    if (!Number.isSafeInteger(after) || after < 0) throw new Error("Cursor de bitácora inválido.");
    const value = await this.#read("/v1/events?after=" + after);
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
