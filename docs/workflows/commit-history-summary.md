# Workflow: Commit History Summary

## Owner und Modus

`koordinator` liest diesen Ablauf als Delegationsplan. `softwareentwicklung_infrastruktur` liest Commit- und PR-Historie; fachliche Zusammenfassungen delegiert der Koordinator an `product_owner`, technische Einordnung an `softwareentwicklung_architektur`. Dokumentation im beauftragten Format übernimmt die inhaltlich zuständige Rolle.

## Ziel

Commits und gemergte Pull Requests eines Repositorys für einen angegebenen Zeitraum erfassen und als tabellarisches fachliches, technisches oder detailliertes Summary ausgeben.

## Verwenden

- Wenn ein Commit- und Pull-Request-Bericht für ein Datum, eine Anzahl vergangener Tage oder einen Zeitraum erstellt werden soll.
- Wenn die Ausgabe für Kundenkommunikation, technische Dokumentation oder eine detaillierte Historienprüfung gebraucht wird.
- Nicht verwenden, wenn offene Pull Requests, geplante Änderungen oder Issues ausgewertet werden sollen.

## Verwendete Skills

- `commit-history-reading`
- `documentation`

## Direkter Alias und Argumentvertrag

- `/summary [<period> ...] [--mode <mode>]`
- `/workflows run commit-history-summary [<period> ...] [--mode <mode>]`

Beide Aufrufe haben denselben Vertrag:

- Ein ISO-Datum `YYYY-MM-DD` bezeichnet einen Kalendertag.
- Eine positive Ganzzahl bezeichnet die Anzahl vergangener Kalendertage einschließlich heute.
- Zwei ISO-Daten bezeichnen Start und Ende eines inklusiven Zeitraums. Das Enddatum muss mindestens dem Startdatum entsprechen.
- `--mode <mode>` und `--mode=<mode>` akzeptieren `customer`, `technical` und `detailed`; ohne Option gilt `customer`.
- Die bereits dokumentierten Argumentformen `<days> Tage`, `<start-date> bis <end-date>` und `mode: <mode>` werden kompatibel auf denselben Vertrag normalisiert. Dies sind Zeitraum- und Moduswerte; stabile IDs und kanonische Optionen bleiben englisch.
- Derselbe Modus darf nur einmal angegeben werden, auch nicht zusätzlich in einer kompatiblen Form. Unbekannte Optionen, ungültige Kalenderdaten, nicht positive Tageszahlen, vertauschte Datumsgrenzen und weitere Tokens sind ungültig.
- Fehlt eine Zeitraumangabe im Command, darf ein bereits eindeutig festgelegter Zeitraum aus dem Nutzerkontext verwendet werden. Fehlt auch dieser, wird vor jeder Datenerhebung gezielt nachgefragt.
- Repository, Branch und Zeitzone werden gemäß der folgenden Tabelle aus vorhandenem Kontext oder Defaults übernommen. Dieser Command definiert dafür keine zusätzlichen Optionen.

Der Koordinator validiert den Berichtsrahmen vor der Delegation. Infrastruktur erfasst die Historie; die inhaltlich zuständigen Rollen bereiten die freigegebene Ausgabe auf.

## Eingaben und Defaults

| Eingabe | Pflicht | Default | Auflösung |
|---|---|---|---|
| Repository | Nein | aktuelles Repository | Explizite User-Angabe hat Vorrang. |
| Branch | Nein | Default-Branch des Repositorys | Nur von diesem Branch erreichbare Commits und in diesen Branch gemergte Pull Requests werden ausgewertet. |
| Zeitraum | Ja | - | Einzelnes Datum, Anzahl Tage oder Start- und Enddatum. |
| Modus | Nein | `customer` | `customer`, `technical` oder `detailed`. |
| Zeitzone | Nein | Zeitzone des Users, sonst `UTC` | Gilt für alle Zeitraumgrenzen und angezeigten Zeitpunkte. |

## Zeitraumregeln

- Ein einzelnes Datum umfasst den betreffenden Kalendertag von `00:00` bis zum Folgetag `00:00`.
- `N Tage` umfasst den aktuellen Kalendertag und die unmittelbar vorhergehenden `N - 1` Kalendertage.
- Ein Zeitraum aus Start- und Enddatum umfasst beide genannten Kalendertage.
- Intern muss jeder Zeitraum als halboffenes Intervall `[Start, Ende)` in der aufgelösten Zeitzone behandelt werden.
- Wenn weder im Command noch im vorhandenen Nutzerkontext ein eindeutiger Zeitraum vorliegt, muss vor der Datenerhebung nachgefragt werden.

