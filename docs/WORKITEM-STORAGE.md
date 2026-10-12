# WorkItem-Speicher

Die PowerShell-Kommandos lesen und ändern den vollständigen Bestand
`runtime/workitems.json`. Der Ordner muss bereits existieren und lokal auf einem
Windows-Dateisystem liegen. `Get-WorkItems` erzeugt den Bestand nicht.

```powershell
$snapshot = .\scripts\Get-WorkItems.ps1
$snapshot.Exists
$snapshot.Revision # absent oder sha256:<Hash der gespeicherten Bytes>

$created = .\scripts\New-WorkItem.ps1 -Item $plannedItem `
    -ExpectedRevision $snapshot.Revision

$current = .\scripts\Get-WorkItems.ps1
$updated = .\scripts\Set-WorkItem.ps1 -Id $itemId -Item $completeUpdatedItem `
    -ExpectedRevision $current.Revision
```

`Path` kann einen alternativen Bestandsort angeben; ohne Angabe gilt
`<RepositoryRoot>/runtime/workitems.json`. `RepositoryRoot` bleibt die Basis für
Vertrag und Markdown-Referenzen. Beim erstmaligen Anlegen muss die erwartete
Revision `absent` lauten. `New` verlangt einen neuen Eintrag im Status `planned`;
`Set` verlangt einen vollständigen Eintrag mit stabiler ID. Die Revision wird
aus den gespeicherten Bytes gebildet. Bei `RevisionConflict` erneut lesen und
die fachliche Änderung bewusst neu anwenden. Es gibt kein automatisches Merge,
Retry oder Force.

Alle Operationen verwenden eine exklusive Sperre neben der Bestandsdatei und
begrenzen das Warten standardmäßig auf 5 Sekunden (zulässig: 0 bis 60 Sekunden).
Schreibvorgänge prüfen den frischen Vorzustand und rufen den bestehenden
`Test-WorkItems.ps1` mit `PreviousPath` auf. Eine erfolgreiche Implementierung
setzt keine Abnahme. Es gibt in dieser Version keine Sperrenübernahme,
Wiederanlauf- oder Crash-Recovery-Funktion.
