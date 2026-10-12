# PR84: Integrationsvorbereitung zur unabhängigen Review

Fachbeitrag an `teamleiter_agent_ressources`, 2026-10-12. WorkItem
`improvement-scripts-order`, Phase `integration-preparation`. Umsetzung und
dieser Bericht sind keine unabhängige QA oder eigene Elternabnahme.

## Auftrag, Freigabe und finales Teilziel

Bestehender Auftragspfad: Koordinator -> Teamleiter Agent Ressources -> Optimierer.
Die menschliche Freigabe vom 2026-10-12 ist im bestehenden
`runtime/scripts-order/workitem-plan.json` dokumentiert. Die eigene frühere
Vorbereitungsabnahme liegt unter
`C:/Users/Tom-OliverMarek/AppData/Local/Temp/agent-org-scripts-order-parent-acceptance.json`:
`preparation_accepted_for_review_publication`, 12:47:35.3595482+02:00.
Eine unveränderte Kopie liegt in [den Reviewbelegen](scripts-order-evidence/parent-preparation-acceptance.json).
Der konkrete aktuelle Folgeauftrag steht in
`C:/Users/Tom-OliverMarek/AppData/Local/Temp/pr84-final-prepare.json.job.json`,
Task `c6ad842d53d74e7e941f5fcc1500093c`, Parent
`1366a0a484bd401d967c166977d72c63`.
[Integrationsteilziel und Grenzen](scripts-order-evidence/workitem-integration.json)
sind vor dem Rebase protokolliert. Der historische Plan bleibt unverändert.

Finales Teilziel: PR84 auf PR83/develop rebasiert, sämtliche aktuellen
PowerShell-Dateien nach bestehender Verantwortung geordnet, Task60-Caller
und Skillchecks nachgewiesen; sichtbarer echter neuer Starter-Smoke für eine
zulässige Folgestufe vorbereitet. Commit/Push dieses Reviewstands sind
beauftragt. Merge, Hauptcheckout und globale Spiegel sind in dieser Phase
nicht beauftragt. Story16 bleibt isoliert, Host unabgenommen; Hostfertigstellung
ist kein Gate für die Skriptordnung. Keine weitere Delegation durch Optimierer.

## SHA, Delta und fachliche Architektur

Übernommener PR84-Head: `32399a6914ecf748545b08f842b0858c901287df`.
Aktuell verifizierte develop-Basis: `4dd9d1501700857d3f035ffb5050301a7c2ac4a5`.
Konfliktfreier Rebase-Head: `c9a3e56f01c6a185552e706703e4b748a244435e`.
`git range-diff` bestätigt den ursprünglichen PR84-Commit als identisch (`=`).
Der endgültige veröffentlichte Head wird im Übergabebericht und der
Runtime-Veröffentlichungsquittung festgehalten; kein rekursiver Eigenhash.

Task60 brachte elf Dateien. Genau eine zusätzliche PS-Datei wurde verschoben:
`scripts/Test-SkillContracts.ps1` ->
`scripts/tests/contracts/Test-SkillContracts.ps1`.
Genau drei Quelltextänderungen: Helperimport `../../contracts/ContractValidation.ps1`,
Repositorywurzel drei Eltern über `$PSScriptRoot`, Fixtureziel
`scripts/tests/contracts/Test-Contracts.ps1`. Kein fachlicher Test geändert.
`SKILLS.md` nennt den aktuellen Aufruf. `TASK60-EVIDENCE.md` kennzeichnet
Altpfade und Originalhashes als historischen Abnahmestand und verlinkt die
aktuelle Integration. Acht Schema-/JSON-Dateien aus Task60 bleiben unverändert.
Keine Fachlogik-, Modell-, Reasoning-, Rechte-, Auth-, Rollen- oder Indexänderung.

