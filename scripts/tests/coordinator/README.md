# Isolierter Hostharness Task 34

Adressat: teamleiter_softwareentwicklung. Fachbelege ersetzen keine Elternabnahme.

Finaler Einstieg benötigt die fachliche Infrastrukturlieferung:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-CoordinatorHost.ps1 -ResultPath '<absolutes Ergebnis.json>' -DeliveryReport '<runtime-rework-report.md>'
```

HostHarness.ps1 verwendet ausschließlich TestMode, explizite isolierte Daten-/Arbeitsordner und Pipe-Namen sowie vorhandene MockRuntime-/ClientWorker-Prozesse. Keine Vorbereitungsselbsttests, Store-/Recoverytests oder NativeResumeprobe werden erneut ausgeführt. Eigene Hosts laufen ohne Fenster; eigene Kinder werden vor Abbruch anhand PID und Startzeit geprüft. Fachbericht muss vorher gelesen sein: die Dateiexistenzprüfung allein bestätigt keine fachliche Lieferung. Der Harness startet keine NativeCLI; deren Hostfortsetzung bleibt bei fehlendem Hostgate ausdrücklich offen.

MockRuntime.ps1 kann zusätzlich identityPath und turnTimingPath unter testRoot schreiben. Das optionale Timingjournal erfasst synthetische Turnintervalle; die Konkurrenz entsteht durch echte OS-Host-/Clientprozesse. initialized akzeptiert zur Backendkompatibilität zusätzlich eine JSON-RPC-ID und antwortet dann; dies ist eine Fixtureerweiterung und kein Beleg nativer Protokollkompatibilität.

Die Hostmatrix umfasst Exklusivität/Idle, Chat/Event, Unicode, Turntokens, unmittelbare und ältere RequestId-Duplikate, kontrollierten Neustart, abrupten eigenen Abbruch mit Jobcleanup, lebende/abweichende eigene Runtimeidentität und Fehlerbudgets. Fensterschutz wird nur als Quellentscheidung geprüft; keine globale GUI-Sperre wird behauptet.

Gezielter Startfehlerreproduzierer mit exakt den dokumentierten RuntimeConfig-Feldern:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/tests/coordinator/DiagnoseHostStartup.ps1 -ResultPath '<absoluter Fehlerbeleg.json>'
```

Aktueller Lauf und seine Grenzen stehen im Resultatordner in qa-host-report.md. Nach dem fehlgeschlagenen Lauf wurde die Abbrucherwartung an KillOnJobClose angepasst und die getrennte Live-/Ambiguous-Prüfung samt Timingauswertung ergänzt; diese durch das Startgate unerreichbaren Teile sind nur AST-geprüft. Keine Aussage über bestandene Host-, Job- oder native Fortsetzung daraus ableiten.