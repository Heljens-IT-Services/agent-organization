# Skill: Code Refactoring

## Zweck

Code strukturieren, ohne beabsichtigtes Verhalten zu ändern, und dabei eine konkret vorhandene strukturelle Last netto reduzieren. Neue Abstraktion, Aufteilung oder Indirektion ist kein Selbstzweck.

## Verwenden

- Wenn Lesbarkeit, Wartbarkeit oder Verantwortungsgrenzen verbessert werden sollen.
- Wenn das zu erhaltende Verhalten durch vorhandenen Kontext oder `code-reading` ausreichend verstanden ist.
- Wenn ein Task oder Plan Zielstruktur, Scope, Verhaltensgrenzen und Verifikation belastbar vorgibt.
- Nicht verwenden, wenn fachliches Verhalten geändert werden soll. Dann Implementierung planen.

## Direkter Alias

- `/refactor`

`/refactor` verwendet den aktuellen Task- und Änderungskontext als Refactoring-Scope. Wenn der Alias unmittelbar nach `/implement <issue-number>` aufgerufen wird, bilden die durch diesen Workflow geänderten produktiven Dateien und zugehörigen Tests den Default-Scope; spätere oder nicht taskbezogene Änderungen gehören nicht automatisch dazu. Wenn das zu erhaltende Verhalten oder die Zuordnung zum vorausgegangenen Änderungssatz nicht eindeutig ist, muss der fehlende Kontext vor dem Refactoring geklärt werden.

## Vorgehen

1. Aus Task oder Plan zu erhaltendes Verhalten, Zielstruktur, Scope und Verifikation übernehmen.
2. Das nächste geplante Refactoring-Arbeitspaket und den kleinsten überprüfbaren Strukturumbau bestimmen.
3. Unmittelbar zu ändernde Dateien und angegebene Referenzen lesen.
4. Refactoring am Sprachtyp ausrichten.
5. Produktivcode, bei Bedarf Testdateien und code-nahe Dokumentation schrittweise ohne beabsichtigte Verhaltensänderung ändern.
6. Nach jedem Arbeitspaket Strukturgewinn, Verhaltenserhalt und erforderliche Verifikation benennen.

## Nachweisbarer Netto-Gewinn

[MUST] Vor einem nicht-trivialen Refactoring muss die konkrete bestehende strukturelle Last benannt werden, die reduziert werden soll.

[MUST] Nach jedem Refactoring-Arbeitspaket muss eine Vorher-Nachher-Aussage belegen, welche konkrete Last reduziert wurde und welche neue Struktur oder Indirektion dafür entstanden ist.

[MUST] Eine neue Abstraktion ist nur dann ein Refactoring-Gewinn, wenn ihre zusätzliche kognitive und strukturelle Last durch einen größeren konkreten Abbau bestehender Last gerechtfertigt ist.

[MUST] Wird Komplexität lediglich in eine neue Datei, Klasse oder Ebene verschoben, ohne Duplikation, Verzweigung, Verantwortungsmischung, Kopplung oder vergleichbare Last zu reduzieren, liegt kein Strukturgewinn vor.

[MUST] Bestehende unnötige Indirektion darf ausdrücklich entfernt, zusammengelegt oder inline genommen werden, sofern keine reale Boundary oder Invariante verloren geht.

[MUST_NOT] Ein Interface, Strategy-/Factory-Layer oder Wrapper darf nicht allein für hypothetische spätere Austauschbarkeit eingeführt werden.

[MUST_NOT] Eine Methode oder Klasse darf nicht allein zur Verkleinerung von Dateien oder Methoden extrahiert werden, wenn dadurch Navigation oder Kontrollfluss schwerer nachvollziehbar werden und keine andere konkrete Last sinkt.

[MUST_NOT] „Clean Code“, „SOLID“, „Best Practice“, „flexibler“, „modularer“ oder „testbarer“ reichen ohne konkrete vorherige Last und nachweisbaren Effekt nicht als alleinige Refactoring-Begründung.

