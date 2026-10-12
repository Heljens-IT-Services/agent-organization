const TRANSPORT_VERSION = "1";
let sessionSecret = null;

export function initializeBridge() {
  const fragment = new URLSearchParams(window.location.hash.slice(1));
  sessionSecret = fragment.get("session");
  if (window.location.hash) {
    history.replaceState(null, "", `${window.location.pathname}${window.location.search}`);
  }
}

export async function dispatch(operation, payload = {}) {
  const requestId = crypto.randomUUID();
  const headers = { "Content-Type": "application/json; charset=utf-8" };
  if (sessionSecret) headers["X-Local-Session"] = sessionSecret;

  let response;
  try {
    response = await fetch("/bridge", {
      method: "POST",
      headers,
      cache: "no-store",
      body: JSON.stringify({ transportVersion: TRANSPORT_VERSION, requestId, operation, payload }),
    });
  } catch (cause) {
    throw new BridgeError("TransportUnavailable", "Die lokale Brücke ist nicht erreichbar.", { cause });
  }

  let envelope;
  try {
    envelope = await response.json();
  } catch (cause) {
    throw new BridgeError("InvalidBridgeResponse", `Die Brücke lieferte keine lesbare JSON-Antwort (HTTP ${response.status}).`, { cause, status: response.status });
  }
  if (envelope?.transportVersion !== TRANSPORT_VERSION || envelope?.requestId !== requestId || envelope?.operation !== operation || typeof envelope?.ok !== "boolean") {
    throw new BridgeError("InvalidBridgeEnvelope", "Die Antworthülle der lokalen Brücke ist ungültig.", { status: response.status });
  }
  if (!response.ok || !envelope.ok) {
    const detail = envelope.error ?? {};
    throw new BridgeError(detail.code || `Http${response.status}`, detail.message || `Die Operation ist fehlgeschlagen (HTTP ${response.status}).`, {
      status: response.status,
      commitState: detail.commitState,
      expectedRevision: detail.expectedRevision,
      actualRevision: detail.actualRevision,
      errorId: detail.errorId ?? detail.id,
      completedAt: envelope.completedAt,
    });
  }
  return { data: envelope.data, completedAt: envelope.completedAt };
}

export class BridgeError extends Error {
  constructor(code, message, details = {}) {
    super(message, details.cause ? { cause: details.cause } : undefined);
    this.name = "BridgeError";
    this.code = code;
    Object.assign(this, details);
  }
}
