# Workflow: Issue Implementation

## Owner und Modus

`koordinator` liest diesen Ablauf ausschließlich als Delegationsplan. Fachlichen Task-Scope delegiert er an `product_owner`, technische Strukturfragen an `softwareentwicklung_architektur`, Gestaltung an `designer`, Implementierung an Backend, Frontend oder Infrastruktur im ausdrücklich zugewiesenen Infrastruktur-Scope, unabhängige Verifikation an `softwareentwicklung_qualitaetssicherung` und Commit/Push an `softwareentwicklung_infrastruktur`. Operative Phasen werden als getrennte Aufträge sequenziell übergeben.

## Ziel

Eine einzelne Arbeitseinheit, ein einzelnes Issue oder ein klar geschnittenes Arbeitspaket implementieren, verifizieren, reviewen, committen und pushen.

Die lokale Task-Verifikation dieses Workflows bleibt vom separaten, graphweiten Acceptance-Workflow abgegrenzt. Eine übergeordnete Acceptance-Prüfung wird durch `issue-graph-implementation.md` beziehungsweise einen ausdrücklichen `/acceptance`-Aufruf gesteuert.

## Verwenden

- Wenn ein einzelnes Issue oder Arbeitspaket innerhalb eines größeren Workflows umgesetzt werden soll.
- Wenn der Scope bereits aus Issue, Story, Planung oder Workflow-Kontext klar ist.
- Nicht verwenden, wenn ein Issue-Graph koordiniert, eine Gesamt-Reihenfolge bestimmt oder ein Pull Request erstellt werden soll. Dann `issue-graph-implementation.md` oder `issue-to-pr.md` nutzen.

## Verwendete Skills

- `github-branch-checkout-from-default`
- `issue-reading`
- `code-reading`
- `code-analysis`
- `code-implementation-planning`
- `code-implementation`
- `code-refactoring` nur für Backend-/Frontend-Änderungssätze
- `code-minimization` nur für Backend-/Frontend-Änderungssätze
- `design-review` bei relevanter visueller Designverantwortung
- `code-testing`
- `code-diff-review`

## Verwendete Workflows

- `design-exploration.md` bei offener gestalterischer Richtungsentscheidung
- `commit-push.md`

## Ablauf

