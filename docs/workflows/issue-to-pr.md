# Workflow: Issue To PR

## Owner und Modus

`koordinator` liest diesen Ablauf als Delegationsplan. Issue-Kontext und Akzeptanzkriterien delegiert er an `product_owner`, technische Planung an Architektur, Umsetzung an Backend/Frontend/Infrastruktur im eigenen Scope, Verifikation an QA sowie Branch, Commit, Push und PR an Infrastruktur. Er lädt keine operativen Fachskills.

## Ziel

Eine bereits umgesetzte Änderung mit Issue-Kontext committen, pushen und als Pull Request erstellen.

## Verwenden

- Wenn eine Änderung bereits umgesetzt ist und aus dem Issue-Kontext ein Pull Request entstehen soll.
- Wenn relevante Issue-Relationships für PR-Kontext oder Verlinkung einbezogen werden sollen.
- Nicht verwenden, wenn die Änderung erst geplant oder implementiert werden muss. Dann `issue-implementation.md`, `issue-graph-implementation.md` oder `bugfix.md` nutzen.

## Verwendete Skills

- `issue-reading`
- `code-testing`
- `code-diff-review`
- `pr-creation`

## Verwendete Workflows

- `commit-push.md`

## Ablauf

1. Der Koordinator delegiert das Lesen des Haupt-Issues und explizit relevanter Relationships als PR-Kontext mit `issue-reading` an `product_owner`; technische Kriterien und offene Punkte gehen an Architektur.
2. Vor der unabhängigen Prüfung bestätigt der Koordinator anhand der Rollenrückgaben die vorgelagerte Backend-/Frontend-Minimierung samt Retests beziehungsweise die Infrastruktur-Scope-Prüfung samt lokaler Verifikation für den aktuellen Stand. Fehlende Belege gehen an den zuständigen Implementierungs-/Bugfix-Workflow zurück. Der Koordinator delegiert die im Issue oder Task vorgesehene unabhängige technische Verifikation mit `code-testing` an QA. Fachliche und technische Kriterienabnahme werden gemäß ihrem Scope an PO beziehungsweise Architektur delegiert. QA benennt technische Testlücken.
3. Der Koordinator delegiert den Review des Änderungssatzes gegen Scope, Nicht-Scope, technische Kriterien, Nebeneffekte und Versandbereitschaft mit `code-diff-review` an QA.
4. `softwareentwicklung_infrastruktur` führt den Workflow `commit-push.md` aus, damit sie den Änderungssatz sauber committet und pusht.
5. Der Koordinator delegiert `pr-creation` an Infrastruktur, damit sie den Pull Request erstellt und den freigegebenen Issue-Kontext verlinkt.

## Rücksprungregeln

- Bei unklarem Issue-Kontext an Product Owner zurückgeben.
- Bei fehlender vorgelagerter Minimierungs-/Retest-Evidenz für Backend/Frontend oder Scope-/Verifikationsevidenz für Infrastruktur an den zuständigen Implementierungs-/Bugfix-Workflow zurückgeben.
- Bei fehlender oder gescheiterter unabhängiger Verifikation an QA zurückgeben.
- Bei nicht versandbereitem Diff an passende Umsetzung oder Refactoring zurückgeben.
- Commit, Push oder PR erst nach belegter Verifikation an Infrastruktur delegieren.

## Rollenübergaben

- Issue-Kontext und Akzeptanzkriterien: `product_owner`.
- Technische Analyse, Technical Stories/Technical Epics/Technical Tasks und technische Kriterien: Architektur, danach Backend, Frontend oder Infrastruktur gemäß Scope.
- Fachliche Black-Box-Acceptance: `product_owner`.
- Unabhängige technische Regression und Review-Prüfungen: `softwareentwicklung_qualitaetssicherung`.
- Commit, Push und PR-Erstellung: `softwareentwicklung_infrastruktur`.
- Planbruch geht an Product Owner oder Architektur entsprechend dem Gegenstand.

## Endergebnis

- gelesener Issue- und Relationship-Kontext
- geprüfte Änderung
- Commit und Push
- erstellter Pull Request

## Grenzen

- Fehlende oder gescheiterte Verifikation blockiert Commit, Push und Pull-Request-Erstellung.
