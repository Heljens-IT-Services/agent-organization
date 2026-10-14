# Workflow: Bugfix From Default

## Owner und Modus

`koordinator` liest und führt diesen Ablauf ausschließlich als Delegationsplan. Branch, Commit, Push und PR delegiert er an `softwareentwicklung_infrastruktur`; technische Ursachen/Planbrüche an `softwareentwicklung_architektur`; Umsetzung an Backend, Frontend oder Infrastruktur im eigenen Änderungsscope; unabhängige Prüfung an `softwareentwicklung_qualitaetssicherung`. Jede Phase wird als Auftrag an den Owner übergeben.

## Ziel

Einen Fehler zielgerichtet analysieren, beheben und absichern und dafür bewusst einen neuen Arbeitsbranch von der Standardbasis bis zu einem Pull Request organisieren.

Dieser Workflow erhält den bisherigen vollständigen Bugfix-Ablauf inklusive Branch-Erstellung und Pull-Request-Erstellung. Für einen Bugfix auf dem bereits aktiven Branch ist stattdessen `bugfix.md` beziehungsweise `/bugfix` zu verwenden.

## Verwenden

- Wenn ein konkretes Fehlverhalten behoben werden soll und ausdrücklich ein eigener Bugfix-Branch von der Standardbasis gewünscht ist.
- Wenn Ursache, Fix, Verifikation, Commit/Push und Pull Request zusammenhängend bearbeitet werden sollen.
- Wenn der Bugfix nicht auf dem aktuell aktiven Arbeitsbranch verbleiben soll.
- Nicht verwenden, wenn der aktuelle Branch bewusst weiterverwendet werden soll. Dann `bugfix.md` beziehungsweise `/bugfix` nutzen.
- Nicht verwenden, wenn nur eine Ursache analysiert werden soll. Dann `code-analysis` nutzen.

## Direkter Alias

- `/bugfix from-default`

Der kanonische Aufruf lautet `/workflows run bugfix-from-default`.

## Verwendete Skills

- `github-branch-checkout-from-default`
- `issue-reading`
- `code-analysis`
- `code-implementation-planning`
- `code-implementation`
- `code-minimization` nur für Backend-/Frontend-Änderungssätze
- `code-testing`
- `code-diff-review`
- `pr-creation`

## Verwendete Workflows

- `commit-push.md`

## Ablauf

1. Bug-Input aufnehmen: vorhandenen Kontext verwenden oder mit `issue-reading` das Issue lesen.
2. Mit `github-branch-checkout-from-default` einen geeigneten Arbeitsbranch von der Standardbasis erstellen.
3. Einen vorhandenen terminalen Issue- oder Task-Plan gegen Repository-Zustand und geltende Regeln prüfen. Nur bei ungeklärter Ursache oder Planbruch mit `code-analysis` Ursache, Scope und Risiken klären.
4. Mit `code-testing` den Bug reproduzieren.
5. Den vorhandenen Issue- oder Task-Plan übernehmen. Nur ohne vollständigen Plan oder bei Planbruch mit `code-implementation-planning` gezielt planen.
6. Mit `code-implementation` den Bugfix umsetzen.
7. Mit `code-testing` prüfen, dass die ursprüngliche Reproduktion nicht mehr fehlschlägt und relevante Regressionen abgedeckt sind.
8. Erst nach erfolgreicher Reproduktion und lokaler Stabilisierung Backend-/Frontend-Änderungssätze durch ihren Implementierungsowner mit `code-minimization` prüfen und minimieren. Infrastruktur prüft eigene Änderungen mit `code-analysis` auf Scope und unbegründete Bestandteile, korrigiert sie bei Bedarf mit `code-implementation` und liefert lokale `code-testing`-Belege; fremde Skills werden nicht benötigt.
9. Nach jeder akzeptierten Reduktion die ursprüngliche Reproduktion und die durch die Reduktion betroffene Regression fokussiert erneut grün prüfen. Eine fehlgeschlagene Reduktion zurücknehmen; echte Unklarheit über Invariante oder Constraint als Planbruch routen.
10. Mit `code-testing` die unabhängige Verifikation des abschließend lokal geprüften Bugfixes ausführen; lokale Implementierer-Retests ersetzen diese nicht.
11. Mit `code-diff-review` Nebeneffekte und Scope-Ausweitung kontrollieren.
12. `softwareentwicklung_infrastruktur` den Commit-Push-Auftrag im beauftragten Task-Scope ausführen lassen.
13. Mit `pr-creation` den Pull Request mit Ursache, Fix und Absicherung zur Standardbasis erstellen.

## Rücksprungregeln

- Bei unklarer Ursache, Scope oder Reproduktion delegiert der Koordinator Analyse an Architektur.
- Bei nicht reproduzierbarem Verhalten werden Repro-Bedingungen, Ursache und Scope geklärt, bevor Umsetzung beginnt.
- Bei einem Planbruch geht fachlicher Scope an Product Owner, technischer Strukturbedarf an Architektur.
- Bei lokalen Implementierungsfehlern wird gezielt an den zuständigen Implementierungs-Owner zurückgegeben.
- Nach jeder Korrektur delegiert der Koordinator die betroffene Verifikation erneut an QA.

## Rollenübergaben

- Branch, Commit, Push und PR-Mutationen: `softwareentwicklung_infrastruktur`.
- Fehlerreproduktion und unabhängige Verifikation: `softwareentwicklung_qualitaetssicherung`.
- Technische Ursache und Strukturplan: `softwareentwicklung_architektur`.
- Umsetzung: Backend, Frontend oder Infrastruktur im eigenen Änderungsscope entsprechend dem Scope.
- Fachlicher Planbruch: `product_owner`; lokaler Implementierungsfehler als gezielter Rückauftrag an den zuständigen Implementierer.

## Endergebnis

- behobener Fehler
- nachvollziehbarer Bugfix-Kontext
- nachvollziehbarer Test- und Review-Kontext
- eigener Bugfix-Arbeitsbranch von der Standardbasis
- Commit und Push
- erstellter Pull Request zur Standardbasis

## Grenzen

- Dieser Workflow darf nur bei ausdrücklich gewünschter Branch-/PR-Orchestrierung verwendet werden.
- Bugfix-Planung und Implementierung dürfen erst beginnen, wenn der Bug reproduziert wurde.
- Nach der Implementierung muss die ursprüngliche Reproduktion erfolgreich sein.
- Relevante Regressionen müssen geprüft werden.
