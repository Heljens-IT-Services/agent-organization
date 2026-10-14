# Workflow: Project Implementation Planning

## Owner

`product_owner` führt die fachliche Phasenplanung aus freigegebener Strategie und Roadmap operativ aus. Strategische Leitplanken werden vom Koordinator als freigegebener Eingangskontext übergeben. Product Owner erfasst technische Constraints nur konzeptuell und meldet technische Richtungsfragen dem Koordinator. Product Owner liest keinen Quellcode und leitet keine technischen Detailpläne ab.

## Ziel

Ein strategisch geklärtes Projektziel durch Human-geführte Klärung in einen freigegebenen Implementierungsplan oberhalb der Epic-Ebene überführen. Der Plan beschreibt große Implementierungsphasen und keine technische Story-/Task-Zerlegung.

## Verwenden

- Wenn ein freigegebenes Projektziel und seine strategischen Leitplanken vor der Epic-Erstellung in fachliche Phasen übersetzt werden sollen.
- Wenn Scope, Nicht-Ziele, operative Feature-Konkretisierung, Abhängigkeiten oder Phasenfreigabe noch mit dem Human geklärt werden müssen.
- Wenn strategische Leitplanken fehlen oder eine neue Produkt- oder Roadmapentscheidung erforderlich wird, an den Koordinator zurückgeben und die Phasenplanung bis zur Klärung als `BLOCKED` kennzeichnen.
- Nicht verwenden, um technische Arbeitspakete auf Datei-, Symbol- oder Task-Ebene zu planen. Dafür `code-implementation-planning` verwenden.
- Nicht verwenden, um automatisch GitHub-Issues oder Epics zu erzeugen. Die Materialisierung einer freigegebenen Phase ist ein nachgelagerter, eigener Schritt.

## Verwendete Skills

- `requirements-clarification`
- `brainstorming` bei mehreren plausiblen Produkt- oder Architekturentscheidungen

## Ablauf

1. Freigegebene Strategie, Roadmap, Zielbild, Outcome-Ziele und den zugewiesenen Planungsscope als Eingangskontext festhalten. Fehlende oder widersprüchliche strategische Leitplanken dem Koordinator melden.
2. Über den Koordinator erwartete Fähigkeiten/Features innerhalb der Leitplanken, Scope, Nicht-Ziele, operative Prioritäten, Abhängigkeiten, Constraints und Phasenerfolgskriterien klären.
3. Offene operative Produkt-, Architektur- oder Vorgehensentscheidungen sichtbar machen. Strategische Richtungsfragen an den Koordinator zurückgeben; technische Richtungsfragen an den Koordinator melden. Bei mehreren tragfähigen operativen Richtungen `brainstorming` verwenden.
4. Prüfen, dass die Klärung belastbar ist: Ziel und Nicht-Ziele sind eindeutig, Scope-Grenzen sind benennbar, operative Prioritäten sind geordnet und wesentliche Entscheidungen sind entschieden oder ausdrücklich als Blocker dokumentiert.
5. Über den Koordinator ein explizites Human-Gate durchführen. Nur eine ausdrückliche Freigabe des Humans darf den Status `READY` beziehungsweise `FINAL` begründen.
6. Nach Freigabe große Implementierungsphasen mit dem Phasenvertrag dieses Workflows formulieren.
7. Jede Phase gegen Zielbild, Scope, Nicht-Ziele, Abhängigkeiten/Constraints und Exit-/Akzeptanzkriterien prüfen.
8. Den Plan als Chat-Kontext ausgeben oder als langlebiges Artefakt dokumentieren, wenn der User dies verlangt oder der konkrete Projektworkflow es vorsieht.

## Human-Gate

Vor der finalen Phasenbildung muss der Human mindestens bestätigen:

