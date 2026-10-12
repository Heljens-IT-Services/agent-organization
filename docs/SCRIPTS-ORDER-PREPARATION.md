# improvement-scripts-order: Vorbereitung zur Review

Stand: 2026-10-12. Fachbeitrag an `teamleiter_agent_ressources`. WorkItem `improvement-scripts-order`: **preparation-accepted-for-review**. Die eigene Teamleiter-Vorbereitungsabnahme ist erteilt; Commit, Push und Review-PR auf develop sind beauftragt. Integration, Merge und Gesamtabschluss bleiben offen; globaler Rollout ist nicht freigegeben.

## Freigabe, Ownership und Teilziele

WorkItem `improvement-scripts-order`, Typ Improvement, Owner `teamleiter_agent_ressources`, Parent-Task `9d9b284d9dfe4b73be7ecc4c5d3ba1aa`. Der vorhandene Plan dokumentiert die menschliche Freigabe vom 2026-10-12 und den Auftragspfad Koordinator -> Teamleiter Agent Ressources -> Optimierer. Scope: vorhandene Skripte nach Verantwortung verschieben und notwendige Pfade korrigieren, keine unabhängigen Logikänderungen.

Die bereits beauftragten Kinderziele laut Plan sind:

| Kind | Fachbeitrag | Ziel |
|---|---|---|
| inventory | agent_ressources_bestandsanalyse | Ordnerarchitektur und Abhängigkeitsinventar |
| implementation | agent_ressources_optimierer | Begrenzte Moves, Pfadkorrekturen, aussagekräftige Checks und neuer sichtbarer Starter-Smoke |
| independent-review | agent_ressources_qualitaetspruefung | Unabhängige Prüfnachweise |

Dies dokumentiert bestehende Aufträge, erteilt keine neuen und erweitert keine Rolle. Kinderabschlüsse ersetzen keine eigene Elternabnahme. Die Nacharbeit ist vom ursprünglichen ausdrücklich freigegebenen Einsortierungs- und Prüfauftrag umfasst und wurde durch den Teamleiter an den Optimierer delegiert; keine zusätzliche menschliche Freigabe wurde behauptet/eingeholt. Die damalige Fixture- und Dokumentationsnacharbeit beschränkte sich auf die bestehende Test-Allowlist und diese drei Evidenzdokumente: `runtime/scripts-order/accounting-repair.md`, `runtime/scripts-order/implementation.md`, `docs/SCRIPTS-ORDER-PREPARATION.md`.

Arbeitsbereich ausschließlich `C:/Users/Tom-OliverMarek/source/repos/agent-organization-scripts-order`, Branch `improvement/scripts-task-folders`. Fremde Änderungen werden erhalten, die parallel laufende Qualitätsprüfung arbeitet lesend. Main, fremde Worktrees, globale Rollen/Mirrors und JSON-Indizes sind nicht Teil dieser Nacharbeit. GitHub Actions bleiben deaktiviert.

## Vollständiger finaler Dateibaum

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
      Test-TaskTokenUsage.ps1
      Test-RolloutTaskUsage.ps1
    contracts/
      Test-Contracts.ps1
    delegation/
      Test-DelegatedProgress.ps1
    workitems/
      Test-WorkItemStore.ps1
      Test-WorkItemStoreRecovery.ps1
      Worker.ps1
      RecoveryWorker.ps1
