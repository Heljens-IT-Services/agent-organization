# Skill: GitHub Integrationsbranch Aktualisieren

## Zweck

Nach einem verifizierten Pull-Request-Merge nach `develop` auf den Integrationsbranch wechseln und ihn sicher per Fast-Forward aktualisieren.

## Verwenden

- Nach einem erfolgreichen, verifizierten Feature- oder Task-Merge nach `develop`.
- Nicht verwenden, solange der Merge nicht bestätigt oder der Arbeitsbaum nicht sauber ist.
- Nicht für die Aktualisierung des Default-Branches verwenden; dafür `default-branch-update` nutzen.

## Vorgehen

1. Verifizierten Merge-Kontext, Repository und Remote bestimmen.
2. Bestätigen, dass der Pull Request nach `develop` gemergt wurde.
3. Arbeitsbaum auf lokale Änderungen prüfen und bei Änderungen stoppen.
4. Remote-Stand holen und die Existenz von `<remote>/develop` bestätigen.
5. Auf den lokalen Branch `develop` wechseln.
6. `develop` ausschließlich per Fast-Forward auf `<remote>/develop` aktualisieren.
7. Aktuellen Branch und Synchronisationsstatus prüfen.

## Kommandos

```powershell
git status --short --branch
git fetch <remote>
git rev-parse --verify <remote>/develop
git switch develop
git merge --ff-only <remote>/develop
git status --short --branch
```

## Grenzen

- Zustandsverändernd arbeiten: Der lokale Branch wird gewechselt und aktualisiert.
- Keine lokalen Änderungen verwerfen, stashen oder automatisch mitnehmen.
- Kein Rebase, Reset oder Merge-Commit.
- Remote nicht raten.
- Arbeitsbranch weder lokal noch remote löschen.
- Bei nicht möglichem Fast-Forward stoppen und vorhandene Daten unverändert lassen.

## Output

- Integrationsbranch und Remote
- aktualisierter Commit-Stand
- bestätigter sauberer Arbeitsbaum
- Blocker, falls kein sicherer Wechsel oder Fast-Forward möglich war

## Qualitätskriterien

- Der Abschluss muss einen sauberen Arbeitsbaum auf dem mit dem Remote synchronisierten Branch `develop` nachweisen.
