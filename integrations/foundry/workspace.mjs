/** Read-only presentation of FoundryProjection DTOs. No HTTP, storage or commands. */
const LIMIT = 48;
const COORD_LIMIT = 1e9;
const ALERTS = Object.freeze({verde: "Alerta verde", ambar: "Alerta ámbar", roja: "Alerta roja"});
const record = value => value !== null && typeof value === "object" && !Array.isArray(value) ? value : {};
const text = value => typeof value === "string" ? value.slice(0, 160).replace(/[\u0000-\u001f\u007f]/g, " ").trim() : "";
const finite = value => typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= COORD_LIMIT;
const position = value => Array.isArray(value) && value.length === 2 && value.every(finite) ? [value[0], value[1]] : null;
const heading = value => finite(value) && value >= 0 && value < 360 ? value : null;
const id = value => typeof value === "string" && value.length > 0 && value.length <= 128 ? value : null;
const format = value => value === null ? "No publicado" : value.toFixed(1).replace(/\.0$/, "").replace(".", ",");
const pointText = value => value ? `X ${format(value[0])} · Y ${format(value[1])}` : "Posición no publicada";

function destination(value, names, docking = false) {
  if (value === "" || value === false) return docking ? "Sin atraque" : "Desactivado";
  const prefix = docking ? "Atracada" : "Activo";
  if (value === true) return `${prefix} · destino no publicado`;
  if (typeof value !== "string") return "No publicado";
  // An id alone is not permission to reveal a target's identity.
  const name = names.get(id(value));
  return name ? `${prefix} · ${name}` : `${prefix} · destino no visible`;
}

/** A bounded, positive view model: never copy the incoming DTO or extra fields. */
export function buildWorkspace(source) {
  const state = record(source), ship = record(state.ship), mission = record(state.mission);
  const own = position(ship.position);
  const contacts = [], names = new Map(), seen = new Set();
  for (const raw of (Array.isArray(state.contacts) ? state.contacts.slice(0, LIMIT) : [])) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    const number = contacts.length + 1;
    const identified = raw.identified === true;
    const name = identified ? text(raw.name) || `Contacto ${number}` : `Eco ${String(number).padStart(2, "0")}`;
    const at = position(raw.position);
    const distance = own && at ? Math.hypot(at[0] - own[0], at[1] - own[1]) : null;
    contacts.push({number, name, identified, position: at, distance});
    const key = id(raw.id);
    if (key !== null) {
      if (seen.has(key)) names.delete(key); // Ambiguous ids must not name a destination.
      else names.set(key, name);
      seen.add(key);
    }
  }
  const level = typeof ship.alert === "string" && Object.hasOwn(ALERTS, ship.alert) ? ship.alert : "unknown";
  let extent = 1;
  if (own) for (const contact of contacts) if (contact.position) {
    extent = Math.max(extent, Math.abs(contact.position[0] - own[0]), Math.abs(contact.position[1] - own[1]));
  }
  return {
    alert: {level, label: level === "unknown" ? "Alerta no publicada" : ALERTS[level]},
    sector: text(mission.sector) || "No publicado",
    position: own,
    heading: heading(ship.heading),
    targetHeading: heading(ship.target_heading),
    speed: finite(ship.speed) ? ship.speed : null,
    autopilot: destination(ship.autopilot, names),
    docked: destination(ship.docked, names, true),
    contacts, extent
  };
}

