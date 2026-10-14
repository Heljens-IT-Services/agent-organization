# Workflow: Refactoring Secure

## Owner und Modus

`koordinator` liest diesen Ablauf ausschließlich als Delegationsplan. Verhalten und fachlichen Scope delegiert er an `product_owner`, technische Strukturplanung an Architektur, Refactoring an Backend/Frontend, unabhängige Regressionstests an QA und Commit/Push/PR an Infrastruktur.

## Ziel

Bestehenden Code strukturell verbessern, ohne Verhalten zu verändern, und die Änderung bis zum Pull Request absichern.

## Verwenden

- Wenn Code wartbarer, lesbarer, weniger redundant oder klarer strukturiert werden soll.
- Wenn vor und nach dem Refactoring explizit belegt werden soll, dass bestehendes Verhalten erhalten bleibt.
- Wenn mehrere zusammenhängende Refactoring-Ziele in einem gemeinsamen Scope bearbeitet werden sollen.
- Nicht verwenden, wenn fachliches Verhalten geändert werden soll. Verhaltensänderungen sind in diesem Workflow verboten.

## Verwendete Skills

- `github-branch-checkout-from-default`
- `code-analysis`
- `code-implementation-planning`
- `code-refactoring`
- `code-minimization` für Backend-/Frontend-Änderungssätze
- `code-testing`
- `code-diff-review`
- `pr-creation`

## Verwendete Workflows

- `commit-push.md`

## Ablauf

1. Mit `github-branch-checkout-from-default` einen geeigneten Arbeitsbranch von der Standardbasis erstellen.
2. Einen vorhandenen terminalen Issue- oder Task-Plan gegen Repository-Zustand und geltende Regeln prüfen. Nur bei fehlender Verhaltensbasis oder Planbruch mit `code-analysis` bestehenden Code, Ziele und Verhaltensgrenzen erfassen.
3. Verhaltensbasis festhalten:
   - vorhandene Tests
   - relevante User-Flows
   - API-Kontrakte
   - Datenformate
   - Seiteneffekte
   - beobachtbares Verhalten
4. Refactoring-Ziele, Reihenfolge, Grenzen und Absicherungsstrategie aus dem Issue- oder Task-Plan übernehmen. Nur ohne vollständigen Plan oder bei Planbruch mit `code-implementation-planning` gezielt nachplanen.
5. Falls die bestehende Absicherung zu schwach ist, Tests mit dem Ziel ergänzen oder anpassen, bestehendes Verhalten zu fixieren.
6. Backend oder Frontend setzt die Strukturverbesserungen mit `code-refactoring` um und stabilisiert sie lokal mit `code-testing`. Erst danach prüft der jeweilige Implementierungsowner den Diff mit `code-minimization`; nach jeder akzeptierten Reduktion wiederholt er die betroffene fokussierte Verifikation. Fehlgeschlagene Reduktionen nimmt er zurück; echte Unklarheit über Invarianten oder Constraints geht an Architektur.
7. QA prüft mit `code-testing` unabhängig Verhalten und Regressionen des finalen Änderungssatzes gegen die zuvor festgehaltene Verhaltensbasis; lokale Implementierer-Retests ersetzen diese Prüfung nicht.
8. Mit `code-diff-review` sicherstellen, dass keine verdeckte Fachlogik oder unbeabsichtigte Verhaltensänderung entstanden ist.
9. Kritische Funde korrigieren und die passende Prüfung wiederholen.
10. Erst nach bestandener Absicherung `softwareentwicklung_infrastruktur` den Commit-Push-Auftrag im beauftragten Task-Scope ausführen lassen.
11. Mit `pr-creation` den Pull Request mit Refactoring-Zielen, Verhaltenserhalt, Teststatus und Review-Kontext erstellen.

## Rücksprungregeln

- Bei unklarem Bestandsverhalten technische Analyse an Architektur zurückgeben.
- Bei fehlender oder schwacher Testbasis QA zur Absicherungsstrategie hinzuziehen.
- Bei lokalen Refactoring-Fehlern die Korrektur an den Implementierungs-Owner delegieren und betroffene Prüfung wiederholen.
- Bei widersprüchlichem Verhalten, Scope oder Plan den Ablauf blockieren und an Product Owner oder Architektur geben.
- Wenn das Ziel eine Verhaltensänderung verlangt, diesen Workflow nicht fortsetzen.

## Rollenübergaben

- Fachlicher Scope und Verhaltensgrenzen: `product_owner`.
- Technische Analyse und Refactoring-Planung: `softwareentwicklung_architektur`.
- Verhaltenserhaltende Strukturänderung: Backend oder Frontend gemäß Scope.
- Regression, Verhaltenserhalt und unabhängige Verifikation: `softwareentwicklung_qualitaetssicherung`.
- Commit, Push und PR: `softwareentwicklung_infrastruktur`.

## Endergebnis

- strukturell verbesserter Code
- erhaltenes und verifiziertes Verhalten
- ergänzte oder angepasste Tests, falls für die Absicherung nötig
- dokumentierter Teststatus
- Commit und Push
- erstellter Pull Request

## Grenzen

- Keine Verhaltensänderungen.
- Kein Wechsel in `bugfix.md` oder `issue-graph-implementation.md` innerhalb dieses Workflows.
- Keine neuen Features.
- Keine fachliche Fehlerbehebung.
- Keine vorbereitenden Commits vor bestandener Absicherung.
- Mehrere Refactoring-Ziele sind erlaubt, wenn sie zusammenhängen und getrennt prüfbar bleiben.
