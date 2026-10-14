# Workflow: Design Exploration

## Owner

`designer` führt diesen Workflow ganzheitlich für Nutzungsziele, Nutzerabläufe, Informationsstruktur, Interaktionen, visuelle Sprache, Komponenten und Darstellung operativ aus. Die Rolle delegiert nicht selbst. Fremdscope und widersprüchliche Produktanforderungen gehen an den Koordinator zur Klärung und weiteren Beauftragung.

## Ziel

Eine offene oder visuell relevante Designaufgabe explorativ verstehen, mehrere belastbare Richtungen entwickeln, mit leichten Prototypen tatsächlich visualisieren, reviewen und iterativ zu einer begründeten Designrichtung führen.

## Verwenden

- Wenn eine neue Oberfläche, ein Layout, ein visueller Produktbereich, ein Informationsdesign oder eine interaktive Darstellung konzipiert werden soll.
- Wenn eine Designfrage mehrere plausible Lösungsrichtungen besitzt und nicht die erste Idee unmittelbar in Produktionscode überführt werden soll.
- Wenn ein bestehendes Design substanziell neu gedacht und vor der Implementierung exploriert werden soll.
- Bei kleinen, bereits stark vorgegebenen visuellen Änderungen darf stattdessen direkt ein passender Design-Skill verwendet werden.

## Verwendete Skills

- `requirements-clarification` bei unklaren Zielen oder Constraints
- `research` bei erforderlichem externen, Repository- oder Produktkontext
- `brainstorming`
- `design-prototyping`
- `design-review`

## Ablauf

1. Ziel, Zielgruppe, Nutzungskontext, Nicht-Ziele und relevante Constraints aus dem vorhandenen Kontext erfassen. Nur bei echten Lücken `requirements-clarification` verwenden.
2. Bestehenden Produkt-, Design-, Wettbewerbs- oder Referenzkontext nur dann mit `research` ergänzen, wenn er für die Designentscheidung tatsächlich benötigt wird.
3. Mit `brainstorming` bei offenem Lösungsraum mehrere substanziell unterschiedliche Designrichtungen entwickeln. Kleine, stark eingeschränkte Aufgaben dürfen mit einer Richtung starten.
4. Die Richtungen so beschreiben, dass ihre Unterschiede in Struktur, Schwerpunkt, Interaktion oder visueller Sprache erkennbar sind; reine Farb- oder Detailvarianten reichen nicht aus.
5. Mit `design-prototyping` die relevanten Richtungen als leichte, renderbare Artefakte visualisieren. Für browserdarstellbare frühe Entwürfe eigenständige Single-File-HTML-Prototypen mit Inline-CSS und Inline-JavaScript bevorzugen, wenn sie die Designfrage ausreichend abbilden.
6. Alle für die Auswahl relevanten Varianten tatsächlich rendern und mit `design-review` beurteilen.
7. Die Richtungen anhand von Nutzerziel, Verständlichkeit, Wirkung, Constraints und Review-Funden vergleichen und eine stärkste Richtung auswählen oder eine erforderliche subjektive Nutzerentscheidung sichtbar machen.
8. Wenn die erste Review relevante Verbesserungsmöglichkeiten zeigt, die gewählte Richtung mit `design-prototyping` gezielt weiterentwickeln und eine neue Iteration erzeugen.
9. Wenn eine neue Iteration erzeugt wurde, die geänderte Fassung erneut rendern und mit `design-review` gegen die priorisierten Funde prüfen.
10. Weitere `design-prototyping`-/`design-review`-Iterationen nur fortsetzen, solange wesentliche Designprobleme bestehen oder eine zusätzliche Iteration einen klaren entscheidungsrelevanten Erkenntnisgewinn erwarten lässt.
11. Die finale Designrichtung mit Begründung, wesentlichen Entscheidungen, bekannten Trade-offs und umsetzungsrelevanten Constraints festhalten.
12. Nicht mehr benötigte explorative Varianten entfernen, sofern sie nicht ausdrücklich als Ergebnis, Vergleichsartefakt oder Handoff erhalten bleiben sollen.
13. Wenn eine produktive Umsetzung beauftragt ist, die gewählte Designrichtung an Backend- oder Frontend-Verantwortung übergeben. Die Produktionsimplementierung ist nicht Bestandteil dieses Workflows.

## Rücksprungregeln

- Wenn Ziel oder Constraints widersprüchlich werden, zurück zu `requirements-clarification`.
- Wenn eine Designrichtung auf fehlendem oder fragwürdigem Kontext beruht, gezielt `research` nachladen und die betroffene Entscheidung erneut prüfen.
- Wenn Varianten nur oberflächlich voneinander abweichen, zurück zu `brainstorming` und strukturell unterschiedliche Richtungen bilden.
- Wenn ein Prototyp die relevante Designfrage nicht sichtbar macht, zurück zu `design-prototyping`.
- Wenn `design-review` wesentliche Probleme findet, mit `design-prototyping` die gewählte Richtung iterieren und anschließend erneut mit `design-review` prüfen.
- Wenn ein Review wegen fehlender Visualisierung nur aus Quelltext möglich wäre, Workflow blockieren oder ein alternatives renderbares Artefakt erzeugen, sofern technisch möglich.

## Rollengrenzen

- `designer` verantwortet Nutzungsszenarien, Nutzerziele, Informationsstruktur, Interaktionen, visuelle Sprache, Komponenten und Darstellung im ausdrücklich zugewiesenen Scope.
- `designer` liest nur den eigenen Rollenindex und führt diesen Workflow ohne Subdelegation aus.
- Widersprüchlicher Produktumfang oder fremde operative Zuständigkeit geht an den Koordinator zur Klärung und weiteren Beauftragung.
- Produktivimplementierung geht nach dem Design-Handoff an Backend oder Frontend. Unabhängige formale Verifikation übernimmt QA.

## Endergebnis

- tatsächlich visualisierte und reviewte Designrichtung
- bei offenem Lösungsraum nachvollziehbar explorierte Alternativen
- mindestens eine Review-Schleife für technisch visualisierbare Designarbeit
- bei relevanten Review-Funden mindestens eine visualisierte und erneut reviewte Iteration
- finaler Prototyp oder klar dokumentierte Designentscheidung
- wesentliche Designbegründungen und Trade-offs
- klarer Handoff für eine optionale Produktionsimplementierung

## Grenzen

- Die erste renderbare Lösung ist nicht automatisch das Endergebnis.
- Keine Scheinexploration durch bloße Farb- oder Detailvarianten.
- Keine unnötige Produktionsarchitektur oder neue Abhängigkeit für frühe Prototypen.
- Keine produktive Implementierung innerhalb dieses Workflows.
- Keine formale Testverifikation durch den Design-Review ersetzen.
- Explorative Artefakte dürfen bewusst wegwerfbar sein und müssen nicht Produktionsstandards erfüllen.

