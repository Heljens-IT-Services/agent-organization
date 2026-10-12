# Runtime-Nacharbeit Task 34

Adressat: teamleiter_softwareentwicklung  
Umfang: `scripts/coordinator/CoordinatorHost.Core.psm1`, `scripts/Start-CoordinatorHost.ps1`; Starteranbindung aus dem vorhandenen Backendstand erhalten. Keine Task- oder Storyabnahme.

## Ergebnis

- Der Host nimmt die private `Enter-WorkItemStoreLock`-Sperre für `session.store.json` über den Modulscope und gibt sie mit `Exit-WorkItemStoreLock` frei. Damit werden vorhandene exklusive Dateisperre, Host/PID/Startzeitbesitz und konservative Lock-Recovery für den Sessionbesitzer genutzt. WorkItem-Modul und Verträge blieben unverändert.
- Das eigene `codex.exe`-Runtimekind wird an ein Windows Job Object mit `KILL_ON_JOB_CLOSE` gebunden. Ein Fehler beim Erzeugen/Konfigurieren/Zuweisen beendet nur den gerade vom Host gestarteten Prozess und lässt den Host fail-closed abbrechen. Beim Hostende schließt er ausschließlich sein eigenes Job-Handle. Ein alter Runtimebesitzer mit lebender oder unklarer PID/Startzeit blockiert weiter den Neustart ohne Killversuch.
- Resume-Wiederholungen sind durch `ResumeRetryLimit` begrenzt und senden ausschließlich `thread/resume` für die persistierte NativeThreadId. Auth-, ungültige Thread- und Protokollfehler werden nicht wiederholt; Timeout und klassifizierte vorübergehende Runtimefehler erhalten nur den begrenzten Resumeversuch. Ersatzthread und Turn-Replay bleiben gesperrt.
- Turns bleiben im Host seriell. Usage wird pro Turn aus dem passenden `thread/tokenUsage/updated`-Snapshot gelesen, bei neuem Turn zurückgesetzt, in `session.json` gespeichert und in Status-/Turnantworten angezeigt. Fehlende Snapshots bleiben `unknown`. Ledgerdateien werden stabil aus der Request-ID dedupliziert, enthalten Request-, ParentTask-, Thread- und Turn-ID sowie den Accounting-Pfad und werden über `Get-TaskTokenUsage.ps1` ausgewertet.
- Die vorhandene absolute Starteranbindung, sichtbare und bestätigte Koordinator-Konsole, Titel, UTF-8, Callerparameter, Tokenanzeige und Schutz vor automatischem Fensterschließen blieben erhalten.

## QA-Schnittstelle

`scripts/tests/coordinator/MockRuntime.ps1` und `ClientWorker.ps1` wurden nicht geändert. Beide erwarten genau `-ConfigPath <absoluter JSON-Pfad>`.

MockRuntime-Konfiguration: `testRoot`, `journal`, `mode`, `turnDelayMilliseconds`. Unterstützte `mode`-Werte: `normal`, `auth-error`, `resume-error`, `resume-mismatch`, `no-response`, `lost-turn-ack`, `cli-error`; `turnDelayMilliseconds` ist 0 bis 2000. Host-`RuntimeConfigPath` verweist auf JSON mit `RuntimeExecutable`, `RuntimeArguments` (Argumentarray) und `WorkingDirectory`. Für den Mock sind das absolute `powershell.exe`- und `MockRuntime.ps1`-Pfade sowie `-NoProfile -ExecutionPolicy Bypass -File <MockRuntime.ps1> -ConfigPath <MockConfig>`.

ClientWorker-Konfiguration: `testRoot`, `ready`, `go`, `result`, `pipeName`, `timeoutMilliseconds`, `request`. Der Pipe-Name muss `story16-qa-` plus 32 Kleinbuchstaben/Ziffern sein; das Timeout ist 100 bis 10000 ms. Alle Barrier-/Ergebnisdateien liegen unter `testRoot`. Der Request enthält `requestId`, `operation`, `logicalSessionId`, `source` und bei `SubmitInput` `inputText`.

Isolierter Mockhostaufruf:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Start-CoordinatorHost.ps1 -TestMode -DataDirectory '<isolierter absoluter Ordner>' -PipeName 'story16-qa-<32 hex>' -RuntimeConfigPath '<MockRuntime-Konfiguration>' -ReadyPath '<testRoot>/host.ready' -ReleasePath '<testRoot>/host.go' -ExitPath '<testRoot>/host.exit' -ResumeRetryLimit 3 -RpcTimeoutMilliseconds 15000 -WorkingDirectory '<isolierter absoluter Ordner>'
```

Für die native Probe `-RuntimeConfigPath` weglassen und `-RuntimeExecutable '<absoluter Pfad zu codex.exe>'` setzen. `-TestMode` und isolierter Daten-/Arbeitsordner bleiben erforderlich. Der Testhost darf dort einen NativeThread genau einmal provisionieren; Modell- und Reasoningwerte werden nicht überschrieben. Kein Koordinatorfenster und keine Produktivdaten werden benötigt.

## Belege und offene Punkte

- Backend-Ausgangsresultat `backend-rework.json`: `success:false`, Fehler `App-server hat seinen Ausgabestrom geschlossen.`, Usage unbekannt. Native Kind-PID 56680 (Start 2026-10-12 12:24:11) wurde nach erneuter Identitätsprüfung beendet; Runner PID 58692 blieb bestehen.
- `scripts/Test-CoordinatorHost.ps1` und `scripts/tests/coordinator/*` wurden nicht verändert. In diesem Lauf wurden keine Tests oder Hoststarts ausgeführt; die vorhandene QA-Vorbereitung ist daher kein Runtime-/Native-Abnahmebeleg.
- Die synchrone Pipeverarbeitung verhindert parallele Runtime-Turns. Ein garantiert begrenztes Einreihen oder ein sofortiger protokollierter `Busy`-Outcome während eines aktiven Turns ist noch nicht implementiert/belegt; Client-Connect-Timeout ist kein Busy-Protokoll.
- Das Job Object wird nach dem Runtime-Prozessstart und vor Hostinitialisierung/Adapterfreigabe zugewiesen. Scheitert die Zuweisung, wird fail-closed beendet. Ein Test des Job-Object-Verhaltens und der Laufzeitumgebung mit verschachtelten Windows-Jobs steht aus.
- Elternabnahme, produktive Threadübergabe und jeder sichtbare Koordinatorfensterstart bleiben außerhalb dieses Nachweises.

## B1 Fortsetzung 2026-10-12

Gezielte Änderungen/Begrenzungen siehe [backend-repair-report.md](C:/Users/Tom-OliverMarek/AppData/Local/Temp/story16-task34-continuation-20261012/backend-repair-report.md). Die bisherigen Hosttest-/QA-Aussagen dieses Berichts bleiben historische Belege; diese Fortsetzung führte keine Hosttests aus.
