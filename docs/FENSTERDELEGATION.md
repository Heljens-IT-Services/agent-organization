# Delegierte Aufgabe im eigenen PowerShell-Fenster

Das vereinbarte Ziel ist ein eigenes CMD-/PowerShell-Fenster mit Codex-Auftrag
und Verlauf. `scripts/Start-DelegatedCodexTask.ps1` öffnet einen eigenen sichtbaren
Runner, zeigt Rolle, Auftrag und ausschließlich übergebenen Kontext und wartet
auf den Controller. Dieser bestätigt ein neues HWND, zugehörige Runner-PID,
eindeutigen Titel und Sichtbarkeit; erst nach dem ACK und zehn Sekunden zum
Mitlesen startet genau ein App-server-Turn. Ohne ACK startet kein Modell.
Der Starter verwendet ausdrücklich `conhost.exe` mit PowerShell, ohne globale
Terminaleinstellungen zu ändern. Das gemeldete echte Console-HWND muss exakt
zum Kandidaten passen; Runner-Parent und native Fensterbesitzer-PID werden
gegen den selbst gestarteten Host geprüft. Titelgleichheit allein reicht nicht.

Voraussetzungen: Windows PowerShell 5.1, vorhandener Codex CLI (geprüft 0.162.1),
lokale Anmeldung und eine installierte Rollen-TOML. Parameter: `Role`, `Task`,
`ContextFile`, `WorkingDirectory`, `ResultPath`, `TimeoutSeconds` und
`KeepWindowOpen`. Taskdaten werden als UTF-8-Jobdatei übergeben, nicht als
Shellcode. Unterstützt wird die einfache Struktur der vorhandenen Rollen.
Die Rollen-ID wird ausdrücklich in `developerInstructions` übergeben, damit
die Repository-Hauptrollenregel zugewiesene operative Sitzungen nicht umdeutet.

```powershell
.\scripts\Start-DelegatedCodexTask.ps1 -Role softwareentwicklung_qualitaetssicherung `
  -Task 'Addiere values und antworte mit sum und marker als JSON.' `
  -ContextFile C:\Temp\auftrag\fixture.json -WorkingDirectory C:\Temp\auftrag `
  -ResultPath C:\Temp\auftrag\result.json -TimeoutSeconds 120
