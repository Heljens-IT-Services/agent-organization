# Skill: GitHub Default Branch Aktualisieren

## Zweck

Nach einem verifizierten Pull-Request-Merge auf den Default-Branch zurückkehren und ihn sicher per Fast-Forward aktualisieren.

## Verwenden

- Nach einem erfolgreichen, verifizierten Merge, wenn der lokale Checkout auf die aktuelle Standardbasis wechseln soll.
- Nicht verwenden, solange der Merge nicht bestätigt oder der Arbeitsbaum nicht sauber ist.

## Vorgehen

1. Verifizierten Merge-Kontext und Repository bestimmen.
2. Arbeitsbaum auf lokale Änderungen prüfen und bei Änderungen stoppen.
3. Default-Branch aus dem Remote-Repository lesen.
4. Remote-Stand holen.
5. Auf den lokalen Default-Branch wechseln.
6. Den Default-Branch ausschließlich per Fast-Forward auf den Remote-Stand aktualisieren.
7. Aktuellen Branch und Synchronisationsstatus prüfen.

## Kommandos

```powershell
git status --short --branch
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
git fetch <remote>
git switch <default-branch>
git merge --ff-only <remote>/<default-branch>
git status --short --branch
```

## Grenzen

- Zustandsverändernd arbeiten: Der lokale Branch wird gewechselt und aktualisiert.
- Keine lokalen Änderungen verwerfen, stashen oder automatisch mitnehmen.
- Kein Rebase, Reset oder Merge-Commit.
- Default-Branch und Remote nicht raten.
- Arbeitsbranch weder lokal noch remote löschen.
- Bei nicht möglichem Fast-Forward stoppen und den Arbeitsbranch beziehungsweise vorhandene Daten unverändert lassen.

## Output

- Default-Branch und Remote
- aktualisierter Commit-Stand
- bestätigter sauberer Arbeitsbaum
- Blocker, falls kein sicherer Wechsel oder Fast-Forward möglich war

## Qualitätskriterien

- Der Abschluss muss einen sauberen Arbeitsbaum auf dem mit dem Remote synchronisierten Default-Branch nachweisen.