## Modi

| Modus | Zielgruppe | Inhalt | Tabellenspalten |
|---|---|---|---|
| `customer` | Kunde oder fachlicher Stakeholder | Nach fachlichem Ergebnis gebündelte Änderungen, Nutzen und sichtbare Wirkung; technische Interna nur, wenn sie für das Verständnis notwendig sind. | Bereich, Änderung, Kundennutzen |
| `technical` | Entwicklung und technische Stakeholder | Gebündelte Implementierungen, betroffene Komponenten, technische Wirkung und dokumentierte Verifikation. | Bereich, Technische Umsetzung, Betroffene Komponenten, Verifikation |
| `detailed` | Audit, Nachverfolgung oder Vollständigkeitsprüfung | Chronologisch absteigende Einzelauflistung aller Pull Requests und Commits einschließlich ihrer Zuordnung. | Zeitpunkt, Typ, ID, Titel, Autor, Pull Request, Link |

Modusnamen werden ohne Beachtung der Groß-/Kleinschreibung aufgelöst und kanonisch in Kleinbuchstaben ausgegeben.

## Prompt-Beispiele

```text
/summary 2026-07-23
/summary 7 --mode technical
/summary 2026-07-01 2026-07-15 --mode detailed
```

## Ablauf

1. Repository, Branch, Zeitraum, Modus und Zeitzone aus der User-Anweisung auflösen.
2. Zeitraum gemäß den Zeitraumregeln in ein exaktes Intervall umrechnen und die aufgelösten Eingaben knapp ausweisen.
3. Mit `commit-history-reading` alle Commits, gemergten Pull Requests und ihre Zuordnung für den Branch und das Intervall laden.
4. Pull Requests als primäre Änderungseinheiten verwenden; zugeordnete Commits nicht zusätzlich als eigenständige Änderungen zählen.
5. Nicht zuordenbare Commits als eigenständige Änderungseinheiten aufnehmen.
6. Im Modus `customer` Änderungen nach fachlichem Ergebnis bündeln und mit `documentation` in kundengerechte Sprache überführen.
7. Im Modus `technical` Änderungen nach technischer Verantwortung oder Komponente bündeln und mit `documentation` präzise zusammenfassen.
8. Im Modus `detailed` Pull Requests und Commits einzeln chronologisch ausgeben; Zuordnungen sichtbar machen, ohne Datensätze zu verbergen.
9. Anzahl der gefundenen Pull Requests, Commits und eigenständigen Commits sowie vorhandene Kontextlücken nennen.

## Rücksprungregeln

- Bei fehlendem oder mehrdeutigem Zeitraum zur Eingabeauflösung zurückkehren und nachfragen.
- Bei unbekanntem Modus die gültigen Modi nennen und nachfragen.
- Bei unklarem Repository oder Branch zur Eingabeauflösung zurückkehren.
- Bei unvollständiger Historie zu `commit-history-reading` zurückkehren oder mit Blocker enden.
- Wenn aus Titel, Body und Commit-Nachrichten keine belastbare fachliche oder technische Aussage ableitbar ist, keine Wirkung erfinden, sondern die Kontextlücke ausweisen.

## Endergebnis

- aufgelöster Berichtsrahmen mit Repository, Branch, Zeitraum, Zeitzone und Modus
- tabellarisches Summary im gewählten Modus
- Anzahl der ausgewerteten Pull Requests, Commits und eigenständigen Commits
- Links zu den zugrunde liegenden Pull Requests und eigenständigen Commits
- benannte Kontextlücken oder Blocker

## Grenzen

- Nur gemergte Pull Requests und vom ausgewählten Branch erreichbare Commits auswerten.
- Keine fachliche Wirkung, Kundenwirkung, Verifikation oder technische Umsetzung erfinden.
- Im Modus `customer` keine Commit-SHAs, Branch-Namen oder Implementierungsdetails in die Haupttabelle aufnehmen.
- Im Modus `technical` keine Verifikation als erfolgreich darstellen, wenn sie nicht aus den Quellen hervorgeht.
- Im Modus `detailed` keine Commits oder Pull Requests wegen vermuteter geringer Relevanz auslassen.
- Keine Dateien erzeugen, außer der User verlangt ausdrücklich ein Artefakt.

