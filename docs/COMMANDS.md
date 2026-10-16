# COMMANDS.md

## Zweck

Commands benennen einen Auftrag oder liefern Orientierung. Der Koordinator weist die Beiträge direkt den zuständigen Rollen zu. Die Agenten bestimmen ihr Vorgehen selbständig aus Ziel und Kontext.

## Grundregeln und Rollenbindung

[MUST] Natürliche Nutzeranfragen werden ebenso anhand ihres Ziels und Scopes zugewiesen. Der Koordinator bestimmt die Zuständigkeit anhand der [Rollen](https://heljens-it-services.github.io/agent-organization/roles/ROLES.md) und des Auftragsziels. Der beauftragte Spezialist wählt seine Wissensquellen gemäß den direkten Rollenfreigaben selbst.

[MUST] Jeder Nutzercommand wird vom Koordinator entgegengenommen und normalisiert. Spezialisten geben neu eingehende Nutzercommands an ihn zurück; bereits zugewiesene Aufträge bleiben bei ihrer Rolle.

[MUST] Der Koordinator übernimmt Routing, Übergaben und Zusammenfassung. Operative Recherche, Codearbeit, Issue-Arbeit, Dokumentation, Tests und externe Mutationen werden direkt der passenden Fachrolle zugewiesen. Mehrere Fachbereiche erhalten abgegrenzte Aufträge. Fehlende Spezialisten oder Werkzeuge werden als konkrete Blocker gemeldet.

[MUST] Aufträge enthalten Ziel, Scope, Nicht-Scope, Kontext, Entscheidungen, Constraints, erwartetes Ergebnis und Belege. Bei ausreichendem Kontext wird direkt gearbeitet; Rückfragen klären fehlende notwendige Angaben, Entscheidungen oder Freigaben.

[MUST] Commands gelten innerhalb der bestehenden Sicherheits-, Berechtigungs-, Prioritäts- und Scoperegeln. Ein Command erlaubt ausschließlich sein beschriebenes Ziel im konkreten Nutzerkontext. Erforderliche Freigaben bleiben maßgeblich.

## Grammatik und Argumente

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

[MUST] Command-Namen, Subcommands, Bereichs-IDs und Technologie-IDs werden ohne Beachtung der Groß-/Kleinschreibung aufgelöst und in kanonischer Kleinschreibung ausgegeben. Öffentliche Namen, IDs und Platzhalter sind englisch. Bereichs- und Technologie-IDs entsprechen `^[a-z0-9]+(?:-[a-z0-9]+)*$` und sind im jeweiligen Index eindeutig.

[MUST] Tokens werden durch Leerraum getrennt; doppelte Anführungszeichen erhalten Leerraum innerhalb eines Arguments. Dokumentierte Optionen unterstützen `--name value` und `--name=value`. Unbekannte Optionen, doppelte nicht wiederholbare Optionen, zusätzliche Positionsargumente und offene Anführungszeichen sind ungültig.

[MUST] Nur die vollständig passende Syntax wird aufgelöst, insbesondere bei `/bugfix from-default` und `/sub-issues <issue-number> flat`. Ungültige oder mehrdeutige Eingaben liefern Grund und passende Beispielsyntax, bevor eine Mutation erfolgt.

[MUST] `<issue-number>` ist eine positive Ganzzahl mit optionalem führendem `#`. `flat` ist ausschließlich das optionale zweite Positionsargument von `/sub-issues`.

[MUST] `/testing` akzeptiert höchstens einen Modus aus `auto`, `build`, `unit`, `integration`, `e2e` und `all`; Standard ist `auto`. Die Prüfebene ändert die fachliche Zuständigkeit nicht.

[MUST] `/summary` akzeptiert als `<period>` ein ISO-Datum `YYYY-MM-DD`, eine positive Tagesanzahl oder zwei ISO-Daten als inklusive Start- und Endgrenze. `--mode` akzeptiert `customer`, `technical` oder `detailed`; Standard ist `customer`. Kompatible Formen wie `7 Tage`, `2026-07-01 bis 2026-07-15` und `mode: technical` werden auf denselben Vertrag normalisiert. Ein eindeutiger Zeitraum darf aus dem Nutzerkontext übernommen werden; andernfalls wird er vor der Datenerhebung erfragt. Repository und Branch folgen dem vorhandenen Kontext, sonst dem aktuellen Repository und dessen Default-Branch.

## Auskunft

| Command | Ergebnis |
|---|---|
| `/help`, `/?` | Allgemeine Hilfe mit Syntax, Commands und Beispielen. `product-owner` liest README.md und PROJECT.md und liefert zwei bis vier relevante Punkte zum Repository-Kontext. Fehlende Quellen werden kenntlich gemacht. |
| `/help <command>` | Syntax, Argumente und Beispiele des Commands; der Name ist mit oder ohne führenden Slash zulässig. Fachliche Details liefert die zuständige Rolle. |
| `/know-how list` | Bereichs-IDs mit Name, Inhalt und Bereichsindex aus dem Know-how-Index. |
| `/know-how show <area-id>` | Name, Inhalt und Index des Wissensbereichs; fachliche Detailauskunft bleibt bei der zuständigen Rolle. |
| `/technologies list` | Jede Technologie-ID einmal mit Name, Zweck und verfügbaren Rollen; Spezialisten erhalten die Mappings ihrer eigenen Rolle. |
| `/technologies show <technology-id>` | Rolle, Regeldatei, Verwendungskriterium, Zweck und Quelle der freigegebenen Mappings. Fachliche Detailauskunft wird dem betreffenden Spezialisten zugewiesen. |

[MUST] Der Koordinator delegiert `/know-how`- und `/technologies`-Auskünfte anhand von Rollenverzeichnis und Auftragsziel an einen passenden Spezialisten. Er lädt dafür weder Indizes noch Inhalte des Know-how-Bereichs. Fehlt eine passende Rolle oder bleibt die Zuständigkeit unklar, meldet er das konkrete Hindernis.

[MUST] Der beauftragte Spezialist löst bei `/technologies list` und `/technologies show <technology-id>` die Technologie über `id` in `technology.index.json` auf. Rollen, zusätzliche Regeldateien und Verwendungskriterien stammen aus den direkten Rollentabellen; `inhalt` dient der Beschreibung, nicht der ID-Auflösung. Er gibt die für seine Rolle freigegebenen Mappings vollständig aus.

[MUST] Hilfe, Know-how- und Technologieauskünfte sind reine Navigation. Sie aktivieren keine Rolle oder Regeldatei und ändern weder Verwendungskriterien noch Quellenfreigaben.

## Direkte Aufträge

Die folgende Tabelle beschreibt Ziel und Zuständigkeit, keine vorgeschriebene Schrittfolge. Fachliche Rollenregeln und Projektvorgaben bleiben maßgeblich.

| Command | Ziel | Direkte Zuständigkeit |
|---|---|---|
| `/minimize` | Funktionierenden Änderungssatz auf begründete Bestandteile reduzieren. | Backend- bzw. Frontend-Rolle des Änderungsscopes. |
| `/refactor` | Struktur bei erhaltenem Verhalten verbessern. | Backend- bzw. Frontend-Rolle des Änderungsscopes. |
| `/testing [<test-mode>]` | Technisches Verhalten mit belegtem Ergebnis prüfen. | Qualitätssicherung; ausdrücklich lokale Verifikation eigener Änderungen beim Implementierungsowner, technische Kriterienprüfung bei Architektur. |
| `/design-prototype` | Eine Designrichtung als leichtes renderbares Artefakt visualisieren. | `designer`. |
| `/design-review` | Ein visuelles oder interaktives Ergebnis bewerten. | `designer`. |
| `/design-explore` | Eine passende visuelle oder interaktive Lösung mit begründeter Designentscheidung erarbeiten. | `designer`. |
| `/commit` | Fertige lokale Änderungen im freigegebenen Umfang logisch committen. | `infrastructure-engineer`; Veröffentlichung ist ein eigener Auftrag. |
| `/push` | Vorhandene lokale Commits auf den konfigurierten Upstream veröffentlichen. | `infrastructure-engineer`; vorhandene Commits bleiben der Umfang. |
| `/cp` | Fertige lokale Änderungen im freigegebenen Umfang committen und pushen. | `infrastructure-engineer`. |
| `/bugfix` | Fehler auf dem aktuellen Branch beheben und absichern. | Betroffene Implementierungsrolle; fachliche Klärung, Architektur und unabhängige Prüfung nach Bedarf direkt zuweisen. |
| `/bugfix from-default` | Isolierten Bugfix von der Standardbasis bis zum Pull Request bearbeiten. | Implementierungsrolle und Infrastruktur für Branch und Pull Request; unabhängige Prüfung bei Qualitätssicherung. |
| `/summary [<period> ...] [--mode <mode>]` | Änderungen aus Commits und gemergten Pull Requests im Zeitraum zusammenfassen. | Infrastruktur liefert Historienbelege; Product Owner beschreibt fachliche Auswirkungen, Architektur technische Details nach gewähltem Modus. |
| `/finish` | Freigegebenen Arbeitsbranch prüfen, committen, mergen und abschließen. | Infrastruktur für Git-Abschluss; fachliche und technische Prüfbeiträge bei ihren zuständigen Rollen. |
| `/implement <issue-number>` | Issue-Graph bis zur verifizierten Implementierung und finalem Pull Request bearbeiten. | Product Owner für fachlichen Scope, Architektur für technische Entscheidungen, betroffene Implementierungsrollen, Qualitätssicherung und Infrastruktur jeweils für ihren Beitrag. |
| `/sanitize <issue-number>` | Issue-Graph auf native GitHub-Issue-Types und Relationships prüfen und eindeutig ableitbare Metadaten korrigieren. | Product Owner für User-Issues; technische Issue-Beiträge einschließlich Technical Tasks separat an Architektur. |
| `/acceptance <issue-number>` | Akzeptanzkriterien des Root-Issues und Child-Graphen am integrierten Stand prüfen und verbleibende Gaps klären. | Product Owner für fachliche Black-Box-Abnahme, Architektur für technische Kriterien, Qualitätssicherung für unabhängige Verifikation; erforderliche Korrekturen an ihre Owner. |
| `/sub-issues <issue-number> [flat]` | Issue in passende Child-Issues zerlegen; `flat` begrenzt auf genau eine Child-Ebene, sonst wird bedarfsgerecht rekursiv strukturiert. | Product Owner für fachliche Hierarchie; technische Issues und Abhängigkeiten separat an Architektur. |
| `/release` | Freigegebenen Stand von `develop` nach `main` veröffentlichen. | Infrastruktur für Veröffentlichung; erforderliche fachliche und technische Freigaben bei den jeweiligen Rollen. |

[MUST] Zuständigkeiten werden anhand der exakten Rollen-IDs im Rollenverzeichnis aufgelöst. Backend, Frontend, Infrastruktur, Architektur und Qualitätssicherung bezeichnen dort die entsprechenden `softwareentwicklung_*`-Rollen. Je abgegrenztem Beitrag wird ein Owner ausgewählt. Fachlicher Klärungsbedarf geht an die passende Rolle; notwendige Nutzerentscheidungen werden erfragt.

## Hilfe, Fehler und Erweiterung

[MUST] Fehlende Argumente oder Subcommands liefern die erwartete Syntax. Unbekannte Commands und IDs verweisen auf passende gültige Kandidaten, `/help`, `/know-how list` oder `/technologies list`. Mehrdeutige Ziele werden vor der Ausführung geklärt.

[MUST] Command-Syntax und Auftragssemantik werden ausschließlich hier gepflegt; Bereichs-IDs im Know-how-Index, Technologie-IDs im Technologieindex und rollenbezogene Mappings in den direkten Rollentabellen. Neue Commands und Optionen werden vor ihrer Nutzung dokumentiert, global eindeutig und rückwärtskompatibel ergänzt. Hosts verwenden dieselbe dokumentierte Bedeutung. `roles` und `actions` bleiben als Root-Namen reserviert.

## Beispiele

```text
/help
/help testing
/know-how list
/know-how show technologies
/technologies list
/technologies show csharp-net
/testing e2e
/minimize
/bugfix from-default
/implement #123
/sanitize 123
/acceptance #123
/sub-issues 123 flat
/summary 7 --mode technical
/commit
/cp
/finish
/release
```
