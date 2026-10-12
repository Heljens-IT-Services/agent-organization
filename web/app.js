import { BridgeError, dispatch, initializeBridge } from "/bridge.js";

const POLL_MS = 5000;
const STALE_AFTER_MS = 5000;
const state = { snapshot: null, selectedId: null, loadedAt: null, refreshing: false, lastReadError: null, refreshTimer: null, search: "", statusFilter: "", view: "details", collapsed: new Set(), specificationCache: new Map(), metrics: null, metricsFor: null, metricsPending: new Map(), metricsTarget: null, preserveEditorFocus: false, toastTimer: null, draft: null, drafts: new Map(), saving: false, explicitDetailFocus: false, focusGeneration: 0 };
const el = {
  connectionDot: document.getElementById("connection-dot"), connectionLabel: document.getElementById("connection-label"), dataAge: document.getElementById("data-age"),
  refreshButton: document.getElementById("refresh-button"), statusFilter: document.getElementById("status-filter"), humanFilter: document.getElementById("human-filter"), treeSearch: document.getElementById("tree-search"), workitemTree: document.getElementById("workitem-tree"), treeEmpty: document.getElementById("tree-empty"),
  itemCount: document.getElementById("item-count"), attentionCount: document.getElementById("attention-count"), attentionList: document.getElementById("attention-list"), lockStatus: document.getElementById("lock-status"),
  detailPanel: document.getElementById("detail-panel"), teamsContent: document.getElementById("teams-content"), metricsContent: document.getElementById("metrics-content"), toast: document.getElementById("toast"),
  createToggle: document.getElementById("create-toggle"), createForm: document.getElementById("create-form"), writeCapabilityNote: document.getElementById("write-capability-note"),
};

initializeBridge();
document.addEventListener("focusin", () => { state.focusGeneration++; });
el.refreshButton.addEventListener("click", () => refreshSnapshot(true));
el.treeSearch.addEventListener("input", () => { state.search = el.treeSearch.value.trim().toLocaleLowerCase(); renderTree(); refreshMetricsScope(); });
el.statusFilter.addEventListener("change", () => { state.statusFilter = el.statusFilter.value; renderTree(); refreshMetricsScope(); });
el.humanFilter.addEventListener("change", () => { el.humanFilter.value = ""; });
document.querySelectorAll("[data-view]").forEach(button => button.addEventListener("click", () => setView(button.dataset.view)));
setView("details");
el.workitemTree.addEventListener("click", event => {
  const button = event.target.closest("[data-work-item-id]"); if (!button) return;
  if (event.target.closest(".tree-chevron") && button.dataset.hasChildren === "true") { if (state.search || state.statusFilter) state.collapsed.delete(button.dataset.workItemId); else state.collapsed.has(button.dataset.workItemId) ? state.collapsed.delete(button.dataset.workItemId) : state.collapsed.add(button.dataset.workItemId); renderTree(); el.workitemTree.querySelector(`[data-work-item-id="${CSS.escape(button.dataset.workItemId)}"]`)?.focus(); return; }
  selectWorkItem(button.dataset.workItemId);
});
el.workitemTree.addEventListener("keydown", event => {
  const current = event.target.closest("[data-work-item-id]"); if (!current) return;
  const nodes = [...el.workitemTree.querySelectorAll("[data-work-item-id]")]; const index = nodes.indexOf(current); let next = null;
  if (event.key === "ArrowDown") next = nodes[Math.min(index + 1, nodes.length - 1)]; if (event.key === "ArrowUp") next = nodes[Math.max(index - 1, 0)];
  if (event.key === "Home") next = nodes[0]; if (event.key === "End") next = nodes.at(-1);
  if (event.key === "ArrowRight" && current.dataset.hasChildren === "true") { if (!(state.search || state.statusFilter) && state.collapsed.has(current.dataset.workItemId)) { state.collapsed.delete(current.dataset.workItemId); renderTree(); next = el.workitemTree.querySelector(`[data-work-item-id="${CSS.escape(current.dataset.workItemId)}"]`); } else { const candidate = nodes[index + 1]; if (candidate?.dataset.parent === current.dataset.workItemId) next = candidate; } }
  if (event.key === "ArrowLeft") { if (!(state.search || state.statusFilter) && current.dataset.hasChildren === "true" && !state.collapsed.has(current.dataset.workItemId)) { state.collapsed.add(current.dataset.workItemId); renderTree(); next = el.workitemTree.querySelector(`[data-work-item-id="${CSS.escape(current.dataset.workItemId)}"]`); } else if(current.dataset.parent) next=el.workitemTree.querySelector(`[data-work-item-id="${CSS.escape(current.dataset.parent)}"]`); }
  if (event.key === "Enter" || event.key === " ") { event.preventDefault(); selectWorkItem(current.dataset.workItemId); return; } if (next) { event.preventDefault(); next.focus(); }
});
el.attentionList.addEventListener("click", event => {
  const button = event.target.closest("[data-open-id]");
  if (button) { state.explicitDetailFocus = true; selectWorkItem(button.dataset.openId); }
});
el.createToggle.addEventListener("click", () => openCreateForm());

refreshSnapshot(false);
state.refreshTimer = window.setInterval(() => refreshSnapshot(false), POLL_MS);
window.setInterval(renderDataAge, 1000);
window.addEventListener("resize", () => { if (window.matchMedia("(min-width: 900px)").matches && state.view === "tree") setView("details"); });

async function refreshSnapshot(manual) {
  if (state.refreshing) return;
  persistActiveEditor();
  state.refreshing = true;
  el.refreshButton.disabled = true;
  try {
    const { data, completedAt } = await dispatch("read", {});
    const snapshot = data?.document ? data : data?.data?.document ? data.data : data;
    if (!snapshot || typeof snapshot !== "object") throw new BridgeError("InvalidReadData", "Die Leseoperation lieferte keinen WorkItem-Snapshot.");
    state.snapshot = snapshot;
    state.loadedAt = parseTime(data?.readAt) ?? parseTime(completedAt) ?? Date.now();
    state.lastReadError = null;
    state.specificationCache.clear();
    state.metrics = null;
    state.metricsFor = null;
    state.metricsTarget = null;
    setConnection("ok", "Verbunden");
    const renderFocus = captureFocusState();
    renderAll(renderFocus);
    renderWriteControls();
    if (state.draft?.mode === "update") {
      const current = findItem(state.draft.id);
      if (!state.selectedId) state.selectedId = state.draft.id;
      if (findItem(state.draft.id)) renderDetails(state.selectedId && findItem(state.selectedId) ? state.selectedId : state.draft.id, renderFocus);
      else {
        el.detailPanel.innerHTML = `<div class="detail-head"><h2 id="detail-title" tabindex="-1">WorkItem fehlt im aktuellen Snapshot</h2><p class="response-lock">Der Draft bleibt erhalten. Ein neuer Read oder eine neue Capability ersetzt weder seine Basis noch seine Eingaben.</p></div><div id="editor-slot" class="detail-body"></div>`;
        renderEditor(renderFocus);
      }
    } else if (state.draft?.mode === "create") renderEditor(renderFocus);
    else if (state.selectedId && findItem(state.selectedId)) renderDetails(state.selectedId, renderFocus);
    else if (state.selectedId) { state.selectedId = null; renderDetails(null, renderFocus); }
    else renderEditor(renderFocus);
    if (manual) showToast("Snapshot aktualisiert.");
  } catch (error) {
    state.lastReadError = errorMessage(error);
    setConnection("error", `Lesefehler · ${errorMessage(error)}`);
    showToast(`Aktualisierung fehlgeschlagen: ${errorMessage(error)}`, true);
    renderAll();
  } finally {
    state.refreshing = false;
    el.refreshButton.disabled = false;
    renderDataAge();
  }
}

function setConnection(kind, label) {
  el.connectionDot.className = `status-dot ${kind}`;
  el.connectionLabel.textContent = label;
}

function renderDataAge() {
  if (!state.loadedAt) { el.dataAge.textContent = "Noch keine Daten"; return; }
  const age = Math.max(0, Date.now() - state.loadedAt);
  el.dataAge.textContent = `${age > STALE_AFTER_MS ? `Daten\u00a0m\u00f6glicherweise veraltet \u2013 letzter erfolgreicher Stand: ${formatDate(state.loadedAt)} (${formatAge(age)})` : `Letzte erfolgreiche Lesung ${formatDate(state.loadedAt)} \u00b7 Datenalter ${formatAge(age)}`}`;
  el.dataAge.setAttribute("role", age > STALE_AFTER_MS ? "alert" : "status");
  el.dataAge.classList.toggle("stale-message", age > STALE_AFTER_MS);
  if (age > STALE_AFTER_MS) {
    el.connectionDot.className = "status-dot stale";
    if (state.snapshot) el.connectionLabel.textContent = state.lastReadError ? `Daten veraltet · Refresh fehlgeschlagen: ${state.lastReadError}` : "Daten veraltet";
  } else if (!state.refreshing && el.connectionDot.classList.contains("stale")) {
    el.connectionDot.className = "status-dot ok";
    el.connectionLabel.textContent = "Verbunden";
  }
}

