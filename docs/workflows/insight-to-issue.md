# Workflow: Insight To Issue

## Owner und Modus

`koordinator` liest diesen Ablauf als Delegationsplan. Erkenntnisreife, Issue-Inhalt, Type und Relationships delegiert er bei User-Issues an `product_owner` und bei technischen Issues einschließlich Technical Tasks an `softwareentwicklung_architektur`; nötige fachliche Untersuchung an die zuständige operative Rolle. Der Koordinator führt keine Recherche oder Issue-Mutation selbst aus.

## Ziel

Aus einer vorhandenen Erkenntnis ein strukturiertes GitHub-Issue erstellen.

## Verwenden

- Wenn eine Erkenntnis aus Brainstorming, Analyse, Research, Anforderungsklärung, User-Beobachtung oder Nutzungskontext issue-reif gemacht und als GitHub-Issue erfasst werden soll.
- Nicht verwenden, wenn die Erkenntnis eine Verbesserung an Agent Instructions, Skills oder Workflows betrifft. Dann `instruction-improvement-issue.md` nutzen.
- Nicht verwenden, wenn nur eine Issue-Grundlage ohne Erstellung gewünscht ist, außer der User verlangt das explizit.

## Verwendete Skills

- `brainstorming`
- `research`
- `requirements-clarification`
- `code-analysis`
- `issue-creation`
- `type-setting`
- `relationship-setting`

## Ablauf

1. Ursprung und Art der Erkenntnis bestimmen: Brainstorming, Analyse, Research, Anforderung, User-Beobachtung oder Nutzungskontext.
2. Prüfen, ob die Erkenntnis anhand der passenden Reifekriterien issue-reif ist.
3. GitHub-Issue-Type als Empfehlung aus dem Kontext ableiten, wenn die Reifekriterien klar auf `Task`, `Story`, `Spike` oder `Epic` zeigen.
4. Ziel-Repository bestimmen.
5. Falls Kontext fehlt, den passenden vorgelagerten Skill nutzen: `requirements-clarification`, `brainstorming`, `research` oder `code-analysis`.
6. Mit `issue-creation` daraus ein GitHub-Issue erstellen.
7. Mit `type-setting` den finalen nativen GitHub-Issue-Type setzen.
8. Mit `relationship-setting` native Relationships setzen, wenn sie aus dem Kontext hervorgehen.

## Reifekriterien

Gemeinsame Mindestkriterien:

- Thema
- Relevanz
- Zielzustand
- Scope und Nicht-Ziele
- passender GitHub-Issue-Type: `Task`, `Story`, `Spike` oder `Epic`

User- oder Product-Issue:

- betroffene Nutzerrolle
- Problem oder Bedürfnis
- Akzeptanz- oder Erfolgskriterien

Technical Issue:

- betroffener technischer Bereich
- beobachtetes Problem oder gewünschte technische Änderung
- technische Randbedingungen oder Risiken
- Verifikationsidee

Spike:

- Fragestellung
- Erkenntnisziel
- Untersuchungsgrenze
- erwartetes Ergebnis, z. B. Entscheidung, Empfehlung, Prototyp oder Dokumentation
- Timebox oder Abbruchkriterium, falls relevant

Epic:

- übergeordnetes Ziel
- grober Scope
- erwartete Teilbereiche oder Child-Issues
- Nicht-Ziele
- Nutzen oder strategische Begründung

## Rücksprungregeln

- Bei unklarem Ziel zurück zu `requirements-clarification`.
- Bei offenen Lösungsrichtungen zurück zu `brainstorming`.
- Bei fehlenden externen Fakten zurück zu `research`.
- Bei fehlender technischer Bewertung zurück zu `code-analysis`.
- Wenn die passenden Reifekriterien nicht erfüllt sind, zurück zu `requirements-clarification`.
- Bei unklarem GitHub-Issue-Type nicht raten, sondern zurück zu `requirements-clarification`.
- Bei unklarer Relationship-Richtung nicht raten, sondern zurück zu `requirements-clarification`.
- Wenn die Erkenntnis Agent Instructions, Skills oder Workflows betrifft, zu `instruction-improvement-issue.md` wechseln; dort ist das Ziel-Repository festgelegt.

## Endergebnis

- erstelltes GitHub-Issue
- Issue-Link
- klarer Scope
- nachvollziehbarer fachlicher und technischer Kontext

## Grenzen

- Kein Issue erstellen, wenn die passenden Reifekriterien nicht erfüllt sind.
- Ziel-Repository nicht still wechseln; Default ist das fachlich relevante Ziel-Repository, außer der User gibt ein anderes Repository vor.
- Keine Erkenntnisse zu Agent Instructions, Skills oder Workflows in diesem Workflow erfassen; dafür `instruction-improvement-issue.md` verwenden.
