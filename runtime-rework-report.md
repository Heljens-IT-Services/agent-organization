# Runtime-Nacharbeit Task 34

Adressat: teamleiter_softwareentwicklung  
Umfang: `scripts/coordinator/CoordinatorHost.Core.psm1`, `scripts/Start-CoordinatorHost.ps1`; Starteranbindung aus dem vorhandenen Backendstand unter `scripts/delegation/Start-DelegatedCodexTask.ps1` erhalten. Keine Task- oder Storyabnahme.

## Ergebnis

- Der Host nimmt die private `Enter-WorkItemStoreLock`-Sperre fÃ¼r `session.store.json` Ã¼ber den Modulscope und gibt sie mit `Exit-WorkItemStoreLock` frei. Damit werden vorhandene exklusive Dateisperre, Host/PID/Startzeitbesitz und konservative Lock-Recovery fÃ¼r den Sessionbesitzer genutzt. WorkItem-Modul und VertrÃ¤ge blieben unverÃ¤ndert.
- Das eigene `codex.exe`-Runtimekind wird an ein Windows Job Object mit `KILL_ON_JOB_CLOSE` gebunden. Ein Fehler beim Erzeugen/Konfigurieren/Zuweisen beendet nur den gerade vom Host gestarteten Prozess und lÃ¤sst den Host fail-closed abbrechen. Beim Hostende schlieÃŸt er ausschlieÃŸlich sein eigenes Job-Handle. Ein alter Runtimebesitzer mit lebender oder unklarer PID/Startzeit blockiert weiter den Neustart ohne Killversuch.
- Resume-Wiederholungen sind durch `ResumeRetryLimit` begrenzt und senden ausschlieÃŸlich `thread/resume` fÃ¼r die persistierte NativeThreadId. Auth-, ungÃ¼ltige Thread- und Protokollfehler werden nicht wiederholt; Timeout und klassifizierte vorÃ¼bergehende Runtimefehler erhalten nur den begrenzten Resumeversuch. Ersatzthread und Turn-Replay bleiben gesperrt.
- Turns bleiben im Host seriell. Usage wird pro Turn aus dem passenden `thread/tokenUsage/updated`-Snapshot gelesen, bei neuem Turn zurÃ¼ckgesetzt, in `session.json` gespeichert und in Status-/Turnantworten angezeigt. Fehlende Snapshots bleiben `unknown`. Ledgerdateien werden stabil aus der Request-ID dedupliziert, enthalten Request-, ParentTask-, Thread- und Turn-ID sowie den Accounting-Pfad und werden Ã¼ber `Get-TaskTokenUsage.ps1` ausgewertet.
- Die vorhandene absolute Starteranbindung, sichtbare und bestÃ¤tigte Koordinator-Konsole, Titel, UTF-8, Callerparameter, Tokenanzeige und Schutz vor automatischem FensterschlieÃŸen blieben erhalten.

## QA-Schnittstelle

`scripts/tests/coordinator/MockRuntime.ps1` und `ClientWorker.ps1` wurden nicht geÃ¤ndert. Beide erwarten genau `-ConfigPath <absoluter JSON-Pfad>`.

MockRuntime-Konfiguration: `testRoot`, `journal`, `mode`, `turnDelayMilliseconds`. UnterstÃ¼tzte `mode`-Werte: `normal`, `auth-error`, `resume-error`, `resume-mismatch`, `no-response`, `lost-turn-ack`, `cli-error`; `turnDelayMilliseconds` ist 0 bis 2000. Host-`RuntimeConfigPath` verweist auf JSON mit `RuntimeExecutable`, `RuntimeArguments` (Argumentarray) und `WorkingDirectory`. FÃ¼r den Mock sind das absolute `powershell.exe`- und `MockRuntime.ps1`-Pfade sowie `-NoProfile -ExecutionPolicy Bypass -File <MockRuntime.ps1> -ConfigPath <MockConfig>`.

ClientWorker-Konfiguration: `testRoot`, `ready`, `go`, `result`, `pipeName`, `timeoutMilliseconds`, `request`. Der Pipe-Name muss `story16-qa-` plus 32 Kleinbuchstaben/Ziffern sein; das Timeout ist 100 bis 10000 ms. Alle Barrier-/Ergebnisdateien liegen unter `testRoot`. Der Request enthÃ¤lt `requestId`, `operation`, `logicalSessionId`, `source` und bei `SubmitInput` `inputText`.