```

Das Fenster zeigt Verlauf, Ausgabe und Thread-ID. Nach terminalem Turn und
gesichertem Ergebnis endet nur der eigene Runner; nur sein neues Fenster wird
geschlossen. Ein nach Runnerende verbleibender Terminalrahmen wird anhand seines
exakten Auftragstitels gezielt geschlossen. `KeepWindowOpen` lässt ihn bis Enter
offen. Vorhandene Fenster werden nicht navigiert oder beendet. Historie bleibt
erhalten; vollständiges Resultat und strukturierte Ereignisse werden neben `ResultPath` gesichert.
Bestehende Artefakte werden nicht überschrieben. Der App-server-Helfer bleibt
unsichtbar; globale Konfiguration und Anmeldung werden nicht verändert oder kopiert.

## Tatsächlicher Test am 12. Oktober 2026

Eine frische QA-Aufgabe mit `values: [2, 3]` und Marker
`agent-terminal-visible-fresh-20261012` lieferte in einem neuen sichtbaren
PowerShell-/Windows-Terminal-Fenster `sum: 5` und den unveränderten Marker.
Der Benutzer bestätigte die lesbare Aufgabe und JSON-Antwort im Fenster.
Controllerprüfung: Runner-PID `14232`, tatsächliches Fenster-HWND `3018888`.
ACK erfolgte um `22:37:44Z`, Turn-Start um `22:37:55Z` am 11. Oktober UTC.
Das Resultat wurde vor normalem Runnerende gesichert; nur der eigene Rahmen
schloss. Der geschützte ChatGPT-Rahmen blieb erhalten. Eine spätere Aufnahme war
nach dem Schließen nicht mehr möglich; es wird kein Screenshotnachweis behauptet.

Thread: `01a12d1d-9122-7b63-bad6-d7ac44e5f56b`; die lokale Rollout-Historie
blieb nach Fensterschluss vorhanden. Der vorherige fehlgeschlagene Fenstertest
startete keinen Modellturn: Windows Terminal liefert für `GetConsoleWindow()`
einen Pseudohandle, weshalb der Controller nun den tatsächlichen neuen
Hostrahmen anhand des eindeutigen Titels identifiziert.

Die anschließende Rollenprobe aus dem Repository mit seiner neuen `AGENTS.md`
lieferte `role: controlling_kennzahlen`, `sum: 5` und den erwarteten Marker.
HWND `5901854`/Runner `8704` wurden vor Modellstart bestätigt; Thread
`01a12d28-f2a1-7780-8a21-3c38c8e0a608` endete erfolgreich. Das Resultat wurde
gesichert und nur das eigene Fenster geschlossen. Dies prüft eine zugewiesene
operative Rolle, keine vollständige fachliche Abnahme aller Rollen.

## Lesbare Delegation und Tokenabrechnung

Der Runner zeigt einen deutschen Banner mit Rolle, Auftrag, Scope/Arbeitsverzeichnis,
absolutem Kontextdateipfad und getrenntem Kontextinhalt. Fortschritt, Ergebnis und
eigene Tokens erscheinen lesbar; das vollständige Controllerresultat bleibt in
`ResultPath` erhalten. `token_usage` enthält den letzten passenden nativen
`tokenUsage.total`-Snapshot oder `null`, wenn kein passendes Ereignis vorliegt.
Ein fehlendes Ereignis ist keine gemessene Null. Rohereignisse einschließlich
`tokenUsage.total` und `tokenUsage.last` bleiben in `.events.jsonl` erhalten.

Zusätzliche optionale Parameter:

- `ParentTaskId`: GUID des aufrufenden Auftrags. Ohne Parameter wird
  `AGENT_ORG_PARENT_TASK_ID` geerbt; ein expliziter leerer Wert startet eine Root.
- `AccountingDirectory`: gemeinsames Ledgerverzeichnis. Ohne Parameter wird
  `AGENT_ORG_ACCOUNTING_DIRECTORY` geerbt, sonst `token-accounting` neben dem
  Resultat verwendet. Ein expliziter leerer Wert verwendet diesen Standard.
- `TaskTitle`: Zusammenfassung aus genau drei Wörtern. Der Fenstertitel lautet
  `<Rolle> - <TaskTitle>`, beispielsweise `Qualitätssicherung - Token Summierung prüfen`.
  Ohne Angabe dienen die ersten drei Auftragswörter als Kurzform; bei kürzeren
  Aufträgen `Auftrag jetzt bearbeiten`. Für sinnvolle Titel die Kurzform übergeben.
- `RoleDisplayName`: optionale lesbare Rollenbezeichnung. Standard ist der Name
  aus dem eigenen Lookup, sonst die Rollen-ID. GUIDs bleiben in Jobmetadaten;
  eine interne Fenstermarkierung schützt Zuordnung und Schließen bei Titelgleichheit.

`Role=koordinator` ist die Ausnahme beim Titel und Fensterschluss: Titel exakt
`Koordinator`, automatisches Offenhalten unabhängig von `KeepWindowOpen`.
Auch Fehler und Timeout enden mit einer Benutzerabfrage in dieser Konsole;
der Controller schließt sie nie automatisch und nimmt ihr HWND in die
geschützten Fenster auf. Nur der Benutzer schließt sie mit Enter oder Fenster-X.
Das schützt den Starterpfad, ist keine allgemeine Betriebssystem-Toolsperre.
Der aktuelle App-Hauptchat besitzt damit keine automatisch zugeordnete Konsole
und wird nicht umbenannt; ein Starteraufruf erzeugt eine eigene Codex-Sitzung.

Nur der eigene Runner setzt beide Umgebungsvariablen auf seine eigene Task-ID
und seinen Ledgerpfad für nachfolgende Starteraufrufe. Jede Aufgabe erhält eine
stabile GUID und genau einen atomar veröffentlichten `<task-id>.usage.json`-Eintrag:
`task_id`, nullable `parent_task_id`, `role`, native `thread_id`/`turn_id` und nullable
`token_usage`. Das Ledger hat kein `status`-Feld. Elternverknüpfungen sind
übergebene/vererbte Auftragsmetadaten und kein Beweis nativer Spawn-Verknüpfung.

Jede Aufgabe startet einen frischen Thread und genau einen Turn. Wiederholte
`thread/tokenUsage/updated`-Ereignisse ersetzen den Snapshot; sie werden nicht
addiert. Nur passende Thread- und Turn-IDs zählen. Nach `turn/completed` erfolgt
ein unterstützter `thread/read`-Roundtrip (`includeTurns=false`); bis zu seiner
Antwort werden auch späte Usage-Ereignisse verarbeitet. Scheitert dieser
Roundtrip, wird der Auftrag als fehlgeschlagen gemeldet; ein zuvor beobachteter
Snapshot bleibt im Resultat als vorläufige native Messung erhalten. Ohne
bestätigten finalen Drain (`usage_finalized=false`) bleibt die Ledgernutzung
`null`, damit ein abgebrochener Auftrag keine vollständige Summe vortäuscht.

```powershell
$usage = .\scripts\Get-TaskTokenUsage.ps1 -TaskId '<task-guid>' `
  -AccountingDirectory C:\Temp\auftrag\token-accounting
$usage | ConvertTo-Json -Depth 10
.\scripts\Test-TaskTokenUsage.ps1
```

