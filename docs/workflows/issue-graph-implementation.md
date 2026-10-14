# Workflow: Issue Graph Implementation

## Owner und Modus

`koordinator` liest diesen Ablauf ausschließlich als Delegationsplan und entscheidet keine fachlichen oder technischen Fragen selbst. Graph und Umsetzungsscope delegiert er an `product_owner`; technische Strukturpläne an `softwareentwicklung_architektur`; Branch, Runtime-Fortschrittsanker und Git-/PR-Lifecycle-Mutationen an `softwareentwicklung_infrastruktur`; Gestaltung an `designer`; Implementierung an Backend, Frontend oder Infrastruktur; formale Verifikation an `softwareentwicklung_qualitaetssicherung`. Issue-Arbeitseinheiten laufen gemäß Plan sequenziell; der Koordinator sammelt Rückgaben und steuert die nächste Phase.

## Ziel

Ein Issue mit seinem relevanten Issue-Graph deterministisch und vollständig bis zur verifizierten Implementierung und zu genau einem finalen Pull Request bearbeiten. Vor der Umsetzung wird der relevante Issue-Graph vollständig erfasst, der Umsetzungsscope festgelegt und ein temporärer Orchestrierungsplan erzeugt. Anschließend wird der vollständige Scope auf genau einem Arbeitsbranch sequenziell abgearbeitet.

## Verwenden

- Wenn ein Issue fachlich und technisch unter Berücksichtigung seines Issue-Graphen vollständig umgesetzt werden soll.
- Wenn Ausgangs-Issue, relevante Issue-Beziehungen, Scope, Ausführungsreihenfolge, Implementierung, Verifikation, Commit/Push und ein finaler Pull Request zusammenhängend bearbeitet werden sollen.
- Wenn mehrere Issues aufgrund von Parent/Child- oder Blocked-by-Beziehungen koordiniert werden müssen.
- Nicht verwenden, wenn der relevante Graph vor der Umsetzung nicht vollständig und deterministisch ausführbar ist.

## Direkte Aliase

- `/implement <issue-number>`

`<issue-number>` muss als positive Ganzzahl mit optional vorangestelltem `#` angegeben werden, zum Beispiel `/implement #123`.

## Verwendete Skills

- `github-branch-checkout-from-default`
- `issue-reading`
- `pr-creation`

## Verwendete Workflows

- `issue-implementation.md`
- `issue-acceptance-convergence.md`

## Phasen

### Phase 1: Graph lesen

1. Der Koordinator delegiert das Lesen des Ausgangs-Issues samt relevanter Parent-, Child- und Blocked-by-Beziehungen mit `issue-reading` an `product_owner`.
2. Product Owner verfolgt Child-Beziehungen vom Ausgangs-Issue rekursiv, bis keine weiteren relevanten Child-Issues gefunden werden.
3. Product Owner liest Blocked-by-Beziehungen für alle scope-relevanten Knoten und erfasst sie als Ausführungsabhängigkeiten; technische Unklarheiten gibt er zur Delegation an Architektur zurück.
4. Bereits besuchte Issues nicht erneut traversieren. Eine besuchte Menge anhand stabiler Repository-/Issue-Identität führen.
5. Parent-Beziehungen oberhalb des Ausgangs-Issues nur als Kontext lesen; daraus nicht automatisch weitere Geschwister oder andere Teilbäume in den Umsetzungsscope aufnehmen.
6. Geschlossene Issues und reine Container-Issues als solche klassifizieren.

### Phase 2: Scope und Ausführbarkeit bestimmen

