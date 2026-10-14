# Workflow: Issue To Sub Issues

## Owner

`product_owner` führt fachliche Zerlegung und User-Issue-Mutationen operativ aus. Technische Child-Issues und Task-Verträge werden als Bedarf an den Koordinator gegeben. Der fachliche Auftrag verwendet Produktkontext und konzeptuelle Constraints.

## Ziel

Ein Issue als Baum bis zu sauber geschnittenen, eigenständig ausführbaren Leaf-Issues zerlegen. Ohne Zusatz rekursiv, mit `flat` genau eine Ebene.

## Verwenden

- Für Epics, Stories oder zu große Tasks, die weiter zerlegt werden sollen.
- Nicht für direkte Umsetzung; dafür `issue-graph-implementation.md`, `issue-to-pr.md` oder `issue-implementation.md` nutzen.

## Direkter Alias

- `/sub-issues <issue-number>`
- `/sub-issues <issue-number> flat`

`<issue-number>` ist eine positive Ganzzahl mit optionalem `#`. `flat` ist das einzige optionale Positionsargument.

## Verwendete Skills

- `issue-reading`
- `requirements-clarification`
- `brainstorming`

## Verwendete Workflows

- `issue-to-sub-issues-flat.md`

## Modi

### Übergabe eines Phase-Epics

Vor der Zerlegung eines aus einem projektweiten Plan materialisierten Epic wird geprüft, dass die zugrunde liegende Phase den Status `READY` besitzt und freigegeben ist. Das Epic muss genau diese Phase repräsentieren; ein passendes bestehendes Epic wird wiederverwendet und nicht dupliziert.

Die Übergabe prüft den nativen Type `Epic` sowie vorhandene native Parent/Child- und `blocked by`-Beziehungen. Body-Links oder Checklisten ersetzen diese Metadaten nicht. Parent/Child ordnet die fachliche Struktur, nicht die Reihenfolge der Phasen. Eine harte Ausführungsabhängigkeit wird nur bei tatsächlicher Notwendigkeit als richtungsstabile `blocked by`-Beziehung ergänzt.

Nach dieser Prüfung übernimmt `/sub-issues` ausschließlich seine normale rekursive oder flache Zerlegung. Es plant keine Projektphasen neu und zieht keine Story-/Task-Mikroplanung aus dem Phasenplan vor.

### Rekursiv

Standard ohne Zusatz.

1. Ausgangs-Issue und vorhandene Child-Struktur lesen.
2. Geschlossene Knoten nicht erneut zerlegen.
3. Offene Leaf-Issues auf Terminalität prüfen.
4. Einen User-Task gegen den kanonischen Task-Issue-Vertrag vervollständigen, soweit die vorhandenen technischen Entscheidungen und der Ausführungsplan von Architektur geliefert wurden; andernfalls den Koordinator um einen abgegrenzten Architekturbeitrag bitten. Technische Strukturentscheidungen oder Pläne nicht selbst ableiten.
5. Neue Child-Issues erneut prüfen.
6. Wiederholen, bis jeder offene Ast in terminalen Leaves endet.
7. Bestehende Issues wiederverwenden und Duplikate vermeiden.
8. Bereits besuchte Issues nicht erneut traversieren; Zyklen als Blocker melden.

### Flat

Bei `/sub-issues <issue-number> flat` `issue-to-sub-issues-flat.md` genau einmal für das Ausgangs-Issue ausführen. Danach nicht weiter zerlegen.

## Terminalitätskriterien

Ein Task-Leaf ist nur terminal, wenn er den [kanonischen Task-Issue-Vertrag](../github/ISSUE_TEMPLATES.md#task-issue-vertrag) vollständig erfüllt und ohne erneute grundlegende Architektur-, Scope- oder Vorgehensentscheidung umgesetzt werden kann.

Zusätzlich:

- `Epic` und `Story` sind im rekursiven Modus nicht terminal, solange eine sinnvolle weitere Zerlegung möglich ist.
- Der Type `Task` allein beendet die Rekursion nicht.
- Ein `Spike` darf terminal sein, wenn sein Ergebnis bewusst Recherche, Analyse, Entscheidung oder Klärung ist.
- Keine künstliche Mindest- oder Zieltiefe erzeugen. Unterschiedliche Äste dürfen unterschiedlich tief sein.
- Nicht bis zu technisch trivialen Kleinstschritten zerlegen.
- Bleiben wesentliche Entscheidungen offen, muss weiter geklärt, geplant oder fachlich sinnvoll zerlegt werden.

## Baumregeln

- Parent/Child beschreibt Hierarchie, nicht automatisch Ausführungsreihenfolge.
- Harte Abhängigkeiten nur als `blocked by` setzen, wenn sie tatsächlich erforderlich sind.
- Abhängigkeiten möglichst auf der niedrigsten fachlich korrekten Ebene ausdrücken.
- Jeder erzeugte Knoten muss kleiner und klarer als sein Parent sein.
- Bestehende passende Child-Issues verwenden statt Duplikate zu erzeugen.

## Rücksprungregeln

- Bei unklarem Issue-Inhalt an Product Owner zur erneuten Issue-Lektüre zurückgeben.
- Bei unklarem fachlichem Ziel oder Scope die Anforderungsklärung durch Product Owner fortsetzen.
- Bei ungeklärtem technischem Scope, fehlendem Ausführungsplan oder technischen Task-Kriterien den Koordinator um einen begrenzten Architekturauftrag bitten.
- Bei unklarem Schnitt fachliche Optionen mit Product Owner erneut strukturieren.
- Bei Zyklen, widersprüchlicher Hierarchie oder nicht belastbarer Zerlegung stoppen und den Blocker benennen.

## Rollenübergaben

- Rekursive oder flache fachliche Zerlegung, fachliche Schnittkriterien und User-Issue-Terminalität: `product_owner`.
- Technische Zerlegung, Technical Stories/Epics/Tasks einschließlich technischer Task-Terminalität: Architektur nach separater Koordinatorzuweisung.
- User-Issue-Erstellung, fachliche Type- und Relationship-Mutationen sowie Read-back: `product_owner`. Technical Tasks einschließlich Inhalts-, Type- und Relationship-Mutationen sowie Read-back: Architektur nach separater Koordinatorzuweisung.
- Technische Detailpläne und technische Strukturentscheidungen werden an den Koordinator zurückgegeben.
- Konflikte in Hierarchie oder fachlichem Scope gehen an Product Owner; keine eigene Subdelegation durch den operativen Owner.

## Endergebnis

### Rekursiv

- vollständiger relevanter Issue-Baum
- terminale offene Leaf-Tasks oder bewusst terminale Spikes
- gesetzte Parent/Child- und erforderliche `blocked by`-Beziehungen

### Flat

- genau eine erzeugte oder vervollständigte Child-Ebene

## Grenzen

- Keine Umsetzung starten.
- Ausgangs-Issue nicht schließen.
- Keine künstliche Zerlegung nur zur Erzeugung weiterer Ebenen.
- Keine Duplikate erzeugen.