[MUST_NOT] Verhalten, öffentliche Semantik oder Fehlerverhalten dürfen nicht verändert werden, um einen Strukturgewinn zu konstruieren. Bei notwendiger Verhaltensänderung ist `code-implementation` zuständig.

[SHOULD] Bei gleichwertigem Verhalten die Zielstruktur mit geringerem gesamten Konzept- und Navigationsaufwand wählen, sofern die adressierte Last mindestens gleichwertig reduziert wird.

Als belastbare strukturelle Last gelten insbesondere reale Duplikation, hohe Verzweigung oder Verschachtelung, vermischte Verantwortungen, konkrete propagierende Kopplung, unnötige Wrapper-Ketten, schwer isolierbare Abhängigkeiten an einer realen Boundary oder fehleranfällige Synchronisation mehrerer Implementierungsstellen. Zusätzliche Layer, ein Interface vor jeder Klasse, ein neuer Pattern-Name oder hypothetische spätere Wiederverwendung sind allein kein Strukturgewinn.

## Grenzen

- Kein fachliches Verhalten, keine Logik, keine Features und keine API absichtlich ändern. Dann `code-implementation` nutzen.
- Wenn eine Verhaltensänderung nötig wird, stoppen und `code-implementation` als passenden Skill benennen.
- Nicht refaktorieren, wenn das zu erhaltende Verhalten unklar ist. Dann vorher `code-reading` oder `code-analysis` nutzen.
- Keine breite Kontextsuche durchführen. Wenn Kontext fehlt, vorher `code-reading` nutzen.
- Nur unmittelbar betroffene Dateien lesen.
- Keine Tests, Builds oder Anwendungen ausführen. Das gehört zu `code-testing`.
- Testdateien dürfen geändert werden, wenn sie an neue Struktur, Namen oder Verantwortungsgrenzen angepasst werden und dasselbe Verhalten absichern.
- Code-nahe Dokumentation darf angepasst werden, wenn sie direkt zu geänderten Namen, Struktur oder Verantwortungsgrenzen gehört.
- README, Architektur-Doku, Nutzer-Doku, Changelog oder externe Dokumentation nicht automatisch aktualisieren. Dann `documentation` nutzen.
- Pro Ausführung ein zusammenhängendes Refactoring-Arbeitspaket umsetzen.
- Mehrere Refactoring-Arbeitspakete nur umsetzen, wenn sie im Plan explizit als ein Umsetzungsschritt zusammengehören.
- Keine breite Analyse, Recherche oder Implementierungsplanung ersetzen.
- `code-refactoring` verbessert bestehende Struktur bei erhaltenem Verhalten und nachgewiesenem Netto-Gewinn. `code-minimization` entfernt nachgelagert unbelegte Änderungsteile; `code-implementation` setzt neues Verhalten um. Diese Verantwortungen dürfen nicht vermischt werden.
- Keine Zielstruktur oder Alternativen während der Ausführung grundlegend neu ableiten; bei Planbruch stoppen.
- Backend: Verantwortlichkeiten dürfen stärker getrennt werden, wenn Logik testbarer und Abhängigkeiten klarer werden.
- HTML/CSS: Struktur eher reduzieren als abstrahieren; Verschachtelung, Container und komplexe Selektoren abbauen.

## Output

- refaktorierter Code
- erhaltendes Verhalten
- Strukturgewinn
- Hinweis auf erforderliche nachgelagerte Verifikation
- Restrisiken, falls sichtbar

## Qualitätskriterien

- Jede Verhaltensänderung explizit markieren.
- Kein Refactoring als verdeckte Feature-Arbeit.
- Vorher-Nachher-Unterschied strukturell erklären.
- Nicht behaupten, etwas sei getestet.
- Strukturgewinn immer konkret benennen.
- Restrisiken nur benennen, wenn sie sichtbar sind; nicht als eigene Analyse ausweiten.
