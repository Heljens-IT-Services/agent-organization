# Lokale Web-Dateibrücke

Die Brücke läuft mit Windows PowerShell 5.1 und verlangt einen bereits vorhandenen autoritativen WorkItem-Bestand auf einem lokalen, bereitstehenden NTFS-Laufwerk. `StorePath` muss auf genau diese vorhandene Storedatei zeigen; fehlende Dateien werden beim Start abgewiesen und niemals durch `expectedRevision=absent` initialisiert. `RepositoryRoot` ist dieser Checkout. Vor der Nutzung muss der reale Storepfad aus der lokalen Umgebung eingesetzt und dessen NTFS-Laufwerk bestätigt werden. Für Metriken kann zusätzlich das vorhandene `AccountingDirectory` angegeben werden.

Im eigenen PowerShell-Fenster starten:

```powershell
powershell.exe -NoProfile -File .\scripts\web\Start-LocalWeb.ps1 `
  -RepositoryRoot (Get-Location).Path `
  -StorePath 'C:\Pfad\zum\bestehenden\workitems.json' `
  -AccountingDirectory 'C:\Pfad\zum\Accounting' `
  -Port 8765
```

Spezifikationen werden nur als Markdown aus fachlichen Wurzelverzeichnissen freigegeben: standardmäßig `docs/specifications/`, `specifications/` und `specs/`. Optionale `-SpecificationDirectories`-Einträge dürfen ausschließlich vorhandene Unterpfade dieser Wurzeln benennen. Die Brücke erzeugt keine dieser Ordner. Organisations-, Rollen-, Index-, Auth-, Schema-, Vertrags- und `AGENTS.md`-Ziele bleiben ausgeschlossen. Wurzel und Pfadsegmente werden auf Reparse Points geprüft.

Der Prozess bindet ausschließlich `127.0.0.1`. Öffne die ausgegebene Launch-URL in diesem Rechnerbrowser. Beende nur diesen Brückenprozess mit Ctrl+C im selben Fenster.

Der Stand unterstützt `read`, `specification`, `metrics` sowie eingeschränktes `create` und `update`. Neue Items starten mit den vom Backend gesetzten Lifecycle- und Zeitfeldern. Updates ändern nur redaktionelle Felder und verwenden die beim Öffnen des Formulars gelesene globale `expectedRevision`. Das Backend liest den aktuellen Bestand vor einem Update und übergibt unverändert dieselbe erwartete Revision an den vorhandenen Schreibcaller. Bei Konflikten Revision und Formulareingaben zur bewussten Prüfung erhalten; die Brücke ersetzt die Revision nicht automatisch.

Items mit irgendeiner vorhandenen `humanInteraction` sind vollständig von Updates gesperrt. Human Response bleibt mit AR-TEMP hart gesperrt (`HumanResponseContractBlocked`), ohne Hostanbindung oder Ereignisübergabe. Teams und Lock-Inhaber werden mangels belegbarer Quelle als nicht verfügbar beziehungsweise unbekannt ausgewiesen. Der Sessionheader ist eine technische Schranke und kein Identitätsnachweis.

Der Snapshot verwendet die Bytesrevision des vorhandenen Get-Callers. Metriken bleiben die Projektion des bestehenden Accounting-Callers und besitzen ein eigenes Lesefenster. Änderungen im Store oder Accounting können zwischen diesen Reads liegen. Nach einem Konflikt den aktuellen Stand bewusst lesen und eigene Eingaben abgleichen. Wenn eine Schreibantwort ausbleibt oder der Caller einen unklaren Publikations-/Aufräumfehler meldet, ist `commitState=unknown`: zuerst frisch lesen und den gespeicherten Inhalt vergleichen, keinesfalls blind erneut senden.