Fachquelle: Bestandsanalyse `runtime/scripts-order/inventory.md`, Task
`dbbb58741cf34ab58b391697f3717e0d`; korrigierter verbindlicher Auftrag und
Umsetzung `implementation-result.json.job.json` / `implementation.md`, Task
`8c4536f93c4a401291c67145eeffe4b4`; unabhängige technische Nachprüfung
`final-review.json` / `final-review.md`, Task `081f02a34c3a4cad8cd0706f79d67f25`.
Die Teamleitung ließ Store-Modul und bestehende Worker an ihren Orten,
verwarf engine/common und Rootwrapper und gruppierte Prüfer unter contracts.
Die Domänen trennen Delegations-Lifecycle, Accounting, WorkItem-CLI/Store und
Vertragsprüfer; Tests liegen unter `tests/<Domäne>`, Prozessworker bei ihren
WorkItem-Tests. Task60 ergänzt denselben Vertragsprüfbereich. Das ist die
bestehende fachliche Ordnung, kein neuer Architekturauftrag.

```text
scripts/
  accounting/
    Get-TaskTokenUsage.ps1
    Import-RolloutTaskUsage.ps1
  contracts/
    ContractValidation.ps1
    Test-Organization.ps1
  delegation/
    Start-DelegatedCodexTask.ps1
  workitems/
    Get-WorkItems.ps1
    New-WorkItem.ps1
    Set-WorkItem.ps1
    Test-WorkItems.ps1
    WorkItemStore.psm1
  tests/
    accounting/
      Test-RolloutTaskUsage.ps1
      Test-TaskTokenUsage.ps1
    contracts/
      Test-Contracts.ps1
      Test-SkillContracts.ps1
    delegation/
      Test-DelegatedProgress.ps1
    workitems/
      RecoveryWorker.ps1
      Test-WorkItemStore.ps1
      Test-WorkItemStoreRecovery.ps1
      Worker.ps1
```

## Prüfungen, Caller und Grenzen

Die historischen **281 Checks** (75 Contracts, 14 Store, 27 Recovery,
55 Progress, 69 Rollout, 41 Accounting) bleiben die abgenommene Baseline;
die 41 Accountingchecks sind darin enthalten. Native TOML-Prüfung für 45
Dateien und der historische sichtbare Smoke werden nicht als neue Läufe gezählt.
Die 18 bisherigen PS-Dateien und alle 45 TOMLs sind gegen den alten Head
unverändert. Deshalb keine Wiederholung der breiten Suiten. Es wurden keine
Organisationsindizes geladen. Die bisherige Abnahme bleibt im
[Vorbereitungsbericht](SCRIPTS-ORDER-PREPARATION.md) getrennt nach Quellen nachlesbar.

| Aktueller Nachweis | Ergebnis | Beleg |
|---|---|---|
| Neuer Skilltest, Windows PowerShell 5.1 `-File`, separater ResultPath | 87/87, Exit 0 | [skills.json](scripts-order-evidence/skills.json) |
| Parser und striktes UTF8 | 19 PS-Dateien, 0 Parserfehler; 0 Root-PS1 | [source-verification.json](scripts-order-evidence/source-verification.json) |
| Ursprüngliche Quellen | 18 PS und 45 TOMLs identische Git-Blobs; physical SHA256 separat | derselbe Beleg |
| BOM und Checkoutbytes | 19/19 passend zum ursprünglichen Gitinhalt mit bestehendem CRLF-Checkout; Skill nur drei Pfadsubstitutionen | [checkout-bytes.json](scripts-order-evidence/checkout-bytes.json) |
| Task60-Schemas und Original-JSONs | 8/8 unverändert | derselbe Beleg |
| Aktive Altpfadscan und Callerziele | keine alten Rootskriptpfade in aktiven Skripten/aktuellen Betriebsdokumenten; alle 15 Moveziele vorhanden | [caller-verification.json](scripts-order-evidence/caller-verification.json) |
| Rebasediff / Whitespace | Rebase `=`; `git diff --check` und gestagter Check Exit 0 | Runtime-Protokoll und Übergabe |
| GitHub Actions | `enabled=false`, nur gelesen | [environment.json](scripts-order-evidence/environment.json) |

