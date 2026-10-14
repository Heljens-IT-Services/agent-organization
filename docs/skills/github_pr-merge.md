# Skill: GitHub PR Merge

## Zweck

Einen freigegebenen Pull Request mit der konfigurierten Merge-Methode zusammenführen und das Ergebnis prüfen.

## Verwenden

- Wenn der User den Merge ausdrücklich beauftragt hat.
- Nicht verwenden, um Checks, Reviews, Konflikte oder Branch-Regeln zu umgehen.

## Vorgehen

1. Repository, Pull Request und ausdrückliche Merge-Autorisierung bestimmen.
2. Pull-Request-Status, Draft-Status, Review-Entscheidung, Mergebarkeit und Head-Commit lesen.
3. Sicherstellen, dass das Check-Ergebnis zum aktuellen Head-Commit gehört.
4. Merge-Methode nach Priorität bestimmen: User-Vorgabe, `PROJECT.md`, eindeutige etablierte Repository-Konvention, eindeutige Repository-Konfiguration.
5. Stoppen, wenn der Pull Request ein Draft ist, erforderliche Reviews oder von den Check-Ergebnissen unabhängige Branch-Regeln nicht erfüllt sind, Konflikte bestehen oder die Merge-Methode mehrdeutig bleibt.
6. Bei `spending-limit-blocked` ausdrücklich fragen, ob der konkrete Pull Request trotz der benannten Checks und Risiken mit dem geprüften Head-Commit gemergt werden soll.
7. Ohne eindeutige Bestätigung oder bei verändertem Head-Commit stoppen; für einen neuen Head-Commit erneut prüfen und fragen.
8. Bei allen anderen nicht erfolgreichen oder fehlenden erforderlichen Checks stoppen.
9. Bei erfolgreichen Checks oder nach der zusätzlichen Bestätigung nur mit der bestimmten normalen Merge-Methode und ohne administrative Umgehung mergen oder in eine erforderliche Merge Queue einreihen.
10. Wenn GitHub den Merge wegen Schutzregeln oder fehlender Rechte ablehnt, den Blocker melden.
11. Wenn GitHub eine Merge Queue verlangt, deren erforderliche Checks und Pull-Request-Zustand bis zu einem terminalen Ergebnis beobachten.
12. Zustand erneut lesen und nur `MERGED` mit Merge-Zeitpunkt und Merge-Commit als Erfolg bewerten.

## Check-Ausnahme

Der Status `no-checks-required` ist merge-zulässig, wenn für den unveränderten Head nachweislich keine erforderlichen Checks konfiguriert sind und keine Checks berichtet werden. Nur tatsächlich konfigurierte, aber fehlende oder nicht erfolgreiche erforderliche Checks blockieren den Merge; administrative Umgehungen bleiben unzulässig.

## Kommandos

```powershell
gh pr view <pr-nummer> --repo <org>/<repo> --json state,isDraft,reviewDecision,mergeable,mergeStateStatus,headRefOid,url
gh repo view <org>/<repo> --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
gh pr merge <pr-nummer> --repo <org>/<repo> --merge --match-head-commit <head-sha>
gh pr merge <pr-nummer> --repo <org>/<repo> --squash --match-head-commit <head-sha>
gh pr merge <pr-nummer> --repo <org>/<repo> --rebase --match-head-commit <head-sha>
gh pr checks <pr-nummer> --repo <org>/<repo> --required --watch --interval 10
gh pr view <pr-nummer> --repo <org>/<repo> --json state,mergedAt,mergeCommit,url
```

Nur genau eine zur aufgelösten Merge-Methode passende `gh pr merge`-Variante ausführen.

## Grenzen

- Extern wirksam arbeiten: Der Pull Request wird tatsächlich gemergt.
- Kein `--admin`, kein ausdrückliches `--auto` und keine Umgehung erforderlicher Checks oder Reviews verwenden.
- Die allgemeine Merge-Autorisierung ersetzt nicht die zusätzliche Bestätigung für einen eingetretenen Spending-Limit-Fall.
- Eine Spending-Limit-Bestätigung gilt nur für den benannten Pull Request und unveränderten Head-Commit.
- Keine Konflikte beheben und keine neuen Commits erstellen.
- Den Source-Branch nicht automatisch löschen.
- Bei unklarem oder verändertem Head-Commit stoppen.

## Output

- Pull Request und Merge-Commit
- verwendete Merge-Methode
- verifizierter Merge- oder terminaler Merge-Queue-Status
- nicht ausgeführter Merge mit Blocker, falls relevant

## Qualitätskriterien

- Merge nur nach ausdrücklicher Autorisierung.
- Schutzregeln nicht umgehen.
- Ergebnis nach der Mutation erneut prüfen.
- Spending-Limit ohne Bestätigung, ein veränderter Head-Commit und gemischte Checkfehler müssen den Merge stoppen.
