# Isolierter Hostharness Task 34

Adressat: teamleiter_softwareentwicklung. Fachbelege ersetzen keine Elternabnahme.

Q0 ist nur Vorbereitung: keine Fixture-, Host- oder Nativeausfuehrung. Spaetere Einzelgate-Ausfuehrung benoetigt separaten Auftrag und gelesene Backendlieferung:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-CoordinatorHost.ps1 -ResultPath '<absolutes Ergebnis.json>' -DeliveryReport '<Backendbericht.md>' -Gate '700ms runtime deadline: no-response'
```

HostHarness.ps1 verwendet ausschließlich TestMode, explizite isolierte Daten-/Arbeitsordner und Pipe-Namen sowie vorhandene MockRuntime-/ClientWorker-Prozesse. Keine Vorbereitungsselbsttests, Store-/Recoverytests oder NativeResumeprobe werden erneut ausgeführt. Eigene Hosts laufen ohne Fenster; eigene Kinder werden vor Abbruch anhand PID und Startzeit geprüft. Fachbericht muss vorher gelesen sein: die Dateiexistenzprüfung allein bestätigt keine fachliche Lieferung. Der Harness startet keine NativeCLI; deren Hostfortsetzung bleibt bei fehlendem Hostgate ausdrücklich offen.

MockRuntime.ps1 kann identityPath und turnTimingPath unter testRoot schreiben. Das Timingjournal erfasst RPC-Empfang und synthetische Turnintervalle; Konkurrenz entsteht durch echte OS-Host-/Clientprozesse. initialized ist strikt eine Notification ohne id, auch id:null ist verboten. Keine Antwort; falsches RPC ist ProtocolViolation mit Fixturefehlerexit. Keine native Protokollabnahme daraus ableiten.

Die Hostmatrix umfasst Exklusivität/Idle, Chat/Event, Unicode, Turntokens, unmittelbare und ältere RequestId-Duplikate, kontrollierten Neustart, abrupten eigenen Abbruch mit Jobcleanup, lebende/abweichende eigene Runtimeidentität und Fehlerbudgets. Fensterschutz wird nur als Quellentscheidung geprüft; keine globale GUI-Sperre wird behauptet.

Gezielter Startfehlerreproduzierer mit exakt den dokumentierten RuntimeConfig-Feldern:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/tests/coordinator/DiagnoseHostStartup.ps1 -ResultPath '<absoluter Fehlerbeleg.json>'
```

Q0-Stand ist nur AST-/Diff-geprueft. Testmatrix, offene Spezifikation und Nativeprobeplan: qa-preparation.md im uebergebenen Tempverzeichnis story16-task34-continuation-20261012. DiagnoseHostStartup bleibt unveraendert; kein automatischer Diagnose-/Suitenlauf.

Gate ist Pflicht; unbekannte Namen ergeben einen Fehler statt eines stillen gruenen Leerlaufs. Exakte Namen stehen in den Check-Aufrufen in HostHarness.ps1. Fristvarianten: `700ms runtime deadline: no-response`, `700ms runtime deadline: start-no-response`, `700ms runtime deadline: resume-no-response`, `700ms runtime deadline: lost-turn-ack`. Weitere neue Gates: `Fixture strictly rejects initialized RPC and never answers notification`, `Harness kill protection refuses unregistered and mismatched identities`, `Optional accountingDirectory absent accepts completed turn`. Prozessvarianten: `Process identity blocks without killing: live`, `Process identity blocks without killing: mismatched-start`, `Process identity blocks without killing: missing-start`, `Process identity blocks without killing: foreign-unregistered`.

Fristen messen ab Mockempfang bis beobachtetem Fehlerzustand/Clientantwort mit vorab festgelegter 550..1700ms-Toleranz; Hostexit separat <=6s. UTC-Ticks enthalten IPC-/Scheduleranteile und sind keine exakte monotone Wrappermessung. Resume-NoResponse verlangt einen Versuch ohne Versionsbeleg fuer sicheren Timeoutretry. 700ms gilt fuer RPC, nicht fuer normalen Modellturn; no-turn-completion ist nur vorbereitet, bis eine separate terminale Frist festgelegt ist.

Readiness prueft aktuelle PID/Startzeit und Dispatcherstatus. Replay setzt zwei unabhaengige Accepted-TurnIds voraus; unveraenderte Nutzlast Duplicate, geaenderte Rejected. Restart prueft aelteres Requestduplikat und neue Runtimeidentitaet. ACKverlust muss nach Restart gesperrt bleiben. Snapshotreads verwenden ReadWrite/Delete-Sharing, 500ms Retry nur fuer Missing-/Sharingrennen; korrupte JSON und Zugriffsfehler bleiben Fehler. Kill-Owned verlangt registriertes eigenes Kind plus exakte Startzeit. foreign-unregistered ist ein eigenes QA-Kind fremd zum Host, kein fremder Benutzerprozess. Frueh beendete Runtime ohne erhaltenen Handle wird nicht als lebendes Kind erfunden; deren Runtimeexitcode kann unbekannt bleiben.