Konkreter neuer Testaufruf:
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/tests/contracts/Test-SkillContracts.ps1 -ResultPath runtime/scripts-order/integration/skills.json`.
Dieser prüft Default-PowerShell-Fixture, Pfadexistenz, Sprachen, Node-Syntax,
JSON-/Antwortsemantik und Negativfälle. Er führt weder produktive Skills noch
`Test-Contracts.ps1` aus. Produktiver Skillrunner bleibt unbelegt und außerhalb Scope.
Starter -> Accounting bleibt `../accounting/Get-TaskTokenUsage.ps1` (Zeile 561);
Store -> Validator bleibt `scripts/workitems/Test-WorkItems.ps1`;
Contracttest -> Validator/Helper bleibt `../../workitems` / `../../contracts`.
Skillcaller: Helper Zeile 4, Root Zeile 5, Fixture Zeile 105; SKILLS.md
enthält den aktuellen Testbefehl. Historische JSON-Abnahmebelege werden nicht umgeschrieben.

## Altjobs, Prozessidentität und Übergang

[Zeitgestempelter Prozessgate](scripts-order-evidence/process-preflight.json)
vergleicht Jobmetadaten, aktuelle PID, Erstellungszeit und konkrete
`-JobFile`-Kommandozeile. Die bekannten alten PR84- und Task60-Aufträge haben
keinen passenden aktuellen Runner. Story16-Teamleitung Task
`8bb5873ff87d4b849433b7b6f5a27023` ist completed; kein passender Runner.
Der ursprüngliche PR84-Teamleiter Task `9d9b284d9dfe4b73be7ecc4c5d3ba1aa`
hat Timeout und keinen terminal_outcome; aktuell kein passender Runner,
daher nicht als erfolgreich abgeschlossen bezeichnet.

Beim ersten Abgleich waren drei neue Jobgruppen geschützt: Teamleitung
`1366a0a484bd401d967c166977d72c63` (Runner 50932), Optimierer
`c6ad842d53d74e7e941f5fcc1500093c` (30960), lesende QA
`02802843702142a988dcc985306d2276` (19428). Beim letzten protokollierten
Abgleich war die QA completed und ohne passenden Runner; Teamleitung und
Optimierer waren weiterhin aktiv. Ihre Prozesse benutzen den stabilen
absoluten Übergangsstarter
`C:/Users/Tom-OliverMarek/source/repos/agent-organization-task60-preparation/scripts/Start-DelegatedCodexTask.ps1`.
Er bleibt unverändert und verfügbar. Kein Prozess, Fenster oder Worktree wurde
geschlossen oder gelöscht. Die Momentaufnahme ersetzt den unmittelbar vor
Merge/Umschaltung zu wiederholenden vollständigen Job-/Pfadabgleich nicht.
Unbekannte alte Metadaten oder fehlende Prozesszuordnung bleiben ein offener Gate.
Der ergänzte Appserver-Abgleich ordnet die sechs cmd/node/codex-Prozesse über
zeitlich plausible Elternketten den aktuellen Teamleiter-/Optimiererjobs zu;
kein unzugeordneter Appserver in dieser Momentaufnahme. Eine breitere spätere
Umschaltprüfung bleibt erforderlich. Die parallele unabhängige QA meldet
Accountinglücken bei zwei alten Leitungen und zwei Story16-Abbrüchen; diese
werden nicht durch eine Prozessbeendigung oder fehlende Runner geschlossen.

## Sichtbarer echter Smoke: eigener Plan und paralleler Teamleiterlauf

[Smokeplan](scripts-order-evidence/new-starter-smoke-plan.json) enthält Rolle,
dreiwortigen Titel, absoluten neuen Starter, Arbeitsverzeichnis, ResultPath,
gemeinsames Accounting und **ParentTaskId der Teamleitung**. Auftrag: keine Tools,
Dateizugriffe oder Delegationen, ausschließlich `SCRIPTS_ORDER_SMOKE_OK`.
Die Teamleitung startet den Smoke direkt als dritten Agentenlevel; der aktuelle
Optimierer startet keinen weiteren Agenten. Keine produktive Änderung.

Bis zur Umstellung erfolgen sämtliche tatsächlichen Starts über den stabilen
Übergangsstarter. Ein direkter neuer-Starter-Smoke davor benötigt eine ausdrücklich
abgegrenzte Smokeausnahme durch die Teamleitung; alternativ folgt er nach der
koordinierten Umstellung in eigener Folgestufe über den neuen Mainstarter.
Der Plan ist ein vorbereiteter Aufruf, kein bestandener Sichtbarkeitsnachweis.
Konkreter Aufruf durch die Teamleitung, ausschließlich nach Erfüllung dieses Gates:

```powershell
& 'C:/Users/Tom-OliverMarek/source/repos/agent-organization-scripts-order/scripts/delegation/Start-DelegatedCodexTask.ps1' `
  -Role agent_ressources_optimierer -TaskTitle 'Neuer Starter Smoke' `
  -Task 'Keine Tools, keine Dateizugriffe, keine Delegationen. Antworte ausschliesslich SCRIPTS_ORDER_SMOKE_OK.' `
  -WorkingDirectory 'C:/Users/Tom-OliverMarek/source/repos/agent-organization-scripts-order' `
  -ResultPath 'C:/Users/Tom-OliverMarek/source/repos/agent-organization-scripts-order/runtime/scripts-order/integration/new-starter-smoke.json' `
  -ParentTaskId '1366a0a484bd401d967c166977d72c63' `
  -AccountingDirectory 'C:/Users/Tom-OliverMarek/AppData/Local/Temp/agent-org-backlog-accounting' `
  -TimeoutSeconds 120
```

