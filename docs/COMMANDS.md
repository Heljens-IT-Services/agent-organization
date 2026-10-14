# COMMANDS.md

## Zweck

Diese Datei definiert die host-unabhängige Slash-Command-Sprache für Navigation, Detailanzeige und bewusste Auswahl veröffentlichter Katalogeinträge.

## Grundregeln

[MUST] Natürliche User-Anfragen und die automatische kontextbezogene Auswahl von Skills und Workflows müssen weiterhin funktionieren.

[MUST] Ein Slash-Command muss als User-Anweisung innerhalb der bestehenden Sicherheits-, Berechtigungs-, Prioritäts-, Scope- und Rückfrageregeln behandelt werden.

[MUST_NOT] Ein Slash-Command darf keine weitergehende Autorisierung ableiten, als seine dokumentierte Semantik und der konkrete User-Kontext hergeben.

[MUST] Die Command-Grammatik und die allgemeinen Auflösungsregeln müssen ausschließlich in dieser Datei gepflegt werden.

[MUST] Stabile IDs und direkte Aliase müssen ausschließlich im jeweils zuständigen Katalog gepflegt werden:

- Skills in [SKILLS.md](https://heljens-it-services.github.io/agent-organization/skills/SKILLS.md)
- Workflows in [WORKFLOWS.md](https://heljens-it-services.github.io/agent-organization/workflows/WORKFLOWS.md)
- Technologien in [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md)

## Rollenbindung

[MUST] Jeder Nutzercommand wird vom Koordinator entgegengenommen, normalisiert und anhand der Katalogmetadaten aufgelöst. Er führt eigene Routing- und Koordinationsschritte aus und übergibt operative Ausführung oder Detailauskunft direkt an die zuständige Rolle. Ein Spezialist gibt einen neu eingehenden Nutzercommand an den Koordinator zurück; die Ausführung eines bereits zugewiesenen Auftrags bleibt in seiner eigenen Rolle.

[MUST] Für jeden operativen Beitrag wird genau ein zuständiger Owner anhand des Auftrags und der Routing-Kriterien bestimmt. Bei mehreren betroffenen Fachbereichen teilt der Koordinator den Auftrag in abgegrenzte direkte Rollenaufträge. Die Kataloge beschreiben zulässige Owner und Auswahlkriterien, keine feste zusätzliche Delegationsstufe.

[MUST] Bei ausreichendem Ziel-, Scope-, Argument- und Berechtigungskontext veranlasst der Koordinator die dokumentierte Ausführung unmittelbar. Er fragt nur nach Informationen, Entscheidungen oder Freigaben, die zur sicheren Ausführung tatsächlich fehlen. Ein gültiger Command ersetzt keine vorgeschriebene Freigabe.

[MUST] Der aktuelle Agent handelt ausschließlich in der in seinem Einstiegspunkt festgelegten Rolle. Rollenwechsel erfolgen durch Delegation an einen verfügbaren Agenten mit passender Rollen-ID; ein Slash-Command aktiviert keine andere Rolle.

[MUST] `/skills list`, `/workflows list` und `/technologies list` zeigen einer operativen Rolle nur die Einträge, die deren eigener Rollenindex freigibt. Der Koordinator erhält nur seine eigenen Einträge sowie die Routing-Metadaten aus den Katalogen.

[MUST] Der Koordinator darf bei `/skills run <skill-id>` einen Fachskill anhand seiner Katalogmetadaten an die Owner-Rolle delegieren, ohne dessen Detaildatei zu laden. Bei `/workflows run <workflow-id>` darf er nur seine eigenen Koordinator-Workflows laden und ausführen; operative Workflows delegiert er an deren Owner.

[MUST] `/skills show <skill-id>`, `/workflows show <workflow-id>` und `/technologies show <technology-id>` geben dem Koordinator bei fremdem Owner Routing-Metadaten aus und delegieren die fachliche Detailauskunft an die zuständige Rolle. Operative Rollen dürfen nur Details zu ihren freigegebenen Skills, Workflows und Technologien laden.

[MUST] Koordinator-Aufträge an Spezialisten müssen Ziel, Scope, Nicht-Scope, relevanten Kontext, Constraints, Entscheidungen, erwartetes Ergebnis und Rückgabeanforderungen enthalten.

[MUST_NOT] Der Koordinator darf operative Recherche, Codearbeit, Issue-Arbeit, Dokumentation, Tests, Git- oder GitHub-Aktionen nicht selbst ausführen. Fehlende Spezialisten oder Tool-Fähigkeiten begründen keinen Rollenwechsel.

## Dispatch und Argumentprüfung

1. Den vollständigen Command gegen Root-Syntax oder einen dokumentierten Alias auflösen; IDs und Aliase bleiben in ihren Katalogen definiert.
2. Aktion und Argumente prüfen. `list`, `show` und Hilfe liefern ausschließlich Auskunft. `run` und direkte Ausführungsaliase starten den dokumentierten Auftrag.
3. Owner anhand des aktuellen Auftrags und der Routing-Kriterien im zuständigen Katalog bestimmen. Bereits übergebene eindeutige Zuständigkeiten bleiben für denselben Scope gültig.
4. Der ausgewählte Owner prüft die Detailargumente, Verwendungskriterien, verfügbaren Ressourcen und erforderlichen Berechtigungen vor jedem operativen Schritt. Ungültige Argumente werden mit erwarteter Syntax zurückgegeben; daraus entsteht keine Teilmutation.
5. Den abgegrenzten Auftrag ausführen lassen und Ergebnis, Verifikation, Abweichungen und Blocker bündeln. Fehlende notwendige Angaben werden gezielt geklärt; ein anderer Rollenauftrag wird ausschließlich durch den Koordinator erteilt.

[MUST] Bei einer Katalogauflösung bleibt die Fachdatei beim ausgewählten Owner. Der Koordinator liest Argument- und Routing-Metadaten, nicht die operativen Details anderer Rollen.

[MUST] Issue-Nummern in `/implement`, `/sanitize`, `/acceptance` und `/sub-issues` sind positive Ganzzahlen mit optionalem führendem `#`. `flat` ist nur bei `/sub-issues` das optionale zweite Positionsargument. Die kanonischen Workflow-Aufrufe akzeptieren dieselben Argumente.

[MUST] `/testing` akzeptiert höchstens einen Modus aus `auto`, `build`, `unit`, `integration`, `e2e` und `all`; ohne Modus gilt `auto`. Die Owner-Auswahl folgt den Routing-Kriterien für `code-testing` und ist unabhängig von der gewählten Prüfebene.

[MUST] `/summary` und `/workflows run commit-history-summary` verwenden denselben Zeitraum- und Optionsvertrag aus dem Workflow-Katalog. Fehlt der Zeitraum auch im vorhandenen Nutzerkontext, wird er vor der Datenerhebung erfragt.

## Grammatik

```ebnf
input       = spacing, "/", root, { separator, token }, spacing ;
root        = name | "?" ;
token       = option | quoted | bare ;
option      = "--", name, [ "=", value ] ;
quoted      = '"', { character - '"' }, '"' ;
bare        = character - ( " " | tab ), { character - ( " " | tab ) } ;
name        = letter-or-digit, { letter-or-digit | "-" } ;
value       = quoted | bare ;
separator   = ( " " | tab ), spacing ;
spacing     = { " " | tab } ;
```

[MUST] Root-Commands, Subcommands, IDs und Aliase müssen in kanonischer Form aus Kleinbuchstaben, Ziffern und Bindestrichen bestehen.

[MUST] Die Auflösung von Root-Commands, Subcommands, IDs und Aliasen muss ohne Beachtung der Groß-/Kleinschreibung erfolgen und im Ergebnis die kanonische Schreibweise ausgeben.

[MUST] Mehrere Tokens müssen durch Leerraum getrennt werden. Doppelte Anführungszeichen dürfen Leerraum innerhalb eines Arguments erhalten.

[MUST] Optionen müssen mit `--` beginnen. Die Formen `--name value` und `--name=value` sind zulässig, sofern der konkrete Command die Option dokumentiert.

[MUST] Nicht dokumentierte Optionen, doppelte nicht wiederholbare Optionen und nicht geschlossene Anführungszeichen müssen als ungültige Eingabe behandelt werden.

## Stabile IDs und Aliase

[MUST] Jeder veröffentlichte Katalogeintrag muss genau eine stabile ID im zuständigen Katalog besitzen.

[MUST] Eine stabile ID muss dem Muster `^[a-z0-9]+(?:-[a-z0-9]+)*$` entsprechen und innerhalb ihres Katalogs eindeutig sein.

[MUST] Die kanonischen Aufrufe eines Katalogeintrags müssen aus Root-Command, Aktion und stabiler ID gebildet werden, beispielsweise `/skills show code-reading` oder `/workflows run bugfix`.

[ALLOW] Ein Katalogeintrag darf zusätzlich einen oder mehrere direkte Aliase aus einem oder mehreren Tokens wie `/finish` oder `/release` besitzen.

[MUST] Direkte Aliase müssen global eindeutig sein und dürfen weder Root-Commands noch Help-Aliase verdecken.

[ALLOW] Ein direkter Alias darf erforderliche Positionsargumente als Platzhalter wie `<issue-number>` dokumentieren.

[MUST] Direkte Aliase müssen vor der Root-Command-Auflösung gegen die vollständige normalisierte Eingabe und die dokumentierte Alias-Syntax abgeglichen werden.

[MUST] Die öffentliche Command-Sprache verwendet ausschließlich englische Aliase, stabile IDs und Syntax-Platzhalter.

[MUST_IF] Wenn ein Alias Positionsargumente definiert, müssen Anzahl, Reihenfolge und Format der Argumente in der Detaildatei des Katalogeintrags dokumentiert und bei der Auflösung validiert werden.

[MUST_IF] Wenn ein Alias Präfix eines anderen Alias ist, darf nur eine exakte vollständige Tokenfolge oder eine vollständig passende dokumentierte Alias-Syntax aufgelöst werden; nicht dokumentierte weitere Tokens sind ungültig.

[MUST] Ein direkter Alias muss dieselbe Semantik und dieselben Grenzen wie der kanonische Aufruf seines Katalogeintrags behalten.

[MUST_NOT] Bei einer mehrdeutigen ID oder einem mehrdeutigen Alias darf der Agent keine Auswahl raten.

## Root-Commands

| Command | Syntax | Verhalten |
|---|---|---|
| Help | `/help`, `/?` | Zeigt die allgemeine Hilfe. |
| Kontext-Hilfe | `/help <command>` | Zeigt Syntax, Subcommands und Beispiele für einen Root-Command oder direkten Alias. |
| Skills | `/skills list`, `/skills show <skill-id>`, `/skills run <skill-id> [<argument> ...]` | Listet, beschreibt oder wählt einen für die aktuelle Rolle freigegebenen Skill aus; der Koordinator delegiert operative Skills an deren Owner. |
| Workflows | `/workflows list`, `/workflows show <workflow-id>`, `/workflows run <workflow-id> [<argument> ...]` | Listet, beschreibt oder startet einen für die aktuelle Rolle freigegebenen Workflow; der Koordinator führt nur Koordinator-Workflows aus. |
| Technologien | `/technologies list`, `/technologies show <technology-id>` | Listet oder beschreibt nur die für die aktuelle Rolle freigegebenen technologiespezifischen Regeldatei-Mappings. |

## Semantik

### `list`

[MUST] `list` gibt dem Nutzer über den Koordinator die Katalogmetadaten mit kanonischer ID, Name, Kurzbeschreibung, Owner und vorhandenem direkten Alias aus. Eigene ausführbare Koordinationsressourcen und delegierbare operative Einträge werden unterscheidbar dargestellt. Ein operativer Spezialist erhält für seinen zugewiesenen Auftrag ausschließlich Einträge seines eigenen Rollenindex.

[MUST_NOT] `list` darf keinen Skill oder Workflow ausführen.

### `show`

[MUST] `show` muss für die aktive Rolle den durch die ID bezeichneten Katalogeintrag und dessen freigegebene Detaildatei laden und Zweck, Verwendung, Grenzen und Quelle knapp wiedergeben. Der Koordinator delegiert die Detailauskunft zu operativen Einträgen an den Owner und lädt deren Fachdatei nicht.

[MUST_NOT] `show` darf den bezeichneten Skill oder Workflow nicht ausführen.

### `technologies`

[MUST] `/technologies list` gibt dem Koordinator jede Technologie-ID genau einmal als Routing-Metadatum mit verfügbaren Ownern und knapper Zweckbeschreibung. Ein operativer Spezialist erhält ausschließlich die für seinen Auftrag freigegebenen Mappings seiner eigenen Rolle.

[MUST] `/technologies show <technology-id>` muss die für die aktive Rolle freigegebenen Mappings mit Rolle, Regeldatei, Verwendungskriterium und Zweck beschreiben. Der Koordinator delegiert die fachliche Detailauskunft an den betreffenden Spezialisten.

[MUST_NOT] `/technologies list` und `/technologies show <technology-id>` dürfen allein durch die ausgewählte Technologie keine zusätzliche Rolle aktivieren oder eine Regeldatei außerhalb ihres Verwendungskriteriums anwenden.

### `run`

[MUST] `run` muss einen Eintrag aus der Freigabe der aktiven Rolle auswählen und dessen Regeln ausführen. Der Koordinator lädt nur eigene Koordinator-Skills und -Workflows; bei operativen Skills und Workflows delegiert er an den ausgewiesenen Owner.

[MUST] Fehlender Task-Kontext oder eine durch den ausgewählten Eintrag vorgeschriebene Rückfrage muss weiterhin geklärt werden.

[MUST_IF] Wenn ein Skill Positionsargumente dokumentiert, muss `run` sie in derselben Anzahl, Reihenfolge und demselben Format wie seine direkten Aliase akzeptieren.

[MUST_IF] Wenn ein Workflow Positionsargumente dokumentiert, muss `run` sie in derselben Anzahl, Reihenfolge und demselben Format wie seine direkten Aliase akzeptieren.

[MUST_NOT] Nicht dokumentierte Positionsargumente dürfen an `run` oder direkte Aliase übergeben werden.

[MUST_IF] Wenn die Verwendungskriterien einer gültigen ID nicht erfüllt sind, muss der Agent stoppen, die Unpassung benennen und auf einen passenden Eintrag oder eine natürliche Anfrage verweisen.

[MUST_NOT] `run` darf Grenzen des ausgewählten Eintrags oder höherrangige Regeln nicht umgehen.

## Hilfe und Fehlerverhalten

[MUST] `/help` muss die verfügbaren Root-Commands, Help-Aliase, die Grundsyntax und mindestens je ein Beispiel für `list`, `show` und `run` nennen.

[MUST] Die allgemeine Hilfe muss direkte Aliase getrennt von Root-Commands mit Katalogtyp und kanonischem Aufruf ausweisen.

[MUST_NOT] Die allgemeine Hilfe darf direkte Skill- oder Workflow-Aliase als Root-Commands darstellen.

[MUST] `/help` und `/?` müssen ohne weiteres Argument `README.md` und `PROJECT.md` durch `product_owner` lesen lassen und die aktuell relevanten Kernaussagen unter `Repository-Kontext` knapp zusammenfassen. Der Koordinator delegiert diesen Leseauftrag.

[MUST] Der Repository-Kontext muss sich auf Zweck, Versionsbasis und für die Nutzung wesentliche fachliche oder technische Leitplanken beschränken und in der Regel zwei bis vier kurze Punkte umfassen.

[MUST_NOT] Der Repository-Kontext darf ganze Abschnitte, Detailstrukturen oder für die aktuelle Orientierung irrelevante Inhalte aus `README.md` und `PROJECT.md` nicht wiederholen.

[MUST_IF] Wenn `README.md` oder `PROJECT.md` fehlt oder nicht gelesen werden kann, muss die Hilfe dies knapp benennen und darf fehlende Inhalte nicht erfinden.

[MUST] `/help <command>` muss den Namen mit oder ohne führenden Slash akzeptieren und die kanonische Syntax, Subcommands, Argumente, Aliase und Beispiele des Ziels nennen. Gehört das Ziel einer operativen Rolle, delegiert der Koordinator die Detailauskunft an deren Owner und lädt die Fachdatei nicht selbst.

[MUST_IF] Wenn ein Root-Command ohne erforderlichen Subcommand eingegeben wird, muss die kontextspezifische Hilfe mit den gültigen Subcommands ausgegeben werden.

[MUST_IF] Wenn ein erforderliches Argument fehlt, muss die Antwort die erwartete Syntax und die passende `list`-Alternative nennen.

[MUST_IF] Bei unbekanntem Root-Command, Subcommand, ID oder Alias muss die Antwort passende gültige Kandidaten nennen oder auf `/help` beziehungsweise den passenden `list`-Command verweisen.

[MUST_IF] Wenn eine Eingabe syntaktisch ungültig oder mehrdeutig ist, muss die Antwort die Ausführung stoppen, den Grund nennen und eine kanonische Beispielsyntax zeigen.

## Erweiterbarkeit

[MUST] Neue Kataloge müssen einen eindeutigen Root-Command, einen eigenen Katalog für stabile IDs und eine in dieser Datei definierte Semantik erhalten.

[MUST] Neue Subcommands und Optionen müssen rückwärtskompatibel ergänzt und vor ihrer Verwendung dokumentiert werden.

[MUST] Die Root-Namen `roles` und `actions` bleiben für spätere Kataloge reserviert.

[MUST_NOT] Ein Host darf keine abweichende Bedeutung für einen dokumentierten Command oder Alias einführen.

## Beispiele

Der direkte Workflow-Alias `/acceptance <issue-number>` akzeptiert eine positive Ganzzahl mit optionalem `#`, zum Beispiel `/acceptance 123` oder `/acceptance #123`.

`/bugfix` führt den Bugfix auf dem aktuell ausgecheckten Branch aus. `/bugfix from-default` wählt bewusst die vollständige Variante mit neuem Branch von der Standardbasis und anschließendem Pull Request.

```text
/help
/help skills
/skills list
/skills show code-reading
/skills run code-reading
/skills run code-minimization
/minimize
/skills run code-refactoring
/refactor
/skills run code-testing
/testing
/testing e2e
/skills run code-testing all
/workflows show feature-finish
/workflows run feature-finish
/workflows run bugfix
/workflows run bugfix-from-default
/bugfix
/bugfix from-default
/workflows run issue-graph-implementation 123
/workflows run issue-sanitize 123
/workflows run issue-acceptance-convergence 123
/workflows run issue-to-sub-issues 123
/workflows run issue-to-sub-issues 123 flat
/implement #123
/sanitize 123
/acceptance 123
/acceptance #123
/sub-issues #123
/sub-issues 123 flat
/finish
/release
/technologies show csharp-net
```

