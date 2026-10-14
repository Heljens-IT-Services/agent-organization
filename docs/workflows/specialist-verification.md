# Workflow: Spezialisten-Verifikation

## Ziel

Eine abgeschlossene Änderung unabhängig anhand der übergebenen Akzeptanzkriterien und des Prüfscopes bewerten.

## Owner

`softwareentwicklung_qualitaetssicherung`

## Verwenden

- Wenn eine abgeschlossene Änderung unabhängig im ausdrücklich beauftragten Prüf- und Technologiescope verifiziert werden soll.

## Verwendete Skills

- `code-reading`
- `code-testing`
- `code-analysis` bei nicht reproduzierbaren oder widersprüchlichen Befunden
- `code-diff-review` für Scope, Risiken und Nebeneffekte
- `research` nur bei notwendigem aktuellem externem Prüfwissen

## Ablauf

1. Akzeptanzkriterien, Prüfumfang, relevanten Änderungsstand und erwartete Evidenz übernehmen.
2. Prüfschritte passend zum Produktverhalten und zur betroffenen Technologie bestimmen.
3. Tests, Builds, manuelle Prüfungen und relevante Diff-Kontrollen ausführen, soweit beauftragt und möglich.
4. Jeden Befund mit Status, konkreter Evidenz und geprüftem Stand dokumentieren.
5. Implementierungsfehler an den Koordinator zur Rückgabe an den zuständigen Implementierer melden; widersprüchliche Kriterien dem Koordinator melden.
6. Unabhängiges Ergebnis dem Koordinator zurückgeben.

## Grenzen

- Keine Implementierung oder eigenständige Korrektur des geprüften Scopes.
- Keine externe Git-/GitHub-Mutation, kein Commit, Push, PR oder Merge.
- Keine Abnahmebehauptung ohne kriterienspezifische Evidenz.

## Rücksprungregeln

- Implementierungsfehler mit Evidenz an den Koordinator zur Korrektur durch den Implementierungsowner zurückgeben; danach die betroffene Prüfung wiederholen. Fehlende Voraussetzungen oder widersprüchliche Kriterien als konkreten Blocker melden.

## Endergebnis

Unabhängige Bewertung des geprüften Stands mit kriterienspezifischen Belegen, Befunden, Einschränkungen und Blockern für den Koordinator.
