# Skill: GitHub Commit

## Zweck

Einen abgeschlossenen lokalen Änderungssatz logisch schneiden und als einen oder mehrere lokale Git-Commits speichern.

## Verwenden

- Wenn lokale Änderungen fertig, getestet und reviewed sind und bewusst committet werden sollen.
- Wenn der User nur einen lokalen Commit ohne Push beauftragt.
- Nicht verwenden, wenn bereits vorhandene lokale Commits nur gepusht werden sollen. Dann `github-push` nutzen.
- Nicht verwenden, wenn Commit und Push zusammenhängend ausgeführt werden sollen. Dann den Workflow `commit-push.md` nutzen.

## Vorgehen

1. Branch, Arbeitsstatus sowie staged, unstaged und untracked Änderungen prüfen.
2. Taskbezogenen Scope bestimmen und fremde Änderungen ausschließen.
3. Logisch zusammengehörige Änderungssätze bilden.
4. Wenn mehrere klar trennbare Änderungssätze vorhanden sind, mehrere Commits vorbereiten.
5. Nur die vollständigen, zum jeweiligen Commit gehörenden Dateien stagen.
6. Gestagten Diff und verbleibende unstaged bzw. untracked Änderungen prüfen.
7. Commit-Message aus Diff und Task-Kontext formulieren.
8. Commit erstellen und Hash, Message sowie verbleibenden Arbeitsstatus prüfen.

## Kommandos

```powershell
git status --short --branch
git diff --stat
git diff
git diff --cached --stat
git diff --cached
git add <pfade>
git commit -m "<type>: <kurze konkrete aenderung>"
git rev-parse HEAD
```

Platzhalter aus dem geprüften Commit-Scope ableiten.

## Grenzen

- Zustandsverändernd arbeiten: Es werden ausschließlich lokale Commits erstellt.
- Keine Remote-Operationen ausführen; insbesondere nicht fetchen, pullen oder pushen.
- Keine unzusammenhängenden oder fremden Änderungen in einen Commit aufnehmen.
- Bei gemischtem Worktree logisch getrennte Commits erstellen, wenn die Trennung fachlich eindeutig ist.
- Nachfragen, wenn Dateien nicht eindeutig einem Änderungssatz zugeordnet werden können.
- Kein Hunk-Staging verwenden; nur ganze Dateien stagen.
- Kein `git add -A` verwenden, wenn der Scope nicht eindeutig den gesamten Worktree umfasst.
- Keine leeren Commits erstellen, außer der User verlangt das ausdrücklich.
- Bestehende Commits nicht amendieren, umschreiben oder zusammenfassen, außer der User verlangt das ausdrücklich.
- Keine Tests, Builds oder Diff-Reviews ersetzen; fehlende Verifikation oder Review als Blocker bzw. Risiko benennen.
- Commit-Message im Format `<type>: <kurze konkrete aenderung>` formulieren.
- Erlaubte Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`, `build`.
- Commit-Message knapp, konkret und ohne Punkt am Ende formulieren.

## Output

- Commit-Message und Commit-Hash je erstelltem Commit
- nicht committete Änderungen
- Test- und Review-Status
- Blocker oder Scope-Hinweise

## Qualitätskriterien

- Jeder Commit muss einen fachlich zusammenhängenden Änderungssatz enthalten.
- Commit-Message muss die konkrete Änderung statt der Aktivität beschreiben.
- Ein erfolgreicher Commit darf nicht als Push dargestellt werden.