function renderAll(focusState = null) {
  renderTree();
  renderAttention();
  renderLockStatus();
  renderTeams();
  renderMetrics(focusState);
}

function revisionOf(snapshot = state.snapshot) { return snapshot?.revision ?? snapshot?.document?.revision ?? null; }
function capabilities() { return state.snapshot?.capabilities ?? state.snapshot?.document?.capabilities ?? {}; }
function renderWriteControls() {
  const caps = capabilities();
  const canCreate = caps.create === true;
  el.createToggle.hidden = !canCreate;
  el.createToggle.disabled = !canCreate || state.saving;
  el.writeCapabilityNote.textContent = canCreate
    ? "Anlegen ist über die eingeschränkte PowerShell-Dateibrücke verfügbar. Antworten auf menschliche Anforderungen sind gesperrt."
    : "Anlegen ist laut Bridge-Capabilities nicht verfügbar.";
  if (state.draft?.mode === "create" && (!activeEditorForm(state.draft) || !canCreate)) renderEditor();
}

function renderLockStatus() {
  const lock = state.snapshot?.lock ?? state.snapshot?.document?.lock;
  if (!lock || lock.state === "unknown") {
    el.lockStatus.textContent = `Lock-Inhaber unbekannt${lock?.observedAt ? ` · Diagnose ${formatDate(lock.observedAt)}` : ""}.`;
    return;
  }
  if (lock.state === "ownerObserved" && lock.owner) {
    const owner = lock.owner;
    el.lockStatus.textContent = `Lock-Inhaber beobachtet (${lock.observedAt ? formatDate(lock.observedAt) : "Zeit unbekannt"}): ${owner.ownerName ?? "Name unbekannt"} · ${owner.host ?? "Host unbekannt"} · PID ${owner.processId ?? "unbekannt"}. Diagnose, kein Besitznachweis.`;
    return;
  }
  if (lock.state === "notObserved") {
    el.lockStatus.textContent = `Zum Zeitpunkt ${lock.observedAt ? formatDate(lock.observedAt) : "unbekannt"} kein Lock beobachtet. Das ist keine Besitzgarantie.`;
    return;
  }
  el.lockStatus.textContent = "Lockstatus unbekannt; es liegen keine belastbaren Inhaberdaten vor.";
}

function getItems() {
  const doc = state.snapshot?.document ?? state.snapshot;
  const raw = doc?.items ?? doc?.workItems ?? state.snapshot?.items ?? [];
  if (Array.isArray(raw)) return raw.filter(item => item && typeof item.id === "string");
  if (raw && typeof raw === "object") return Object.values(raw).filter(item => item && typeof item.id === "string");
  return [];
}

function findItem(id) { return getItems().find(item => item.id === id) ?? null; }
function labelOf(item) { return typeof item?.title === "string" && item.title.trim() ? item.title : item?.id ?? "Ohne Titel"; }
function humanInteraction(item) { return item?.humanInteraction && typeof item.humanInteraction === "object" ? item.humanInteraction : null; }

