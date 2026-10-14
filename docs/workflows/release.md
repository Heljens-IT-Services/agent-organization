# Workflow: Release

## Owner und Modus

`koordinator` liest diesen Ablauf ausschließlich als Delegationsplan. Scope- und Reifefragen delegiert er an `product_owner`, unabhängige Check-Bewertung und Veröffentlichungsverifikation an `softwareentwicklung_qualitaetssicherung`, Branchwechsel, PR, Check-Beobachtung, Merge, Push und Veröffentlichung an `softwareentwicklung_infrastruktur`. Externe Mutationen erfolgen nur durch Infrastruktur im ausdrücklich beauftragten Umfang.

## Ziel

Den freigegebenen Stand von `develop` mit `/release` kontrolliert über einen Pull Request nach `main` veröffentlichen und den lokalen Default-Branch aktualisieren.

## Verwenden

- Wenn der User `/release` oder kanonisch `/workflows run release` beauftragt.
- Ausschließlich für die Freigabe von `develop` nach `main`.
- Nicht für den Abschluss eines Feature- oder Task-Branches; dafür `/finish` beziehungsweise den Workflow `feature-finish` verwenden.

## Reifekriterien

- Der Branch `develop` ist aktiv, der Arbeitsbaum ist sauber und der lokale Branch ist mit dem Remote synchronisiert.
- Die Remote-Branches `develop` und `main` sind vorhanden und `main` ist der aufgelöste Default-Branch.
- `develop` enthält gegenüber `main` zu veröffentlichende Änderungen.
- Der User hat mit `/release` Pull Request, Check-Beobachtung und Merge von `develop` nach `main` ausdrücklich beauftragt.

## Verwendete Skills

- `code-diff-review`
- `pr-creation`
- `pr-checks-observation`
- `github-pr-merge`
- `default-branch-update`

## Ablauf

1. `PROJECT.md`, Repository-Kontext, Working Tree, Remote, Default-Branch sowie die Branch-Zustände von `develop` und `main` bestimmen.
2. Stoppen, wenn nicht `develop` aktiv ist, der Arbeitsbaum Änderungen enthält, `develop` nicht mit dem Remote synchronisiert ist, einer der beiden Remote-Branches fehlt oder `main` nicht der Default-Branch ist.
3. Commits und Gesamtdiff von `<remote>/main` bis `<remote>/develop` bestimmen. Wenn kein Unterschied besteht, ohne Mutation mit dem Hinweis beenden, dass nichts zu veröffentlichen ist.
4. Mit `code-diff-review` den vollständigen Release-Diff prüfen und nur bei `versandbereit` oder `versandbereit mit Hinweisen` fortfahren.
5. Die seit `main` in `develop` enthaltenen Pull Requests und deren noch offene, durch den Release tatsächlich erledigte Issues bestimmen. Diese Issues im Release-PR mit `Closes #<nummer>` verknüpfen, damit sie erst durch die Veröffentlichung nach `main` geschlossen werden.
6. Mit `pr-creation` einen vorhandenen Pull Request von `develop` nach `main` wiederverwenden oder mit `main` als expliziter Basis und `develop` als explizitem Head erstellen. `/release` gilt als ausdrückliche Anweisung, den Pull Request als Ready for Review bereitzustellen.
7. Infrastruktur mit `pr-checks-observation` die erforderlichen Checks für den unveränderten Pull-Request-Head bis zu einem terminalen Zustand beobachten.
8. Bei vollständig erfolgreichen erforderlichen Checks oder dem zulässigen Status `no-checks-required` und erfüllten übrigen Repository-Regeln mit `github-pr-merge` und der aufgelösten Merge-Methode mergen. Bei `spending-limit-blocked` nur nach der dort vorgeschriebenen zusätzlichen Bestätigung fortfahren; eine erforderliche Merge Queue bis zum terminalen Ergebnis beobachten.
9. Nach verifiziertem Merge mit `default-branch-update` auf `main` wechseln und ihn per Fast-Forward aktualisieren.
10. Pull Request, enthaltene Issues, Check-Ergebnis, Merge und lokalen Abschlusszustand zusammenfassen.

## Rücksprungregeln

Ein Pull Request darf bei `no-checks-required` fortgesetzt werden, wenn der Status nach [PR Checks Beobachten](https://heljens-it-services.github.io/agent-organization/skills/github_pr-checks-observation.md) für den unveränderten Head belegt ist. Bei ausdrücklich nachgewiesener Tarifgrenze gilt dessen Ersatzpfad mit verfügbaren Quellen, lokalen Pflichtprüfungen, unabhängiger Verifikation und offengelegter Sichtbarkeitsgrenze. Bekannte fehlende Pflichtchecks, unklare API-/Berechtigungsfehler und GitHubs serverseitige Merge-Ablehnung bleiben Blocker.

## Rollenübergaben

- Release-Scope und fachliche Reifekriterien: `product_owner`, wenn Klärung erforderlich ist.
- Unabhängiger Diff-Review, Check-Bewertung und Live-/Pages-Verifikation: `softwareentwicklung_qualitaetssicherung`.
- Branchwechsel, PR, Check-Beobachtung, Merge, Push und Veröffentlichung: `softwareentwicklung_infrastruktur`.
- Bei fehlenden Rechten, Checks, Reviews oder unklarer Merge-Methode liefert Infrastruktur einen Blocker zurück; Koordinator delegiert keine Umgehung.

## Endergebnis

- ein vorhandener Release-Pull-Request wurde wiederverwendet oder mit Base `main` und Head `develop` erstellt
- enthaltene offene Issues sind im Release-Pull-Request korrekt verknüpft
- erforderliche Checks sind für den gemergten Head-Commit erfolgreich, oder für diesen Head-Commit ist `no-checks-required` verifiziert, oder der nachgewiesene Spending-Limit-Fall wurde ausdrücklich bestätigt
- der Release-Pull-Request ist regelkonform gemergt
- der lokale Checkout steht auf dem per Fast-Forward aktualisierten Branch `main`

## Grenzen

- Auf `develop` oder `main` keine Release-Änderungen committen.