1. Product Owner bestimmt aus dem gelesenen Graphen die fachlich tatsächlich umzusetzenden Issue-Knoten; Architektur liefert technische Kriterien zur Ausführbarkeit.
2. Parent/Child-Beziehungen bestimmen Zugehörigkeit und fachlichen Scope, aber nicht automatisch die Ausführungsreihenfolge.
3. Geschlossene Issues nicht erneut umsetzen.
4. Ein Parent- oder Container-Issue nicht zusätzlich als eigenes Arbeitspaket behandeln, wenn sein vollständiger Umsetzungsumfang durch aufgenommene Child-Issues abgedeckt ist.
5. Die Ausführungsreihenfolge anhand harter Abhängigkeiten bestimmen. Ein blockierter Knoten darf erst umgesetzt werden, nachdem seine Blocked-by-Abhängigkeiten erfüllt sind.
6. Wenn mehrere Knoten unabhängig voneinander ausführbar sind, eine stabile Reihenfolge festlegen.
7. Vor jeder Codeänderung sicherstellen, dass der vollständige Umsetzungsscope mit genau einem Arbeitsbranch und einem finalen Pull Request deterministisch ausführbar ist.
8. Wenn ein externer Blocker, ein Abhängigkeitszyklus, eine unklare Scope-Grenze oder eine andere Unstimmigkeit diese vollständige Ausführung verhindert, vor der Implementierung stoppen und den konkreten Grund melden. Keine partielle Umsetzung beginnen und keinen alternativen Ausführungsmodus ableiten.
9. Ergebnis der Phase ist eine explizite Menge aus:
   - umzusetzenden Issues
   - Kontext-Issues
   - bereits erledigten Issues
   - deterministischer Ausführungsreihenfolge

### Phase 3: Arbeitsbranch und Orchestrierungsplan vorbereiten

1. Der Koordinator delegiert die Vorbereitung genau eines geeigneten Arbeitsbranches von der Standardbasis mit `github-branch-checkout-from-default` an Infrastruktur.
2. Der Koordinator übergibt an Infrastruktur die Erfassung eines Orchestrierungsplans als langlebigen Fortschrittsanker im unversionierten Git-Verwaltungsbereich. Der Plan koordiniert Issue-Knoten und ersetzt nicht deren technische Task-Pläne. Pfad und Dateiname müssen aus Repository und Ausgangs-Issue deterministisch ableitbar sein.
3. Infrastruktur hält den Orchestrierungsplan als Runtime-Artefakt. Er muss Sitzungsunterbrechungen überstehen und darf nicht Bestandteil des fachlichen Repository-Änderungssatzes, eines Commits oder des Pull Requests werden.
4. Der Plan muss mindestens enthalten:
   - Ausgangs-Issue
   - alle gelesenen relevanten Issue-Knoten mit Status und Klassifikation
   - relevante Parent/Child- und Blocked-by-Beziehungen
   - finalen Umsetzungsscope
   - nicht umzusetzende Kontext- oder bereits erledigte Knoten mit Grund
   - deterministische Umsetzungsreihenfolge
   - letzten abgeschlossenen Schritt mit Commit- und Push-Kontext
5. Der Koordinator verwendet den zurückgemeldeten Plan während der Umsetzung als Orchestrierungsgrundlage und delegiert seine Aktualisierung nach jedem zustandsverändernden Schritt an Infrastruktur.

Empfohlene Struktur des Fortschrittsankers:

```markdown
# Issue Graph Execution Plan

## Root
- #123

## Scope
- #124 - ready
- #125 - blocked by #124
- #126 - ready

## Context only
- #123 - container; vollständig durch Child-Issues abgedeckt
- #120 - parent context

## Execution order
1. #124
2. #125
3. #126

## Progress
- last completed: none
```

### Phase 4: Nach Plan umsetzen

