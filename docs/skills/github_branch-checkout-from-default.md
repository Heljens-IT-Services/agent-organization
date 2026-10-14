# Skill: GitHub Branch Checkout From Default

## Zweck

Einen aufgabenbezogenen Arbeitsbranch von einer aktuellen Standardbasis erstellen oder bestätigen, dass bereits ein passender Branch aktiv ist.

## Verwenden

- Vor Beginn einer neuen Aufgabe.
- Wenn Arbeit von `develop`, `main` oder einer expliziten Basis starten soll.
- Nicht verwenden, wenn bewusst auf dem aktuellen Branch weitergearbeitet werden soll.

## Arbeitsbranch-Regeln

[MUST] Vor jeder zustandsverändernden Implementierung muss der Agent prüfen, ob ein aufgabenbezogener Arbeitsbranch aktiv ist.

[SHOULD] Implementierungen sollen auf einem aufgabenbezogenen Branch erfolgen, nicht direkt auf `main`, `develop`, `master` oder einem anderen Integrationsbranch.

[MUST_IF] Wenn der aktuelle Branch `main`, `develop`, `master` oder ein anderer Integrationsbranch ist und der User keine ausdrücklich abweichende Anweisung gegeben hat, muss vor der Implementierung ein aufgabenbezogener Arbeitsbranch erstellt werden.

[MUST_IF] Wenn der User ausdrücklich verlangt, auf `main`, `develop`, `master` oder einem anderen Integrationsbranch zu arbeiten, muss der Agent diese Abweichung vor zustandsverändernden Änderungen kurz benennen.

## Vorgehen

1. Aktuellen Branch und Arbeitsstatus prüfen, z. B. `git status --short --branch`.
2. Bestimmen, ob bereits ein passender Arbeitsbranch aktiv ist.
3. Wenn ein passender Arbeitsbranch aktiv ist, keinen neuen Branch erstellen und Status melden.
4. Basisbranch nach Priorität bestimmen: explizite User-Vorgabe, Workflow-/Issue-Vorgabe, Remote-Default, `develop`, `main`, `master`.
5. Remote-Stand holen, z. B. `git fetch origin`.
6. Vor dem Checkout prüfen, ob die lokale Basis mit dem Remote-Branch aktuell ist.
7. Basis per Fast-Forward aktualisieren, falls Remote voraus ist.
8. Gewünschten Branch-Namen gegen lokale und Remote-Branches prüfen.
9. Bei lokalen uncommitted fachlichen Änderungen nachfragen, bevor sie auf einen neuen Branch mitgenommen werden. Ausdrücklich als unversioniert definierte Runtime-Artefakte bleiben unberücksichtigt.
10. Aufgabenbezogenen Branch nach Konvention erstellen.
11. Branch und mitgenommene lokale Änderungen melden.

## Kommandos

```powershell
git status --short --branch
git fetch origin
git branch --list
git branch --remotes
git switch <basis-branch>
git merge --ff-only origin/<basis-branch>
git switch -c <neuer-branch> <basis-branch>
git status --short --branch
```

Platzhalter aus Aufgabe, Basisbranch und Branch-Namenskonvention ableiten.

## Grenzen

- Extern wirksam arbeiten: Branch kann tatsächlich gewechselt oder erstellt werden.
- Keine lokalen Änderungen verwerfen.
- Lokale uncommitted fachliche Änderungen nicht automatisch mitnehmen.
- Keine Rebase-, Reset- oder Merge-Commits erzeugen.
- Basisbranch nicht raten, wenn er unklar ist.
- Wenn nach Prioritätenliste keine Basis klar ist, stoppen und nachfragen.
- Nur Fast-Forward-Aktualisierung der Basis verwenden.
- Wenn die Basis nicht per Fast-Forward aktualisiert werden kann, stoppen und Blocker melden.
- Nicht von veralteter lokaler Basis branchen.
- Branch-Namen nicht doppelt lokal oder remote verwenden.
- Branch-Namenskonvention: `feature/<kurzer-scope>`, `bugfix/<kurzer-scope>`, `refactor/<kurzer-scope>` oder `chore/<kurzer-scope>`.
- Bei Issue-Bezug: `<typ>/<issue-number>-<kurzer-scope>`.

## Output

- Basisbranch
- neuer Branch
- Hinweis, wenn kein Checkout nötig war
- Hinweis auf lokale Änderungen

## Qualitätskriterien

- Branch-Name muss Aufgabe und Scope erkennen lassen.
- Der neue Branch muss auf der geprüften aktuellen Basis starten.
