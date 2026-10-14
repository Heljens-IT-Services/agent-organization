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
3. Erforderliche Checks aus den anwendbaren Projektregeln und verfügbaren GitHub-Quellen (Zielbranch, Branch Protection, Rulesets, Check Runs und Commit-Statuses) sowie ihren aktuellen Status lesen. Alle Ergebnisse vollständig einschließlich Pagination auswerten. Bei nachgewiesener Tarifgrenze den unten definierten Ersatzpfad verwenden.
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
- Bei Authentifizierungs-, Berechtigungs-, unklaren API- oder Netzwerkfehlern stoppen und den Blocker melden. Ausschließlich die unten nachgewiesene Tarifgrenze erlaubt den Ersatzpfad; ein HTTP-Status allein genügt nicht.

## Zulässiger Zustand ohne CI-Checks

Wenn keine erforderlichen Checks konfiguriert sind und für den unveränderten Pull-Request-Head weder Check Runs noch Commit-Statuses berichtet werden, ist `no-checks-required` ein zulässiger terminaler Status. Der Nachweis folgt den verfügbaren Quellen und gegebenenfalls dem nachstehenden Tarif-Ersatzpfad. Dieser Status ist kein CI-Erfolg und ersetzt weder taskbezogene lokale Pflichtprüfungen noch unabhängige Verifikation. Eine aus irgendeiner anwendbaren Quelle bekannte erforderliche Prüfung, die fehlt, bleibt `missing-required-check` und blockiert.

## Tarifgerechter Ersatzpfad

1. `plan-feature-unavailable` nur dann als Quellenbefund dokumentieren, wenn GitHub für die konkret angefragte Funktion ausdrücklich meldet, dass sie für dieses Repository im aktuellen Tarif nicht verfügbar ist, etwa mit der Aufforderung zu einem Tarifupgrade oder öffentlicher Repository-Sichtbarkeit. Endpoint, HTTP-Status, genaue Meldung, Repository, Zielbranch, Head-Commit und Abrufzeit festhalten. Ein bloßes `403`, `404`, fehlende Administration-Berechtigung, Authentifizierungsproblem, Rate Limit oder eine leere Antwort beweist keine Tarifgrenze.
2. Nur die nachweislich tarifbedingt nicht verfügbare Quelle ausnehmen. Alle übrigen verfügbaren Quellen aus Schritt 3 lesen; Fehler dieser Quellen bleiben Blocker. Aus unbekanntem oder unlesbarem Schutzstatus nicht „unprotected“ ableiten. Bei einem ausdrücklich ungeschützten Zielbranch ist eine nicht anwendbare Branch-Protection-Konfiguration kein fehlender Pflichtcheck.
3. Bekannte Projektanforderungen, verfügbare Branch-Protection-/Ruleset-Anforderungen und alle gemeldeten Check Runs sowie Commit-Statuses für den unveränderten Head bewerten. Ausstehende Prüfungen beobachten; fehlende oder nicht erfolgreiche Pflichtprüfungen blockieren. Nicht als erforderlich zuordenbare gemeldete Prüfungen nicht ignorieren: bei ausstehenden, fehlgeschlagenen, abgebrochenen oder übersprungenen Ergebnissen den offenen Befund melden und nicht aufgrund der Tarifgrenze freigeben.
4. `no-checks-required` nur ausgeben, wenn in sämtlichen anwendbaren, erfolgreich gelesenen Quellen keine erforderlichen GitHub-Checks konfiguriert sind, keine Check Runs oder Commit-Statuses berichtet werden und ausschließlich die ausdrücklich belegte Tarifquelle nicht verfügbar ist. Bekannte lokale Pflichtprüfungen müssen für den unveränderten Änderungssatz erfolgreich und die vom aufrufenden Workflow verlangte unabhängige Verifikation belegt sein; fehlende Evidenz blockiert. Bei vorhandenen Checks deren tatsächliche Ergebnisse ausgeben, niemals `no-checks-required`.
5. Verwendete Ersatzquellen, Test-/Verifikationsevidenz und verbleibende Sichtbarkeitsgrenze ausdrücklich berichten. Die nicht verfügbare Quelle bleibt `plan-feature-unavailable`, nicht „erfolgreich geprüft“. Diese Einschränkung allein ist bei erfüllten übrigen Gates kein Merge-Blocker. GitHub entscheidet beim normalen, Head-gebundenen Merge abschließend über serverseitige Regeln; eine Ablehnung bleibt verbindlich.

Der Ersatzpfad ist die Standardregel bei belegter Tarifgrenze und braucht keine kostenpflichtige Funktion. Er autorisiert weder ein Upgrade, Ausgaben, öffentliche Repository-Sichtbarkeit, Berechtigungs-/Schutzregeländerungen noch einen administrativen Bypass. Er ist vom separaten `spending-limit-blocked`-Fall zu unterscheiden und ändert dessen Bestätigungspflicht nicht.

## Output

- Pull Request und beobachteter Head-Commit
- terminaler Status der erforderlichen Checks
- `no-checks-required` mit Quellenbelegen, wenn keine erforderlichen GitHub-Checks konfiguriert sind und keine Checks oder Commit-Statuses berichtet werden
- gegebenenfalls `plan-feature-unavailable` als Quellenbefund mit genauer Meldung, Ersatzquellen, lokaler Test-/Verifikationsevidenz und verbleibender Sichtbarkeitsgrenze
- erfolgreiche, fehlgeschlagene, abgebrochene, übersprungene oder fehlende Checks
- `spending-limit-blocked` mit betroffenen Checks und GitHub-Evidenz, falls eindeutig nachgewiesen
- Blocker oder erforderliche erneute Beobachtung

## Qualitätskriterien

- Nur terminale Ergebnisse als abgeschlossen melden.
- Check-Status nicht relativieren.
- Ergebnis an den unveränderten Pull-Request-Head binden.
- Ein reiner Spending-Limit-Fall ergibt `spending-limit-blocked`; ein gemischter oder unbelegter Fehlerfall bleibt fehlgeschlagen.