1. Der Koordinator beauftragt die Abarbeitung des Orchestrierungsplans in der festgelegten Reihenfolge.
2. Je Issue-Knoten delegiert der Koordinator genau eine abgeschlossene Arbeitseinheit gemäß `issue-implementation.md` an die zuständigen Spezialisten. Dieser Teilworkflow enthält nach lokaler Konvergenz und vor der unabhängigen technischen QA-Prüfung die Backend-/Frontend-Minimierung beziehungsweise die rollenbezogene Infrastrukturprüfung. Wenn eine Arbeitseinheit Designverantwortung enthält, delegiert der Koordinator die nötige Design-Exploration, das Handoff und den visuellen Review an `designer` vor der formalen Verifikation.
3. Ein nächstes Issue erst beginnen, wenn das vorherige Issue gemäß `issue-implementation.md` vollständig implementiert, verifiziert, reviewed, committed, gepusht und mit dem verpflichtenden persistenten deutschen Issue-Abschlusskommentar dokumentiert wurde.
4. Jeder vollständig umgesetzte Issue-Knoten muss mindestens einem eindeutig zuordenbaren Commit entsprechen. Wenn ein Issue mehrere logisch getrennte Commits benötigt, sind mehrere Commits zulässig.
5. Änderungen verschiedener Issue-Knoten nicht absichtlich in demselben Commit vermischen.
6. Nach dem persistenten Issue-Kommentar den Orchestrierungsplan gegen den tatsächlichen Zustand prüfen und aktualisieren.
7. Während dieser Phase keinen Pull Request erstellen. Der Pull Request gehört ausschließlich in Phase 6 nach vollständiger Abarbeitung des Umsetzungsscope.
8. Erkennt die Umsetzung eine Unstimmigkeit, durch die der vorab festgelegte Scope nicht mehr vollständig nach diesem Workflow ausführbar ist, stoppen und den konkreten Zustand melden. Nicht selbstständig in einen alternativen Workflow, eine partielle Umsetzung oder mehrere Pull Requests wechseln.

### Phase 5: Graphweite Acceptance-Konvergenz

1. Nach vollständiger Implementierung aller Scope-Knoten delegiert der Koordinator die fachliche Black-Box-Abnahme an Product Owner, die technische Kriterienprüfung an Architektur und unabhängige technische Regression an QA gemäß `issue-acceptance-convergence.md`. Wenn der User ausdrücklich einen engeren `/acceptance`-Scope gewählt hat, gilt dieser Scope.
2. Bei `PASS` mit der Abschluss- und PR-Phase fortfahren.
3. Bei `GAP` die finale PR-Phase blockieren, den Gap klassifizieren und den in `issue-acceptance-convergence.md` definierten Remediation-/Konvergenzzyklus ausführen: betroffene Issues auf dem bestehenden Arbeitsbranch mit `issue-implementation` lokal stabilisieren, rollenbezogen prüfen und fokussiert retesten; erst danach die vollständige ursprüngliche Acceptance-Menge erneut prüfen.
4. Bei `BLOCKED` den Workflow mit konkreter Begründung stoppen. Keinen finalen PR als vollständig akzeptierten Scope erzeugen.

### Phase 6: Abschluss und finaler Pull Request

1. Der Koordinator bittet Infrastruktur, anhand der Rückgaben zu prüfen, dass jeder Issue-Knoten im Umsetzungsscope vollständig implementiert, fachlich und technisch abgenommen sowie unabhängig technisch gesichert wurde.
2. Infrastruktur prüft für jeden Issue-Knoten, dass der Änderungssatz committed und auf den vorgesehenen Upstream gepusht wurde.
3. Infrastruktur vergleicht Commit-Historie und Orchestrierungsplan. Kein umgesetztes Issue darf ohne eindeutig zuordenbaren Commit-Kontext verbleiben.
4. Infrastruktur prüft, dass keine fachlichen Änderungen aus dem Umsetzungsscope uncommitted oder ungepusht verbleiben.
5. Infrastruktur prüft den lokalen Git-Arbeitsbaum. Vor PR-Erstellung muss er frei von unbeabsichtigten staged, unstaged oder untracked fachlichen Änderungen sein.
6. Infrastruktur entfernt Runtime-Artefakte im Arbeitsbaum und behält den Fortschrittsanker im Git-Verwaltungsbereich bis zur abschließenden Integritätsprüfung.
7. Infrastruktur prüft danach den Git-Arbeitsbaum erneut. Runtime-Artefakte dürfen weder staged noch committed sein und nicht im Arbeitsbaum zurückbleiben.
8. Ist der Arbeitsbaum nicht sauber oder fehlt ein Commit beziehungsweise Push, blockiert Infrastruktur die PR-Erstellung und meldet oder behebt den konkreten Restzustand im übertragenen Scope.
9. Der Koordinator übergibt den finalen Issue-Scope und die zurückgemeldeten Fach-, Technik- und QA-Belege an Infrastruktur als Pull-Request-Kontext.
10. Der Koordinator delegiert `pr-creation` an Infrastruktur, um genau einen Pull Request für den vollständigen Umsetzungsscope zu erstellen.
11. Infrastruktur verlinkt das Ausgangs-Issue und weitere durch den PR vollständig abgeschlossene Scope-Issues so, dass GitHub sie beim Merge schließen kann.
12. Infrastruktur prüft den Fortschrittsanker gegen Issue-Graph, Commit-, Push- und Pull-Request-Status und entfernt ihn.
13. Infrastruktur prüft den sauberen Arbeitsbaum erneut und meldet den Abschluss samt Belegen an den Koordinator.

