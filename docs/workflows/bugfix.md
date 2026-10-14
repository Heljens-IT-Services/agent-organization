# Workflow: Bugfix

## Owner und Modus

`koordinator` liest und führt diesen Ablauf ausschließlich als Delegationsplan. Der Koordinator delegiert Ursachen- und Strukturfragen an `softwareentwicklung_architektur`, Implementierung an `softwareentwicklung_backend`, `softwareentwicklung_frontend` oder bei Infrastrukturänderungen `softwareentwicklung_infrastruktur`, unabhängige Prüfung an `softwareentwicklung_qualitaetssicherung` sowie Commit/Push an `softwareentwicklung_infrastruktur`. Jede operative Handlung ist ein Spezialistenauftrag mit Scope und Rückgabevertrag.

## Ziel

Einen Fehler zielgerichtet auf dem aktuell ausgecheckten Branch analysieren, beheben und absichern, ohne den umgebenden Branch- oder Pull-Request-Lifecycle eigenständig zu verändern.

Für einen bewusst isolierten Bugfix mit neuem Branch von der Standardbasis und anschließendem Pull Request ist `bugfix-from-default.md` beziehungsweise `/bugfix from-default` zu verwenden.

## Verwenden

- Wenn ein konkretes Fehlverhalten auf dem aktuell ausgecheckten Arbeitsbranch behoben werden soll.
- Wenn Ursache, Fix, Verifikation und Commit/Push zusammenhängend bearbeitet werden sollen.
- Wenn der Bugfix Bestandteil eines bereits laufenden Feature-, Agent- oder Remediation-Branches ist.
- Nicht verwenden, wenn ausdrücklich ein neuer Bugfix-Branch von der Standardbasis mit anschließendem Pull Request gewünscht ist. Dann `bugfix-from-default.md` beziehungsweise `/bugfix from-default` nutzen.
- Nicht verwenden, wenn nur eine Ursache analysiert werden soll. Dann `code-analysis` nutzen.

## Direkter Alias

- `/bugfix`

Der kanonische Aufruf lautet `/workflows run bugfix`.

## Verwendete Skills

- `issue-reading`
- `code-analysis`
- `code-implementation-planning`
- `code-implementation`
- `code-minimization` nur für Backend-/Frontend-Änderungssätze
- `code-testing`
- `code-diff-review`

## Verwendete Workflows

- `commit-push.md`

## Ablauf

1. Bug-Input aufnehmen: vorhandenen Kontext verwenden oder mit `issue-reading` das Issue lesen.
2. Den aktuell ausgecheckten Branch und den Working Tree feststellen. Den Branch nicht automatisch wechseln, neu erstellen oder auf eine andere Basis zurücksetzen.
3. Prüfen, dass der vorhandene Arbeitsstand für den Bugfix eindeutig weiterverwendet werden kann. Bei nicht zuordenbaren oder fachfremden lokalen Änderungen stoppen und den konkreten Zustand melden.
4. Einen vorhandenen terminalen Issue- oder Task-Plan gegen Repository-Zustand und geltende Regeln prüfen. Nur bei ungeklärter Ursache oder Planbruch mit `code-analysis` Ursache, Scope und Risiken klären.
5. Mit `code-testing` den Bug reproduzieren.
6. Den vorhandenen Issue- oder Task-Plan übernehmen. Nur ohne vollständigen Plan oder bei Planbruch mit `code-implementation-planning` gezielt planen.
7. Mit `code-implementation` den Bugfix umsetzen.
8. Mit `code-testing` prüfen, dass die ursprüngliche Reproduktion nicht mehr fehlschlägt und relevante Regressionen abgedeckt sind.
9. Erst nach erfolgreicher Reproduktion und lokaler Stabilisierung Backend-/Frontend-Änderungssätze durch ihren Implementierungsowner mit `code-minimization` prüfen und minimieren. Infrastruktur prüft eigene Änderungen mit `code-analysis` auf Scope und unbegründete Bestandteile, korrigiert sie bei Bedarf mit `code-implementation` und liefert lokale `code-testing`-Belege; fremde Skills werden nicht benötigt.
10. Nach jeder akzeptierten Reduktion die ursprüngliche Reproduktion und die durch die Reduktion betroffene Regression fokussiert erneut grün prüfen. Eine fehlgeschlagene Reduktion zurücknehmen; echte Unklarheit über Invariante oder Constraint als Planbruch routen.
11. Mit `code-testing` die unabhängige Verifikation des abschließend lokal geprüften Bugfixes ausführen; lokale Implementierer-Retests ersetzen diese nicht.
12. Mit `code-diff-review` Nebeneffekte und Scope-Ausweitung kontrollieren.
13. `softwareentwicklung_infrastruktur` den Commit-Push-Auftrag im beauftragten Task-Scope ausführen lassen.

## Rücksprungregeln

- Bei unklarer Ursache, Scope oder Reproduktion delegiert der Koordinator Analyse an Architektur.
- Bei nicht reproduzierbarem Verhalten werden Repro-Bedingungen, Ursache und Scope geklärt, bevor Umsetzung beginnt.
- Bei einem Planbruch geht fachlicher Scope an Product Owner, technischer Strukturbedarf an Architektur.
- Bei lokalen Implementierungsfehlern wird gezielt an den zuständigen Implementierungs-Owner zurückgegeben.
- Nach jeder Korrektur delegiert der Koordinator die betroffene Verifikation erneut an QA.

## Rollenübergaben

- Fehlerreproduktion und unabhängige Regression: `softwareentwicklung_qualitaetssicherung`.
- Technische Ursachen- oder Strukturfragen: `softwareentwicklung_architektur`.
- Codeänderungen und lokale Entwicklungschecks: `softwareentwicklung_backend`, `softwareentwicklung_frontend` oder bei Infrastrukturänderungen `softwareentwicklung_infrastruktur`.
- Unabhängige Verifikation und technischer Diff-Review: `softwareentwicklung_qualitaetssicherung`.
- Commit und Push: `softwareentwicklung_infrastruktur`.
- Planbruch geht an `product_owner` bei fachlichem Scope oder an Architektur bei technischer Strukturfrage. Ein Fehlerbefund geht als gezielter Rückauftrag an den Implementierungs-Owner.

## Endergebnis

- behobener Fehler auf dem bereits aktiven Branch
- nachvollziehbarer Bugfix-Kontext
- nachvollziehbarer Test- und Review-Kontext
- Commit und Push auf dem aktuellen Branch
- keine implizite Branch-Erstellung
- keine implizite Pull-Request-Erstellung

## Grenzen

- Den aktuell ausgecheckten Branch nicht automatisch wechseln oder ersetzen.
- Keinen neuen Branch erzeugen.
- Keinen Pull Request erzeugen.
- Bugfix-Planung und Implementierung dürfen erst beginnen, wenn der Bug reproduziert wurde.
- Nach der Implementierung muss die ursprüngliche Reproduktion erfolgreich sein.
- Relevante Regressionen müssen geprüft werden.