`Get-TaskTokenUsage.ps1` gibt `own`, `inclusive`, `known_partial`, `missing_count`,
`distinct_known_usage_count` und `task_count` zurück. Es summiert eigene native
Verbräuche des Teilbaums, niemals bereits inklusive Kindersummen. Identische
Task-IDs und identische native Thread/Turn-Verbräuche werden dedupliziert.
Widersprüchliche Duplikate, ungültige Datensätze und Elternzyklen schlagen
ausdrücklich fehl, auch außerhalb des angefragten Teilbaums im selben Ledger.
Fehlen Messungen, bleibt `inclusive=null`; ein unbekannter eigener Verbrauch ist
`own=null`. `known_partial` enthält die endlichen bekannten Summen und
`missing_count` zählt Aufgaben ohne Messung einschließlich einer fehlenden Root.
Eine bekannte eigene Messung bleibt bei unbekannten Kindern erhalten.
Der Starter sichert diese Auswertung im Resultat als `token_summary` und zeigt
eigene sowie inklusive Tokens. Summen gelten ausschließlich für registrierte
Ledgeraufträge; nicht registrierte Kinder sind damit nicht automatisch erfasst.

Gesamttokens ergeben sich ausschließlich aus der Summe nativer `totalTokens`.
`cachedInputTokens` ist eine Teilmenge der Eingabe, `reasoningOutputTokens` eine
Teilmenge der Ausgabe. Diese Kategorien werden separat summiert und nicht zur
Gesamtsumme addiert; optional fehlende `cacheWriteInputTokens` werden gemäß
lokalem Schema als 0 behandelt. Eine externe Root ohne eigenen Ledgerdatensatz
hat unbekannte eigene und inklusive Tokens, aber bekannte Nachkommensummen.
Aktuelle native Hauptchats erhalten damit keinen automatischen UI-Zähler.
Abgeschlossene, eindeutig ausgewählte Turns lassen sich ausdrücklich importieren:

```powershell
.\scripts\Import-RolloutTaskUsage.ps1 -RolloutPath '<genaue-rollout-datei>' `
  -ThreadId '<native-thread-guid>' -TurnId '<abgeschlossene-turn-guid>' `
  -Role koordinator -AccountingDirectory C:\Temp\auftrag\token-accounting
```

`TaskId` ist standardmäßig die Turn-ID; `ParentTaskId` ordnet den importierten
Auftrag ausdrücklich zu. Der Import bevorzugt beobachtete native
`token_usage_record.turn_token_usage` mit passender Thread-/Turnidentität.
Ältere Formate verwenden die Differenz kumulativer Snapshots vor Auftragsbeginn
und bis zum Abschluss. Ohne belastbare Baseline oder Endmessung bleibt diese
Differenz `null`; geerbte Gesamthistorien werden nicht als eigener Verbrauch
summiert. Laufende Turns werden nicht als abgeschlossen importiert. Das lokale
Rolloutformat ist keine zugesicherte öffentliche API; unbekannte oder mehrdeutige
Formate schlagen explizit fehl. Der Import ist idempotent und überschreibt keine
widersprüchlichen Einträge. Er liest Metadaten, keine ausgegebenen Gesprächsinhalte.

Dies ist ausschließlich ein manuelles Startskript, kein universeller Plattformhook.
Die Offline-Fixtures prüfen Aggregation, Fehlerfälle und den simulierten nativen
Ereignisstrom ohne Modellstart. Die aktuelle sichtbare QA-Liveprobe lieferte
`sum: 5`, native Gesamttokens `19.234` (`19.214` Eingabe, `20` Ausgabe; Cache und
Reasoning jeweils `0`). Sichtbarkeit wurde vor Modellstart bestätigt, das
Resultat gesichert und nur das eigene Fenster geschlossen. Abgeschlossene
Root-/Leiter-/Spezialistenturns wurden zusätzlich mit nativen identitätsgebundenen
Nutzungswerten importiert.

Die anschließende echte Kettenprobe startete zuerst den sichtbaren
`Teamleiter Softwareentwicklung - QA Auftrag delegieren`, danach dessen
`Qualitätssicherung - Summe korrekt pruefen`. Beide bestätigten Console-Bindung
vor Arbeit; das Kind verwendete exakt die Leiter-Task-ID als `parent_task_id`.
Das Kind lieferte `sum: 5`; der Leiter bündelte nur dessen Belege. Gemessen:
Leiter `207.488`, Kind `19.381`, dedupliziert inklusive `226.869` Tokens. Beide
Auftragsfenster schlossen nach Sicherung. Die separat gestartete Konsole
`Koordinator` blieb offen. Normales Routing verwendet diese echten sichtbaren
Sitzungen; vorhandene native Threads lassen sich damit nicht rückwirkend umziehen.

Protokollquelle: [Offizielle App-server-Turn-Ereignisse](https://learn.chatgpt.com/docs/app-server#turn-events).
Maßgebliche lokale CLI-Schemas: `ThreadTokenUsageUpdatedNotification.json` und
`ThreadReadParams.json` unter `agent-org-usage-schema/v2` im übergebenen Temp-Pfad.

## Weitere Grenzen

Eine automatische Kopplung aller nativen Delegationswerkzeuge an dieses Skript
ist noch nicht implementiert. Ein späterer MCP-Wrapper wäre eine eigene Aufgabe.
Separate Sitzungen und Rollenwerte beweisen keine generelle Umgehung
übergeordneter Berechtigungsregeln oder eine vollständige Trennung der Rechte.
Die Desktop-App wird nicht automatisiert; der vereinbarte Terminalweg ersetzt
die frühere Forderung nach einem separaten App-Fenster.

Quelle: [App-server-Lifecycle](https://learn.chatgpt.com/docs/app-server#lifecycle-overview);
das lokale CLI-Schema bestätigt `developerInstructions`, `config`, `cwd`,
`model`, `sandbox` und `approvalPolicy` für `thread/start`.
