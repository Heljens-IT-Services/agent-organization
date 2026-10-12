# WorkItems v1

Verbindlich ist [workitems.schema.json](../../schemas/workitems.schema.json).
Der Bestand enthält `schemaVersion: "1.0"` und eine flache `items`-Liste.
`parentId` bildet beliebig tiefe Aufgabenbäume; die drei Agentenebenen sind davon unabhängig.

## Daten

Jeder Eintrag hat eine stabile kleingeschriebene ID, Elternreferenz oder `null`,
Titel, Beschreibung, menschlichen oder agentischen Owner, messbares Ziel
(`description`, `metric`, `target`), Priorität und Abhängigkeiten. `dueAt` ist optional.
`specification` enthält entweder `inline` oder eine vorhandene relative Markdown-Datei.
Eigene Akzeptanzkriterien haben innerhalb der Aufgabe eindeutige IDs.

`result` enthält Zusammenfassung und Belege. `verifications` bewahrt Prüfversuche
mit Implementierungszeit, Prüfzeit, Prüfer und belegtem Ergebnis je Kriterium.
Belege sind nichtleere Referenzen oder nachvollziehbare Beschreibungen; ihre
fachliche Wahrheit muss ein Prüfer feststellen, nicht der Schema-Validator.
`createdAt`, `updatedAt`, `implementedAt`, `acceptedAt` trennen Anlage, Bearbeitung,
letzte Umsetzung und Abnahme. Zeitangaben sind gültige UTC-Zeitstempel mit `Z`,
Sekunden und optional bis zu sieben Nachkommastellen; keine Schaltsekunden.
Fehlende Umsetzungs-/Abnahmezeiten bleiben `null`.

## Lebenszyklus

| Zustand | Erlaubte nächste Zustände |
|---|---|
| `planned` | `in_progress`, `blocked`, `cancelled` |
| `in_progress` | `blocked`, `implemented`, `cancelled` |
| `blocked` | `planned`, `in_progress`, `implemented`, `rework`, `cancelled` |
| `implemented` | `blocked`, `rework`, `accepted`, `cancelled` |
| `rework` | `in_progress`, `blocked`, `implemented`, `cancelled` |
| `accepted`, `cancelled` | keine |

Verbindliche Übergänge stehen in `x-statusTransitions` des Schemas. Diese Erweiterung
wird vom PowerShell-Prüfer ausgewertet; normale Schema-Prüfer prüfen Struktur,
keine Zustandswechsel oder Referenzgraphen.

`implemented` bleibt offen und benötigt Ergebnisbelege sowie Umsetzungszeit.
`accepted` braucht eine erfolgreiche Prüfung aller eigenen Kriterien für die
aktuelle Umsetzung und `acceptedAt` gleich deren Prüfzeit. Eltern brauchen zudem
abgeschlossene Kinder (`accepted` oder `cancelled`) und eigene Geschäftskriterien;
ihre Abnahme darf nicht vor den Kinderabschlüssen liegen. Abhängigkeiten benötigen
`accepted`; ein abgebrochener Eintrag erfüllt keine Abhängigkeit.

Fehlgeschlagene Prüfung führt zu `rework`. Nacharbeit erhält alte Prüfungen und
erhöht bei erneuter Umsetzung `implementedAt`. Alte Prüfungen nehmen keine neue
Umsetzung ab. Spezifikationsänderungen nach Umsetzung benötigen zuerst Nacharbeit.
Ein bislang nicht umgesetzter, blockierter Eintrag darf die Umsetzung nicht
überspringen; ein schon umgesetzter Eintrag darf aus der Blockade zur Prüfung zurückkehren.
Terminale Einträge bleiben unverändert; Folgearbeit erhält neue IDs.
Ergebnisänderungen nach Umsetzung brauchen eine neue Implementierungszeit;
vorhandene Prüfungen dürfen nicht für ein ausgetauschtes Ergebnis verwendet werden.

`humanInteraction` ist `null` oder eine Anforderung mit Art (`clarification`,
`approval`, `action`), Beschreibung, Anforderungszeit und Antwort. Eine Antwort
enthält Beschreibung, Antwortzeit und menschliche Kennung. Fehlende Antworten
halten die Aufgabe `blocked` (oder sie wird abgebrochen); die Anforderung darf
nicht zum Umgehen der Blockade gelöscht werden. Andere Blockaden nutzen
`blockReason`, das bei Wiederaufnahme entfernt wird. Antworttexte müssen fachlich
ausgewertet werden und erteilen keine pauschale Dienst- oder Änderungsfreigabe.

## Prüfung

```powershell
.\scripts\Test-WorkItems.ps1 -Path .\examples\workitems\goal-with-children.json
.\scripts\Test-WorkItems.ps1 -Path next.json -PreviousPath current.json
.\scripts\Test-Contracts.ps1 -ResultPath "$env:TEMP\contract-tests.json"
```

Geprüft werden Struktur, IDs, Rollen/Markdown, Eltern-/Abhängigkeitszyklen und
kombinierte Abschluss-Deadlocks. Aktive Aufgaben benötigen abgenommene Abhängigkeiten.
Mit `PreviousPath` werden zusätzlich Übergänge, Zeitstempel, Prüfhistorie und
Fortbestand alter IDs geprüft; neue Einträge beginnen `planned`. Ohne Vorzustand
kann die Entstehung eines importierten Zustands nicht nachgewiesen werden. Die
spätere Schreibschnittstelle muss den gespeicherten Vorzustand übergeben (Epic #6).

[Beispiele](../../examples/workitems) enthalten gültige Ziele, menschliche
Blockaden und Elternabnahmen; `invalid/` enthält ungültige Status-, ID- und Zyklusfälle.

Die gemeinsame PowerShell-5.1-Prüfung benötigt keine zusätzliche Laufzeit.
Sie unterstützt nur verwendete Schlüssel: lokale `$defs`/`$ref`, `type`, `const`,
`enum`, `anyOf`, `required`, `properties`, `additionalProperties`, `items`,
`minItems`, `uniqueItems`, `minLength`, `pattern`, `format: date-time`, Metadaten
und Übergangsliste. Unbekannte Schema-Schlüssel werden abgewiesen. Die Schema-Dateien
sind JSON Schema 2020-12; der PowerShell-Prüfer ist kein allgemeiner Schema-Validator.