Nach Umstellung kann derselbe Aufruf den neuen Mainstarter verwenden. Die
Teamleitung aktualisiert ParentTaskId bei einem späteren eigenen Lauf; die
oben gebundene ID ist die aktuelle Teamleitung und nicht der Optimierertask.
Erforderliche Belege: go/window-ACK visible, controller_visibility_confirmed,
console_binding_verified, tatsächlicher neuer Runnerpfad, exakte Antwort,
success/completed, window_closed, usage_finalized, Parent/Ledgerzuordnung und
keine Toolitems. Own/inclusive nicht addieren. Fehlende Messung bleibt unbekannt.
Der aktuelle Optimiererstart hat ein sichtbares gebundenes ACK im separaten
`%TEMP%/pr84-final-prepare.json.go.json`; das beweist keinen neuen-Starter-Smoke.

Während dieser Vorbereitung hat die Teamleitung unabhängig einen zulässigen
direkten neuen-Pfad-Smoke auf Ebene drei ausgeführt, Task
`7446a7a6727043278d475d0f160ebb7e`, Rolle `agent_ressources_bestandsanalyse`.
Der begrenzte Auftrag erlaubt Lesen von maximal acht README-Zeilen sowie
Pfadexistenzprüfungen, verbietet Änderungen und weitere Delegationen und
kennzeichnet die ausdrückliche neue-Pfad-Smokeausnahme. Dies ist ein anderer
Lauf als der oben vorbereitete exakte No-Tool-Smoke und wird getrennt ausgewiesen.

