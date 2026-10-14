# Skill: GitHub PR Checks Beobachten

## Zweck

Die erforderlichen Checks eines Pull Requests bis zu einem terminalen Zustand beobachten und ihr Ergebnis richtungsstabil bewerten.

## Verwenden

- Wenn ein Pull Request vor Review, Merge oder Abschluss auf erforderliche Checks warten muss.
- Wenn der Status bereits laufender GitHub-Actions- oder externer Checks beobachtet werden soll.
- Nicht verwenden, um fehlgeschlagene Checks zu analysieren oder zu reparieren.

## Vorgehen

1. Repository und Pull Request eindeutig bestimmen.
2. Aktuellen Head-Commit des Pull Requests lesen und für die Beobachtung festhalten.
3. Erforderliche Checks und ihren aktuellen Status lesen.
4. Laufende erforderliche Checks bis zu einem terminalen Zustand beobachten.
5. Vor dem Ergebnis prüfen, ob der Pull-Request-Head unverändert ist.
6. Den Status `spending-limit-blocked` nur ausgeben, wenn alle nicht erfolgreichen erforderlichen Checks durch eine konkrete GitHub-Meldung nachweislich allein wegen des erreichten GitHub-Actions-Spending-Limits nicht ausgeführt werden konnten.
7. Bei `spending-limit-blocked` Pull Request, Head-Commit, betroffene Checks, GitHub-Evidenz und das Risiko eines Merges ohne erfolgreiche Checks melden.
8. Nur bei vollständig erfolgreichen erforderlichen Checks oder bei `no-checks-required` ein zulässiges Ergebnis ausgeben.
9. Alle anderen fehlgeschlagenen, abgebrochenen, übersprungenen oder fehlenden erforderlichen Checks mit ihrem Status melden.

## Kommandos

```powershell
gh pr view <pr-nummer> --repo <org>/<repo> --json headRefOid,url
gh pr checks <pr-nummer> --repo <org>/<repo> --required --watch --interval 10
gh pr checks <pr-nummer> --repo <org>/<repo> --required --json name,state,link
gh run view <run-id> --repo <org>/<repo>
gh pr view <pr-nummer> --repo <org>/<repo> --json headRefOid,url
```

## Grenzen

- Read-only arbeiten.
- Keine Checks neu starten, abbrechen, überspringen oder administrativ umgehen.
- Keine CI-Fehler analysieren oder beheben; ausschließlich die GitHub-Ursachenmeldung darf zur Spending-Limit-Klassifikation gelesen werden.
- Ein neuer Head-Commit macht das bisherige Ergebnis ungültig und erfordert eine neue Beobachtung.
- Fehlende erforderliche Checks nicht stillschweigend als erfolgreich behandeln, wenn Repository-Regeln Checks erwarten.
- Bei gemischten oder nicht eindeutig belegten Ursachen nicht als `spending-limit-blocked` klassifizieren.
- Bei Authentifizierungs-, Berechtigungs- oder API-Fehlern stoppen und den Blocker melden.

## Zulässiger Zustand ohne CI-Checks

Wenn keine erforderlichen Checks konfiguriert sind und für den unveränderten Pull-Request-Head keine Checks berichtet werden, ist `no-checks-required` ein zulässiger terminaler Status. Dieser Zustand darf nicht als fehlgeschlagener Check oder als fehlende Pflichtprüfung behandelt werden. Eine tatsächlich konfigurierte erforderliche Prüfung, die fehlt, läuft weiterhin unter `missing-required-check` und blockiert.

## Output

- Pull Request und beobachteter Head-Commit
- terminaler Status der erforderlichen Checks
- `no-checks-required`, wenn keine erforderlichen Checks konfiguriert sind und keine Checks berichtet werden
- erfolgreiche, fehlgeschlagene, abgebrochene, übersprungene oder fehlende Checks
- `spending-limit-blocked` mit betroffenen Checks und GitHub-Evidenz, falls eindeutig nachgewiesen
- Blocker oder erforderliche erneute Beobachtung

## Qualitätskriterien

- Nur terminale Ergebnisse als abgeschlossen melden.
- Check-Status nicht relativieren.
- Ergebnis an den unveränderten Pull-Request-Head binden.
- Ein reiner Spending-Limit-Fall ergibt `spending-limit-blocked`; ein gemischter oder unbelegter Fehlerfall bleibt fehlgeschlagen.
