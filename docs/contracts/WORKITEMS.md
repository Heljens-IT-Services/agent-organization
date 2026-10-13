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

Neue Anforderungen ergänzen in derselben Struktur `requestId`, `required: true`,
`humanId`, optional `proposal` (`reference`, `sha256`, verpflichtender lokaler `path`)
und `resolution`. Antworten ergänzen die exakte Request-ID, `decision`
(`provided`, `approved`, `rejected`, `insufficient`), `evidence` zum tatsächlichen
menschlichen Originaleingang und bei einem Vorschlag dessen `proposalSha256`.
`reference` ist eine fachliche Referenz, niemals eine implizite Dateiquelle.
Neue gebundene Producerrequests und der Anfragesetter verlangen einen expliziten
lesbaren `path` und gleichen dessen Bytes mit `sha256` ab; neue Requests speichern
den aufgelösten absoluten Pfad. Web und Antwort-/Resumepfade verwenden nur diesen
Pfad. Das Snapshotschema erlaubt separat `legacyHumanProposal` ohne `path` für
Bestand/Historie; der Transitionguard verweigert neue oder erneuerte pathlose
Bindungen. Solcher Bestand bleibt lesbar und wird über `PreviousRequestId` mit
realer Proposaldatei ausdrücklich erneuert, nicht über einen Referencefallback.
`satisfied` benötigt eine passende Antwort; bei Freigaben ausdrücklich `approved`
für die identischen Vorschlagsbytes. `rejected`/`insufficient` bleiben blockiert;
Statuswechsel und Agentergebnisse erfüllen keine menschliche Anforderung.

`Set-WorkItemHumanRequest.ps1` bindet eine neue Anfrage an ein vorhandenes WorkItem
mit CAS-Revision und bildet den Hash aus der tatsächlichen Vorschlagsdatei.
Eine erneute Anfrage braucht `PreviousRequestId`, archiviert die unveränderte
bisherige Interaction in `humanInteractionHistory` und beginnt mit leerer Antwort.
Vorschlagsänderungen benötigen diesen neuen Request und eine neue Antwort;
Scopeänderungen erhalten ein separates WorkItem. `Complete-DelegatedWorkItem.ps1`
übernimmt `humanId`/`proposal` aus einem korrelierten blockierten Ergebnis, niemals
eine Agentantwort als Humanantwort. Alte `kind`/`description`-Producer bleiben lesbar.

`Set-WorkItemHumanResponse.ps1` ist der menschliche Eingang (auch über die bestehende
lokale Web-Brücke). Er verlangt Originalbeleg, zuständigen Respondenten, offene
Anfrage und die frisch gelesene globale Revision; neue Requests verlangen zusätzlich
die exakte Request-ID. Gebundene Vorschlagsbytes werden vor Antwort und Fortsetzung
abgeglichen. Ein erfolgreicher CAS persistiert Antwort und Auflösung, hält das
WorkItem zunächst `blocked` und schreibt die bestehende recoverbare Store-Outbox.
Der Antwortintent enthält `humanResponseEvent` einschließlich resultierender Revision;
nur dieser Intent publiziert die neue gebundene Antwort, nicht spätere Statuswrites.
Der Koordinatorimport erzeugt daraus ein idempotentes `human_response`-Ereignis,
gebunden an WorkItem, Request, Antwort und Proposal. Eine eigene `propose_resume`
Entscheidung prüft dies und abgenommene Dependencies; sie ersetzt keine Elternabnahme.
Nur das betroffene WorkItem und seine expliziten Dependencies warten. Ein gemeinsamer
Elternknoten allein sperrt unabhängige Geschwister bei Humanwaiting nicht.
Diese Ausnahme gilt nur bei `blocked`, offener unbeantworteter Anfrage ohne
Auflösung und `blockReason: null` oder negativer Humanentscheidung mit exakt
passendem Humanblockmarker bis zur ausdrücklichen Erneuerung. So sperrt auch eine
Ablehnung unabhängige Geschwister nicht. Historische satisfied Interactions
heben keine Elternblockade auf. Ein zusätzlicher `blockReason` bleibt bei neuer
Anfrage und Antwort erhalten. Beim Producer bezeichnet nur `reason: null` mit
Humanrequest reines Humanwaiting; andere oder bereits gespeicherte Gründe bleiben
Blockquellen. Der genaue vom Antwortsetter erzeugte Humanmarker darf bei expliziter
Erneuerung ersetzt werden; ein Humanresponse-Resume darf andere Gründe nicht löschen.
Deren Aufhebung braucht die vorhandene separate Koordinatorbewertung über einen
anderen gebundenen Resumetrigger. Negative Entscheidungen bleiben zusätzlich in
der Interaction erhalten und verhindern Resume unabhängig vom Blocktext.
Reguläre menschliche Owner bleiben zulässig, werden aber nicht als Agenten gestartet.
Ihr Ergebnis und die getrennte Kriterienprüfung laufen über den vorhandenen regulären
WorkItem-Schreibweg (`Set-WorkItem.ps1`); eine Humanantwort setzt weder `implementedAt`
noch `acceptedAt`. Eine abhängige Folgeaufgabe wird erst nach der erforderlichen
WorkItem-Abnahme planbar, eine Fortsetzung desselben beantworteten Agenten-WorkItems
über den gebundenen Resumeweg. Der Antwortkanal wählt keine freie Folgeaufgabe.

