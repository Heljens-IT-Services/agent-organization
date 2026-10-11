# Delegierte Aufgabe im eigenen PowerShell-Fenster

Das vereinbarte Ziel ist ein eigenes CMD-/PowerShell-Fenster mit Codex-Auftrag
und Verlauf. `scripts/Start-DelegatedCodexTask.ps1` öffnet einen eigenen sichtbaren
Runner, zeigt Rolle, Auftrag und ausschließlich übergebenen Kontext und wartet
auf den Controller. Dieser bestätigt ein neues HWND, zugehörige Runner-PID,
eindeutigen Titel und Sichtbarkeit; erst nach dem ACK und zehn Sekunden zum
Mitlesen startet genau ein App-server-Turn. Ohne ACK startet kein Modell.

Voraussetzungen: Windows PowerShell 5.1, vorhandener Codex CLI (geprüft 0.162.1),
lokale Anmeldung und eine installierte Rollen-TOML. Parameter: `Role`, `Task`,
`ContextFile`, `WorkingDirectory`, `ResultPath`, `TimeoutSeconds` und
`KeepWindowOpen`. Taskdaten werden als UTF-8-Jobdatei übergeben, nicht als
Shellcode. Unterstützt wird die einfache Struktur der vorhandenen Rollen.

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
erhalten; Resultat und reduzierte Ereignisse werden neben `ResultPath` gesichert.
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

## Grenzen

Eine automatische Kopplung aller nativen Delegationswerkzeuge an dieses Skript
ist noch nicht implementiert. Ein späterer MCP-Wrapper wäre eine eigene Aufgabe.
Separate Sitzungen und Rollenwerte beweisen keine generelle Umgehung
übergeordneter Berechtigungsregeln oder eine vollständige Trennung der Rechte.
Die Desktop-App wird nicht automatisiert; der vereinbarte Terminalweg ersetzt
die frühere Forderung nach einem separaten App-Fenster.

Quelle: [App-server-Lifecycle](https://learn.chatgpt.com/docs/app-server#lifecycle-overview);
das lokale CLI-Schema bestätigt `developerInstructions`, `config`, `cwd`,
`model`, `sandbox` und `approvalPolicy` für `thread/start`.
