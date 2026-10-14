# Workflow: Commit Push

## Owner und Modus

`softwareentwicklung_infrastruktur` liest und führt diesen operativen Ablauf aus. Der Koordinator weist den Auftrag bei Bedarf dieser Rolle zu, führt aber keine Git-Aktion aus und lädt diesen Workflow nicht.

## Ziel

Einen abgeschlossenen lokalen Änderungssatz logisch committen und die neu erstellten Commits anschließend auf den konfigurierten Upstream pushen.

## Verwenden

- Wenn der User `/cp` oder gleichbedeutend Commit und Push als zusammenhängenden Ablauf beauftragt.
- Wenn Änderungen fertig, getestet und reviewed sind.
- Nicht verwenden, wenn nur ein lokaler Commit gewünscht ist. Dann `/commit` beziehungsweise `github-commit` nutzen.
- Nicht verwenden, wenn nur vorhandene Commits gepusht werden sollen. Dann `/push` beziehungsweise `github-push` nutzen.

## Verwendete Skills

- `github-commit`
- `github-push`

## Ablauf

1. Task-Scope, Teststatus, Review-Status, Branch und Arbeitsstatus bestimmen.
2. Vor dem Commit das Push-Ziel und den Remote-Status nach den Regeln von `github-push` prüfen.
3. Stoppen, wenn Scope, Teststatus, Review-Status oder Push-Status keinen sicheren Commit mit anschließendem Push erlauben.
4. Mit `github-commit` ausschließlich den taskbezogenen Änderungssatz committen.
5. Mit `github-push` die neu erstellten Commits auf den konfigurierten Upstream pushen oder den Branch bei eindeutigem Ziel erstmals veröffentlichen.
6. Commit-Hashes, Messages, Push-Ziel und synchronen Abschlusszustand ausgeben.

## Rücksprungregeln

- Bei unklarem oder gemischtem Commit-Scope zu `github-commit` zurückkehren und die Trennung klären.
- Bei fehlender Verifikation oder nicht versandbereitem Review zur passenden vorgelagerten Umsetzung oder Prüfung zurückkehren.
- Wenn der Commit fehlschlägt, keinen Push ausführen.
- Wenn der Push fehlschlägt, den lokalen Commit erhalten und den Push-Blocker melden.

## Endergebnis

- taskbezogene Änderungen sind logisch committed
- erstellte Commits sind auf den konfigurierten Upstream gepusht
- lokaler Branch und Upstream sind synchron
- nicht zum Scope gehörende Änderungen bleiben unverändert

## Grenzen

- Bei bekanntem Remote-Vorsprung, Divergenz oder mehrdeutigem Push-Ziel keinen lokalen Commit beginnen.
- Ein fehlender Upstream ist kein Blocker, wenn `github-push` Remote und gleichnamigen Zielbranch eindeutig und sicher bestimmen kann.
- Keinen Pull Request erstellen.
- Keine fehlgeschlagene Commit- oder Push-Phase als vollständigen Erfolg darstellen.