/** A non-interactive supplement to the existing authorized station forms. */
export class CrewWorkspace {
  constructor(document) {
    this.document = document;
    this.element = this.node("section", "", "lagunak-workspace");
    this.element.setAttribute("aria-label", "Resumen operativo de la nave");
    this.alert = this.node("p", "", "lagunak-alert");
    this.alert.setAttribute("role", "status");
    this.alert.setAttribute("aria-live", "polite");
    this.alert.setAttribute("aria-atomic", "true");
    this.summary = this.node("dl", "", "lagunak-navigation");
    this.map = this.node("div", "", "lagunak-contact-map");
    this.map.setAttribute("role", "img");
    this.note = this.node("p", "", "lagunak-map-note");
    this.contacts = this.node("ol", "", "lagunak-contact-list");
    this.contacts.setAttribute("aria-label", "Contactos visibles y distancias");
    this.element.append(this.node("h3", "Resumen operativo"), this.alert, this.summary,
      this.node("h3", "Contactos visibles"), this.map, this.note, this.contacts);
    this.clear();
  }

  node(tag, value = "", className = "") {
    const node = this.document.createElement(tag);
    node.textContent = value;
    if (className) node.className = className;
    return node;
  }

  update(source) {
    const view = buildWorkspace(source);
    const signature = JSON.stringify(view);
    this.element.hidden = false;
    if (signature === this.signature) return;
    this.signature = signature;
    // Keep the live region stable; an unchanged alert is not announced every poll.
    if (this.alert.textContent !== view.alert.label) this.alert.textContent = view.alert.label;
    this.alert.className = `lagunak-alert lagunak-alert-${view.alert.level}`;
    this.summary.replaceChildren();
    for (const [label, value] of [
      ["Sector", view.sector], ["Posición", pointText(view.position)],
      ["Rumbo", view.heading === null ? "No publicado" : `${format(view.heading)}°`],
      ["Rumbo ordenado", view.targetHeading === null ? "No publicado" : `${format(view.targetHeading)}°`],
      ["Velocidad", format(view.speed)], ["Piloto automático", view.autopilot], ["Atraque", view.docked]
    ]) this.summary.append(this.node("dt", label), this.node("dd", value));

    this.map.replaceChildren();
    this.map.hidden = view.position === null;
    this.contacts.replaceChildren();
    if (view.position) {
      this.map.setAttribute("aria-label", "Mapa relativo: nave en el centro, X crece a la derecha, Y hacia abajo. Contactos numerados en la lista.");
      this.marker("◆", "lagunak-map-ship", 50, 50);
    } else this.map.setAttribute("aria-label", "Mapa no disponible");
    for (const contact of view.contacts) {
      if (view.position && contact.position) {
        const x = 50 + 40 * (contact.position[0] - view.position[0]) / view.extent;
        const y = 50 + 40 * (contact.position[1] - view.position[1]) / view.extent;
        this.marker(String(contact.number), contact.identified ? "lagunak-map-known" : "lagunak-map-echo", x, y);
      }
      this.contacts.append(this.node("li", `${contact.name} · ${pointText(contact.position)} · Distancia ${format(contact.distance)}`));
    }
    const visible = view.contacts.length ? `${view.contacts.length} contactos en la proyección recibida.` : "Sin contactos en la proyección recibida.";
    this.note.textContent = visible + (view.position
      ? ` Escala automática: del centro al margen marcado, ${format(view.extent)} unidades. X →, Y ↓. Distancias y velocidad en unidades de simulación; no es un Atlas.`
      : " Mapa no disponible: falta la posición de la nave.");
  }

  marker(label, className, x, y) {
    const node = this.node("span", label, `lagunak-map-marker ${className}`);
    // Only bounded numeric calculations enter CSS. Names never enter HTML or attributes.
    node.setAttribute("style", `left:${x.toFixed(3)}%;top:${y.toFixed(3)}%`);
    node.setAttribute("aria-hidden", "true");
    this.map.append(node);
  }

  clear() {
    this.signature = null;
    this.element.hidden = true;
    this.alert.textContent = "";
    this.alert.className = "lagunak-alert";
    this.summary.replaceChildren();
    this.map.replaceChildren();
    this.map.hidden = true;
    this.map.setAttribute("aria-label", "Mapa no disponible");
    this.contacts.replaceChildren();
    this.note.textContent = "";
  }
}