1. Der Koordinator übergibt die Arbeitseinheit und den vorhandenen Kontext an die passende Fachrolle; Klärungsbedarf zu fachlichem Issue-Kontext geht an `product_owner`, zu technischen Issues einschließlich Technical Tasks an `softwareentwicklung_architektur`.
2. Der Koordinator delegiert Branchprüfung oder erforderliche Branchvorbereitung an `softwareentwicklung_infrastruktur`.
3. Wenn Issue-Kontext fehlt, delegiert der Koordinator das Lesen mit `issue-reading` je fachlichem oder technischem Scope an `product_owner` beziehungsweise Architektur.
4. Der Koordinator übergibt den vorhandenen fachlichen Scope an `product_owner` zur Klärung von Ziel, Scope, Nicht-Scope und Akzeptanzkriterien und einen vorhandenen technischen Plan an Architektur zur technischen Einordnung.
5. Die zugewiesene Umsetzungsrolle liest geltende Regeln und mit `code-reading` ausschließlich unmittelbar relevante Dateien und Referenzimplementierungen.
6. Wenn die Arbeitseinheit Designverantwortung enthält, delegiert der Koordinator an `designer`, um offenes Design zu explorieren und ein Handoff zu liefern. Ein belastbares vorhandenes Design-Handoff wird übernommen, ohne eine erneute Exploration zu erzwingen.
7. Der Koordinator delegiert die Konsistenzprüfung technischer Pläne, Design-Handoffs, Repository-Zustand und technischer Risiken an `softwareentwicklung_architektur`. Nur bei fehlender technischer Ausführbarkeit, wesentlichen offenen Architekturentscheidungen, neuem technischem Risiko oder echtem Planbruch wird mit `code-implementation-planning` gezielt nachgeplant.
8. Der Koordinator beauftragt Backend, Frontend oder bei ausdrücklich zugewiesenen Infrastruktur-Arbeitspaketen Infrastruktur mit dem nächsten geplanten Arbeitspaket; die Rolle setzt es mit `code-implementation` oder bei reinem Verhaltenserhalt und direkter Rollenfreigabe mit `code-refactoring` im definierten Scope um.
9. Der Implementierungsowner führt die für sein Arbeitspaket vorgesehene lokale Entwicklungsverifikation mit `code-testing` aus und berichtet die Belege.
10. Der Koordinator gibt konkrete lokale Implementierungsfehler gezielt an den zuständigen Implementierungsowner zurück; dieser korrigiert sie im unveränderten Scope und wiederholt nur die relevante Prüfung. Ein lokaler Fehler löst keine vollständige Neuplanung aus.
11. Der Koordinator beauftragt die Arbeitspakete in der geplanten Reihenfolge, bis der technische Plan abgearbeitet ist.
12. Bei einem visuellen oder interaktiven Ergebnis delegiert der Koordinator den Design-Review gegen Ziel, Handoff und Constraints an `designer`. Lokale Umsetzungsabweichungen gehen gezielt an den Frontend-Owner zurück; grundlegende Richtungsfragen an die Designrolle.
13. Wenn die Arbeitseinheit lokal funktional konvergiert ist, delegiert der Koordinator bei Backend- oder Frontend-Änderungssätzen die Minimierung mit `code-minimization` an den jeweiligen Implementierungsowner. Infrastruktur prüft eigene Änderungen mit `code-analysis` auf Scope und unbegründete Bestandteile, korrigiert sie bei Bedarf mit `code-implementation` und liefert lokale `code-testing`-Belege. Bei rotem oder diagnostisch instabilem Stand findet keine Minimierung statt; sie erzeugt keine neuen Features, Scope-Issues oder Refactorings.
14. Nach jeder akzeptierten Reduktion delegiert der Koordinator die betroffene fokussierte Verifikation an den Implementierungsowner. Eine fehlgeschlagene Reduktionshypothese wird zurückgenommen und als kein fachlicher Acceptance-GAP behandelt; echte Unklarheit über Acceptance, Invariante oder Architektur-Constraint geht an Product Owner oder Architektur.
15. Der Koordinator delegiert die unabhängige technische Task-Verifikation und Regression auf dem abschließend lokal geprüften Änderungssatz mit `code-testing` an `softwareentwicklung_qualitaetssicherung`. Fachliche Akzeptanzkriterien gehen zur Black-Box-Abnahme an `product_owner`; technische Akzeptanzkriterien an `softwareentwicklung_architektur`. Implementierer-Retests ersetzen unabhängige QA-Prüfungen nicht.
16. Der Koordinator delegiert den Review des finalen Änderungssatzes gegen Scope, Nicht-Scope, Akzeptanzkriterien, Seiteneffekte, Regressionen und fehlende Prüfungen mit `code-diff-review` an `softwareentwicklung_qualitaetssicherung`.
17. Der Koordinator delegiert kritische Funde im unveränderten Scope an den zuständigen Implementierungsowner und danach die zum Fund passende erneute Prüfung: technische Akzeptanz durch Architektur, unabhängige QA-Befunde durch QA oder fachliche Kriterien durch Product Owner.
18. `softwareentwicklung_infrastruktur` führt für die abgeschlossene Arbeitseinheit den Workflow `commit-push.md` aus.
19. Der Koordinator bittet Infrastruktur, zu bestätigen, dass der vollständige Änderungssatz dieser Arbeitseinheit committed und gepusht ist und keine zugehörigen fachlichen Änderungen uncommitted verbleiben.
20. Sobald die Arbeitseinheit vollständig umgesetzt, verifiziert, reviewed, committed und gepusht ist, delegiert der Koordinator an `softwareentwicklung_infrastruktur`, einen kurzen persistenten Abschlusskommentar im zugehörigen GitHub-Issue zu hinterlegen. Inhalt und Belege stammen aus den Rückgaben von Implementierungsowner und QA. Der Kommentar muss auf Deutsch den Umsetzungsstatus, den relevanten Commit-Kontext, den Verifikationsstatus und – solange der finale Pull Request oder Merge noch aussteht – diesen offenen Abschluss enthalten. Das Issue nicht über diesen Kommentar schließen.
21. `softwareentwicklung_infrastruktur` verwendet für den beauftragten Kommentar `gh issue comment <issue-number> --body "..."`. Der Inhalt muss mindestens diesem Muster folgen:

    ```text
    Umsetzung abgeschlossen.
    Commit: <commit-sha>
    Verifikation: erfolgreich|mit Hinweisen|fehlgeschlagen.
    Issue bleibt bis zum finalen PR/Merge geöffnet.
    ```

22. Bei Ausführung innerhalb eines Issue-Graphen bittet der Koordinator Infrastruktur, erst nach erfolgreichem Kommentar den Fortschrittsanker zu aktualisieren und die Rückgabe an den aufrufenden Workflow zu liefern.
23. Ein Issue darf nur geschlossen werden, wenn der übergeordnete Kontext dies ausdrücklich erlaubt; zuständige GitHub-Lifecycle-Mutationen delegiert der Koordinator an Infrastruktur. Die bestehende Schließlogik über den finalen Pull Request bleibt ansonsten maßgeblich.

## Planbruch

In Analyse oder Planung zurückspringen, wenn:

- wesentliche Produkt-, Architektur-, Scope- oder Vorgehensentscheidungen fehlen,
- erwartete Dateien, APIs oder Referenzimplementierungen fehlen oder wesentlich abweichen,
- der Plan geltenden Regeln widerspricht oder die Akzeptanzkriterien nicht erreichen kann,
- die erforderliche Änderung den definierten Scope wesentlich überschreitet,
- eine Prüfung einen grundlegenden fachlichen oder architektonischen Widerspruch statt eines lokalen Implementierungsfehlers zeigt.

## Commit-Grenze

- Eine abgeschlossene Arbeitseinheit endet zwingend mit Commit und Push.
- Wenn die Arbeitseinheit einem Issue entspricht, muss ihr Änderungssatz mindestens einem eindeutig diesem Issue zuordenbaren Commit entsprechen.
- Mehrere logisch getrennte Commits für dasselbe Issue sind zulässig.
- Änderungen verschiedener Issues dürfen nicht absichtlich in demselben Commit vermischt werden, wenn dieser Workflow als Teil von `issue-graph-implementation.md` läuft.
- Der aufrufende Workflow darf erst zur nächsten Arbeitseinheit wechseln, wenn Commit und Push dieser Arbeitseinheit erfolgreich abgeschlossen wurden.
- Fehlgeschlagener Commit oder Push bedeutet, dass die Arbeitseinheit nicht abgeschlossen ist.

## Rücksprungregeln

- Bei unklarem Issue-Kontext wird fachlicher Bedarf an Product Owner und technischer Bedarf einschließlich Technical Tasks an Architektur zurückgegeben.
- Bei unklarem Code- oder Schnittstellenkontext wird technische Analyse an Architektur delegiert.
- Bei fachlichen Scope-Erweiterungen ist eine Product-Owner-/Human-Klärung erforderlich.
- Lokale Implementierungsfehler gehen an den Implementierungs-Owner zurück; QA prüft die Korrektur erneut.
- Bei fehlender Verifikation wird kein Abschluss gemeldet.

## Rollenübergaben

- Fachlicher Issue-Scope, User Stories/User Epics und fachliche Akzeptanzkriterien: `product_owner`.
- Technische Issues, technischer Plan und technische Akzeptanzkriterien: `softwareentwicklung_architektur`.
- Gestaltung, falls beauftragt: `designer`.
- Code-Lesen, Analyse und Implementierung: Backend, Frontend oder Infrastruktur gemäß Scope.
- Unabhängige technische Task-Verifikation und Regression: `softwareentwicklung_qualitaetssicherung`.
- Commit und Push: `softwareentwicklung_infrastruktur`.
- Planbruch wird an Product Owner (fachlich) oder Architektur (technisch) delegiert; lokale Implementierungs- oder Testfehler gehen gezielt an den Implementierer.

## Endergebnis

- umgesetzte und verifizierte Arbeitseinheit
- erfüllte Akzeptanzkriterien
- bei relevanter Designverantwortung visuell reviewte Produktivimplementierung
- dokumentierter Teststatus
- eindeutig zuordenbarer Commit-Kontext
- erfolgreicher Push
- keine zur Arbeitseinheit gehörenden uncommitted fachlichen Änderungen
- persistenter deutscher Abschlusskommentar mit Status-, Commit- und Verifikationskontext

## Grenzen

- Keinen Pull Request erstellen.
- Keinen Issue-Graph koordinieren.
- Keine Gesamt-Reihenfolge über mehrere Issues bestimmen.
- Keine Branch-Erstellung ausführen, wenn dieser Workflow als Teilworkflow aus `issue-graph-implementation.md`, `bugfix.md`, `refactoring-secure.md` oder einem anderen vorgelagerten Workflow mit bereits vorbereitetem Arbeitsbranch läuft.
- Wenn dieser Workflow direkt gestartet wird, muss vor der Implementierung ein passender Arbeitsbranch aktiv sein; andernfalls `github-branch-checkout-from-default` verwenden.
- Keine Nebenfunde umsetzen, außer sie blockieren die Arbeitseinheit.
- Issue nicht schließen, wenn der Abschluss über einen späteren PR-Merge erfolgen soll.
- Nach erfolgreichem Commit und Push keinen nächsten Graph-Knoten beginnen und keinen Fortschrittsanker als abgeschlossen markieren, bevor der persistente Issue-Kommentar erfolgreich erstellt wurde.
- Wenn dieser Workflow aus `issue-graph-implementation.md` aufgerufen wird, Scope-Issues standardmäßig nicht manuell schließen; der Graph-Workflow entscheidet die abschließende PR-Verlinkung und Schließsemantik.
- Eine abgeschlossene Arbeitseinheit darf nicht als Abschluss eines noch offenen Issue-Graphen kommuniziert werden.

