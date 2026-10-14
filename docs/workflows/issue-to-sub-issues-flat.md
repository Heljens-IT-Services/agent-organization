# Workflow: Issue To Sub Issues Flat

## Owner

`product_owner` führt die fachliche Zerlegung von User Stories/User Epics in genau eine Child-Ebene operativ aus. Technischer Zerlegungs- und Klärungsbedarf wird dem Koordinator mit fachlichen Kriterien und konzeptuellen Auswirkungen gemeldet. Er vermittelt den erforderlichen Teilkontext.

## Ziel

Ein Issue genau eine Ebene in klare Child-Issues zerlegen.

## Verwenden

- Für bewusst flache Zerlegung.
- Als atomarer Teilworkflow von `issue-to-sub-issues.md`.
- Nicht verwenden, wenn das Ausgangs-Issue bereits terminal ist.

## Verwendete Skills

- `issue-reading`
- `requirements-clarification`
- `brainstorming`
- `issue-creation`
- `type-setting`
- `relationship-setting`

## Ablauf

1. Ausgangs-Issue und vorhandene direkte Children lesen.
2. Ziel, Scope und Akzeptanzkriterien klären, falls sie für einen Schnitt nicht ausreichen.
3. Vorhandene passende Child-Issues wiederverwenden.
4. Falls nötig mit `brainstorming` den Schnitt bestimmen.
5. Genau eine fachliche Child-Ebene planen. Wenn technische Children oder ein technischer Task-Vertrag erforderlich sind, stoppt Product Owner vor deren technischer Planung und bittet den Koordinator, Architektur im eigenen Scope einzusetzen.
6. Fehlende User-Child-Issues erstellen und ihren Type setzen. Wesentliche offene Entscheidungen sichtbar lassen und einen Task nicht ohne belegten technischen Ausführungsplan als terminal behandeln.
7. Parent/Child-Beziehungen setzen.
8. Erforderliche `blocked by`-Beziehungen setzen.
9. Die erzeugte Ebene zurücklesen und prüfen.

## Schnittkriterien

- ein klares Ziel pro Child-Issue
- eigenständig verständlich und kleiner als der Parent
- klarer Scope und Nicht-Scope
- belastbare Abschluss- oder Akzeptanzkriterien
- keine semantischen Duplikate
- Parent/Child nicht als Ausführungsreihenfolge interpretieren
- Type kontextbasiert bestimmen
- technische Task-Children erfüllen den kanonischen Task-Issue-Vertrag nach Planung durch Architektur oder sind ausdrücklich als nicht terminal erkennbar

## Rollenübergaben

- Zerlegung, Schnittkriterien und fachliche Parent/Child-Entscheidung: `product_owner`.
- User-Issue-Erstellung, fachliche Types/Relationships und Read-back: `product_owner`.
- Technical Stories/Epics/Tasks einschließlich Erstellung, Inhaltsänderungen, technischer Task-Verträge, technischer Types/Relationships und Read-back: Architektur nach separater Zuweisung durch den Koordinator.
- Technische Detailplanung geht über den Koordinator an Architektur.

## Rücksprungregeln

- Bei unklarem Ziel oder Schnitt an Product Owner zurückgeben.
- Bei widersprüchlicher Hierarchie oder Type-Zuordnung vor der Mutation stoppen.
- Schreibmutationen erst nach eindeutiger Ableitung ausführen und anschließend zurücklesen.

## Endergebnis

- genau eine verifizierte Child-Ebene
- gesetzte Types und Beziehungen

## Grenzen

- Keine zweite Ebene erzeugen.
- Keine Umsetzung starten.
- Ausgangs-Issue nicht schließen.
- Keine künstliche Zerlegung erzeugen.