Migration innerhalb Schema 1.0 ist additiv und ausgeführt erst bei ausdrücklichem
Write: alte offene Informations-/Aktionsrequests erhalten bei realer Antwort den
deterministischen Schlüssel aus WorkItem-ID und genauer Anfragezeit sowie den
gelieferten Menschen/Beleg. Vorhandene Antworten werden unverändert erhalten und
nie nachträglich zu `approved` hochgestuft. Alte Approvalrequests werden über den
Anfragesetter mit konkreten Vorschlagsbytes und Human-ID erneuert; alte Antwort oder
offene Anfrage bleibt Historie. Aktive historische Snapshots bleiben lesbar; der
Legacy-Freitext allein eröffnet keinen neuen Freigabe-/Resumeweg. Terminale Einträge
bleiben unverändert, neue Arbeit erhält neue WorkItems. Kein Bestand wird installiert
oder automatisch migriert.

Der vorhandene Delegations-Jobmarker sperrt agentische Antwortaufnahme, der normale
Storeweg verweigert direkte Antwort-/Auflösungsänderungen. Respondent, Originalbeleg
und lokale Session sind keine unabhängig authentifizierte menschliche Identität.
Die tatsächliche Zuständigkeit und Originalquelle werden im menschlichen Eingang
verantwortet. Gleiche lokale Dateirechte erlauben Umgehen des Anwendungspfads;
hier wird keine zusätzliche Authentifizierungs-/Codeattestationsplattform behauptet.

## Produktive Validierung

Es gilt die [aktuelle Prüfregel](../../AGENTS.md): keine Tests ausführen oder erstellen.

```powershell
.\scripts\workitems\Test-WorkItems.ps1 -Path .\examples\workitems\goal-with-children.json
.\scripts\workitems\Test-WorkItems.ps1 -Path next.json -PreviousPath current.json
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

## OrganisationsÄnderungen

Änderungen empfindlicher Organisationsstrukturen benötigen ein abgegrenztes
WorkItem und vorherige menschliche Freigabe. Es gilt ausschließlich
Koordinator -> zuständiger Teamleiter -> Optimierer; der Teamleiter entscheidet
über interne Besetzung und Zusammenarbeit. Die Umsetzung liefert Ergebnisbelege,
keine eigene Elternabnahme. Unabhängige Prüfung und abschließende Entscheidung
bleiben separat; [AR55](AR55-IMPLEMENTATION.md) dokumentiert diesen Auftrag.
