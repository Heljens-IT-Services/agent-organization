# Skill: Code Implementieren

## Zweck

Eine geklärte Änderung mit minimalem Write-Scope und der kleinsten hinreichenden Lösung im Code umsetzen. Ein enger Write-Scope begrenzt den äußeren Änderungsbereich, ersetzt aber nicht die Begründung für die Lösungsgröße innerhalb dieses Scopes.

## Verwenden

- Wenn Ziel, Scope und Richtung ausreichend klar sind.
- Wenn eine kleine, offensichtliche Änderung direkt umgesetzt werden kann.
- Wenn für nicht-triviale Änderungen bereits ein belastbarer Plan vorliegt.
- Wenn ein terminaler Task das nächste geplante Arbeitspaket eindeutig vorgibt.
- Nicht verwenden, wenn erst Anforderung, Ursache, Optionen oder Plan geklärt werden müssen.
- Bei nicht-trivialen Änderungen muss bereits ein belastbarer Plan aus Task oder `code-implementation-planning` vorliegen; ihn nicht pauschal erneut erzeugen.

## Minimal hinreichende Lösung

[MUST] Vor dem Einführen einer neuen Abstraktion, Indirektion, Konfigurationsoption, Dependency oder parallelen Implementierungsvariante muss ein konkreter aktueller Treiber im Task oder bestehenden Repository benennbar sein.

[MUST] Wenn bestehende Architektur, API oder Extension Points den Task ohne zusätzliche konzeptionelle Ebene sauber tragen, muss die Implementierung diese vorhandenen Möglichkeiten bevorzugt nutzen.

[MUST] Eine neue Dependency benötigt einen konkret fehlenden Capability-Baustein. Vor ihrer Einführung muss geprüft werden, ob Standardbibliothek oder bereits vorhandene Dependencies den Bedarf angemessen abdecken.

[MUST] Ein zusätzlicher Fallback oder alternativer Pfad braucht einen real vorhandenen Fehler-/Kompatibilitätsfall oder eine explizite Anforderung. Ein rein hypothetischer zukünftiger Fall ist kein ausreichender Treiber.

[MUST] Wenn eine direkte Lösung und eine stärker abstrahierte Lösung den heutigen Vertrag gleichermaßen sauber, sicher und wartbar erfüllen, ist die Lösung mit weniger neuen Konzepten und Indirektionen zu wählen.

[MUST_NOT] Ein Interface darf nicht allein wegen hypothetischer künftiger Austauschbarkeit eingeführt werden. Mehrere reale Implementierungen, ein bestehendes Repository-Pattern, Test-/Boundary-Anforderungen oder ein expliziter Architektur-Constraint können dagegen gültige Treiber sein.

[MUST_NOT] Für eine einzelne konkrete Anforderung darf kein generisches Mini-Framework, Strategy-/Factory-System, Plugin-Modell oder konfigurierbare Pipeline aufgebaut werden, solange keine aktuelle Variation diesen Generalisierungsgrad benötigt.

[MUST_NOT] Neue Config-Flags, Optionsobjekte oder öffentliche API-Parameter dürfen nicht vorsorglich für hypothetische zukünftige Varianten eingeführt werden.

[MUST_NOT] Eine alte und eine neue Implementierung dürfen nicht parallel bestehen bleiben, wenn der Task keine Migration, Kompatibilitätsphase, Rollback-Fähigkeit oder andere aktuelle Notwendigkeit dafür verlangt.

[MUST_NOT] Bestehenden Code darf der Agent nicht um jeden Preis wiederverwenden, wenn dadurch stärkere Kopplung, semantisch falsche Verantwortung oder riskante Sonderlogik entsteht. `reuse > new abstraction` ist eine Präferenz, kein Zwang gegen saubere Architektur.

[SHOULD] Vor neuer Struktur in dieser Reihenfolge prüfen: bestehende Logik direkt anpassen -> vorhandenen Extension Point nutzen -> vorhandene Abstraktion gezielt erweitern -> erst dann neue Abstraktion einführen.

[SHOULD] Bei gleichwertigen Lösungen lokale Änderung vor zusätzlicher Indirektion und bestehende Capability vor neuer Dependency bevorzugen.

### Gültige aktuelle Treiber

Zusätzliche Struktur kann gerechtfertigt sein durch:

- ein ausdrückliches Akzeptanzkriterium oder einen Task-Constraint;
- mehrere bereits existierende reale Varianten oder Implementierungen;
- bestehende Duplikation, die im selben Task zwingend gemeinsam geändert werden muss;
- eine definierte Architektur-/Schichtengrenze des Repositorys;
- eine im Repository tatsächlich verwendete testbare Boundary oder Dependency-Inversion;
- einen realen Fehler-, Kompatibilitäts-, Migrations- oder Rollback-Pfad;
- eine Security-, Performance-, Transaktions- oder Datenintegritätsanforderung.

Nicht hinreichend allein sind „flexibler“, „sauberer“ ohne konkrete reduzierte Last, „besser erweiterbar“, „könnte später gebraucht werden“, „Best Practice“ ohne Repository-/Problembezug oder ein möglicher späterer Testing-Vorteil ohne aktuellen Boundary-Bedarf.

## Vorgehen

1. Das nächste geplante Arbeitspaket mit Ziel, Scope, erwartetem Ergebnis und Verifikation übernehmen.
2. Unmittelbar zu ändernde Dateien und angegebene Referenzimplementierungen lesen.
3. Das Arbeitspaket in der vorgesehenen Reihenfolge entlang bestehender Patterns umsetzen.
4. Produktivcode, relevante Testdateien und code-nahe Dokumentation nur innerhalb dieses Arbeitspakets anpassen.
5. Ergebnis gegen den technischen Plan, Scope, Nicht-Scope und bekannte Risiken prüfen.
6. Die im technischen Plan vorgesehene nachgelagerte Verifikation durch `code-testing` benennen.

## Grenzen

- Keine ungeplanten Nebenänderungen vornehmen.
- Keine Anforderungen stillschweigend erweitern.
- Nicht implementieren, wenn Ziel oder Scope unklar ist. Dann `requirements-clarification` oder `code-implementation-planning` nutzen.
- Keine breite Analyse, Recherche oder Alternativenabwägung durchführen.
- Während der Ausführung keine grundlegende Neuplanung oder erneute Alternativenabwägung durchführen.
- Keine breite Kontextsuche durchführen. Wenn Kontext fehlt, vorher `code-reading` nutzen.
- Nur unmittelbar betroffene Dateien lesen.
- Keine Tests, Builds oder Anwendungen ausführen. Das gehört zu `code-testing`.
- Verhalten, Logik, Feature oder API gezielt verändern; das ist der Zweck dieses Skills.
- Kein reines Refactoring durchführen. Verhaltenserhaltende Strukturverbesserung mit Zweck Lesbarkeit, Wartbarkeit oder Redundanzabbau gehört zu `code-refactoring`.
- Minimale strukturelle Anpassungen sind erlaubt, wenn sie unmittelbar nötig sind, um die Verhaltensänderung sauber einzubauen.
- `code-implementation` entscheidet über die für den heutigen Vertrag minimal hinreichende neue Lösung. `code-refactoring` verbessert danach bewusst bestehende Struktur bei Verhaltenserhalt; `code-minimization` entfernt in einer nachgelagerten Phase unbelegte Reste. Planung wird nicht ersetzt.
- Testdateien dürfen angepasst oder ergänzt werden, wenn sie zur umgesetzten Änderung gehören.
- Code-nahe Dokumentation darf aktualisiert werden, wenn sie direkt zur geänderten Stelle gehört, z. B. Kommentare, XML-docs, JSDoc oder API-Beschreibungen im selben Änderungsbereich.
- README, Architektur-Doku, Nutzer-Doku, Changelog oder externe Dokumentation nicht automatisch aktualisieren.
- Kleine lokale Abweichungen vom Plan sind erlaubt, wenn Ziel und Scope gleich bleiben.
- Stoppen und den Planbruch mit dem passenden vorgelagerten Skill benennen, wenn Architektur, Scope, Risiko oder Annahmen kippen.
- Pro Ausführung ein zusammenhängendes Arbeitspaket umsetzen.
- Mehrere Arbeitspakete nur umsetzen, wenn sie im Plan explizit als ein Umsetzungsschritt zusammengehören.
- Backend: Logik, Orchestrierung, Datenzugriff und Hilfen trennen, wenn Verantwortungen sonst vermischt werden.
- HTML/CSS: DOM und Styling direkt halten; unnötige Wrapper, Helferklassen und tiefe Verschachtelung vermeiden.

## Output

- umgesetzte Änderung
- kurze Zusammenfassung
- Hinweis auf erforderliche nachgelagerte Verifikation
- offene Punkte, falls nach der Implementierung sichtbar

## Qualitätskriterien

- Bestehende Architektur und Konventionen respektieren.
- Nicht behaupten, etwas sei getestet.
- Offene Punkte nur benennen, wenn sie sichtbar sind; nicht als eigene Analyse ausweiten.
