# Skill: GitHub Push

## Zweck

Bereits vorhandene lokale Commits eines Branches auf dessen konfigurierten Remote-Upstream pushen oder einen neuen Branch bei eindeutigem Push-Ziel erstmals veröffentlichen.

## Verwenden

- Wenn lokale Commits vorhanden sind, die noch nicht auf dem konfigurierten Upstream liegen.
- Wenn ein lokaler Branch noch keinen Upstream besitzt und erstmals auf einen eindeutig bestimmbaren Remote unter demselben Branchnamen gepusht werden soll.
- Wenn der User nur einen Push ohne neuen Commit beauftragt.
- Nicht verwenden, wenn lokale Änderungen zuerst committet werden sollen. Dann `github-commit` nutzen.
- Nicht verwenden, wenn Commit und Push zusammenhängend ausgeführt werden sollen. Dann den Workflow `commit-push.md` nutzen.

## Vorgehen

1. Aktuellen Branch, Arbeitsstatus und konfigurierten Upstream bestimmen.
2. Wenn ein Upstream existiert, dessen Remote und Remote-Branch als Push-Ziel verwenden.
3. Wenn kein Upstream existiert, den Push-Remote in dieser Reihenfolge bestimmen: explizite User-Vorgabe, `branch.<branch>.pushRemote`, `remote.pushDefault`, `branch.<branch>.remote` oder genau ein vorhandener Remote. Den lokalen Branchnamen als Remote-Branch verwenden.
4. Stoppen, wenn bei fehlendem Upstream Remote oder Zielbranch nicht eindeutig und sicher bestimmbar sind.
5. Remote-Status fetchen und prüfen, ob der Zielbranch bereits auf dem Remote existiert.
6. Bei vorhandenem Remote-Branch den Ahead-/Behind-Status zwischen lokalem Branch und Remote-Branch bestimmen.
7. Stoppen, wenn der Remote-Branch voraus bzw. mit dem lokalen Branch divergiert ist.
8. Ohne Push abschließen, wenn ein bestehender Upstream bereits synchron ist.
9. Vorhandene lokale Commits pushen. Bei fehlendem Upstream den Branch mit `--set-upstream` auf das zuvor bestimmte Push-Ziel veröffentlichen.
10. Remote-Status erneut lesen und den synchronen Stand sowie den konfigurierten Upstream verifizieren.

## Kommandos

```powershell
git status --short --branch
git branch --show-current
git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}"
git config --get "branch.<branch>.pushRemote"
git config --get remote.pushDefault
git config --get "branch.<branch>.remote"
git remote
git fetch <remote>
git rev-list --left-right --count "HEAD...@{upstream}"
git rev-list --left-right --count "HEAD...refs/remotes/<remote>/<branch>"
git log --oneline "@{upstream}..HEAD"
git push
git push --set-upstream <remote> "HEAD:<branch>"
git rev-list --left-right --count "HEAD...@{upstream}"
```

Branch, Remote und Upstream aus dem geprüften Repository-Zustand ableiten. `git push --set-upstream` nur bei bisher fehlendem Upstream und eindeutig bestimmtem Ziel verwenden.

## Grenzen

- Extern wirksam arbeiten: Bereits vorhandene lokale Commits werden gepusht.
- Keine Dateien stagen und keine Commits erstellen, amendieren oder umschreiben.
- Kein Pull, Merge oder Rebase ausführen.
- Einen vorhandenen Upstream nicht automatisch ändern.
- Einen fehlenden Upstream nur beim ersten Push setzen, wenn Remote und gleichnamiger Zielbranch eindeutig und sicher bestimmt sind.
- Kein Force-Push und keine Umgehung von Branch-Regeln verwenden.
- Keine Tags pushen, außer der User verlangt das ausdrücklich.
- Uncommittete Änderungen dürfen nicht als Teil des Pushes dargestellt werden und müssen im Abschluss genannt werden.
- Bei mehrdeutigem Push-Ziel, Remote-Vorsprung, Divergenz, Berechtigungsfehlern oder abgelehntem Push stoppen und den lokalen Zustand unverändert lassen.

## Output

- gepushte Commit-Hashes oder Hinweis, dass nichts zu pushen war
- Remote, Upstream und Branch; bei einem Erst-Push zusätzlich der neu gesetzte Upstream
- verifizierter Ahead-/Behind-Status
- nicht gepushte uncommittete Änderungen
- Blocker, falls der Push nicht ausgeführt wurde

## Qualitätskriterien

- Nur bereits vorhandene lokale Commits dürfen veröffentlicht werden.
- Erfolg muss durch einen synchronen lokalen und entfernten Branch verifiziert werden.
- Ein erfolgreicher Push darf nicht als Commit-Erstellung dargestellt werden.