[Resultat](scripts-order-evidence/teamleader-smoke-result.json),
[sichtbares ACK](scripts-order-evidence/teamleader-smoke-go.json),
[Job](scripts-order-evidence/teamleader-smoke-job.json),
[Fensterbindung](scripts-order-evidence/teamleader-smoke-window.json) und
[Starter-Aufrufprovenienz](scripts-order-evidence/smoke-launch-provenance.json)
belegen den echten neuen Worktree-Starter. completed/success, visible,
controller_visibility_confirmed, console_binding_verified, window_closed
und usage_finalized sind true. Ausgabe enthält SMOKE_OK, explizite Rolle,
Arbeitsverzeichnis, README-Header und beide aktuellen Starter-/Skillpfade.
Parent ist die aktuelle Teamleitung `1366a0a484bd401d967c166977d72c63`, Accounting
das gemeinsame `agent-org-backlog-accounting`. Own=inclusive **70.641 Tokens**,
ein deduplizierter Datensatz, missing_count=0; einmal zählen, kein Eigenverbrauch
dieses Optimierers. Keine vierte Agentenebene. Diese fremde beauftragte Evidenz
ersetzt keine unabhängige finale Headabnahme; der ursprüngliche Plan bleibt vorbereitet.

## Backup-/Spiegelplan und verbleibende Abnahmen

Branchbackup vor Rebase: `runtime/scripts-order/integration/pr84-before-rebase.bundle`.
Wiederherstellung nur des eigenen Branchs aus diesem Bundle; keine fremden
Worktrees, keine pauschalen Resets. Remoteupdate mit Lease auf den übernommenen
PR84-Head; bei konkurrierendem Remotehead stoppen und an Teamleitung berichten.

Vor späterem Merge: unabhängige QA an finaler Head-SHA, eigene dokumentierte
Elternabnahme und aktueller Altjob-/Pfadgate. Stabile Task60-Kopie und laufende
Aufträge behalten ihre Pfade; zukünftige Vorlagen werden vor Umschaltung angepasst.
Kein Hauptcheckoutupdate oder globaler Spiegel in dieser Vorbereitung.

Spätere Spiegelquelle ist ausschließlich der nach Merge per Fast-forward
aktualisierte saubere develop-Hauptcheckout, niemals dieser Featureworktree.
Die Teamleitung lässt vor jedem Schreiben eine konkrete Allowlist aus ihren
beauftragten Rollen-/Indexspiegeln und kanonischen Quellpfaden erstellen;
Organisationsindizes werden durch diesen Optimierer nicht geladen. Je Ziel:
vorhandene Datei bytegenau sichern, SHA256/Existenz/Quell- und Zielpfad in einem
Manifest erfassen, fehlende Ziele kennzeichnen, aus gemergter Quelle kopieren
und bytegleich unabhängig zurücklesen. Nur diese Ziele zurückrollen; fremde
Legacy-Dateien und persönliche Config erhalten. Keine Branch-/Worktree-Löschung.
Eine genaue globale Zielallowlist ist in diesem Vorbereitungsauftrag nicht
übergeben und wird deshalb nicht erfunden.

Offen: unabhängige finale QA einschließlich Bewertung des aktuellen echten
Teamleiter-Smokes, eigene Integrationsabnahme, unmittelbar vor Umschaltung erneuter Prozessgate sowie
konkreter Backup-/Spiegelallowlist. Story16/Host folgt eigenständig und bleibt
unabgenommen. Doppelte globale Rollendefinitionswarnung bleibt Umweltbefund.
Fast-/Modell-/Reasoningkonfiguration wurde nicht geändert; aktuelles Jobmetadata
enthält keinen Fast/service_tier-Override.
Das effektive Fast-Aus ist damit noch nicht unabhängig nachgewiesen und bleibt
ein konkretes Abnahmekriterium; keine persönliche Config wurde dafür geladen.
Kein eigenständiger
GitHub-Administrationsbedarf festgestellt; CI bleibt deaktiviert.
Gemessener finaler Eigenverbrauch dieses noch laufenden Tasks ist unbekannt;
historische Kinderwerte werden nicht als Eigenverbrauch übernommen.