- freigegebenes strategisches Zielbild und erwartete Fähigkeiten,
- Scope und Nicht-Ziele,
- Prioritäten und wesentliche Abhängigkeiten,
- relevante operative Produkt- und Architekturentscheidungen,
- dass die daraus gebildeten Phasen als Grundlage für Epic-Issues dienen dürfen.

Ohne diese Freigabe bleibt der Plan `DRAFT` oder `BLOCKED`; ein finaler oder belastbarer Plan darf nicht behauptet werden.

## Planvertrag

Ein freigegebener Plan enthält mindestens:

- freigegebenes strategisches Zielbild und erwarteten Zielzustand,
- vereinbarten Scope und Nicht-Ziele,
- Prioritäten, Constraints und wesentliche Entscheidungen,
- offene Punkte oder Blocker,
- geordnete große Implementierungsphasen,
- pro Phase Ziel, Scope, Nicht-Ziele, wesentliche Abhängigkeiten/Constraints und Exit-/Akzeptanzkriterien,
- Status `DRAFT`, `READY` oder `BLOCKED`, Freigabeentscheidung und Freigabekontext.

Phasen sind fachliche High-Level-Zielzustände oberhalb von Epics. Sie dürfen keine unnötige Mikroplanung für Stories, Tasks, Dateien oder Symbole enthalten.

## Phase-zu-Epic-Mapping

Eine Phase ist `epic-reif`, wenn der Plan den Status `READY` besitzt, die Phase ausdrücklich freigegeben ist und ihr Ziel, Scope, Nicht-Ziele, wesentliche Abhängigkeiten/Constraints sowie Exit-/Akzeptanzkriterien vollständig beschrieben sind.

Beim Materialisieren wird genau eine freigegebene Phase als ein GitHub-Issue vom nativen Type `Epic` abgebildet. Das Epic übernimmt mindestens:

- Phasenname und Zielzustand,
- Kontext, Scope und Nicht-Ziele,
- relevante Abhängigkeiten und Constraints,
- Exit-/Akzeptanzkriterien sowie den Freigabekontext.

Der Mapping-Schritt verwendet ein vorhandenes passendes Epic wieder, statt ein Duplikat zu erzeugen. Ein noch nicht freigegebener oder wesentlich offener Phasenstand darf nicht als finales Epic materialisiert werden. Die weitere Zerlegung des Epic erfolgt ausschließlich über `/sub-issues`; Story-/Task-Planung wird nicht vorgezogen.

Die Phasenreihenfolge wird nicht durch Parent/Child simuliert. Nur eine tatsächlich erforderliche harte Ausführungsabhängigkeit wird zusätzlich als richtungsstabile native `blocked by`-Beziehung modelliert.

## Rücksprungregeln

- Bei unklarem operativem Scope oder Nicht-Ziel zu `requirements-clarification` zurückkehren.
- Bei einer offenen strategischen Richtungsentscheidung den Koordinator um strategische Klärung bitten; bis zur Klärung `BLOCKED` bleiben.
- Bei einer offenen operativen Richtungsentscheidung zu `brainstorming` zurückkehren.
- Bei fehlender Human-Freigabe im Status `DRAFT` beziehungsweise `BLOCKED` verbleiben.

## Endergebnis

- geklärtes und vom Human freigegebenes Zielbild
- klar abgegrenzter projektweiter Implementierungsplan
- große, einzeln beschriebene Implementierungsphasen oberhalb der Epic-Ebene
- sichtbare offene Punkte und Blocker
- keine automatisch erzeugten Issues und keine technische Task-Mikroplanung

## Grenzen

- Keine implizite oder automatische Human-Freigabe.
- Keine neuen Anforderungen ohne Klärung in den Plan aufnehmen.
- Keine Strategie, Roadmap oder Featurehypothese in diesem Workflow neu festlegen oder ändern.
- Keine Epic-, Story- oder Task-Erstellung in diesem Workflow.
- Keine technische Detailplanung von Stories oder Tasks vorwegnehmen.

