# Skill: Code Analyse

## Zweck

Code, Branches, Legacy-Bereiche oder konkrete Fehlverhalten bewerten und einordnen.

## Verwenden

- Bei Analysefragen zu Bugs, Fehlverhalten, Seiteneffekten, Legacy-Code, Branches, Architektur, Wartbarkeit oder konkreten Code-Stellen.
- Verwenden, wenn eine Bewertung oder Einordnung erwartet wird.
- Default-Modus: `context-only`, ohne Repository-Artefakt.
- Expliziter Artefaktmodus: nur bei einem zulässigen, benennbaren Persistenztreiber.
- Nicht automatisch bei "Fix bug X" verwenden. Das gehört in einen Bugfix-Workflow, der Analyse explizit als Schritt benennt.
- Nicht verwenden, wenn Code nur gelesen oder als Kontext erklärt werden soll. Dann `code-reading` nutzen.

## Vorgehen

1. Auftrag, Ausgangsfrage und naheliegende Annahmen knapp festhalten.
2. Betroffenen Scope bestimmen: Dateien, Symbole, Branches, Module, Datenflüsse, Schnittstellen oder Laufzeitkontext.
3. Read-only Evidenz aus Code, Diffs, Historie und vorhandenen Logs sammeln.
4. Bei Docker-Projekten Container-Logs und Datenbankinhalte nur lesend prüfen, wenn sie für die Analyse relevant sind.
5. Befunde mit Evidenz abgleichen und Unsicherheiten markieren.
6. Bewertung nach Ursache/Verhalten, Auswirkungen, Risiken, Wartbarkeit/Komplexität, Architekturgrenzen, Testbarkeit und Abhängigkeiten/Schnittstellen strukturieren.
7. Vor einer Persistenz prüfen, ob ein zulässiger Persistenztreiber vorliegt, und Modus sowie Grund festhalten.
8. Im Default-Modus Analyse nur in den Agenten-Kontext laden und knapp zusammenfassen; im ausdrücklich ausgelösten Artefaktmodus das vereinbarte Artefakt erstellen.

## Grenzen

- Hauptsächlich read-only arbeiten.
- Keine Produktivcode-Änderungen vornehmen.
- Keine Debug-Logs, Repro-Skripte oder Tests anlegen, außer der User fordert es explizit.
- Keine Tests oder Builds ausführen und keine externe Recherche durchführen; benötigte Ergebnisse vorgelagert mit `code-testing` bzw. `research` laden.
- Schreibend ist nur das Analyseartefakt unter `docs/` vorgesehen, falls der ausdrücklich ausgelöste Modus ein Artefakt verlangt.
- Bei unklarem Auftrag selbstständig mit naheliegenden Annahmen starten und diese im Artefakt oder im Context-only-Ergebnis markieren.

## Artefaktmodus

[MUST] `code-analysis` arbeitet ohne ausdrücklichen Persistenzgrund im Context-only-Modus und erzeugt keine Datei im Repository.

[MUST] Ein Analyseartefakt darf nur entstehen, wenn mindestens einer dieser konkreten Persistenztreiber vorliegt:

1. Der User verlangt ausdrücklich eine Datei oder persistente Analyse.
2. Ein aufrufender Workflow definiert das Analyseartefakt ausdrücklich als erforderliches Endergebnis oder Handoff.
3. Die Analyse selbst ist das vereinbarte fachliche Deliverable und nicht nur Vorarbeit für Umsetzung.
4. Ein benannter nachgelagerter Prozess oder Mensch benötigt denselben Befund sitzungsübergreifend als Referenz und dieser Bedarf kann nicht sinnvoll durch Issue- oder Task-Kontext abgedeckt werden.

[MUST] Wenn ein Artefakt erzeugt wird, müssen Persistenztreiber, Modus, Zweck und nachgelagerter Verbraucher im Output oder im aufrufenden Kontext benannt sein.

[MUST_NOT] Ein Artefakt darf nicht allein deshalb erzeugt werden, weil die Analyse nicht-trivial, lang, technisch interessant oder später möglicherweise nützlich ist.

[MUST_NOT] Root-Cause-Diagnose innerhalb eines Bugfix-, Implementierungs- oder Remediation-Workflows darf standardmäßig keine `docs/analysis-*`-Datei erzeugen, wenn die Erkenntnisse unmittelbar in denselben Arbeitsfluss einfließen.

[MUST_NOT] Ephemere Hypothesen, verworfene Ursachen, Debug-Spuren oder Zwischenbefunde dürfen nicht als dauerhafte Dokumentation konserviert werden, sofern sie nicht selbst relevante Nachweise des beauftragten Deliverables sind.

[SHOULD] Persistenter technischer Kontext, der dauerhaft benötigt wird, soll an der fachlich richtigen kanonischen Stelle landen, zum Beispiel im Issue, in Architektur-/Nutzerdokumentation oder einem Decision Record, statt automatisch als generische Analyseakte.

- Dateiname: `analysis-<scope>.md`, ohne Timestamp und ohne Unterordner.
- Minimalistisch und scharf formulieren.
- Bulletpoint-Listen und Tabellen bevorzugen.
- Code-Schnipsel vermeiden, außer sie sind gewünscht oder für Evidenz zwingend nötig.

Standardabschnitte:

- Ausgangsfrage
- Annahmen
- Untersuchter Scope
- Relevante Dateien/Symbole
- Befunde mit Evidenz
- Bewertung
- Risiken/Auswirkungen
- Offene Fragen

## Output

- Analyseartefakt unter `docs/analysis-<scope>.md`, außer im Context-only-Modus
- kurze Chat-Zusammenfassung der zentralen Befunde, Bewertung, Risiken und offenen Fragen

## Qualitätskriterien

- Keine Lösung verkaufen, bevor die Ursache belastbar ist.
- Unsicherheit explizit markieren.
- Dateipfade, Symbole oder Logs nennen, wenn sie die Aussage stützen.
- Beobachtung, Bewertung und Annahme klar trennen.
- Keine nächsten Schritte als eigenen Abschnitt im Artefakt ausgeben.
