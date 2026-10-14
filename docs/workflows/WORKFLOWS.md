# WORKFLOWS.md

## Zweck

Dieser Katalog definiert stabile Workflow-IDs, Aliase und Owner. Er ist Routing-Metadatum und enthält keine operative Regel. Workflows dürfen nur von ihrer Owner-Rolle gelesen werden.

## Workflows

| ID | Workflow | Direkte Aliase | Owner / Modus | Lesen und verwenden, wenn | Detaildatei |
|---|---|---|---|---|---|
| `issue-acceptance-convergence` | Issue Acceptance Convergence | `/acceptance <issue-number>` | `koordinator` / Delegationsplan | Akzeptanzkriterien eines Root-Issues und Child-Graphen gegen den integrierten Stand geprüft und Gaps konvergiert werden sollen. | [issue-acceptance-convergence.md](https://heljens-it-services.github.io/agent-organization/workflows/issue-acceptance-convergence.md) |
| `bugfix` | Bugfix | `/bugfix` | `koordinator` / Delegationsplan | Ein Fehler auf dem aktuellen Branch analysiert, behoben und abgesichert werden soll. | [bugfix.md](https://heljens-it-services.github.io/agent-organization/workflows/bugfix.md) |
| `bugfix-from-default` | Bugfix From Default | `/bugfix from-default` | `koordinator` / Delegationsplan | Ein isolierter Bugfix von der Standardbasis bis zum Pull Request bearbeitet werden soll. | [bugfix-from-default.md](https://heljens-it-services.github.io/agent-organization/workflows/bugfix-from-default.md) |
| `commit-history-summary` | Commit History Summary | `/summary [<period> ...] [--mode <mode>]` | `koordinator` / Delegationsplan | Änderungen aus Commits und gemergten Pull Requests für einen Zeitraum zusammengefasst werden sollen. | [commit-history-summary.md](https://heljens-it-services.github.io/agent-organization/workflows/commit-history-summary.md) |
| `commit-push` | Commit Push | `/cp` | `softwareentwicklung_infrastruktur` / operativ | Fertige lokale Änderungen im ausdrücklich beauftragten Umfang committet und gepusht werden sollen. | [commit-push.md](https://heljens-it-services.github.io/agent-organization/workflows/commit-push.md) |
| `design-exploration` | Design Exploration | `/design-explore` | `designer` / operativ | Eine visuelle oder interaktive Lösung exploriert, visualisiert und reviewed werden soll. | [design-exploration.md](https://heljens-it-services.github.io/agent-organization/workflows/design-exploration.md) |
| `feature-finish` | Feature Finish | `/finish` | `koordinator` / Delegationsplan | Ein freigegebener Arbeitsbranch sicher committed, geprüft, gemergt und abgeschlossen werden soll. | [feature-finish.md](https://heljens-it-services.github.io/agent-organization/workflows/feature-finish.md) |
| `issue-graph-implementation` | Issue Graph Implementation | `/implement <issue-number>` | `koordinator` / Delegationsplan | Ein Issue-Graph bis zur verifizierten Implementierung und einem finalen Pull Request bearbeitet werden soll. | [issue-graph-implementation.md](https://heljens-it-services.github.io/agent-organization/workflows/issue-graph-implementation.md) |
| `issue-sanitize` | Issue Graph Sanitization | `/sanitize <issue-number>` | `product_owner` / operativ | Ein Issue-Graph auf native GitHub-Issue-Types und Relationships geprüft und eindeutig ableitbare Metadaten korrigiert werden sollen. | [issue-sanitize.md](https://heljens-it-services.github.io/agent-organization/workflows/issue-sanitize.md) |
| `insight-to-issue` | Insight To Issue | - | `koordinator` / Delegationsplan | Eine Erkenntnis als strukturiertes GitHub-Issue erfasst werden soll. | [insight-to-issue.md](https://heljens-it-services.github.io/agent-organization/workflows/insight-to-issue.md) |
| `instruction-improvement-issue` | Instruction Improvement Issue | - | `koordinator` / Delegationsplan | Ein Verbesserungsvorschlag für Agentenregeln als Issue erfasst werden soll. | [instruction-improvement-issue.md](https://heljens-it-services.github.io/agent-organization/workflows/instruction-improvement-issue.md) |
| `issue-to-pr` | Issue To PR | - | `koordinator` / Delegationsplan | Ein Ticket bis zur Pull-Request-Erstellung überführt werden soll. | [issue-to-pr.md](https://heljens-it-services.github.io/agent-organization/workflows/issue-to-pr.md) |
| `issue-to-sub-issues` | Issue To Sub Issues | `/sub-issues <issue-number>`<br>`/sub-issues <issue-number> flat` | `product_owner` / operativ | Ein Issue rekursiv oder flach in Child-Issues zerlegt werden soll. | [issue-to-sub-issues.md](https://heljens-it-services.github.io/agent-organization/workflows/issue-to-sub-issues.md) |
| `issue-to-sub-issues-flat` | Issue To Sub Issues Flat | - | `product_owner` / operativ | Genau eine Child-Ebene erzeugt werden soll. | [issue-to-sub-issues-flat.md](https://heljens-it-services.github.io/agent-organization/workflows/issue-to-sub-issues-flat.md) |
| `issue-implementation` | Issue Implementation | - | `koordinator` / Delegationsplan | Ein einzelnes Arbeitspaket implementiert, unabhängig verifiziert und für den vereinbarten Git-Abschluss vorbereitet werden soll. | [issue-implementation.md](https://heljens-it-services.github.io/agent-organization/workflows/issue-implementation.md) |
| `project-implementation-planning` | Project Implementation Planning | - | `product_owner` / operativ | Ein durch freigegebene Strategie geklärtes Projektziel in ausdrücklich freizugebende große Phasen strukturiert werden soll. | [project-implementation-planning.md](https://heljens-it-services.github.io/agent-organization/workflows/project-implementation-planning.md) |
| `online-publication-check` | Online-Publikation prüfen | - | `softwareentwicklung_qualitaetssicherung` / operativ, read-only | GitHub-Pages-Quelle, Erreichbarkeit, Vernetzung und Inhalte der Veröffentlichung geprüft werden sollen. | [online-publikation-pruefen.md](https://heljens-it-services.github.io/agent-organization/workflows/online-publikation-pruefen.md) |
| `refactoring-secure` | Refactoring Secure | - | `koordinator` / Delegationsplan | Verhaltenserhaltendes Refactoring geplant, umgesetzt und abgesichert werden soll. | [refactoring-secure.md](https://heljens-it-services.github.io/agent-organization/workflows/refactoring-secure.md) |
| `release` | Release | `/release` | `koordinator` / Delegationsplan | Der freigegebene Stand von `develop` kontrolliert nach `main` veröffentlicht werden soll. | [release.md](https://heljens-it-services.github.io/agent-organization/workflows/release.md) |
| `specialist-implementation` | Specialist Implementation | - | `softwareentwicklung_backend`, `softwareentwicklung_frontend`, `softwareentwicklung_infrastruktur` / operativ nach Änderungsscope | Ein geklärter technischer Auftrag innerhalb der eigenen Implementierungszuständigkeit umgesetzt werden soll. | [specialist-implementation.md](https://heljens-it-services.github.io/agent-organization/workflows/specialist-implementation.md) |
| `architecture-planning` | Architecture Planning | - | `softwareentwicklung_architektur` / operativ | Eine technische Strukturentscheidung oder ein technischer Umsetzungsplan gebraucht wird. | [architecture-planning.md](https://heljens-it-services.github.io/agent-organization/workflows/architecture-planning.md) |
| `specialist-verification` | Specialist Verification | - | `softwareentwicklung_qualitaetssicherung` / operativ | Eine Änderung unabhängig anhand von Akzeptanzkriterien geprüft werden soll. | [specialist-verification.md](https://heljens-it-services.github.io/agent-organization/workflows/specialist-verification.md) |

## Routing- und Argument-Metadaten

[MUST] Der Koordinator bearbeitet Nutzercommands als Einstiegspunkt. Bei Koordinator-Workflows koordiniert er die beschriebenen Beiträge; operative Workflows weist er direkt dem ausgewiesenen Owner zu.

- `specialist-implementation`: Backend-Services, APIs und Persistenz gehen an `softwareentwicklung_backend`; Oberflächen und clientseitige Interaktionen an `softwareentwicklung_frontend`; CI, Deployment und Infrastruktur an `softwareentwicklung_infrastruktur`. Mehrere Bereiche erhalten getrennte direkte Aufträge.
- `issue-sanitize`, `issue-to-sub-issues` und `issue-to-sub-issues-flat`: `product_owner` bearbeitet User-Issues. Technical Tasks einschließlich Inhalts-, Type- und Relationship-Mutationen sowie weitere technische Issue-Beiträge werden dem Koordinator zurückgegeben und von ihm separat an `softwareentwicklung_architektur` zugewiesen. Der operative Owner delegiert selbst keine weiteren Rollen.
- `/implement`, `/sanitize`, `/acceptance` und `/sub-issues`: `<issue-number>` ist eine positive Ganzzahl mit optionalem `#`. Nur `/sub-issues` akzeptiert zusätzlich `flat`.
- `/summary`: `<period>` ist ein ISO-Datum `YYYY-MM-DD`, eine positive Tagesanzahl oder zwei ISO-Daten als inklusive Start- und Endgrenze. `--mode` akzeptiert `customer`, `technical` oder `detailed`; Default ist `customer`. Zeitraumwerte dürfen aus eindeutigem vorhandenem Nutzerkontext übernommen werden; andernfalls fragt der Koordinator vor der Datenerhebung nach. Repository und Branch folgen dem vorhandenen Kontext beziehungsweise dem aktuellen Repository und seinem Default-Branch.
- Historisch dokumentierte Summary-Zeitraumwerte `7 Tage` und `2026-07-01 bis 2026-07-15` sowie `mode: technical` bleiben als kompatible Argumentformen zulässig. Sie werden auf denselben Zeitraum und Modus normalisiert. Die englischen Command-Namen, IDs und kanonischen Optionen bleiben unverändert.
- Direkte Aliase und `/workflows run <workflow-id>` verwenden dieselben Argumente. Nicht dokumentierte Zusatzargumente sind ungültig. Die Detailvalidierung erfolgt vor operativen Schritten durch den Owner.

## Rollenbasierte Freigabe

[MUST] Die Owner-Spalte ist Routing-Metadatum. Nur die jeweilige Owner-Rolle darf die Workflow-Detaildatei laden und ausführen.

[MUST] Koordinator-Workflows beschreiben ausschließlich die Auswahl, Phasenfolge und Delegation. Jeder operative Schritt ist ein Auftrag an die angegebene Spezialistenrolle.

[MUST_NOT] `koordinator` darf keine operativen Regeln aus Workflow-Detaildateien ausführen. Er liest nur Workflow-Details aus seiner eigenen Owner-Menge.

[MUST_NOT] Ein operativer Spezialist darf einen Koordinator-Workflow nicht übernehmen, selbst delegieren oder fremde Rollenregeln laden.