const STATUS = { planned:["Geplant","\u25f7"], in_progress:["In Arbeit","\u27f3"], blocked:["Blockiert","\u26d4"], implemented:["Umgesetzt","\u25cf"], rework:["Nacharbeit","\u21b6"], accepted:["Abgenommen","\u2713"], cancelled:["Abgebrochen","\u00d7"] };
function statusLabel(value) { return STATUS[value]?.[0] ?? "Status unbekannt"; }
function statusIcon(value) { return STATUS[value]?.[1] ?? "?"; }
function setView(view) { if (view === "tree" && window.matchMedia("(min-width: 900px) and (max-width: 1199px)").matches) view = "details"; state.view = view; document.body.dataset.view = view; document.querySelectorAll("[data-view]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.view === view))); }

function captureFocusState() {
  const active = document.activeElement;
  if (!active || active === document.body) return null;
  const form = active.closest?.("form.editor-form");
  return { id: active.id || null, name: active.name || null, draftKey: form?.dataset.draftKey ?? null, openId: active.dataset?.openId ?? null, focusKey: active.dataset?.focusKey ?? null, generation: state.focusGeneration,
    treeId: active.dataset?.workItemId ?? null, selectionStart: typeof active.selectionStart === "number" ? active.selectionStart : null,
    selectionEnd: typeof active.selectionEnd === "number" ? active.selectionEnd : null, selectionDirection: active.selectionDirection ?? "none" };
}
function restoreFocusState(saved) {
  if (!saved || saved.generation !== state.focusGeneration) return;
  assignFocusKeys(document);
  let target = saved.draftKey ? [...document.querySelectorAll("form.editor-form")].find(form => form.dataset.draftKey === saved.draftKey)?.elements.namedItem(saved.name) : null;
  if (!target && saved.id && !saved.draftKey) target = document.getElementById(saved.id);
  if (!target && saved.focusKey) target = document.querySelector(`[data-focus-key="${CSS.escape(saved.focusKey)}"]`);
  if (!target && saved.treeId) target = [...el.workitemTree.querySelectorAll("[data-work-item-id]")].find(node => node.dataset.workItemId === saved.treeId);
  if (!target && saved.openId) target = [...el.attentionList.querySelectorAll("[data-open-id]")].find(node => node.dataset.openId === saved.openId);
  if (!target?.isConnected) return;
  target.focus({ preventScroll: true });
  if (saved.selectionStart != null && typeof target.setSelectionRange === "function") target.setSelectionRange(saved.selectionStart, saved.selectionEnd, saved.selectionDirection);
}
function assignFocusKeys(root) {
  root.querySelectorAll("summary").forEach(summary => {
    const section = summary.closest(".detail-section")?.querySelector("h3")?.textContent?.trim() ?? "summary";
    summary.dataset.focusKey ||= `summary:${section}:${summary.textContent.trim()}`;
  });
}

function renderTree() {
  const focusedId = document.activeElement?.dataset?.workItemId ?? null;
  const items = getItems();
  el.itemCount.textContent = String(items.length);
  const byId = new Map(items.map(item => [item.id, item]));
  const children = new Map();
  for (const item of items) {
    const parent = typeof item.parentId === "string" && byId.has(item.parentId) ? item.parentId : null;
    if (!children.has(parent)) children.set(parent, []);
    children.get(parent).push(item);
  }
  for (const list of children.values()) list.sort((a, b) => labelOf(a).localeCompare(labelOf(b), "de"));
  const matching = new Set();
  if (state.search || state.statusFilter) {
    const includeParents = item => {
      if (matching.has(item.id)) return;
      matching.add(item.id);
      const parent = item.parentId && byId.get(item.parentId);
      if (parent) includeParents(parent);
    };
    for (const item of items) if ((!state.search || `${labelOf(item)} ${item.id} ${item.description ?? ""}`.toLocaleLowerCase().includes(state.search)) && (!state.statusFilter || item.status === state.statusFilter)) includeParents(item);
  }
  const attentionIds = new Set(items.filter(item => humanInteraction(item) && humanInteraction(item).response == null && item.status !== "cancelled").map(item => item.id));
  const visited = new Set();
  const suppressed = new Set();
  const rows = [];
  const visit = (item, depth) => {
    if (visited.has(item.id) || suppressed.has(item.id) || ((state.search || state.statusFilter) && !matching.has(item.id))) return;
    visited.add(item.id);
    const filterActive = Boolean(state.search || state.statusFilter);
    const effectiveCollapsed = state.collapsed.has(item.id) && !filterActive;
    const visibleChildren = (children.get(item.id) ?? []).filter(child => !filterActive || matching.has(child.id));
    const nested = effectiveCollapsed ? [] : visibleChildren;
    if (effectiveCollapsed) {
      const suppressDescendants = child => { if (suppressed.has(child.id)) return; suppressed.add(child.id); for (const descendant of children.get(child.id) ?? []) suppressDescendants(descendant); };
      for (const child of children.get(item.id) ?? []) suppressDescendants(child);
    }
    const title = labelOf(item);
    const visibleChildrenExist = visibleChildren.length > 0; const owner = item.owner?.id ?? item.owner?.name ?? "Owner unbekannt";
    rows.push(`<div class="tree-row" role="none"><button role="treeitem" aria-level="${depth + 1}" aria-expanded="${visibleChildrenExist ? String(!(state.collapsed.has(item.id) && !filterActive)) : "false"}" class="tree-item${state.selectedId === item.id ? " selected" : ""}${attentionIds.has(item.id) ? " attention" : ""}" type="button" style="--depth:${depth}" data-work-item-id="${escapeAttr(item.id)}" data-parent="${escapeAttr(item.parentId ?? "")}" data-has-children="${visibleChildrenExist}" aria-current="${state.selectedId === item.id ? "true" : "false"}" title="${escapeAttr(title)}"><span class="tree-chevron" aria-hidden="true">${visibleChildrenExist ? state.collapsed.has(item.id) && !filterActive ? "\u25b8" : "\u25be" : ""}</span><span class="tree-label">${escapeHtml(title)}</span><span class="tree-meta"><span class="tree-status-symbol status-${statusClass(item.status)}" aria-hidden="true">${statusIcon(item.status)}</span>${escapeHtml(statusLabel(item.status))} \u00b7 ${escapeHtml(owner)}</span>${attentionIds.has(item.id) ? `<span class="tree-attention" aria-label="Offene menschliche Anforderung">! Aufmerksamkeit</span>` : ""}</button></div>`);
    for (const child of nested) visit(child, depth + 1);
  };
  for (const root of children.get(null) ?? []) visit(root, 0);
  for (const item of items) if (item.parentId == null || !byId.has(item.parentId)) visit(item, 0);
  el.workitemTree.innerHTML = rows.join("");
  el.treeEmpty.hidden = rows.length > 0;
  el.treeEmpty.textContent = !items.length ? "Noch keine WorkItems vorhanden. Es werden keine Ziele oder Beispiele als echte Aufgaben angezeigt." : (state.search || state.statusFilter) ? "Keine WorkItems entsprechen dem aktuellen Such- und Statusfilter." : "Keine unverknüpften Wurzeln darstellbar. Die geladene Hierarchie enthält ungeklärte Elternbeziehungen.";
  if (focusedId) el.workitemTree.querySelector(`[data-work-item-id="${CSS.escape(focusedId)}"]`)?.focus();
}

function renderAttention() {
  const focusState = captureFocusState();
  const items = getItems();
  const open = items.filter(item => { const h = humanInteraction(item); return h && h.response == null && item.status !== "cancelled"; });
  const ended = items.filter(item => { const h = humanInteraction(item); return h && h.response == null && item.status === "cancelled"; });
  const responded = items.filter(item => { const h = humanInteraction(item); return h && h.response != null; });
  el.attentionCount.textContent = String(open.length);
  const emptyMessage = !items.length ? "Noch keine WorkItems im Snapshot." : "Keine menschlichen Anforderungen im Snapshot.";
  const hasInteraction = open.length + ended.length + responded.length > 0;
  const parentPath = item => {
    const chain = [];
    let current = item;
    const seen = new Set([item.id]);
    while (current?.parentId) {
      const parent = findItem(current.parentId);
      if (!parent || seen.has(parent.id)) break;
      seen.add(parent.id); chain.unshift(labelOf(parent)); current = parent;
    }
    return chain.length ? chain.join(" › ") : "Ziel / Elternpfad unbekannt";
  };
  const card = (item, history = false) => {
    const interaction = humanInteraction(item);
    const description = interaction?.description ?? interaction?.message ?? interaction?.request ?? "Keine verständliche Beschreibung im Snapshot vorhanden.";
    const context = [interaction?.kind && `Art: ${display(interaction.kind)}`, interaction?.requestedAt && `Angefragt: ${formatDate(interaction.requestedAt)}`, `WorkItem: ${item.id}`, `Pfad: ${parentPath(item)}`, `Zust\u00e4ndiger Mensch: ${"Unbekannt"}`, `Fortsetzung: ${interaction?.continuation ?? interaction?.affectedContinuation ?? "Nicht erfasst"}`, item.blockReason && `Blockgrund: ${display(item.blockReason)}`].filter(Boolean).join(" · ");
    const kindTitle = { clarification:"Ben\u00f6tigte Information", action:"Ihre Antwort wird ben\u00f6tigt", approval:"Menschliche Freigabe erforderlich" }[interaction?.kind] ?? "Ungekl\u00e4rte menschliche Anforderung";
    const heading = history === "responded" ? "Antwort vorhanden \u00b7 Aufl\u00f6sung unbekannt" : history === "ended" ? "Aufgabe abgebrochen \u00b7 Aufl\u00f6sung unbekannt" : kindTitle;
    const responseText = interaction?.response?.description ?? "";
    return `<article class="attention-card"><span class="attention-mark" aria-hidden="true"></span><div class="attention-main"><div class="attention-title">${heading} · ${escapeHtml(labelOf(item))}</div><div class="attention-desc">${escapeHtml(description)}</div><div class="attention-meta"><span>${escapeHtml(context)}</span>${history === "responded" && interaction?.response?.respondedAt ? `<span>Antwort: ${escapeHtml(formatDate(interaction.response.respondedAt))}</span>` : ""}</div>${history === "responded" ? `<div class="response-lock">Historische Antwort: ${escapeHtml(responseText)}. Sie wird nur angezeigt; ob sie die Anforderung auflöst, ist unbekannt.</div>` : history === "ended" ? `<div class="response-lock">Der Aufgabenstatus ist cancelled. Die Anforderung wird nicht als offen gezählt; ihre Auflösung bleibt unbekannt.</div>` : `<div class="response-lock">Verantwortliche Person unbekannt. Aufgabenowner ist keine Anforderungszuständigkeit. Antworten sind gesperrt.</div>`}</div><button class="attention-open" type="button" data-open-id="${escapeAttr(item.id)}">Ansehen</button></article>`;
  };
  const blockedOptions = ["A", "B"].map(letter => `<article class="attention-card neutral-option"><div class="attention-main"><h3 class="attention-title">Eingangsoption ${letter} (Arbeitstitel; keine Produktidentit\u00e4t)</h3><p class="attention-desc">Identit\u00e4t, Freigabegrenze und Folgeschritt: offen.</p><p class="response-lock">Identit\u00e4t, Freigabegrenze und Folgeschritt sind noch nicht durch Koordinator/Mensch gekl\u00e4rt.</p><p class="attention-meta">Keine Interaktionsart zugeordnet. Eingabe, Senden und Freigabe gesperrt.</p></div></article>`).join("");
  el.attentionList.innerHTML = `${!hasInteraction ? `<p class="placeholder">${emptyMessage}</p>` : ""}${blockedOptions}${open.map(item => card(item)).join("")}${ended.map(item => card(item, "ended")).join("")}${responded.map(item => card(item, "responded")).join("")}`;
  restoreFocusState(focusState);
}

function selectWorkItem(id) {
  persistActiveEditor();
  state.selectedId = id;
  state.draft = state.drafts.get(draftKey("update", id)) ?? null;
  state.metrics = null; state.metricsFor = null; state.metricsTarget = null;
  renderTree();
  renderDetails(id);
  renderEditor();
  renderMetrics();
  if (state.view !== "details" && (window.matchMedia("(max-width: 899px)").matches || window.matchMedia("(min-width: 900px) and (max-width: 1199px)").matches)) setView("details");
  if (state.explicitDetailFocus || window.matchMedia("(max-width: 899px)").matches || window.matchMedia("(min-width: 900px) and (max-width: 1199px)").matches) document.getElementById("detail-title")?.focus();
  state.explicitDetailFocus = false;
}

function renderDetails(id, inheritedFocus = null) {
  const focusState = inheritedFocus ?? captureFocusState();
  const item = id ? findItem(id) : null;
  if (!item) {
    el.teamsContent = null; el.metricsContent = null;
    el.detailPanel.innerHTML = `<div class="empty-state detail-empty"><span class="empty-icon" aria-hidden="true">◫</span><h2 id="detail-title" tabindex="-1">WorkItem auswählen</h2><p>Wähle links ein Ziel oder WorkItem, um Details, Verlauf und Nachweise anzusehen.</p></div>`;
    restoreFocusState(focusState);
    return;
  }
  const parents = []; const seenParents = new Set([item.id]); let parentId = item.parentId;
  while (parentId && !seenParents.has(parentId)) { seenParents.add(parentId); const ancestor = findItem(parentId); if (!ancestor) break; parents.unshift(ancestor); parentId = ancestor.parentId; }
  const crumb = [...parents.map(labelOf), labelOf(item)].map(escapeHtml).join(" <span>›</span> ");
  const fields = [
    ["Aufgabenowner", formatOwner(item.owner)], ["Ziel / Messung", formatGoal(item.goal)], ["Priorität", item.priority],
    ["Abhängigkeiten", formatList(item.dependencies)], ["Fällig", item.dueAt && formatDate(item.dueAt)], ["Erstellt", item.createdAt && formatDate(item.createdAt)],
    ["Aktualisiert", item.updatedAt && formatDate(item.updatedAt)], ["Revision", revisionOf()], ["Lock-Inhaber", state.snapshot?.lock?.owner?.ownerName ?? "Unbekannt"], ["Implementiert", item.implementedAt && formatDate(item.implementedAt)], ["Abgenommen", item.acceptedAt && formatDate(item.acceptedAt)],
  ].filter(([, value]) => value != null && value !== "");
  const criteria = Array.isArray(item.acceptanceCriteria) ? item.acceptanceCriteria : [];
  const checks = Array.isArray(item.verifications) ? item.verifications : [];
  const criterionResults = criteria.map(criterion => ({ criterion, results: checks.flatMap(check => (Array.isArray(check?.results) ? check.results : []).filter(result => result?.criterionId === criterion?.id).map(result => ({ result, check }))) }));
  const status = display(item.status ?? "Status unbekannt");
  const interaction = humanInteraction(item);
  const spec = item.specification;
  const specText = typeof spec?.inline === "string" ? spec.inline : typeof spec?.markdown === "string" ? `Markdown-Datei: ${spec.markdown}` : display(spec);
  el.detailPanel.innerHTML = `<div class="detail-head"><div class="crumb">${crumb}</div><div class="detail-title-line"><h2 id="detail-title" tabindex="-1">${escapeHtml(labelOf(item))}</h2><span class="status-pill status-${statusClass(item.status)}"><span aria-hidden="true">${statusIcon(item.status)}</span> ${escapeHtml(statusLabel(item.status))}</span></div><div class="detail-id">${escapeHtml(item.id)}${item.parentId ? ` · parentId ${escapeHtml(item.parentId)}` : " · Root (parentId: null)"}</div></div>${item.blockReason ? `<p class="response-lock"><strong>Bekannter Blockgrund:</strong> ${escapeHtml(display(item.blockReason))}</p>` : ""}<div class="detail-body">${item.description ? `<p class="detail-summary">${escapeHtml(item.description)}</p>` : ""}<div class="meta-grid">${fields.map(([label, value]) => `<div class="meta-cell"><div class="meta-label">${escapeHtml(label)}</div><div class="meta-value">${escapeHtml(display(value))}</div></div>`).join("")}</div><section class="detail-section"><h3>Spezifikation</h3><div id="specification-content" class="text-block">${spec != null ? escapeHtml(specText) : "Nicht erfasst."}</div></section><section class="detail-section"><h3>Akzeptanzkriterien · ${criteria.length}</h3>${criteria.length ? `<ul class="criteria-list">${criterionResults.map(({ criterion, results }) => `<li><strong>${escapeHtml(criterion?.id ?? "Kriterium")}</strong> · ${escapeHtml(criterion?.description ?? display(criterion))}<div class="criterion-result">${results.length ? results.map(({ result, check }) => `<p><span class="verified-pill">${result?.passed === true ? "✓ Geprüft · bestanden" : result?.passed === false ? "⛔ Geprüft · nicht bestanden" : "? Prüfergebnis unbekannt"}</span> · ${escapeHtml(display(result?.evidence ?? "Beleg nicht erfasst"))} · ${escapeHtml(check?.reviewer?.id ?? "Prüfer nicht erfasst")} · ${escapeHtml(check?.checkedAt ? formatDate(check.checkedAt) : "Prüfzeit nicht erfasst")}</p>`).join("") : `<p>Prüfergebnis unbekannt · kein criterionId-Beleg zugeordnet</p>`}</div></li>`).join("")}</ul>` : `<p class="text-block">Nicht erfasst.</p>`}</section>${item.result != null ? `<section class="detail-section"><h3>Ergebnis und Belege</h3><p class="text-block">${escapeHtml(item.result.summary ?? display(item.result))}</p>${Array.isArray(item.result.evidence) ? `<ul class="criteria-list">${item.result.evidence.map(evidence => `<li>${escapeHtml(evidence)}</li>`).join("")}</ul>` : ""}</section>` : `<section class="detail-section"><h3>Ergebnis und Belege</h3><p class="text-block">Nicht erfasst.</p></section>`}${checks.length ? `<section class="detail-section"><h3>Pr\u00fcfungen \u00b7 ${checks.length}</h3><div class="evidence-list">${checks.map((check, index) => `<article class="evidence-card"><strong><span class="verified-pill">\u2713 Gepr\u00fcft</span> ${escapeHtml(check?.reviewer?.id ? `Prüfer ${check.reviewer.type}: ${check.reviewer.id}` : `Nachweis ${index + 1}`)} · ${escapeHtml(check?.passed === true ? "bestanden" : check?.passed === false ? "nicht bestanden" : "Ergebnis unbekannt")}</strong><p>${check?.implementedAt ? `Umsetzung ${escapeHtml(formatDate(check.implementedAt))} · ` : ""}${check?.checkedAt ? `Prüfung ${escapeHtml(formatDate(check.checkedAt))}` : "Prüfzeit unbekannt"}</p>${Array.isArray(check?.results) ? check.results.map(result => `<p><strong>${escapeHtml(result.criterionId)}</strong> · ${escapeHtml(result.passed ? "bestanden" : "nicht bestanden")} · ${escapeHtml(result.evidence)}</p>`).join("") : ""}</article>`).join("")}</div></section>` : `<section class="detail-section"><h3>Pr\u00fcfungen</h3><p class="text-block">Nicht erfasst.</p></section>`}${interaction ? `<section class="detail-section"><h3>Menschliche Anforderung</h3><p class="text-block">${escapeHtml(interaction.description ?? "Beschreibung fehlt")}</p>${interaction.response != null ? `<p class="text-block" style="margin-top:8px">Historische Antwort: ${escapeHtml(interaction.response.description ?? display(interaction.response))} · ${interaction.response.respondedAt ? escapeHtml(formatDate(interaction.response.respondedAt)) : "Zeit unbekannt"}</p>` : ""}<p class="response-lock" style="margin-top:9px">Antwort und Bearbeitung dieses WorkItems sind gesperrt. Zuständigkeit und fachliche Auflösung werden nicht aus Aufgabenowner oder Antworttext abgeleitet.</p></section>` : `<section class="detail-section"><h3>Menschliche Anforderung</h3><p class="text-block">Nicht erfasst.</p></section>`}<section class="detail-section"><h3>Team und Verlauf</h3><p class="text-block">Aufgabenowner: ${escapeHtml(formatOwner(item.owner))}. Delegierende und ausf\u00fchrende Personen: Nicht erfasst, sofern keine WorkItem-Verlaufsprojektion vorliegt.</p>${Array.isArray(item.history) ? `<ul class="criteria-list">${item.history.map(entry => `<li>${escapeHtml(display(entry))}</li>`).join("")}</ul>` : `<p class="text-block">Teamzuordnung und Verlauf: Nicht erfasst.</p>`}<div id="teams-content" class="auxiliary-content"></div></section><section class="detail-section"><h3>Metriken</h3><div id="metrics-content" class="auxiliary-content"></div></section></div>`;
  if (capabilities().update === true && item.humanInteraction == null) {
    const button = document.createElement("button"); button.type = "button"; button.className = "button button-quiet"; button.dataset.focusKey = "action:edit"; button.textContent = "Redaktionell bearbeiten";
    button.addEventListener("click", () => openEditForm(item)); el.detailPanel.querySelector(".detail-head").append(button);
  } else if (item.humanInteraction != null) {
    const lock = document.createElement("p"); lock.className = "response-lock"; lock.textContent = "Bearbeitung gesperrt: Dieses WorkItem enthält eine menschliche Interaktion."; el.detailPanel.querySelector(".detail-head").append(lock);
  }
  const slot = document.createElement("div"); slot.id = "editor-slot"; el.detailPanel.querySelector(".detail-body").append(slot);
  if (state.draft?.mode === "update" && state.draft.id === item.id) renderEditor(focusState);
  el.teamsContent = el.detailPanel.querySelector("#teams-content"); el.metricsContent = el.detailPanel.querySelector("#metrics-content");
  renderTeams(); renderMetrics(focusState);
  if (typeof spec?.markdown === "string") loadSpecification(item, spec.markdown);
  assignFocusKeys(el.detailPanel);
  restoreFocusState(focusState);
}

const createFields = ["id", "parentId", "title", "description", "owner", "goal", "priority", "dependencies", "specification", "acceptanceCriteria", "dueAt"];
const updateFields = ["title", "description", "goal", "priority", "dueAt", "parentId", "dependencies", "specification", "acceptanceCriteria"];
const jsonFields = new Set(["owner", "goal", "dependencies", "specification", "acceptanceCriteria"]);
function openCreateForm() {
  if (capabilities().create !== true || !revisionOf()) return;
  persistActiveEditor();
  state.draft = state.drafts.get("create") ?? { mode: "create", baseRevision: revisionOf(), values: { parentId: "", title: "", description: "", owner: "", goal: "", priority: "", dependencies: "[]", specification: "", acceptanceCriteria: "[]", dueAt: "" }, message: "", commitState: "known" };
  state.drafts.set("create", state.draft);
  el.createForm.hidden = false; renderEditor(); el.createForm.scrollIntoView({ behavior: "smooth", block: "start" });
}
function openEditForm(item) {
  if (capabilities().update !== true || item.humanInteraction != null || !revisionOf()) return;
  persistActiveEditor();
  state.draft = state.drafts.get(draftKey("update", item.id)) ?? { mode: "update", id: item.id, baseRevision: revisionOf(), baseItem: structuredClone(item), values: Object.fromEntries(updateFields.map(key => [key, has(item, key) ? editorValue(key, item[key]) : ""])), message: "", commitState: "known" };
  state.drafts.set(draftKey("update", item.id), state.draft);
  renderEditor(); activeEditorForm(state.draft)?.scrollIntoView({ behavior: "smooth", block: "center" });
}
function editorValue(key, value) { return jsonFields.has(key) ? JSON.stringify(value, null, 2) : value == null ? "" : String(value); }
function editorHost(draft) { return draft?.mode === "create" ? el.createForm : el.detailPanel.querySelector("#editor-slot"); }
function activeEditorForm(draft) { return editorHost(draft)?.querySelector("form.editor-form") ?? null; }
function isActiveEditor(form, draft) { return state.draft === draft && form?.isConnected && form.dataset.draftKey === draftKey(draft.mode, draft.id); }
function persistActiveEditor() {
  const draft = state.draft;
  const form = activeEditorForm(draft);
  if (draft && form?.dataset.draftKey === draftKey(draft.mode, draft.id)) captureDraftFields(form, draft);
}
function renderEditor(inheritedFocus = null) {
  const focusState = inheritedFocus ?? captureFocusState();
  const draft = state.draft;
  const createHost = el.createForm;
  const updateHost = el.detailPanel.querySelector("#editor-slot");
  if (draft?.mode !== "create") { createHost.hidden = true; createHost.replaceChildren(); }
  if (draft?.mode !== "update" && updateHost) updateHost.replaceChildren();
  if (!draft) return;
  const host = editorHost(draft);
  if (!host) return;
  const reasons = editorBlockReasons(draft);
  const revisionChanged = revisionOf() !== draft.baseRevision;
  const editorLocked = reasons.some(reason => !reason.startsWith("Seit dem Öffnen geändert.")) || state.saving;
  const saveLocked = reasons.length > 0 || state.saving;
  const fields = draft.mode === "create" ? createFields : updateFields;
  const controls = fields.map(key => `<label class="editor-field${["description", "owner", "goal", "dependencies", "specification", "acceptanceCriteria"].includes(key) ? " wide" : ""}"><span>${escapeHtml(key)}${key === "title" || (key === "id" && draft.mode === "create") ? " *" : ""}</span>${jsonFields.has(key) ? `<textarea id="editor-${key}" name="${key}" aria-describedby="${key}-error" ${draft.fieldErrors?.[key] ? "aria-invalid=\"true\"" : ""} rows="${key === "acceptanceCriteria" || key === "specification" ? 5 : 3}" spellcheck="false" placeholder="${key === "dependencies" || key === "acceptanceCriteria" ? "[]" : "JSON-Wert"}" ${editorLocked ? "disabled" : ""}>${escapeHtml(draft.values[key] ?? "")}</textarea>` : `<input id="editor-${key}" name="${key}" aria-describedby="${key}-error" ${draft.fieldErrors?.[key] ? "aria-invalid=\"true\"" : ""} value="${escapeAttr(draft.values[key] ?? "")}" ${key === "title" || (key === "id" && draft.mode === "create") ? "required aria-required=\"true\"" : ""} ${key === "dueAt" ? "type=\"datetime-local\"" : ""} ${editorLocked ? "disabled" : ""}>`}<span id="${key}-error" class="field-error" ${draft.fieldErrors?.[key] ? "" : "hidden"}>${escapeHtml(draft.fieldErrors?.[key] ?? "")}</span></label>`).join("");
  const priorConflict = draft.priorConflict ? `<details class="conflict-record"><summary>Ursprünglicher Konfliktdraft · Revision ${escapeHtml(draft.priorConflict.baseRevision)}</summary><p>Ursprüngliche Eingaben:</p><pre>${escapeHtml(JSON.stringify(draft.priorConflict.values, null, 2))}</pre><p>Beim Abgleich gelesener Stand:</p><pre>${escapeHtml(JSON.stringify(draft.priorConflict.item, null, 2))}</pre></details>` : "";
  const canRebase = draft.conflict && !["unknown", "observed-present"].includes(draft.commitState);
  const latestItem = draft.mode === "update" ? findItem(draft.id) : null;
  const conflictItem = draft.conflict?.item ?? latestItem;
  const conflictSummary = draft.conflict || revisionChanged ? `<div class="conflict-record" role="alert"><strong>Abgleich erforderlich</strong><p>Basisrevision ${escapeHtml(draft.baseRevision)} · aktuelle Revision ${escapeHtml(draft.conflict?.revision ?? revisionOf() ?? "unbekannt")}</p><p>Änderungszeit/Quelle: ${escapeHtml(conflictItem?.updatedAt ?? "Nicht erfasst")} / ${escapeHtml(conflictItem?.updatedBy ?? "Nicht erfasst")}</p><p>Betroffene Felder: ${escapeHtml(Object.keys(draft.values).filter(key => JSON.stringify(conflictItem?.[key]) !== JSON.stringify(draft.baseItem?.[key])).join(", ") || "Nicht erfasst")}</p></div>` : "";
  const html = `<form class="editor-form" data-draft-key="${escapeAttr(draftKey(draft.mode, draft.id))}" novalidate><div class="editor-heading"><h3>${draft.mode === "create" ? "Neues WorkItem" : "Redaktionelle Änderung"}</h3><span>Basisrevision: <code>${escapeHtml(draft.baseRevision)}</code></span></div><p class="placeholder">Die beim Öffnen gelesene globale Bytesrevision bleibt für diesen Save fest. Polling ändert sie nicht.</p><div class="editor-grid">${controls}</div><div class="editor-actions"><button class="button" type="submit" data-focus-key="action:save" ${saveLocked ? "disabled" : ""}>${state.saving ? "Speichern …" : "Speichern"}</button><button class="button button-quiet" type="button" data-editor-action="read" data-focus-key="action:read" ${state.saving ? "disabled" : ""}>Basis bewusst neu lesen und abgleichen</button>${canRebase ? `<button class="button button-quiet" type="button" data-editor-action="rebase" data-focus-key="action:rebase" ${state.saving ? "disabled" : ""}>Eigene Eingaben in neuen Draft übernehmen</button>` : ""}<button class="button button-quiet" type="button" data-editor-action="close" data-focus-key="action:close" ${state.saving ? "disabled" : ""}>Entwurf ausdrücklich verwerfen</button></div>${reasons.map(reason => `<div class="editor-message" role="status">${escapeHtml(reason)}</div>`).join("")}<div class="editor-message" role="status" aria-live="polite">${escapeHtml(draft.message || "")}</div>${draft.progress ? `<div class="editor-message" role="status">${escapeHtml(draft.progress)}</div>` : ""}${conflictSummary}${priorConflict}</form>`;
  host.innerHTML = html;
  assignFocusKeys(host);
  restoreFocusState(focusState);
  if (draft.mode === "create") createHost.hidden = false;
  const form = host.querySelector("form.editor-form");
  form.addEventListener("input", event => captureDraft(event, draft, form));
  form.addEventListener("change", event => captureDraft(event, draft, form));
  form.addEventListener("click", event => handleEditorAction(event, draft, form));
  form.addEventListener("submit", event => saveDraft(event, draft, form));
}
function editorBlockReasons(draft) {
  const reasons = [];
  if (draft.conflict || revisionOf() !== draft.baseRevision) reasons.push("Seit dem Öffnen geändert. Ihre Eingaben sind erhalten; prüfen Sie die aktuelle Fassung und wenden Sie Ihre Änderung bewusst erneut an.");
  if (draft.commitState === "unknown") reasons.push("Commitstatus-Sperre: Status unbekannt. Erst den Readbackbefund prüfen; keine Wiederholung.");
  if (draft.commitState === "observed-present") reasons.push("Readback-Sperre: Gewünschte Fassung wurde gefunden. Keine Wiederholung.");
  if (draft.mode === "create" && capabilities().create !== true) reasons.push("Capability-Sperre: Die aktuelle Bridge erlaubt kein Create.");
  if (draft.mode === "update" && capabilities().update !== true) reasons.push("Capability-Sperre: Die aktuelle Bridge erlaubt kein Update.");
  if (draft.mode === "update" && !findItem(draft.id)) reasons.push("Item-Sperre: Dieses WorkItem fehlt im aktuellen Snapshot.");
  if (draft.mode === "update" && findItem(draft.id)?.humanInteraction != null) reasons.push("Interaktionssperre: Dieses WorkItem enthält eine menschliche Interaktion.");
  return reasons;
}
function captureDraft(event, draft, form) {
  if (!isActiveEditor(form, draft) || event.currentTarget !== form) return;
  if (!draft || !event.target?.name || !Object.prototype.hasOwnProperty.call(draft.values, event.target.name)) return;
  draft.values[event.target.name] = event.target.value;
  if (draft.fieldErrors?.[event.target.name]) { delete draft.fieldErrors[event.target.name]; event.target.removeAttribute("aria-invalid"); const errorNode = event.target.closest(".editor-field")?.querySelector(".field-error"); if (errorNode) { errorNode.textContent = ""; errorNode.hidden = true; } }
}
function handleEditorAction(event, draft, form) {
  const button = event.target.closest("[data-editor-action]"); if (!button || !isActiveEditor(form, draft)) return;
  event.preventDefault();
  if (button.dataset.editorAction === "close") {
    if (!window.confirm("Diesen Entwurf mit allen Eingaben verwerfen?")) return;
    const key = draftKey(draft.mode, draft.id);
    if (state.drafts.get(key) === draft) state.drafts.delete(key);
    state.draft = null; renderDetails(state.selectedId); renderEditor(); return;
  }
  if (button.dataset.editorAction === "rebase") { rebaseDraft(draft); return; }
  reconcileDraft(draft, false, form);
}
async function parseDraftValues(draft) {
  const result = {};
  for (const key of (draft.mode === "create" ? createFields : updateFields)) {
    const raw = draft.values[key] ?? "";
    if (key === "parentId" && raw.trim() === "") { result[key] = null; continue; }
    if (draft.mode === "create" && key === "description" && raw === "") { result[key] = ""; continue; }
    if (jsonFields.has(key)) {
      if (raw.trim() === "") { if (key === "dependencies" || key === "acceptanceCriteria") result[key] = []; else if (key === "specification") { if (draft.mode === "create" || has(draft.baseItem, key)) result[key] = null; } else if (draft.mode === "create" || has(draft.baseItem, key)) throw new Error(`${key} benötigt einen JSON-Wert; für null bitte null eingeben.`); }
      else { try { result[key] = JSON.parse(raw); } catch { throw new Error(`${key} enthält ungültiges JSON.`); } }
    } else if (key === "dueAt" && raw === "") { if (draft.mode === "update" && has(draft.baseItem, key)) result[key] = null; }
    else if (raw !== "") result[key] = key === "dueAt" && raw.length === 16 ? new Date(raw).toISOString() : raw;
  }
  return result;
}
async function saveDraft(event, draft, form) {
  event.preventDefault();
  if (!draft || !isActiveEditor(form, draft) || state.saving) return;
  if (editorBlockReasons(draft).length) { renderEditor(); return; }
  try {
    captureDraftFields(form, draft);
    const values = await parseDraftValues(draft);
    if (editorBlockReasons(draft).length) { if (state.draft === draft) renderEditor(); return; }
    if (!values.title || (draft.mode === "create" && !values.id)) { const missing = draft.mode === "create" && !values.id ? "id" : "title"; draft.fieldErrors = { ...(draft.fieldErrors ?? {}), [missing]: "Dieses Pflichtfeld muss ausgefüllt werden." }; renderEditor(); activeEditorForm(draft)?.elements.namedItem(missing)?.focus(); state.preserveEditorFocus = true; return; }
    let changes = values;
    if (draft.mode === "update") changes = Object.fromEntries(Object.entries(values).filter(([key, value]) => JSON.stringify(value) !== JSON.stringify(draft.baseItem[key])));
    if (draft.mode === "update" && !Object.keys(changes).length) { draft.message = "Keine Änderungen zum Speichern."; if (state.draft === draft) renderEditor(); return; }
    state.saving = true; draft.message = "Schreibvorgang läuft …"; if (state.draft === draft) renderEditor();
    const operation = draft.mode;
    const payload = operation === "create" ? { expectedRevision: draft.baseRevision, item: values } : { workItemId: draft.id, expectedRevision: draft.baseRevision, changes };
    const { data } = await dispatch(operation, payload);
    draft.message = `Gespeichert. Revision ${data?.revision ?? "unbekannt"}.`;
    const key = draftKey(draft.mode, draft.id);
    if (state.drafts.get(key) === draft) state.drafts.delete(key);
    if (state.draft === draft) state.draft = null;
    await refreshSnapshot(false); showToast(draft.message);
  } catch (error) {
    if (error?.commitState === "unknown" || ["TransportUnavailable", "InvalidBridgeResponse", "InvalidBridgeEnvelope"].includes(error?.code)) {
      draft.commitState = "unknown";
      draft.message = `Commitstatus unbekannt (${errorMessage(error)}). Speichern ist gesperrt; zuerst wird frisch gelesen.`;
      if (state.draft === draft) renderEditor(); state.saving = false; await reconcileDraft(draft, true); return;
    }
    const fieldMatch = String(error?.message ?? "").match(/^(id|title|parentId|description|owner|goal|priority|dependencies|specification|acceptanceCriteria|dueAt)\s/);
    if (fieldMatch) draft.fieldErrors = { ...(draft.fieldErrors ?? {}), [fieldMatch[1]]: errorMessage(error) };
    draft.message = `${errorMessage(error)}${error?.errorId ? ` · Fehler-ID ${error.errorId}` : ""}${error?.expectedRevision ? ` · erwartete Revision ${error.expectedRevision}` : ""}${error?.actualRevision ? ` · gelesene aktuelle Revision ${error.actualRevision}` : ""}. Eingaben und Basis bleiben erhalten.`;
    if (["RevisionConflict", "DuplicateWorkItemId"].includes(error?.code)) await reconcileDraft(draft, false);
  } finally { state.saving = false; if (state.draft && !state.preserveEditorFocus) renderEditor(); state.preserveEditorFocus = false; }
}
function captureDraftFields(form, draft) { for (const input of form.querySelectorAll("[name]")) draft.values[input.name] = input.value; }
async function reconcileDraft(draft = state.draft, unknown = false, form = activeEditorForm(draft)) {
  if (!draft) return;
  if (form && isActiveEditor(form, draft)) captureDraftFields(form, draft);
  draft.progress = "Lese bewusst einen neuen Stand zum Abgleich …"; if (state.draft === draft) renderEditor();
  try {
    const { data } = await dispatch("read", {}); const fresh = data?.document ? data : data?.data?.document ? data.data : data;
    const saved = draft.mode === "create" ? getItemsFrom(fresh).find(item => item.id === draft.values.id) : getItemsFrom(fresh).find(item => item.id === draft.id);
    state.snapshot = fresh; state.loadedAt = parseTime(data?.readAt) ?? Date.now();
    state.metrics = null; state.metricsFor = null; state.metricsTarget = null;
    const renderFocus = captureFocusState();
    const desired = await parseDraftValues(draft).catch(() => ({}));
    const current = draft.mode === "create" ? saved : saved;
    const differs = current ? (draft.mode === "create" ? JSON.stringify(current) !== JSON.stringify({ ...desired, status: "planned" }) : Object.entries(desired).some(([key, value]) => JSON.stringify(current[key]) !== JSON.stringify(value))) : null;
    draft.conflict = { revision: revisionOf(fresh), item: current ? structuredClone(current) : null, values: structuredClone(draft.values), differs, unknown: unknown || draft.commitState === "unknown" };
    draft.progress = "";
    if (draft.conflict.unknown && current && !differs) { draft.commitState = "observed-present"; draft.message = `Vorher unbekannter Commitstatus: aktueller Read zeigt die gewünschte Änderung. Gespeicherter Stand: ${JSON.stringify(current)}. Keine Wiederholung gesendet.`; }
    else draft.message = `${draft.conflict.unknown ? "Commitstatus bleibt unbekannt. " : "Konfliktstand frisch gelesen. "}${current ? `Aktueller Stand: ${JSON.stringify(current)}. Abweichungen zur Eingabe: ${differs ? "vorhanden" : "keine erkennbaren"}.` : `Item ${draft.mode === "create" ? draft.values.id : draft.id} im frischen Snapshot nicht vorhanden; das klärt einen unbekannten Commitstatus nicht.`} Entwurf, Basisrevision ${draft.baseRevision} und Werte bleiben erhalten. Neuer Stand ${revisionOf(fresh)}. Speichern erst nach ausdrücklicher Übernahme in einen neuen Draft.`;
    renderAll(renderFocus); renderWriteControls();
    if (state.draft !== draft) { renderEditor(renderFocus); return; }
    if (draft.mode === "update" && !findItem(draft.id)) {
      el.detailPanel.innerHTML = `<div class="detail-head"><h2 id="detail-title" tabindex="-1">WorkItem fehlt im aktuellen Snapshot</h2><p class="response-lock">Abgleich gelesen. Der Entwurf bleibt erhalten.</p></div><div id="editor-slot" class="detail-body"></div>`;
      renderEditor(renderFocus);
    } else { renderDetails(state.selectedId, renderFocus); }
  } catch (error) { draft.progress = `Abgleich fehlgeschlagen (${errorMessage(error)}). Entwurf und ursprüngliche Basis bleiben erhalten.`; if (state.draft === draft) renderEditor(); }
}
function draftKey(mode, id) { return mode === "create" ? "create" : `update:${id}`; }
function rebaseDraft(old) {
  if (!old?.conflict || ["unknown", "observed-present"].includes(old.commitState)) return;
  if (!window.confirm(`Frischen Stand ${old.conflict.revision} geprüft? Eigene Eingaben werden in einen neuen Draft übernommen; es wird noch nichts gespeichert.`)) return;
  const freshItem = old.conflict.item;
  const next = old.mode === "update" && freshItem
    ? { ...old, priorConflict: { baseRevision: old.baseRevision, baseItem: structuredClone(old.baseItem), values: structuredClone(old.values), item: structuredClone(freshItem) }, baseRevision: old.conflict.revision, baseItem: structuredClone(freshItem), values: { ...old.values }, conflict: null, commitState: "known", message: "Neuer Draft auf Basis des frisch gelesenen Stands. Prüfe die Unterschiede; Speichern ist eine separate Aktion." }
    : old.mode === "create"
      ? { ...old, priorConflict: { baseRevision: old.baseRevision, values: structuredClone(old.values), item: old.conflict.item ? structuredClone(old.conflict.item) : null }, baseRevision: old.conflict.revision, conflict: null, commitState: "known", message: "Neuer Create-Draft auf Basis der frisch gelesenen Revision. Speichern ist eine separate Aktion." }
      : null;
  if (!next) return;
  state.drafts.set(draftKey(next.mode, next.id), next); if (state.draft === old) state.draft = next; renderEditor();
}
function getItemsFrom(snapshot) { const doc = snapshot?.document ?? snapshot; const items = doc?.items ?? doc?.workItems ?? snapshot?.items ?? []; return Array.isArray(items) ? items : Object.values(items || {}); }

async function loadSpecification(item, markdownPath) {
  const box = document.getElementById("specification-content");
  if (!box) return;
  const revision = state.snapshot?.revision ?? state.snapshot?.document?.revision ?? "";
  const key = `${item.id}\u0000${revision}`;
  if (state.specificationCache.has(key)) { box.textContent = state.specificationCache.get(key); return; }
  box.textContent = `Lese Spezifikation (${markdownPath})…`;
  try {
    const { data } = await dispatch("specification", { workItemId: item.id, expectedRevision: revision });
    if (state.selectedId !== item.id || !document.getElementById("specification-content")) return;
    const content = data?.content ?? data?.data?.content;
    if (typeof content !== "string") throw new BridgeError("InvalidSpecification", "Die Spezifikationsprojektion enthält keinen Text.");
    state.specificationCache.set(key, content);
    document.getElementById("specification-content").textContent = content;
  } catch (error) {
    const target = document.getElementById("specification-content");
    if (target && state.selectedId === item.id) target.textContent = `Spezifikation nicht verfügbar: ${errorMessage(error)} · Referenz: ${markdownPath}`;
  }
}

function renderTeams() {
  if (!el.teamsContent?.isConnected) return;
  const teams = state.snapshot?.teams ?? state.snapshot?.document?.teams;
  if (!teams || teams.available !== true || !Array.isArray(teams.items)) {
    const reason = teams?.reason ?? "Es wurde keine freigegebene sichere Teamprojektion geliefert. Teamindizes werden nicht geladen.";
    el.teamsContent.innerHTML = `<div class="notice"><strong>Teamdaten unbekannt</strong>${escapeHtml(reason)}</div>`;
    return;
  }
  if (!teams.items.length) { el.teamsContent.innerHTML = `<div class="notice">Die Teamprojektion ist verfügbar, enthält aber keine Teams.</div>`; return; }
  el.teamsContent.innerHTML = teams.items.map(team => `<article class="team-entry"><div class="metric-row"><span>${escapeHtml(team.label ?? team.teamId ?? "Team")}</span><strong>${escapeHtml(team.leaderId ?? "Leitung unbekannt")} · ${Array.isArray(team.members) ? team.members.length : 0} Mitglieder</strong></div>${Array.isArray(team.members) && team.members.length ? `<ul class="team-members">${team.members.map(member => `<li>${escapeHtml(member.label ?? member.id ?? "Mitglied unbekannt")} <span>${member.available === true ? "verfügbar" : member.available === false ? "nicht verfügbar" : "Verfügbarkeit unbekannt"}</span></li>`).join("")}</ul>` : `<p class="placeholder">Mitglieder unbekannt oder nicht enthalten.</p>`}</article>`).join("");
}

async function renderMetrics(inheritedFocus = null) {
  const item = state.selectedId && findItem(state.selectedId);
  const target = el.metricsContent;
  if (!target?.isConnected) return;
  if (!item) { el.metricsContent.innerHTML = `<p class="placeholder">Wähle ein WorkItem für dessen vorhandene Metrikprojektion.</p>`; return; }
  const revision = revisionOf() ?? "unbekannte Revision";
  const key = `${item.id}\u0000${revision}`;
  if (state.metricsFor === key && state.metrics) { state.metricsTarget = target; drawMetrics(state.metrics, item, target, inheritedFocus); return; }
  const pendingFocus = inheritedFocus ?? captureFocusState();
  target.innerHTML = `<p class="placeholder">Vorhandene Projektion wird gelesen…</p>`;
  try {
    let pending = state.metricsPending.get(key);
    if (!pending) {
      pending = dispatch("metrics", { workItemId: item.id }).finally(() => { if (state.metricsPending.get(key) === pending) state.metricsPending.delete(key); });
      state.metricsPending.set(key, pending);
    }
    const { data } = await pending;
    if (state.selectedId !== item.id || (revisionOf() ?? "unbekannte Revision") !== revision || target !== el.metricsContent || !target.isConnected) return;
    state.metrics = data?.metrics ?? data?.data ?? data;
    state.metricsFor = key;
    state.metricsTarget = target;
    drawMetrics(state.metrics, item, target, pendingFocus);
    if (pendingFocus && document.activeElement === document.body) restoreFocusState(pendingFocus);
  } catch (error) {
    if (state.selectedId === item.id && (revisionOf() ?? "unbekannte Revision") === revision && target === el.metricsContent && target.isConnected) {
      target.innerHTML = `<div class="notice"><strong>Metrikprojektion nicht verfügbar</strong>${escapeHtml(errorMessage(error))}</div>`;
      if (pendingFocus && document.activeElement === document.body) restoreFocusState(pendingFocus);
    }
  }
}

function refreshMetricsScope() {
  if (state.metrics && state.metricsFor && state.metricsTarget?.isConnected) {
    const item = state.selectedId && findItem(state.selectedId);
    if (item && state.metricsFor === `${item.id}\u0000${revisionOf() ?? "unbekannte Revision"}`) drawMetrics(state.metrics, item, state.metricsTarget);
  }
}

function drawMetrics(metrics, item, target = el.metricsContent, inheritedFocus = null) {
  const focusState = inheritedFocus ?? captureFocusState();
  const metricRevision = metrics?.storeRevision ?? metrics?.revision ?? null;
  const snapshotRevision = state.snapshot?.revision ?? state.snapshot?.document?.revision ?? null;
  const mismatch = metricRevision != null && snapshotRevision != null && metricRevision !== snapshotRevision;
  const fields = ["tokenUsage", "executionCorrelation", "lifecycle", "criterionDecisions", "goalMeasurements", "measurementGaps", "measurementConflicts", "goalAchievement", "firstAcceptanceRate", "scopeLimit"];
  const projected = Object.fromEntries(fields.map(key => [key, has(metrics ?? {}, key) ? metrics[key] : "Feld in dieser Projektion nicht enthalten"]));
  const token = metrics?.tokenUsage;
  const loadedItems = getItems();
  const statusCounts = Object.fromEntries(Object.keys(STATUS).map(status => [status, loadedItems.filter(entry => entry.status === status).length]));
  const unknownStatusCount = loadedItems.filter(entry => !Object.prototype.hasOwnProperty.call(STATUS, entry.status)).length;
  const snapshotStatusCounts = `<details class="metric-field"><summary>Vertragsstatuszählung · geladener Snapshot (${loadedItems.length} WorkItems)</summary>${Object.entries(statusCounts).map(([status, count]) => `<div class="metric-row"><span>${statusIcon(status)} ${escapeHtml(statusLabel(status))}</span><strong>${count}</strong></div>`).join("")}<div class="metric-row"><span>Status unbekannt</span><strong>${unknownStatusCount}</strong></div></details>`;
  const tokenCoverage = token == null ? "Tokenabdeckung unbekannt" : `Tokenabdeckung: ${display(token.coverage ?? token.coverageStatus ?? "Status nicht ausgewiesen")}; own und inclusive getrennt, keine Summierung.`;
  const tokenScopes = token && typeof token === "object" ? ["own", "inclusive"].map(scope => `<details class="metric-field" open><summary>tokenUsage · ${scope}</summary><pre>${escapeHtml(has(token, scope) ? display(token[scope]) : "Unbekannt / nicht ausgewiesen")}</pre></details>`).join("") : ["own", "inclusive"].map(scope => `<div class="metric-row"><span>tokenUsage · ${scope}</span><strong>Unbekannt</strong></div>`).join("");
  const readWindow = metrics?.readWindow;
  const sourcePaths = Array.isArray(readWindow?.sourcePaths) ? readWindow.sourcePaths : Array.isArray(metrics?.sourcePaths) ? metrics.sourcePaths : [];
  const projectionMeta = (readWindow || sourcePaths.length) ? `<details class="projection-meta"><summary>Quellfenster und Quellen</summary><div>${readWindow ? `Lesefenster: ${escapeHtml(readWindow.startedAt ?? "unbekannt")} – ${escapeHtml(readWindow.endedAt ?? "unbekannt")} · ${escapeHtml(readWindow.consistency ?? "Konsistenz unbekannt")}` : "Lesefenster unbekannt"}</div>${sourcePaths.length ? `<ul>${sourcePaths.map(path => `<li>${escapeHtml(path)}</li>`).join("")}</ul>` : "Quellpfade unbekannt"}</details>` : `<div class="metric-revision">Quellpfade und Lesefenster unbekannt.</div>`;
  const explicit = `${snapshotStatusCounts}${tokenScopes}${fields.filter(key => key !== "tokenUsage").map(key => `<details class="metric-field"><summary>${escapeHtml(metricFieldLabel(key))}</summary><div class="metric-readable">${escapeHtml(metricReadable(key, projected[key]))}</div><pre>${escapeHtml(display(projected[key]))}</pre></details>`).join("")}`;
  const navFilter = [state.search && `Text „${state.search}“`, state.statusFilter && `Status ${statusLabel(state.statusFilter)}`].filter(Boolean).join(" · ") || "keiner";
  target.innerHTML = `<p class="metric-scope">Auswahl: ${escapeHtml(item.id)} · Revision: ${escapeHtml(snapshotRevision ?? "unbekannt")}. Baumfilter: ${escapeHtml(navFilter)} (wirkt nur auf Navigation). Kennzahlenumfang: einzelne WorkItem-Projektion wie geliefert; Statuszählung: geladener Snapshot. Keine Rollen-/Team- oder Prozentableitung.</p>${mismatch ? `<div class="notice"><strong>Revisionsabweichung</strong>Metriken und WorkItem-Snapshot stammen aus unterschiedlichen Ständen. Aktualisiere den Snapshot vor einem Vergleich.</div>` : ""}<p class="notice">${escapeHtml(tokenCoverage)}. Fehlende Felder und unbekannte Werte bleiben ausdrücklich sichtbar.</p>${explicit}<details class="projection-meta"><summary>Vollständige Rohprojektion</summary><pre>${escapeHtml(JSON.stringify(metrics, null, 2) ?? "Unbekannt")}</pre></details><div class="metric-revision">${metricRevision ? `Metrikrevision: ${escapeHtml(metricRevision)} · Snapshot: ${escapeHtml(snapshotRevision ?? "unbekannt")}` : "Revision der Metrikprojektion unbekannt"} · Projektion für ${escapeHtml(item.id)}. Keine eigene Aggregation.</div>${projectionMeta}`;
  assignFocusKeys(target);
  restoreFocusState(focusState);
}

function metricFieldLabel(key) {
  return ({ lifecycle: "Vertragsstatuszählung · lifecycle", criterionDecisions: "Kriterienentscheidungen · criterionDecisions", goalMeasurements: "Zielmessungen", measurementGaps: "Fehlende Messungen", measurementConflicts: "Messkonflikte", goalAchievement: "Zielerreichung", firstAcceptanceRate: "Erstabnahmequote", scopeLimit: "Metrikbereich", executionCorrelation: "Ausführungszuordnung" })[key] ?? key;
}
function metricReadable(key, value) {
  if (value == null || value === "Feld in dieser Projektion nicht enthalten") return display(value);
  if (key === "lifecycle" && typeof value === "object") return Object.entries(value).map(([status, count]) => `${statusLabel(status)}: ${display(count)}`).join(" · ");
  if (key === "criterionDecisions" && Array.isArray(value)) return value.map(entry => `${entry?.criterionId ?? "Kriterium unbekannt"}: ${display(entry?.decision ?? entry?.passed ?? "Entscheidung unbekannt")}${entry?.evidence ? ` · Beleg: ${display(entry.evidence)}` : ""}`).join("\n") || "Keine Kriterienentscheidungen ausgewiesen.";
  const entries = Array.isArray(value) ? value : typeof value === "object" ? Object.entries(value).map(([name, entry]) => ({ name, ...(entry && typeof entry === "object" ? entry : { value: entry }) })) : null;
  if (!entries) return display(value);
  return entries.map(entry => {
    if (!entry || typeof entry !== "object") return display(entry);
    const name = entry.name ?? entry.metric ?? entry.criterionId ?? entry.id ?? "Messwert";
    const amount = entry.value ?? entry.measuredValue ?? entry.actual ?? "Wert unbekannt";
    return [name, `Wert ${display(amount)}`, has(entry, "target") ? `Soll ${display(entry.target)}` : "Soll nicht erfasst", entry.unit ? `Einheit ${display(entry.unit)}` : "Einheit nicht erfasst", display(entry.period ?? entry.window ?? "Zeitraum nicht erfasst"), display(entry.source ?? entry.origin ?? "Herkunft nicht erfasst")].join(" · ");
  }).join("\n");
}

function formatOwner(owner) {
  if (!owner) return "Unbekannt";
  const type = owner.type === "human" ? "Menschlicher Aufgabenowner" : display(owner.type ?? "Owner");
  return `${type}: ${owner.id ?? "ID unbekannt"}`;
}
function formatGoal(goal) {
  if (!goal) return "Nicht erfasst";
  if (typeof goal === "string") return goal;
  return [goal.description, goal.metric && `Messgröße: ${goal.metric}`, has(goal, "target") && `Zielwert: ${display(goal.target)}`].filter(Boolean).join(" · ") || JSON.stringify(goal);
}
function formatList(value) { return Array.isArray(value) ? (value.length ? value.map(entry => typeof entry === "string" ? entry : entry?.id ?? JSON.stringify(entry)).join(" · ") : "Keine") : display(value); }
function statusClass(value) { return typeof value === "string" ? value.toLowerCase().replace(/[^a-z0-9_-]/g, "") : "unknown"; }
function has(obj, key) { return Object.prototype.hasOwnProperty.call(obj, key); }
function display(value) { if (value == null) return "Unbekannt"; if (typeof value === "string") return value; if (typeof value === "object") return JSON.stringify(value, null, 2); return String(value); }
function formatDate(value) { const date = parseTime(value); return date == null ? display(value) : new Intl.DateTimeFormat("de-DE", { dateStyle: "medium", timeStyle: "short" }).format(date); }
function parseTime(value) { if (value == null) return null; const parsed = Date.parse(value); return Number.isFinite(parsed) ? parsed : null; }
function formatAge(ms) { const sec = Math.floor(ms / 1000); return sec < 60 ? `${sec} s` : `${Math.floor(sec / 60)} min ${sec % 60} s`; }
function errorMessage(error) {
  const messages = {
    LockTimeout: "Die Datei wird gerade bearbeitet. Warten Sie und lesen Sie den Stand erneut.",
    LockOwnerUncertain: "Sperrinhaber nicht sicher feststellbar. Bearbeitung angehalten; Sperre nicht l\u00f6sen. Identit\u00e4t kl\u00e4ren lassen.",
    LockIdentityUnavailable: "Sperrinhaber nicht sicher feststellbar. Bearbeitung angehalten; Sperre nicht l\u00f6sen. Identit\u00e4t kl\u00e4ren lassen.",
    RevisionConflict: "Der Stand wurde inzwischen ge\u00e4ndert. Neu lesen und Ihre \u00c4nderung bewusst auf die aktuelle Fassung anwenden.",
    StoreRecoveryRequired: "Bestand kann nicht sicher geladen werden. Daten und Belege erhalten; zust\u00e4ndige Person muss die Revision kl\u00e4ren.",
    InvalidStoredDocument: "Bestand kann nicht sicher geladen werden. Daten und Belege erhalten; zust\u00e4ndige Person muss die Revision kl\u00e4ren.",
    PublishFailed: "Speicherergebnis noch zu pr\u00fcfen. Aktuellen Bestand erneut lesen; angezeigte Belege erhalten.",
    TemporaryCleanupFailed: "Speicherergebnis noch zu pr\u00fcfen. Aktuellen Bestand erneut lesen; angezeigte Belege erhalten."
  };
  if (error instanceof BridgeError && messages[error.code]) return messages[error.code];
  if (error?.code === "ValidationError") return error.message ?? "Eingabe bitte prüfen.";
  return error instanceof BridgeError ? `${error.code}: ${error.message}` : error instanceof Error ? error.message : String(error);
}
function escapeHtml(value) { return String(value).replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]); }
function escapeAttr(value) { return escapeHtml(value).replace(/`/g, "&#96;"); }
function showToast(message, error = false) { window.clearTimeout(state.toastTimer); el.toast.textContent = message; el.toast.className = `toast${error ? " error" : ""}`; el.toast.hidden = false; state.toastTimer = window.setTimeout(() => { el.toast.hidden = true; }, 5000); }
