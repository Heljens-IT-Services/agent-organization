// AR-108: an additive view of the existing, scoped accounting projection.
const settingsByScope = new Map();
const fields = ["totalTokens", "inputTokens", "outputTokens", "cachedInputTokens", "reasoningOutputTokens"];
const unknown = "Unbekannt";
const esc = value => String(value ?? unknown).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const label = value => value ?? unknown;
const count = value => value == null ? unknown : value.toLocaleString("de-DE");
const emptySum = () => Object.fromEntries(fields.map(field => [field, 0n]));
const seriesKey = row => JSON.stringify([row.modelId ?? null, row.reasoningEffort ?? null]);
const roleKey = row => JSON.stringify(row.roleId ?? null);
function usageOf(row) {
  if (row?.eligible !== true || !row.tokenUsage) return null;
  const usage = {};
  for (const field of fields) {
    const value = row.tokenUsage[field];
    if (typeof value === "string" && /^\d+$/.test(value)) usage[field] = BigInt(value);
    else if (Number.isSafeInteger(value) && value >= 0) usage[field] = BigInt(value);
    else return null;
  }
  if (usage.cachedInputTokens > usage.inputTokens || usage.reasoningOutputTokens > usage.outputTokens) return null;
  return usage;
}
function add(sum, usage) { for (const field of fields) sum[field] += usage[field]; }
function measurementTime(row) {
  const value = row.measurementUTC;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?Z$/.test(value)) return null;
  const time = Date.parse(value); return Number.isFinite(time) ? time : null;
}
function bucketOf(time, interval) {
  const start = new Date(time); start.setUTCHours(0, 0, 0, 0);
  if (interval === "week") start.setUTCDate(start.getUTCDate() - (start.getUTCDay() + 6) % 7);
  if (interval === "month") start.setUTCDate(1);
  const end = new Date(start);
  if (interval === "month") end.setUTCMonth(end.getUTCMonth() + 1);
  else end.setUTCDate(end.getUTCDate() + (interval === "week" ? 7 : 1));
  return { key: start.toISOString().slice(0, 10), start: start.getTime(), end: end.getTime() };
}
function seriesColor(key) { let hash = 0; for (const c of key) hash = (hash * 31 + c.charCodeAt(0)) >>> 0; return `hsl(${hash % 360} 65% 44%)`; }
function bucketDistance(start, end, interval) {
  if (interval === "month") { const a = new Date(start); const b = new Date(end); return (b.getUTCFullYear() - a.getUTCFullYear()) * 12 + b.getUTCMonth() - a.getUTCMonth(); }
  return (end - start) / (86400000 * (interval === "week" ? 7 : 1));
}
function options(values, selected) {
  return values.map(value => `<option value="${esc(JSON.stringify(value))}"${selected == null || selected.includes(JSON.stringify(value)) ? " selected" : ""}>${esc(label(value))}</option>`).join("");
}
function distinct(rows, field) { return [...new Set(rows.map(row => row[field] ?? null))].sort((a,b) => label(a).localeCompare(label(b))); }
function summaryCells(group) {
  return fields.slice(0, 3).map(field => `<td>${group.measured ? count(group.sum[field]) : unknown}</td>`).join("");
}
function periodText(bucket) { return `[${new Date(bucket.clipStart ?? bucket.start).toISOString()}, ${new Date(bucket.clipEnd ?? bucket.end).toISOString()})${bucket.partial ? " · Teilintervall" : ""}`; }
function tooltipText(bucket, series, sum, records) {
  return `${periodText(bucket)} · Rolle ${label(series.roleId)} · Modell ${label(series.modelId)} · Reasoning ${label(series.reasoningEffort)} · Gesamt ${count(sum.totalTokens)}, Input ${count(sum.inputTokens)}, Output ${count(sum.outputTokens)} · Cached Input ${count(sum.cachedInputTokens)} (Teilmenge), Reasoning Output ${count(sum.reasoningOutputTokens)} (Teilmenge) · ${records.length} native Messungen · WorkItems ${[...new Set(records.map(row => row.workItemId))].map(label).join(", ")} · Verbrauch nach finalem Messzeitpunkt (UTC); Inventar- und Familienvollständigkeit unbekannt`;
}
export function renderTokenHistory(host, projection, scope) {
  if (!projection || projection.version !== 1 || !Array.isArray(projection.records)) {
    host.innerHTML = `<p class="notice">Historische Rollenprofile unbekannt: diese Metrikquelle liefert keine History-Projektion.</p>`; return;
  }
  if (!settingsByScope.has(scope)) settingsByScope.set(scope, { role: null, interval: "day", from: "", to: "", model: null, reasoning: null, hidden: new Set() });
  const settings = settingsByScope.get(scope);
  const all = projection.records;
  const from = settings.from ? Date.parse(`${settings.from}T00:00:00Z`) : null;
  const to = settings.to ? Date.parse(`${settings.to}T00:00:00Z`) + 86400000 : null;
  const invalidPeriod = from != null && to != null && from >= to;
  const dateFilter = from != null || to != null;
  const matchesProfile = row => (settings.model == null || settings.model.includes(JSON.stringify(row.modelId ?? null))) &&
    (settings.reasoning == null || settings.reasoning.includes(JSON.stringify(row.reasoningEffort ?? null)));
  const profileRows = all.filter(matchesProfile);
  const periodRows = invalidPeriod ? [] : profileRows.filter(row => {
    const time = measurementTime(row);
    return !dateFilter || (time != null && (from == null || time >= from) && (to == null || time < to));
  });
  const rows = periodRows.filter(row => !settings.hidden.has(seriesKey(row)));
  const filteredOut = all.filter(row => !matchesProfile(row) || settings.hidden.has(seriesKey(row)));
  const unplaced = profileRows.filter(row => !settings.hidden.has(seriesKey(row)) && measurementTime(row) == null && usageOf(row));
  const measuredSummary = records => { const sum=emptySum(); let measured=0; for (const row of records) { const usage=usageOf(row); if (usage) { add(sum,usage); measured++; } } return {sum,measured}; };
  const visibleSummary=measuredSummary(rows), filteredSummary=measuredSummary(filteredOut), unplacedSummary=measuredSummary(unplaced);
  const roles = new Map();
  for (const row of rows) {
    const key = roleKey(row);
    if (!roles.has(key)) roles.set(key, { key, roleId: row.roleId, sum: emptySum(), measured: 0, missing: 0, profiles: new Map() });
    const role = roles.get(key); const profileKey = seriesKey(row);
    if (!role.profiles.has(profileKey)) role.profiles.set(profileKey, { ...row, sum: emptySum(), measured: 0, missing: 0 });
    const profile = role.profiles.get(profileKey); const usage = usageOf(row);
    if (usage) { add(role.sum, usage); add(profile.sum, usage); role.measured++; profile.measured++; }
    else { role.missing++; profile.missing++; }
  }
  const sortedRoles = [...roles.values()].sort((a,b) => label(a.roleId).localeCompare(label(b.roleId)));
  // Keep a deliberate choice through filter changes; do not silently chart another role.
  if (settings.role == null && sortedRoles.length) settings.role = sortedRoles[0].key;
  const selected = roles.get(settings.role);
  const selectedRows = periodRows.filter(row => roleKey(row) === settings.role);
  const series = new Map(); const buckets = new Map();
  for (const row of selectedRows) {
    const key = seriesKey(row);
    if (!series.has(key)) series.set(key, { key, ...row });
    const time = measurementTime(row); const usage = usageOf(row);
    if (time == null || !usage || settings.hidden.has(key)) continue;
    const bucket = bucketOf(time, settings.interval);
    bucket.clipStart = Math.max(bucket.start, from ?? bucket.start); bucket.clipEnd = Math.min(bucket.end, to ?? bucket.end);
    bucket.partial = bucket.clipStart !== bucket.start || bucket.clipEnd !== bucket.end;
    if (!buckets.has(bucket.key)) buckets.set(bucket.key, { ...bucket, series: new Map() });
    const target = buckets.get(bucket.key);
    if (!target.series.has(key)) target.series.set(key, { sum: emptySum(), records: [] });
    add(target.series.get(key).sum, usage); target.series.get(key).records.push(row);
  }
  const orderedSeries = [...series.values()].sort((a,b) => a.key.localeCompare(b.key));
  const orderedBuckets = [...buckets.values()].sort((a,b) => a.start - b.start);
  const chartSummary=measuredSummary(selectedRows.filter(row => !settings.hidden.has(seriesKey(row)) && measurementTime(row) != null));
  const summaryText = summary => `${summary.measured} Messungen · Gesamt ${summary.measured ? count(summary.sum.totalTokens) : unknown} · Input ${summary.measured ? count(summary.sum.inputTokens) : unknown} · Output ${summary.measured ? count(summary.sum.outputTokens) : unknown}`;
  const bucketTable = orderedBuckets.map(bucket => [...bucket.series.entries()].map(([key,value]) => {
    const s=series.get(key);
    return `<tr><th scope="row">${esc(periodText(bucket))} · ${esc(label(s.modelId))} · ${esc(label(s.reasoningEffort))}</th>${summaryCells({sum:value.sum,measured:value.records.length})}<td>${value.records.length}</td></tr>`;
  }).join("")).join("");
  const coverage = projection.coverage ?? {};
  const organizationScope = projection.scope?.kind === "organization_observed";
  const scopeText = organizationScope ? "Gesamtübersicht · konfigurierter Quellenumfang" : `WorkItemfamilie ${projection.scope?.workItemId ?? scope} · ${(projection.scope?.includedWorkItemIds ?? []).join(", ")}`;
  const scopeDiagnostics = `<p class="notice">${organizationScope ? "Gesamtinventar" : "Familieninventar"}: Vollständigkeit unbekannt · ${esc(coverage.status ?? "known_partial")} · Originalrooterfassung ${esc(projection.scope?.originalRootCapture ?? "nicht bewiesen")}. Familienlücken ${coverage.bindingGaps?.length ?? unknown} · Quellenfehler ${coverage.sourceFailures?.length ?? unknown}. Diese Diagnosen bleiben unabhängig von Serien- und Zeitraumfiltern erhalten.</p><details class="projection-meta"><summary>Quellenumfang, Revision und Lesefenster</summary><pre>${esc(JSON.stringify({ scope: projection.scope, projectionRevision: projection.projectionRevision, generatedAt: projection.projectionGeneratedAtUTC, readWindow: projection.readWindow, diagnostics: coverage.diagnostics }, null, 2))}</pre></details>`;
  const missing = all.filter(row => !usageOf(row)).length;
  const noTime = all.filter(row => measurementTime(row) == null).length;
  const noMetadata = all.filter(row => [row.roleId, row.modelId, row.reasoningEffort].some(value => value == null)).length;
  const conflicts = all.filter(row => Array.isArray(row.metadataConflicts) && row.metadataConflicts.length).length;
  const statusCounts = ["provisional", "measurement_missing", "accounting_identity_or_correlation_conflict", "own_native_counter_semantics_unproven"].map(reason => `${reason}: ${all.filter(row => row.exclusionReason === reason).length}`).join(" · ");
  const fieldGaps = ["roleId","modelId","reasoningEffort","measurementUTC"].map(field => `${field}: unknown ${all.filter(row => row[field] == null).length}, conflict ${all.filter(row => row.metadataConflicts?.includes(field)).length}`).join(" · ");
  const coverageMissing = ["missingExpectedExecutions", "missingExpectedNativeTurns", "executionSetUnknownWorkItemIds", "bindingGaps", "parentBindingGaps", "correlationConflicts", "nativeConflicts", "incompleteTransfers"].map(key => `${key}: ${Array.isArray(coverage[key]) ? coverage[key].length : unknown}`).join(" · ");
  host.innerHTML = `<h4>Historischer Tokenverbrauch nach Rolle</h4><p class="metric-scope">Umfang: ${esc(scopeText)}. ${esc(projection.semantics)} Zeiten und Intervalle in UTC. Gezeigte Summen sind bekannte Teilsummen; ohne Messung steht „Unbekannt“.</p>${scopeDiagnostics}
    <p class="notice">${missing} Records ohne verwendbare eigene Messung · ${noMetadata} mit fehlenden Rollen-/Modell-/Reasoningwerten · ${noTime} ohne Verbrauchszeit · ${conflicts} Metadatenkonflikte. Erwartungsmenge: ${projection.scope?.expectedSetComplete === true ? "belegt" : "nicht vollständig belegt"}; ${projection.scope?.expectedNativeKeys?.length ?? unknown} erwartete native Schlüssel beobachtet. Familienabdeckung: ${coverage.familyCompletenessProven === true ? "belegt" : "unbekannt / unvollständig"} (${esc(coverage.familyCompletenessReason)}). ${esc(coverageMissing)}</p>
    <div class="history-filters"><label>Intervall<select data-history-control="interval"><option value="day"${settings.interval === "day" ? " selected" : ""}>Tag</option><option value="week"${settings.interval === "week" ? " selected" : ""}>Woche (Montag)</option><option value="month"${settings.interval === "month" ? " selected" : ""}>Monat</option></select></label>
    <label>Von (UTC)<input type="date" data-history-control="from" value="${esc(settings.from)}"></label><label>Bis einschließlich (UTC)<input type="date" data-history-control="to" value="${esc(settings.to)}"></label>
    <label>Modell<select multiple size="4" data-history-control="model">${options(distinct(all, "modelId"), settings.model)}</select></label><label>Reasoning<select multiple size="4" data-history-control="reasoning">${options(distinct(all, "reasoningEffort"), settings.reasoning)}</select></label><button type="button" class="button button-quiet" data-history-reset>Filter zurücksetzen</button></div>
    ${invalidPeriod ? `<p class="response-lock" role="alert">Der Beginn muss vor dem Ende des Zeitraums liegen.</p>` : ""}
    <p class="metric-scope">Scope-Diagnosen bleiben ungefiltert: ${esc(statusCounts)} · ${esc(fieldGaps)}. Diagnosezahlen können sich überschneiden und werden nicht zu einer Lückensumme addiert. Mehrfachauswahl: leere Modell-/Reasoningwahl wählt keine Serie; Zurücksetzen wählt alle.</p>
    <p class="metric-scope">Sichtbare gemessene Teilsumme der Rollentabelle (alle Rollen): ${esc(summaryText(visibleSummary))}. Durch Serien-/Profilfilter ausgeblendet (zeitlich unbegrenzter Vergleich): ${esc(summaryText(filteredSummary))}. Zeitlich nicht zuordenbar bei aktueller Serien-/Profilwahl: ${esc(summaryText(unplacedSummary))}${dateFilter ? "; außerhalb der Zeitraumssumme; Zeitabdeckung unvollständig" : "; in der unbegrenzten Tabelle enthalten"}.</p>
    <p class="metric-scope">${rows.length} von ${all.length} Records im Filter. ${dateFilter ? `${noTime} Records mit unbekannter Verbrauchszeit können nicht dem Zeitraum zugeordnet werden.` : "Records ohne Verbrauchszeit stehen in der Übersicht, außerhalb des Diagramms."} Legenden-, Modell-/Reasoning- und Zeitraumfilter wirken gemeinsam auf Tabelle, Säulen, Tooltip und sichtbare Summe. ODER innerhalb Modell/Reasoning, UND zwischen den Feldern.</p>
    <div class="history-table-scroll" tabindex="0" aria-label="Rollentabelle, horizontal scrollbar"><table class="history-table"><caption>Gemessene eigene Teilsummen nach Rolle, Modell und Reasoning</caption><thead><tr><th scope="col">Rolle / Modell / Reasoning</th><th scope="col">Gesamt</th><th scope="col">Input</th><th scope="col">Output</th><th scope="col">Messungen / Lücken</th></tr></thead><tbody>${sortedRoles.map((role,index) => `<tr class="history-role"><th scope="row"><button type="button" class="button button-quiet" data-history-role="${index}" aria-pressed="${settings.role === role.key}">${esc(label(role.roleId))}</button></th>${summaryCells(role)}<td>${role.measured} / ${role.missing}</td></tr>${[...role.profiles.values()].sort((a,b) => seriesKey(a).localeCompare(seriesKey(b))).map(profile => `<tr><th scope="row">${esc(label(profile.modelId))} · ${esc(label(profile.reasoningEffort))}</th>${summaryCells(profile)}<td>${profile.measured} / ${profile.missing}</td></tr>`).join("")}`).join("") || `<tr><td colspan="5">Keine Records im gewählten Filter; Verbrauch unbekannt.</td></tr>`}</tbody></table></div>
    <h4>Zeitreihe · ${esc(selected ? label(selected.roleId) : "gewählte Rolle ohne Records im Filter")}</h4><div class="history-legend" aria-label="Serien ein- und ausblenden">${orderedSeries.map((s,index) => `<label><input type="checkbox" data-history-series="${index}"${settings.hidden.has(s.key) ? "" : " checked"}><span class="history-swatch" style="background:${seriesColor(s.key)}" aria-hidden="true"></span>${index + 1}. ${esc(label(s.modelId))} · ${esc(label(s.reasoningEffort))}</label>`).join("") || "Keine Modell-/Reasoningserien im Filter."}</div>
    <p class="metric-scope">${selectedRows.filter(row => measurementTime(row) == null).length} ausgewählte Records ohne Verbrauchszeit; ${selectedRows.filter(row => !usageOf(row)).length} ohne eigene Messung. Leere Zeitintervalle bedeuten fehlende Beobachtung, keinen belegten Nullverbrauch.</p>
    <p class="metric-scope">Sichtbare Zeitreihenteilsumme der gewählten Rolle: ${esc(summaryText(chartSummary))}. Undatierte Messungen sind hier ausgeschlossen.</p>
    <div class="history-chart" tabindex="0" aria-label="Gestapelte Zeit-Säulen, horizontal scrollbar"></div><p class="history-tooltip" role="status">Säule mit Maus oder Tastatur auswählen: Zeitraum, Zuordnung und Tokens.</p>
    <div class="history-table-scroll" tabindex="0" aria-label="Tabellenalternative der Zeitreihe"><table class="history-table"><caption>Verbrauch nach finalem Messzeitpunkt (UTC) · ${esc(selected ? label(selected.roleId) : unknown)} · gleiche Schnittintervalle und Serien wie im Diagramm; Vollständigkeit unbekannt</caption><thead><tr><th scope="col">UTC-Intervall / Modell / Reasoning</th><th scope="col">Gesamt</th><th scope="col">Input</th><th scope="col">Output</th><th scope="col">Messungen</th></tr></thead><tbody>${bucketTable || `<tr><td colspan="5">Keine zeitlich zuordenbare Messung; Verbrauch unbekannt.</td></tr>`}</tbody></table></div>
    <details class="metric-field"><summary>Messdaten, Metadatenquellen und Importzeit</summary><p>measurementUTC ist Verbrauchs-/Messzeit. importedAtUTC ist Import-/Publikationszeit und verschiebt die Zeitreihe nicht.</p><pre>${esc(JSON.stringify({ records: rows, excluded: projection.excluded, coverage }, null, 2))}</pre></details>`;
  drawChart(host, orderedBuckets, orderedSeries, settings, scope);
  // Integrate with the existing polling focus restoration, with stable identities.
  host.querySelectorAll("[data-history-control]").forEach(control => { control.dataset.focusKey = `history:${scope}:control:${control.dataset.historyControl}`; });
  host.querySelectorAll("[data-history-role]").forEach(button => { button.dataset.focusKey = `history:${scope}:role:${sortedRoles[Number(button.dataset.historyRole)].key}`; });
  host.querySelectorAll("[data-history-series]").forEach(input => { input.dataset.focusKey = `history:${scope}:series:${orderedSeries[Number(input.dataset.historySeries)].key}`; });
  host.querySelector("[data-history-reset]").dataset.focusKey = `history:${scope}:reset`;
  host.querySelector(".history-chart").dataset.focusKey = `history:${scope}:chart`;
  host.querySelector(".history-table-scroll").dataset.focusKey = `history:${scope}:table`;
  host.querySelectorAll("[data-history-control]").forEach(control => control.addEventListener("change", () => {
    const name = control.dataset.historyControl;
    settings[name] = name === "model" || name === "reasoning" ? [...control.selectedOptions].map(option => option.value) : control.value;
    renderTokenHistory(host, projection, scope);
    host.querySelector(`[data-history-control="${name}"]`)?.focus();
  }));
  host.querySelectorAll("[data-history-role]").forEach(button => button.addEventListener("click", () => {
    settings.role = sortedRoles[Number(button.dataset.historyRole)].key; renderTokenHistory(host, projection, scope);
    host.querySelector(`[data-history-role="${button.dataset.historyRole}"]`)?.focus();
  }));
  host.querySelectorAll("[data-history-series]").forEach(input => input.addEventListener("change", () => {
    const key = orderedSeries[Number(input.dataset.historySeries)].key;
    if (input.checked) settings.hidden.delete(key); else settings.hidden.add(key);
    renderTokenHistory(host, projection, scope); host.querySelector(`[data-history-series="${input.dataset.historySeries}"]`)?.focus();
  }));
  host.querySelector("[data-history-reset]").addEventListener("click", () => {
    Object.assign(settings, { from: "", to: "", model: null, reasoning: null, hidden: new Set() }); renderTokenHistory(host, projection, scope); host.querySelector("[data-history-reset]")?.focus();
  });
}
function drawChart(host, buckets, series, settings, scope) {
  const chart = host.querySelector(".history-chart");
  if (!buckets.length) { chart.innerHTML = `<p class="placeholder">Keine zeitlich zuordenbaren eigenen Messungen für die ausgewählten Serien. Verbrauch unbekannt.</p>`; return; }
  const totals = buckets.map(bucket => [...bucket.series.values()].reduce((sum,s) => sum + s.sum.totalTokens, 0n));
  const max = totals.reduce((a,b) => a > b ? a : b, 0n);
  const scaleMax = max > 0n ? max : 1n;
  const slots = bucketDistance(buckets[0].start, buckets.at(-1).start, settings.interval) + 1;
  const width = Math.max(640, 100 + slots * 78); const height = 310; const baseline = 250; const plotHeight = 210;
  const tooltips = []; const columnWidth = (width - 100) / slots;
  const bars = buckets.map((bucket,index) => {
    let y = baseline; const x = 80 + bucketDistance(buckets[0].start, bucket.start, settings.interval) * columnWidth;
    const segments = series.filter(s => !settings.hidden.has(s.key) && bucket.series.has(s.key)).map(s => {
      const value = bucket.series.get(s.key); const pixels = Number(value.sum.totalTokens * 1000000n / scaleMax) / 1000000 * plotHeight;
      y -= pixels; const tip = tooltipText(bucket, s, value.sum, value.records); const tipIndex = tooltips.push(tip) - 1;
      return `<g tabindex="0" role="img" aria-label="${esc(tip)}" data-focus-key="history:${esc(scope)}:bar:${esc(bucket.key)}:${esc(JSON.stringify([s.roleId,s.modelId,s.reasoningEffort]))}" data-history-tooltip="${tipIndex}"><title>${esc(tip)}</title><rect x="${x}" y="${value.sum.totalTokens === 0n ? baseline - 2 : y}" width="${Math.max(12,columnWidth - 20)}" height="${value.sum.totalTokens === 0n ? 2 : Math.max(0.5,pixels)}" fill="${seriesColor(s.key)}" stroke="var(--surface)" stroke-width="1"/></g>`;
    }).join("");
    return `${segments}<text x="${x}" y="275" class="history-axis">${esc(bucket.key)}</text>`;
  }).join("");
  chart.innerHTML = `<svg width="${width}" height="${height}" role="group" aria-label="Gestapelter bekannter Gesamtverbrauch, Tokens nach UTC-Zeitintervall"><text x="8" y="22" class="history-axis">Tokens</text><text x="8" y="42" class="history-axis">${count(max)}</text><text x="8" y="250" class="history-axis">0</text><line x1="70" x2="${width - 10}" y1="250" y2="250" stroke="var(--muted)"/>${bars}</svg>`;
  const tooltip = host.querySelector(".history-tooltip");
  chart.querySelectorAll("[data-history-tooltip]").forEach(segment => {
    const show = () => { tooltip.textContent = tooltips[Number(segment.dataset.historyTooltip)]; };
    segment.addEventListener("mouseenter", show); segment.addEventListener("focus", show); segment.addEventListener("click", show);
  });
}
