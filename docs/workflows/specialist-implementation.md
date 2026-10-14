# Workflow: Spezialisten-Implementierung

## Ziel

Eine geklärte und abgegrenzte technische Änderung innerhalb der eigenen Implementierungszuständigkeit ausführen.

## Owner

Die vom Koordinator ausdrücklich zugewiesene Implementierungsrolle gemäß eigener Rollenbeschreibung.

## Verwenden

- Für beauftragte Code-, API-, UI- oder Infrastrukturänderungen mit festgelegtem Ziel und Scope.

## Verwendete Skills

- `code-reading`
- `code-analysis` bei bestehendem Verhalten oder Ursache
- `code-implementation`
- `code-refactoring` nur bei direkter Freigabe im eigenen Rollenindex und verhaltenserhaltendem Auftrag
- `code-minimization` nur bei direkter Freigabe im eigenen Rollenindex, nach lokaler Stabilisierung und sofern im aufrufenden Workflow vorgesehen
- `code-testing` für ausdrücklich beauftragtes lokales Implementierungsfeedback

## Ablauf

1. Den übergebenen Plan, Scope, Nicht-Scope, Constraints und Akzeptanzkriterien prüfen.
2. Nur den eigenen Rollenindex und für die Aufgabe freigegebene Technologien verwenden.
3. Bestehenden Code und relevante Grenzen gezielt lesen; ungeklärte technische Strukturentscheidungen an den Koordinator zurückgeben.
4. Die zugewiesene Änderung im ausdrücklich freigegebenen Dateiscope umsetzen.
5. Eigene lokale Rückmeldung oder direkte Entwicklungschecks nur ausführen, wenn der Auftrag sie ausdrücklich als Implementierungsfeedback vorsieht; Bedarf an formaler unabhängiger Verifikation dem Koordinator melden.
6. Änderungen und Nachweise dem Koordinator zurückgeben.

## Grenzen

- Keine Issue- oder Projektplanung, keine selbständige Subdelegation und keine Arbeit außerhalb des zugewiesenen Scopes.
- Keine eigenständigen Git-, GitHub-, Commit-, Push-, PR-, Merge- oder Veröffentlichungsschritte.
- Keine formale Abnahme oder unabhängige Testverifikation.
- Bei fremder Zuständigkeit oder Planbruch stoppen und den Koordinator mit dem konkreten Befund informieren.

## Rücksprungregeln

- Lokale Fehler im zugewiesenen Scope korrigieren und die betroffene lokale Prüfung wiederholen. Planbrüche, fehlende Freigaben oder fremde Zuständigkeit mit konkretem Befund an den Koordinator zurückgeben.

## Endergebnis

Ergebnis, geänderte Bereiche, Verifikation oder deren Auslassung, Abweichungen, Blocker und weiterer Bedarf für den Koordinator.
