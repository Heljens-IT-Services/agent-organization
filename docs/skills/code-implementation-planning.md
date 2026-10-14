# Skill: Code Implementierungsplanung

## Rollenbindung

Die technische Implementierungsplanung konkretisiert betroffene Strukturen, Schnittstellen, Reihenfolge und Verifikation im ausdrücklich zugewiesenen Architektur-Scope.

[MUST] Fehlende fachliche Entscheidungen werden dem Koordinator zur Klärung gemeldet. Der technische Plan baut auf dem freigegebenen fachlichen Kontext auf.

## Zweck

Belastbaren vorhandenen Kontext in einen konkreten, testbaren technischen Umsetzungsplan überführen.

## Verwenden

- Vor nicht-trivialen Codeänderungen.
- Wenn mehrere Dateien, Schichten oder Risiken betroffen sind.
- Wenn ein Plan als Agenten-Kontext für die Umsetzung oder als technische Vorarbeit für ein GitHub-Issue gebraucht wird.
- Nicht verwenden, wenn Ziel, Scope, Nicht-Ziele oder Akzeptanzkriterien noch unklar sind. Dann `requirements-clarification` nutzen.
- Nicht verwenden, wenn der nächste Schritt offensichtlich und klein ist.

## Vorgehen

1. Prüfen, ob Ziel, Scope, Nicht-Ziele, Akzeptanzkriterien und relevanter Kontext ausreichend vorliegen.
2. Fehlenden Kontext explizit benennen und passenden vorgelagerten Skill fordern.
3. Zielzustand und Definition of Done fixieren.
4. Betroffene Bereiche und Schnittstellen benennen.
5. Strukturentscheidung an den Sprachtyp anpassen.
6. Umsetzungsschritte arbeitspaketgenau in Ausführungsreihenfolge formulieren.
7. Test- oder Verifikationsplan und Risiken festlegen.
8. Betriebsart beachten: Agenten-Kontext, Chat-Output, Artefakt oder GitHub-Issue-Vorarbeit.
9. Bei GitHub-Issue-Vorarbeit alle Inhalte für den [kanonischen Task-Issue-Vertrag](../github/ISSUE_TEMPLATES.md#task-issue-vertrag) liefern. Wesentliche offene Entscheidungen verhindern einen terminalen Task und müssen als Klärungsbedarf sichtbar bleiben.
10. Den vollständigen Plan einschließlich Verifikation intern an den Koordinator übergeben. Im Default genügt gegenüber dem Nutzer eine kurze Bestätigung durch den Koordinator; weitere Arbeit wird von ihm rollenbezogen zugewiesen.

## Current-Driver-Test für neue Struktur

[MUST] Vor jeder neuen konzeptionellen Ebene im technischen Plan muss `softwareentwicklung_architektur` diese vier Fragen konkret beantworten:

1. **Current pressure:** Welcher konkrete heutige Task- oder Repository-Zustand erzeugt den Bedarf?
2. **Failure without it:** Was würde ohne diese Ebene heute dupliziert, verletzt, untestbar gekoppelt, unsicher, inkompatibel oder anderweitig konkret schlechter?
3. **Evidence:** Wo ist dieser Druck sichtbar, etwa in Acceptance Criterion, bestehenden Implementierungen/Consumern, realer Duplikation, Invariante, Architekturregel, Failure Mode oder Betriebsconstraint?
4. **Simpler alternative:** Kann der aktuelle Vertrag ohne diese Ebene über bestehende Struktur oder eine direktere Lösung gleichwertig erfüllt werden?

[MUST] Wenn Frage 1 oder 3 nicht konkret beantwortet werden kann oder Frage 4 mit „ja“ beantwortet wird, darf die neue Ebene standardmäßig nicht geplant werden.

Als neue konzeptionelle Ebene gelten insbesondere neue Interfaces oder Basisklassen, Service-/Provider-/Manager-/Repository-Layer, Strategy/Factory/Adapter/Facade/Bridge, Plugin-/Pipeline-/Handler-Modelle, öffentliche Config- oder API-Erweiterungen, neue Dependencies, Parallel-/Fallbackpfade und Generalisierungen für aktuell nicht vorhandene Variationen.

[MUST] Jede neu geplante Ebene muss Current Driver und heutige Evidenz im Task oder Repository besitzen. Ein Plan darf spekulative Struktur nicht durch ihre eigene Aufnahme in den Task-Contract nachträglich legitimieren.

[MUST] Bei Variation oder Wiederverwendung müssen reale aktuelle Varianten, Implementierungen oder Consumer benannt werden. Eine erwartete zweite Variante reicht nicht.

[MUST] Bei Testbarkeit müssen die konkrete schwer kontrollierbare Dependency/Boundary und der aktuelle Verifikationsbedarf benannt werden; „für Unit Tests besser“ allein reicht nicht.

[MUST] Bei Repository-Architektur muss die relevante Boundary oder Konvention im betroffenen Bereich tatsächlich gelten; Pattern-Ähnlichkeit aus einem anderen Bereich reicht nicht automatisch.

[MUST] Wenn direkte Lösung und neue Abstraktion den aktuellen Vertrag, dieselben Invarianten und die erforderliche Wartbarkeit gleichwertig erfüllen, ist die Variante mit weniger neuen Konzepten und Navigationsschritten zu planen.

[MUST_NOT] Zukünftige Features, Provider, Consumer, Modi, Mandanten oder Skalierungsanforderungen dürfen nicht erfunden werden, um eine zusätzliche Ebene zu rechtfertigen.

[MUST_NOT] Ungenutzte Extension Points, leere Hooks, Optionsfelder ohne aktuellen zweiten Wert oder APIs ohne aktuellen Consumer dürfen nicht als Vorbereitung Teil des Plans werden. Pattern-Namen und allgemeine Begriffe wie „flexibel“, „modular“, „Clean Architecture“, „SOLID“ oder „Best Practice“ sind ohne konkrete Evidenz keine Treiber.

Zulässige Treiber sind insbesondere explizite Acceptance-/Task-Constraints, bestehende Boundary-Regeln, mindestens zwei reale aktuelle Varianten oder Consumer, berührte Duplikation, reale externe Grenzen, Security-/Autorisierungs-/Transaktions-/Datenintegritäts- oder Compliance-Invarianten, Migrations-/Kompatibilitäts-/Rollback-Bedarf sowie konkrete Performance- oder Betriebsanforderungen.

## Grenzen

- Keine Codeänderungen vornehmen.
- Keinen Code, keine Issues und keine externe Dokumentation selbst lesen.
- Wenn Kontext fehlt, vorgelagert `code-reading`, `code-analysis`, `research`, `brainstorming` oder `requirements-clarification` nutzen.
- Nicht blind planen, wenn belastbarer Kontext fehlt.
- Design- oder Architekturentscheidungen nur aufnehmen, wenn sie die Umsetzung direkt steuern.
- Keine breite Alternativenabwägung ausführen. Dann `brainstorming` nutzen.
- Umsetzungsschritte nicht zu grob und nicht mikrogranular formulieren.
- Dateien oder Symbole nur nennen, wenn sie bekannt und für die Umsetzung hilfreich sind.
- Offene Punkte und Risiken klar benennen, wenn sie sichtbar sind.
- Keine Scheingenauigkeit erzeugen: unbekannte Dateien, Symbole oder Entscheidungen nicht erfinden.
- Bei offenen Punkten fragen, ob zuerst geklärt oder bewusst mit Annahmen weitergeplant werden soll.
- Kritische Risiken, die die Umsetzbarkeit gefährden, nicht überspringen.
- Betriebsart muss explizit vom User genannt werden; Default ist ein Plan im Agenten-Kontext.
- Keine Anforderungen stillschweigend erweitern.
- Keine Planung vortäuschen, wenn wesentliche Ziel- oder Scope-Fragen offen sind.
- Backend: Verantwortlichkeiten, Abhängigkeiten und testbare Grenzen bewusst trennen. Mehr Struktur ist nur bei konkret benannter reduzierter Kopplung oder anderer aktueller Last akzeptabel.
- HTML/CSS: Markup und Styling flach halten. Wrapper, Selektorketten und Abstraktion nur einführen, wenn sie konkret vereinfachen.

## Artefakt

- Nur erstellen, wenn der User es explizit verlangt.
- Dateiname: `docs/plan-<scope>.md`.
- Inhalt entspricht dem Output dieses Skills.
- Als Artefakt Checkbox-Listen für Arbeitspakete und Verifikation bevorzugen.

## Output

- Zielzustand
- Scope und Nicht-Ziele
- Akzeptanzkriterien
- Definition of Done
- betroffene Bereiche
- Umsetzungsschritte
- umsetzungsrelevante Design- oder Architekturentscheidungen
- Testplan
- Risiken oder offene Punkte
- Hinweise, falls der Plan als GitHub-Issue-Vorarbeit gedacht ist
- keine Issue-Form; bei GitHub-Issue-Vorarbeit aber eine eindeutige Zuordnung zum kanonischen Task-Issue-Vertrag
- Bei Betriebsart Agenten-Kontext vollständiger interner Plan an den Koordinator; nur die nutzerseitige Bestätigung bleibt kurz

## Qualitätskriterien

- Plan muss direkt umsetzbar sein.
- Scope klein halten.
- Tests oder Verifikation immer benennen.
- Test- oder Verifikationsplan gehört zu jeder Betriebsart, auch Agenten-Kontext.
- Reihenfolge muss die Umsetzung logisch tragen.
- Annahmen und offene Punkte klar markieren.
- Schritte sollen konkrete Arbeitspakete mit betroffenem Bereich beschreiben.
- Der Plan soll auf eine ausführbare Grundlage zielen, nicht auf Scheinsicherheit.

