# Workflow: Feature Finish

## Owner und Modus

`koordinator` liest diesen Ablauf ausschließlich als Delegationsplan. Unabhängige Verifikation delegiert er an `softwareentwicklung_qualitaetssicherung`; Branchabschluss, Commit, Push, Check-Beobachtung und Merge an `softwareentwicklung_infrastruktur`. Jede Phase wartet auf die belegte Rückgabe der vorherigen.

## Ziel

Einen bereits umgesetzten und vom User freigegebenen Arbeitsbranch mit `/finish` sicher committen, veröffentlichen, prüfen und nach `develop` mergen.

## Verwenden

- Wenn der User `/finish` oder gleichbedeutend den vollständigen Branch-Abschluss beauftragt.
- Für den Abschluss eines Feature- oder Task-Branches nach `develop`.
- Nicht für die Freigabe von `develop` nach `main`; dafür `/release` beziehungsweise den Workflow `release` verwenden.
- Wenn Implementierung und taskbezogene lokale Verifikation bereits abgeschlossen sind oder im Workflow abgeschlossen werden können.
- Nicht verwenden, um Implementierung, Fehlerbehebung oder fachliche Freigabe zu ersetzen.

## Reifekriterien

- Ein aufgabenbezogener Arbeitsbranch ist aktiv und ist weder `develop` noch `main`.
- Der Remote-Branch `develop` ist als Zielbranch vorhanden und auflösbar.
- Task-Scope und taskbezogene Änderungen sind eindeutig.
- Task-Akzeptanzkriterien und vorgesehene Verifikation sind gegen den realen Stand prüfbar.
- Der User hat den vollständigen Abschluss einschließlich Commit, Push, Pull Request, Check-Beobachtung und Merge ausdrücklich beauftragt.
- Repository, Remote und Branch-Zustände sind auflösbar.

## Verwendete Skills

- `code-testing`
- `code-diff-review`
- `pr-creation`
- `pr-checks-observation`
- `github-pr-merge`
- `integration-branch-update`

## Verwendete Workflows

- `commit-push.md`

## Ablauf

1. `PROJECT.md`, Repository-Kontext, aktuellen Branch, Working Tree, Remote, den Zielbranch `develop` und taskbezogenen Scope bestimmen.
2. Stoppen, wenn `develop` oder `main` aktiv ist, `develop` remote nicht existiert, der Task-Scope unklar ist oder fremde Änderungen nicht sicher vom Task getrennt werden können.
3. Mit `code-testing` die im Task vorgesehene Verifikation und relevante lokale Ergänzungsprüfungen ausführen oder einen bereits belastbaren Teststatus bestätigen.
4. Mit `code-diff-review` den gesamten Änderungssatz gegen Scope, Nicht-Scope und Akzeptanzkriterien prüfen und nur bei `versandbereit` oder `versandbereit mit Hinweisen` fortfahren.
5. `softwareentwicklung_infrastruktur` den Workflow `commit-push.md` für ausschließlich taskbezogene Änderungen ausführen lassen.
6. Mit `pr-creation` einen vorhandenen Pull Request für den Branch gegen `develop` wiederverwenden oder mit `develop` als expliziter Basis erstellen. `/finish` gilt für diesen Workflow als ausdrückliche Anweisung, den Pull Request als Ready for Review bereitzustellen.
7. Infrastruktur mit `pr-checks-observation` die erforderlichen Checks für den unveränderten Pull-Request-Head bis zu einem terminalen Zustand beobachten.
8. Bei vollständig erfolgreichen erforderlichen Checks oder dem zulässigen Status `no-checks-required` und erfüllten übrigen Repository-Regeln mit `github-pr-merge` und der aufgelösten Merge-Methode mergen. Bei `spending-limit-blocked` nur nach der dort vorgeschriebenen zusätzlichen Bestätigung fortfahren; eine erforderliche Merge Queue bis zum terminalen Ergebnis beobachten.
9. Nach verifiziertem Merge mit `integration-branch-update` auf `develop` wechseln und ihn per Fast-Forward aktualisieren.
10. Commit, Pull Request, Check-Ergebnis, Merge und lokalen Abschlusszustand zusammenfassen.

## Rücksprungregeln

Ein Pull Request darf bei `no-checks-required` fortgesetzt werden, wenn keine erforderlichen Checks konfiguriert sind und keine Checks für den unveränderten Head berichtet werden. Das Fehlen eines tatsächlich konfigurierten erforderlichen Checks bleibt ein Blocker.

`/finish` bleibt der technische Branch-/PR-/Merge-Abschluss. Die fachliche graphweite Acceptance-Prüfung erfolgt davor über `issue-acceptance-convergence` und wird hier nicht dupliziert.

`/finish` führt keine nachträgliche fachliche Minimierung durch. Fehlt bei Backend-/Frontend-Änderungen die vorgelagerte Minimierungs- und Retest-Evidenz oder bei Infrastrukturänderungen die rollenbezogene Scope-Prüfung und lokale Verifikation, ist der technische Abschluss nicht reif und muss an den zuständigen Implementierungs-/Bugfix-Workflow zurückgegeben werden.

- Bei fehlgeschlagenen lokalen Prüfungen zur passenden Implementierung oder Fehlerbehebung zurückkehren; keine beliebigen Fehler außerhalb des Task-Scopes beheben.
- Bei `code-diff-review` mit Bewertung `nicht versandbereit` zur passenden Umsetzung zurückkehren.
- Bei `spending-limit-blocked` zur ausdrücklichen Rückfrage in `github-pr-merge` wechseln.
- Bei anderen fehlgeschlagenen oder abgebrochenen Checks, Konflikten, fehlenden Reviews, unklarer Merge-Methode oder fehlenden Rechten stoppen und den Arbeitsbranch aktiv lassen.
- Wenn der Merge nicht verifiziert werden kann, nicht auf `develop` wechseln.

## Rollenübergaben

- Reifekriterien und offene fachliche Scope-Entscheidungen: `product_owner`.
- Unabhängige Verifikation und Check-Bewertung: `softwareentwicklung_qualitaetssicherung`.
- Commit, Push, PR, Check-Beobachtung, Merge und lokaler Branchabschluss: `softwareentwicklung_infrastruktur`.
- Der Koordinator delegiert Phasen einzeln und wartet auf belegte Rückgaben, bevor die nächste Mutation beauftragt wird.

## Endergebnis

- taskbezogene Änderungen sind bewusst committed und gepusht
- ein vorhandener Pull Request wurde wiederverwendet oder ein passender Pull Request erstellt
- erforderliche Checks sind für den gemergten Head-Commit erfolgreich, oder für diesen Head-Commit ist `no-checks-required` verifiziert, oder der nachgewiesene Spending-Limit-Fall wurde ausdrücklich bestätigt
- der Pull Request ist regelkonform gemergt
- der lokale Checkout steht auf dem per Fast-Forward aktualisierten Branch `develop`