```

14 Moves; keine `scripts/*.ps1`, kein engine/common-Framework und keine permanenten Rootwrapper. Vier vorhandene Dateien bleiben am selben Ort: `scripts/contracts/ContractValidation.ps1`, `scripts/workitems/WorkItemStore.psm1`, `scripts/tests/workitems/Worker.ps1`, `scripts/tests/workitems/RecoveryWorker.ps1`.

| Original | Final |
|---|---|
| scripts/Start-DelegatedCodexTask.ps1 | scripts/delegation/Start-DelegatedCodexTask.ps1 |
| scripts/Get-TaskTokenUsage.ps1 | scripts/accounting/Get-TaskTokenUsage.ps1 |
| scripts/Import-RolloutTaskUsage.ps1 | scripts/accounting/Import-RolloutTaskUsage.ps1 |
| scripts/Get-WorkItems.ps1 | scripts/workitems/Get-WorkItems.ps1 |
| scripts/New-WorkItem.ps1 | scripts/workitems/New-WorkItem.ps1 |
| scripts/Set-WorkItem.ps1 | scripts/workitems/Set-WorkItem.ps1 |
| scripts/Test-WorkItems.ps1 | scripts/workitems/Test-WorkItems.ps1 |
| scripts/Test-Organization.ps1 | scripts/contracts/Test-Organization.ps1 |
| scripts/Test-Contracts.ps1 | scripts/tests/contracts/Test-Contracts.ps1 |
| scripts/Test-DelegatedProgress.ps1 | scripts/tests/delegation/Test-DelegatedProgress.ps1 |
| scripts/Test-TaskTokenUsage.ps1 | scripts/tests/accounting/Test-TaskTokenUsage.ps1 |
| scripts/Test-RolloutTaskUsage.ps1 | scripts/tests/accounting/Test-RolloutTaskUsage.ps1 |
| scripts/Test-WorkItemStore.ps1 | scripts/tests/workitems/Test-WorkItemStore.ps1 |
| scripts/Test-WorkItemStoreRecovery.ps1 | scripts/tests/workitems/Test-WorkItemStoreRecovery.ps1 |

## Scope- und Ergebnisbelege

Quelle sind die vorhandenen Berichte und Resultate unter `runtime/scripts-order/`: `workitem-plan.json`, `implementation.md`, `moves.json`, `move-diffs.txt`, `parser-bom.json`, `paths.log`, `old-reference-scan.txt` und die unten benannten Ergebnisse. Runtime ist ignoriert; dieses Repositorydokument hält die wesentlichen Befunde dauerhaft für die spätere explizite Aufnahme fest. Die Inventaranalyse ist ein früher Architekturvorschlag; maßgeblich für den finalen Baum ist die korrigierte Implementierung, nicht deren verworfene engine/organization/Worker-Moves.

Der Implementierungsbericht weist aktive vollständige Pfadkorrekturen in scripts, README, AGENTS und Betriebs-/Vertragsdokumentation aus. Das Store-Modul erhielt drei Validatorpfadkorrekturen, Worker vier CLI-Pfadkorrekturen; ContractValidation und RecoveryWorker blieben unverändert. Accounting-Produktionsskripte wurden unverändert verschoben. Fünf RepositoryRoot-Defaults werden wegen Windows-PowerShell-5.1-`-File` nach param/Fehlerpräferenz berechnet, nur wenn nicht explizit gebunden; Schemawurzel und parametrisierte Datenwurzel bleiben getrennt. Test-Fixture-Roots sowie relative Imports und Starter->Accounting-Aufruf wurden an die neue Tiefe angepasst. Keine Modell-, Reasoning-, Rechte-, Rollen-, Schema- oder Indexänderung.

Die breiten Ergebnisse stammen aus dem vorhandenen Implementierungslauf; sie wurden in dieser Nacharbeit nicht wiederholt und sind keine unabhängige Abnahme:

| Prüfung | Vorhandenes Ergebnis | Beleg |
|---|---|---|
| Contracts | 75/75, auch Windows PowerShell `-File`, Exit 0 | contracts.json, contracts.log |
| WorkItem Store | 14/14, echte Worker-/Parallelitäts-/Abbruchtests | store.json |
| Recovery | 27/27, NTFS/Prozesskills/Recovery; Modulhash vor/nach identisch | recovery.json |
| DelegatedProgress | 55 Checks, Exit 0 | progress.log |
| RolloutTaskUsage | 69 Checks, Exit 0 | rollout.log |
| Organization | valid, 9 Teams, 35 Agenten, keine unavailableRoles | paths.log, implementation.md |
| WorkItems-Beispiel | valid, 3 WorkItems, transitionsChecked=false | paths.log, implementation.md |
| Parser/Encoding | 18 PS1/PSM1 ohne Parserfehler, striktes UTF8; 6 mit/12 ohne BOM wie Original | parser-bom.json |
| Native TOML | 45 Dateien mit Python 3.13 tomllib bestanden | implementation.md |
| Defaultroots/Pfade | tatsächliche Get/New/Set-Aufrufe ohne RepositoryRoot/Path, Validatoren und Referenzscan bestanden | paths.log, root-reference-scan.txt |

Die Qualitätsprüfung reproduzierte den identischen Accounting-Baselinefehler nach 38 Checks: die AST-Fixture lud `Write-ProgressDisplay`, jedoch dessen vorhandene Abhängigkeit `Format-ProgressLines` nicht. Die freigegebene Nacharbeit ergänzt ausschließlich `'Format-ProgressLines', ` unmittelbar vor `'Write-ProgressDisplay'` in `scripts/tests/accounting/Test-TaskTokenUsage.ps1`. Keine Produktionslogik und keine neue Funktion wurden geändert.

Frisch ausgeführt: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/tests/accounting/Test-TaskTokenUsage.ps1`: Exit 0, **41 Prüfungen**, einschließlich Flush-Roundtrip, Raw-Usage-Erhalt und schema-konformem metadata-only thread/read. Fixture: `C:/Users/Tom-OliverMarek/AppData/Local/Temp/agent-org-usage-test-229b5b40bac14e01a8b8fb16537deca0`. UTF8-BOM erhalten; 146 CRLF-Zeilenenden unverändert; 12514 -> 12538 Bytes, exakt die 24 Bytes der Allowlist-Ergänzung. Syntax- und Diffcheck werden in `accounting-repair.md` festgehalten. Alte Accounting-Logs mit Exit 1 bleiben historische Fehlerbelege, nicht aktueller Teststatus.

Abschlusschecks dieser Nacharbeit: Testsyntax 0 Parserfehler; `git diff --check` und `git diff --cached --check` jeweils Exit 0; alle vier verfassten Dateien strikt gültiges UTF8 ohne nachgestellte Leerzeichen. Alle 14 Move-Map-Zeilen gegen `moves.json` und vorhandene Zieldateien bestätigt; Endbaum mit 18 Skripten und ohne Root-PS1 bestätigt. Ausschließlich dieses neue Vorbereitungspapier wurde in den Git-Index aufgenommen; keine anderen Dateien gestagt und kein Commit erstellt.

## Vorhandener sichtbarer Smoke am neuen Pfad

Der vorhandene Lauf startete über `scripts/delegation/Start-DelegatedCodexTask.ps1` mit Rolle `agent_ressources_optimierer`, Titel `Neuer Pfad Smoke`, WorkingDirectory dieses Worktree, ResultPath `runtime/scripts-order/new-path-smoke.json`, geerbter ParentTaskId/AccountingDirectory und TimeoutSeconds 120. Aufgabe: keine Tools/Dateizugriffe/Delegationen, ausschließlich `SCRIPTS_ORDER_SMOKE_OK`. Exakter Aufruf steht im Implementierungsbericht. In dieser Nacharbeit wurde kein Smoke gestartet.

Aus `new-path-smoke.json` und den zugehörigen `.go.json`-/`.window.json`-Belegen: Task `fccf20b22c7f43b0abd87d9608bb2509`, Runner PID 47100, HWND 15470224, Titel `Agent Ressources Optimierer - Neuer Pfad Smoke`; sichtbares ACK am `2026-10-12T10:16:28.6913151Z`, visible=true, controller_visibility_confirmed=true, console_binding_verified=true, model_started=true, terminal_outcome=completed, success=true, Ausgabe exakt `SCRIPTS_ORDER_SMOKE_OK`, window_closed=true, usage_finalized=true. Event-/Public-/Jobbelege bleiben in Runtime; der vorhandene Pfadprüfbericht bestätigt keine gestarteten Toolitems und den Schutz fremder Fenster.

Historische Smoke-Messung: own=inclusive=19856 Tokens, input=19845, cachedInput=12416, output=11, reasoningOutput=0, cacheWriteInput=0, missing_count=0, ein deduplizierter Datensatz. Diese Werte beschreiben ausschließlich diesen Smoke; own und inclusive werden nicht addiert. Thread `01a12f9d-47bf-74f2-ab46-0ac2031c01a2`, Turn `01a12f9d-4ae7-7871-bc06-20785f5b0182`, tatsächlicher geerbter Parent `8c4536f93c4a401291c67145eeffe4b4`. Diese historische Smoke-Messung ist in der unten dokumentierten deduplizierten Kindersumme einmal enthalten. Der vollständige WorkItem-Gesamtverbrauch bleibt unbekannt; keine Hochrechnung aus dem Smoke.

## Historische Referenzpolitik

Alte Pfade und Hashes in STORY14-, AR55-, EPIC-5-Berichten sowie Story15-JSON-Originalbelegen bleiben ausdrücklich historisch. Die Markdown-Berichte kennzeichnen dies; STORY15-ACCEPTANCE kennzeichnet auch die verlinkten JSON-Belege. Historische JSON-Dateien bleiben unverändert. Keine Umdeutung alter Messungen zu neuen Läufen. Aktive Befehle verwenden die finalen Pfade; allgemeine Starter-Basenamen in TOMLs erfordern keine Rollenänderung. Der vorhandene Altpfadscan trennt historische Resttreffer von aktiven Referenzen.

Der berichtete Baselinevergleich HEAD=origin/develop=`46c1da60dc0c4502f37eae9667ec7662605f4a81` stammt aus dem früheren Implementierungshandoff und ist keine frisch verifizierte Remoteaussage dieser Nacharbeit.

## Exakter Übergangsgate

1. Die eigene dokumentierte Teamleiter-Vorbereitungsabnahme vom 2026-10-12T12:47:35.3595482+02:00 liegt vor. Der gesonderte Auftrag für die expliziten 41 Pfade umfasst Commit, Push und einen **Draft-Review-PR auf develop**. Dieses Vorbereitungsgate ist geschlossen; Merge, Integration und globaler Rollout bleiben gesonderte offene Gates.
2. Der Koordinator verantwortet das **kombinierte Story16-/Task60-Pfadmapping und Rebase** im Integrationspfad. Die dann tatsächlich integrierten Host-/Skill-/Fixturedateien inventarisieren und notwendige Starter-, Test-, Fixture- und Rootreferenzen in die gemeinsame Map aufnehmen. Die finale fremde Dateiliste ist hier nicht bekannt; keine fremden Worktrees lesen oder vorwegnehmen.
3. **Alle aktiven Delegierten mit alten absoluten Mainpfaden müssen vollständig drainiert sein**, einschließlich laufender Runner-/Job-/Vorlagenreferenzen. Künftige Tasktemplates vor der Umschaltung für den neuen absoluten Starter bereitstellen. Während der Umschaltung keine neue Aufgabe mit einem noch fehlenden oder bereits entfernten Pfad starten.
4. **Mainpfad und sämtliche aktiven Referenzen atomar** in einem koordinierten quieszenten Integrationsschritt wechseln, einschließlich AGENTS und neu integrierter Dateien. Bis dahin bleibt der operative absolute Mainstarter `C:/Users/Tom-OliverMarek/source/repos/agent-organization/scripts/Start-DelegatedCodexTask.ps1` unverändert. Ziel danach: `C:/Users/Tom-OliverMarek/source/repos/agent-organization/scripts/delegation/Start-DelegatedCodexTask.ps1`. Neue Starterverfügbarkeit vor Wiederaufnahme bestätigen. **Keine permanenten Rootwrapper.**
5. **Mirrors ausschließlich aus dem gemergten Mainquellstand** aktualisieren, niemals aus Branch-/Worktreequellen. Keine globale Änderung durch diese Nacharbeit.
6. Am kombinierten Integrationsstand erforderliche Parser/TOML/Contract/Store/Recovery/Accounting/Rollout/Progress/Console-/sichtbare Smokechecks sowie Story16-/Task60-Checks, Referenz-/Defaultrootscan und Main-/Mirrorquellgleichheit nachweisen. Dies ist ein künftiger Integrationsgate des Koordinators, kein Auftrag zur Wiederholung breiter Suiten in dieser Nacharbeit. GitHub Actions bleiben deaktiviert.

Die vorhandene unabhängige Nachprüfung `runtime/scripts-order/final-review.md` / `final-review.json` (Task `081f02a34c3a4cad8cd0706f79d67f25`) bestätigt Technik PASS und nennt ausschließlich DOC-AUTH-01 als verbleibenden Dokumentationsdefekt. Der spätere Optimiererauftrag `aa77d48be1d44252925a80a23aa4a8bc` korrigierte die drei Freigabeaussagen; `runtime/scripts-order/authorization-correction.md` dokumentiert den tatsächlichen Diff. Der Abschlussauftrag `113788133fb64e1fa3341c9433aa46a5` bestätigte durch gezielten Text-Read-back die Korrektur in accounting-repair.md:7, implementation.md:89 und diesem Dokument:17. DOC-AUTH-01 ist damit auf Dokumentationsebene geschlossen; das historische Reviewergebnis approved=false bleibt unverändert. Keine neue Testkette oder unabhängige Abnahme wurde dadurch behauptet.

Die eigene Vorbereitungsabnahme ist erteilt. Offen bleiben das finale kombinierte Story16-/Task60-Mapping samt Integrationsnachweisen und die oben beschriebenen Umschaltungs- und Rolloutgates. Die im vorhandenen Smoke gemeldete doppelte globale Rollendefinition `agent_ressources_optimierer` bleibt ein bestehender Umgebungsbefund unter `C:/Users/Tom-OliverMarek/.codex/agents`; keine globale Prüfung oder Reparatur durch diesen Abschlussauftrag. Der Accounting-Fixturefehler ist behoben; die eigene Vorbereitungsabnahme ist separat durch den Teamleiter dokumentiert.
## Eigene Teamleiter-Vorbereitungsabnahme und Veröffentlichung

Verbindliche Quelle: `%TEMP%/agent-org-scripts-order-parent-acceptance.json`, aufgezeichnet am **2026-10-12T12:47:35.3595482+02:00** durch `teamleiter_agent_ressources`, Parent-Task `9d9b284d9dfe4b73be7ecc4c5d3ba1aa`, Evidenz-Task `113788133fb64e1fa3341c9433aa46a5`. Entscheidung: `preparation_accepted_for_review_publication`. Der dauerhaft dokumentierte WorkItem-Status lautet **preparation-accepted-for-review**, nicht integrated, merged oder insgesamt abgeschlossen. Der ältere Runtime-Plan mit status=preparation ist ein historischer Planungsstand.

Die eigene Elternprüfung übernimmt die vorhandene unabhängige technische Nachprüfung und 26 unveränderte Quellhashes. Sie bewertet 14 Moves, zweckmäßige Modul-/Workerplatzierung, beendete alte eigene Schreiber, die geschlossene Dokumentationskorrektur DOC-AUTH-01 und die vollständige explizite 41-Pfad-Allowlist. Notwendige minimale Testfixture-Nacharbeit war im ursprünglich menschlich genehmigten Auftrag enthalten. Die Teamleitung erteilt die Vorbereitungsabnahme und beauftragt Veröffentlichung per Commit/Push/Review-PR auf develop. Diese Abnahme ersetzt weder die unabhängige Prüfung noch die spätere Integrationsabnahme.

Ergebnisbelege: `runtime/scripts-order/final-review.json` / `final-review.md` (Technik PASS; historisches approved=false wegen des später korrigierten DOC-AUTH-01), `authorization-correction.md` (tatsächlicher Korrekturdiff), `%TEMP%/agent-org-scripts-order-close-optimizer.json` (erfolgreich abgeschlossen, Usage finalisiert, Text-Read-back, 26 Quellhashes und 41 Pfade), sowie die oben zugeordneten Prüfergebnisse. **281 vorhandene Prüfungen = 75 Contracts + 14 Store + 27 Recovery + 55 Progress + 69 Rollout + 41 Accounting**. Dazu kommen die vorhandenen Parser-/Encodingnachweise für 18 Dateien, 45 native TOMLs und der sichtbare neue Starter-Smoke. Diese Veröffentlichung wiederholt keine Recherche- oder Testketten.

Writerstatus laut Abschlussvorbereitung: alte eigene Runner für ursprüngliche Leitung, Inventar, Implementierung, Fixture-Reparatur, unabhängige Review, finale Nachprüfung, Freigabeformulierung und Smoke beendet. PID 50376 wurde als neuer conhost-Prozess wiederverwendet und ist kein alter Reviewer. Abschlussvorbereitung erfolgreich beendet, window_closed=true. Die aktuellen Abschlussaufträge und Story16-/Task60-Prozesse bleiben geschützt; kein Prozess oder Fenster wird durch diese Veröffentlichung geschlossen.

Veröffentlicht werden ausschließlich die 41 expliziten Pfade des Abschlussberichts, einschließlich der 14 entfernten Ursprungspfade. Git-Rename-Erkennung kann daraus 27 Dateieinträge bilden; die Allowlist zählt alte und neue Pfade getrennt. Runtimebelege bleiben ungestagt. Hauptcheckout und fremde Änderungen bleiben erhalten. Vorhandene Prozesse, absolute Pfade und Vorlagen werden nicht automatisch umgestellt. GitHub Actions bleiben deaktiviert; keine Rootwrapper, globalen Spiegeländerungen oder Mergeaktion.

Weiterhin ausdrücklich offen: finales Story16-/Task60-Mapping mit aktuellen Host-/Skill-/Fixturedateien und Rebase; vollständiger Abschluss aktiver Delegationen mit alten absoluten Hauptcheckoutpfaden; vorbereitete Vorlagen und koordinierter ruhender Pfadwechsel; kombinierte Integrationsprüfungen und Quellgleichheit; globaler Rollout ausschließlich aus dem später gemergten Hauptquellstand. Die doppelte globale Rollendefinition bleibt ein offener Umgebungsbefund. Die vier alten absoluten Hauptcheckoutpfade für Start-DelegatedCodexTask, Get-TaskTokenUsage, Test-Organization und Test-Contracts waren laut Abschlussvorbereitung weiterhin vorhanden und bleiben bis zur koordinierten Umschaltung erforderlich.

Tokenbelege: sieben eindeutige frühere operative Tasks **4.264.696** gemessene eigene Tokens; Abschlussvorbereitung `113788133fb64e1fa3341c9433aa46a5` laut finalisiertem Ledger **900.747** Tokens. Deduplizierte bekannte Kindersumme: **5.165.443**, jeder Task einmal; der Smoke ist bereits enthalten, inklusive Implementierungssummen werden nicht zusätzlich addiert. Eigenverbrauch des aktuellen Teamleiterlaufs `7d2f5543ab2b4fcca02496cbc8b85c0b` aus `agent-org-scripts-order-finish-leader.json.events.jsonl`, thread/tokenUsage/updated vom **2026-10-12T10:47:45.3045327Z**: **515.902 Tokens als gemessener Zwischenstand** (Input 512.736, Cached Input 432.512, Output 3.166; Reasoning Output 198 im Output enthalten). Finale eigene Teamleiterwerte und vollständiger WorkItem-Gesamtverbrauch sind unbekannt; Zwischenstand und Kindersumme werden separat berichtet.