Isolierter Mockhostaufruf:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Start-CoordinatorHost.ps1 -TestMode -DataDirectory '<isolierter absoluter Ordner>' -PipeName 'story16-qa-<32 hex>' -RuntimeConfigPath '<MockRuntime-Konfiguration>' -ReadyPath '<testRoot>/host.ready' -ReleasePath '<testRoot>/host.go' -ExitPath '<testRoot>/host.exit' -ResumeRetryLimit 3 -RpcTimeoutMilliseconds 15000 -WorkingDirectory '<isolierter absoluter Ordner>'
```

FÃ¼r die native Probe `-RuntimeConfigPath` weglassen und `-RuntimeExecutable '<absoluter Pfad zu codex.exe>'` setzen. `-TestMode` und isolierter Daten-/Arbeitsordner bleiben erforderlich. Der Testhost darf dort einen NativeThread genau einmal provisionieren; Modell- und Reasoningwerte werden nicht Ã¼berschrieben. Kein Koordinatorfenster und keine Produktivdaten werden benÃ¶tigt.

## Belege und offene Punkte

- Backend-Ausgangsresultat `backend-rework.json`: `success:false`, Fehler `App-server hat seinen Ausgabestrom geschlossen.`, Usage unbekannt. Native Kind-PID 56680 (Start 2026-10-12 12:24:11) wurde nach erneuter IdentitÃ¤tsprÃ¼fung beendet; Runner PID 58692 blieb bestehen.
- `scripts/Test-CoordinatorHost.ps1` und `scripts/tests/coordinator/*` wurden nicht verÃ¤ndert. In diesem Lauf wurden keine Tests oder Hoststarts ausgefÃ¼hrt; die vorhandene QA-Vorbereitung ist daher kein Runtime-/Native-Abnahmebeleg.
- Die synchrone Pipeverarbeitung verhindert parallele Runtime-Turns. Ein garantiert begrenztes Einreihen oder ein sofortiger protokollierter `Busy`-Outcome wÃ¤hrend eines aktiven Turns ist noch nicht implementiert/belegt; Client-Connect-Timeout ist kein Busy-Protokoll.
- Das Job Object wird nach dem Runtime-Prozessstart und vor Hostinitialisierung/Adapterfreigabe zugewiesen. Scheitert die Zuweisung, wird fail-closed beendet. Ein Test des Job-Object-Verhaltens und der Laufzeitumgebung mit verschachtelten Windows-Jobs steht aus.
- Elternabnahme, produktive ThreadÃ¼bergabe und jeder sichtbare Koordinatorfensterstart bleiben auÃŸerhalb dieses Nachweises.

## B1 Fortsetzung 2026-10-12

Gezielte Ã„nderungen/Begrenzungen siehe [backend-repair-report.md](C:/Users/Tom-OliverMarek/AppData/Local/Temp/story16-task34-continuation-20261012/backend-repair-report.md). Die bisherigen Hosttest-/QA-Aussagen dieses Berichts bleiben historische Belege; diese Fortsetzung fÃ¼hrte keine Hosttests aus.

## Übergabesicherung #34 (2026-10-12)

Aktueller Quellenstand: `scripts/Start-CoordinatorHost.ps1` und `scripts/coordinator/CoordinatorHost.Core.psm1` wurden ausschließlich aus dem Backendbeitrag übernommen und checkpointet. Es wurden keine fachlichen Codeänderungen ergänzt.

Die von den eigenen unveröffentlichten Commits `c26a0fa` und `d1f7c8a` eingeführten Testartefakte `scripts/Test-CoordinatorHost.ps1` sowie `scripts/tests/coordinator/{ClientWorker.ps1,DiagnoseHostStartup.ps1,HostHarness.ps1,MockRuntime.ps1,README.md}` sind aus diesem Featurezweig entfernt. Historische QA-Aussagen und Messwerte oben bleiben unverändert und sind keine aktuellen Funktionsbelege. Für diese Übergabe wurden keine Tests ausgeführt oder erstellt; Laufzeit- und Funktionsverhalten bleibt unbelegt und ist von der Teamleitung abzunehmen.