## Rollenübergaben

- Graph erfassen, Issue-Scope strukturieren und fachliche Ausführbarkeit: `product_owner`.
- Technical-Task-Inhalte, -Types und -Relationships, technische Task-Pläne und technische Planbrüche: `softwareentwicklung_architektur`.
- Arbeitsbranch, Runtime-Fortschrittsanker, Commit, Push, PR und persistente Issue-Kommentare: `softwareentwicklung_infrastruktur`.
- Design-Handoff und visuelle Exploration: `designer`.
- Implementierung: Backend, Frontend oder Infrastruktur passend zum Scope.
- Fachliche Black-Box-Acceptance: `product_owner`.
- Technische Kriterienprüfung: `softwareentwicklung_architektur`.
- Unabhängige technische Regression und Gesamtsicherung: `softwareentwicklung_qualitaetssicherung`.
- Issue-Arbeitseinheiten bleiben sequenziell; Schreibzugriffe auf denselben Worktree werden nicht parallel delegiert.

## Endergebnis

- vollständig gelesener und klassifizierter relevanter Issue-Graph
- explizit bestimmter und vorab vollständig ausführbarer Umsetzungsscope
- genau ein Arbeitsbranch für den vollständigen Umsetzungsscope
- vollständig abgearbeiteter temporärer Orchestrierungsplan
- verifizierte Änderungen für alle Scope-Issues
- eindeutig pro Issue zuordenbarer Commit-/Push-Kontext
- entfernter temporärer Orchestrierungsplan und entfernte sonstige Runtime-Artefakte
- sauberer lokaler Git-Arbeitsbaum
- genau ein finaler Pull Request für den vollständigen Umsetzungsscope

## Grenzen

- Genau einen Arbeitsbranch für den vollständigen Umsetzungsscope verwenden.
- Während der Graph-Umsetzung keine Pull Requests erstellen.
- Genau einen Pull Request nach vollständiger Umsetzung des gesamten Scope erstellen.
- Keine Pull-Request-Schnitte, gestapelten Pull Requests, Ausführungswellen oder partiellen Graph-Umsetzungen innerhalb dieses Workflows planen oder ausführen.
- Sonderfälle nicht innerhalb von `/implement` lösen. Wenn der vollständige Scope nicht nach diesem Ablauf ausführbar ist, vor der Implementierung stoppen oder bei einer erst später erkannten grundlegenden Unstimmigkeit die weitere Ausführung stoppen und den Grund melden.
- Ausgangs-Issue nicht manuell schließen, wenn der Abschluss über den Pull-Request-Merge erfolgen soll.
- Child- oder andere Scope-Issues während der Graph-Umsetzung nicht vorzeitig manuell schließen, wenn sie durch denselben Pull Request abgeschlossen werden sollen.
- Parent/Child-Beziehungen nicht als harte Ausführungsabhängigkeit interpretieren, sofern keine zusätzliche Blocked-by- oder fachlich eindeutige Abhängigkeit besteht.
- Blockierende Issues außerhalb des fachlichen Graph-Scope nicht allein aufgrund einer Blocked-by-Beziehung automatisch umsetzen.
- Keine Umsetzung beginnen, bevor ein belastbarer Orchestrierungsplan vorliegt.
- Den Fortschrittsanker niemals committen oder in den Pull Request aufnehmen.
- Keinen Pull Request erstellen, solange der Arbeitsbaum nicht sauber ist oder abgeschlossene Issue-Knoten ohne vollständigen Commit-/Push-Kontext existieren.
- Wenn automatisches Schließen nicht sicher ist, im PR-Kontext sichtbar machen.
