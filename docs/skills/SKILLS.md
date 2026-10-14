# SKILLS.md

## Zweck

Dieser Katalog definiert stabile IDs, Aliase, Kurzbeschreibungen und fachliche Owner der veröffentlichten Skills. Er ist Routing-Metadatum. Jede Rolle lädt ausschließlich ihren eigenen Rollenindex und die dort verlinkten Dateien.

## Verwendung

[MUST] Operative Rollen müssen die in ihrem Rollenindex freigegebenen Skill-Dateien lesen, bevor sie diese Fähigkeiten anwenden.

[MUST] Der Koordinator nutzt IDs, verfügbare Owner, Auswahlkriterien und Kurzbeschreibungen dieses Katalogs als Routing-Metadaten. Er liest und verwendet eigene freigegebene Koordinationsskills; operative Skill-Details verbleiben beim ausgewählten Spezialisten.

[MUST_IF] Mehrere passende Skills sind anzuwenden, wenn mehrere ihrer beschriebenen Situationen eintreten und kein passender Workflow den zusammenhängenden Ablauf festlegt.

## Skills

| ID | Skill | Direkter Alias | Verfügbare Rolle(n) | Lesen und verwenden, wenn | Detaildatei |
|---|---|---|---|---|---|
| `requirements-clarification` | Requirements Clarification | - | `product_manager`, `product_owner`, `designer` | Anforderungen, Ziele, Nicht-Ziele oder Scope-Grenzen unklar sind. | [requirements-clarification.md](https://heljens-it-services.github.io/agent-organization/skills/requirements-clarification.md) |
| `brainstorming` | Brainstorming | - | `product_manager`, `product_owner`, `designer` | Denk- oder Lösungsrichtungen interaktiv entwickelt und abgewogen werden sollen. | [brainstorming.md](https://heljens-it-services.github.io/agent-organization/skills/brainstorming.md) |
| `code-analysis` | Code Analysis | - | `softwareentwicklung_architektur`, `softwareentwicklung_backend`, `softwareentwicklung_frontend`, `softwareentwicklung_infrastruktur`, `softwareentwicklung_qualitaetssicherung` | Code, Branches, Legacy-Bereiche oder Fehlverhalten im eigenen technischen Scope bewertet werden sollen. | [code-analysis.md](https://heljens-it-services.github.io/agent-organization/skills/code-analysis.md) |
| `code-diff-review` | Code Diff Review | - | `softwareentwicklung_architektur` (eigene technische Kriterien), `softwareentwicklung_qualitaetssicherung` (unabhängiger technischer Review) | Ein Änderungssatz auf technische Kriterien, Scope, Risiken oder Nebeneffekte geprüft werden soll. | [code_diff-review.md](https://heljens-it-services.github.io/agent-organization/skills/code_diff-review.md) |
| `code-implementation` | Code Implementation | - | `softwareentwicklung_backend`, `softwareentwicklung_frontend`, `softwareentwicklung_infrastruktur` (jeweils eigener Scope), `softwareentwicklung_qualitaetssicherung` (nur Testautomatisierung) | Eine geklärte technische Änderung im eigenen Rollen-Scope umgesetzt werden soll. | [code-implementation.md](https://heljens-it-services.github.io/agent-organization/skills/code-implementation.md) |
| `code-implementation-planning` | Code Implementation Planning | - | `softwareentwicklung_architektur` | Ein technischer Umsetzungsplan mit betroffenen Strukturen und Arbeitsschritten erforderlich ist. | [code-implementation-planning.md](https://heljens-it-services.github.io/agent-organization/skills/code-implementation-planning.md) |
| `code-minimization` | Code Minimization | `/minimize` | `softwareentwicklung_backend`, `softwareentwicklung_frontend` | Ein lokal funktionierender Änderungssatz auf unnötige, nicht begründete Bestandteile reduziert werden soll. | [code-minimization.md](https://heljens-it-services.github.io/agent-organization/skills/code-minimization.md) |
| `code-reading` | Code Reading | - | `softwareentwicklung_architektur`, `softwareentwicklung_backend`, `softwareentwicklung_frontend`, `softwareentwicklung_infrastruktur`, `softwareentwicklung_qualitaetssicherung` | Bestehender Code gezielt in den eigenen Arbeitskontext geladen werden muss. | [code-reading.md](https://heljens-it-services.github.io/agent-organization/skills/code-reading.md) |
| `code-refactoring` | Code Refactoring | `/refactor` | `softwareentwicklung_backend`, `softwareentwicklung_frontend` | Struktur ohne beabsichtigte Verhaltensänderung verbessert werden soll. | [code_refactoring.md](https://heljens-it-services.github.io/agent-organization/skills/code_refactoring.md) |
| `code-testing` | Code Testing | `/testing`<br>`/testing <test-mode>` | `softwareentwicklung_architektur` (technische Kriterien), `softwareentwicklung_backend`, `softwareentwicklung_frontend`, `softwareentwicklung_infrastruktur` (jeweils lokale Verifikation eigener Änderungen), `softwareentwicklung_qualitaetssicherung` (unabhängige Verifikation) | Eigene technische Änderungen lokal verifiziert, technische Kriterien geprüft oder Softwareverhalten unabhängig verifiziert werden soll. | [code-testing.md](https://heljens-it-services.github.io/agent-organization/skills/code-testing.md) |
| `design-prototyping` | Design Prototyping | `/design-prototype` | `designer` | Eine Designrichtung als leichtes renderbares Artefakt visualisiert werden soll. | [design-prototyping.md](https://heljens-it-services.github.io/agent-organization/skills/design-prototyping.md) |
| `design-review` | Design Review | `/design-review` | `designer` | Ein visuelles oder interaktives Ergebnis betrachtet, bewertet oder mit Varianten verglichen werden soll. | [design-review.md](https://heljens-it-services.github.io/agent-organization/skills/design-review.md) |
| `documentation` | Documentation | - | Alle operativen Rollen | Dokumentation im zugewiesenen fachlichen Scope erstellt, aktualisiert oder umstrukturiert werden soll. | [documentation.md](https://heljens-it-services.github.io/agent-organization/skills/documentation.md) |
| `github-branch-checkout-from-default` | GitHub Branch Checkout From Default | - | `softwareentwicklung_infrastruktur` | Ein Arbeitsbranch von der aktuellen Standardbasis erstellt oder bestätigt werden soll. | [github_branch-checkout-from-default.md](https://heljens-it-services.github.io/agent-organization/skills/github_branch-checkout-from-default.md) |
| `github-commit` | GitHub Commit | `/commit` | `softwareentwicklung_infrastruktur` | Fertige lokale Änderungen logisch geschnitten und ohne Push committet werden sollen. | [github_commit.md](https://heljens-it-services.github.io/agent-organization/skills/github_commit.md) |
| `commit-history-reading` | Commit History Reading | - | `softwareentwicklung_infrastruktur` | Commits und gemergte Pull Requests eines Repositorys für einen Zeitraum vollständig gelesen werden sollen. | [github_commit-history-reading.md](https://heljens-it-services.github.io/agent-organization/skills/github_commit-history-reading.md) |
| `default-branch-update` | Default Branch Update | - | `softwareentwicklung_infrastruktur` | Nach einem verifizierten Merge sicher auf den aktualisierten Default-Branch gewechselt werden soll. | [github_default-branch-update.md](https://heljens-it-services.github.io/agent-organization/skills/github_default-branch-update.md) |
| `integration-branch-update` | Integration Branch Update | - | `softwareentwicklung_infrastruktur` | Nach einem verifizierten Feature-Merge sicher `develop` aktualisiert werden soll. | [github_integration-branch-update.md](https://heljens-it-services.github.io/agent-organization/skills/github_integration-branch-update.md) |
| `issue-creation` | Issue Creation | - | `product_owner` (User Stories/User Epics/User Tasks), `softwareentwicklung_architektur` (Technical Stories/Technical Epics/Technical Tasks) | Ein fachliches oder technisches GitHub-Issue aus vorhandenem Kontext erstellt werden soll. | [github_issue-creation.md](https://heljens-it-services.github.io/agent-organization/skills/github_issue-creation.md) |
| `issue-reading` | Issue Reading | - | `product_owner` (fachlicher Kontext), `softwareentwicklung_architektur` (technischer Kontext) | Ein GitHub-Issue und seine Kommentare im eigenen Scope gelesen werden müssen. | [github_issue-reading.md](https://heljens-it-services.github.io/agent-organization/skills/github_issue-reading.md) |
| `product-acceptance` | Product Acceptance | - | `product_owner` | Fachliche Akzeptanzkriterien anhand des sichtbaren Produktverhaltens geprüft werden sollen. | [product-acceptance.md](https://heljens-it-services.github.io/agent-organization/skills/product-acceptance.md) |
| `pr-checks-observation` | PR Checks Observation | - | `softwareentwicklung_qualitaetssicherung`, `softwareentwicklung_infrastruktur` | Erforderliche Pull-Request-Checks bis zu einem terminalen Zustand beobachtet werden sollen. | [github_pr-checks-observation.md](https://heljens-it-services.github.io/agent-organization/skills/github_pr-checks-observation.md) |
| `pr-creation` | PR Creation | - | `softwareentwicklung_infrastruktur` | Ein Pull Request mit Titel, Body, Base und Head erstellt oder wiederverwendet werden soll. | [github_pr-creation.md](https://heljens-it-services.github.io/agent-organization/skills/github_pr-creation.md) |
| `github-pr-merge` | GitHub PR Merge | - | `softwareentwicklung_infrastruktur` | Ein freigegebener Pull Request regelkonform gemergt werden soll. | [github_pr-merge.md](https://heljens-it-services.github.io/agent-organization/skills/github_pr-merge.md) |
| `github-push` | GitHub Push | `/push` | `softwareentwicklung_infrastruktur` | Vorhandene lokale Commits ohne neuen Commit auf den konfigurierten Upstream gepusht werden sollen. | [github_push.md](https://heljens-it-services.github.io/agent-organization/skills/github_push.md) |
| `repository-baseline-configuration` | Repository Baseline Configuration | - | `softwareentwicklung_infrastruktur` | Die standardisierte GitHub-Basiskonfiguration eines Repositorys geprüft oder ergänzt werden soll. | [github_repository-baseline-configuration.md](https://heljens-it-services.github.io/agent-organization/skills/github_repository-baseline-configuration.md) |
| `relationship-setting` | Relationship Setting | - | `product_owner` (fachliche Hierarchie), `softwareentwicklung_architektur` (technische Abhängigkeiten) | Native GitHub-Beziehungen im fachlichen oder technischen Scope gesetzt werden sollen. | [github_relationship-setting.md](https://heljens-it-services.github.io/agent-organization/skills/github_relationship-setting.md) |
| `type-setting` | Type Setting | - | `product_owner` (fachlicher Scope), `softwareentwicklung_architektur` (technischer Scope) | Der native GitHub-Issue-Type eines Issues im eigenen Scope eindeutig bestimmt und gesetzt werden soll. | [github_type-setting.md](https://heljens-it-services.github.io/agent-organization/skills/github_type-setting.md) |
| `research` | Research | - | `product_manager`, `product_owner`, `softwareentwicklung_architektur`, `softwareentwicklung_qualitaetssicherung`, `designer` | Für die eigene Zuständigkeit benötigter Web-, Repository-, Issue- oder PR-Kontext recherchiert werden soll. | [research.md](https://heljens-it-services.github.io/agent-organization/skills/research.md) |
| `delegation-planning` | Delegation Planning | - | `koordinator` | Eine Anfrage in abgegrenzte Aufträge für operative Spezialisten zerlegt werden soll. | [delegation-planning.md](https://heljens-it-services.github.io/agent-organization/skills/delegation-planning.md) |

## Routing-Kriterien bei mehreren verfügbaren Rollen

Die Rollenliste benennt zulässige Ausführer. Der Koordinator wählt je abgegrenztem Beitrag genau eine Rolle anhand dieser Kriterien; die Rollenbeschreibung bleibt die Quelle der tatsächlichen Skill-Freigabe.

| Skill / Gruppe | Owner-Auswahl aus Auftrag und vorhandenem Kontext |
|---|---|
| `requirements-clarification`, `brainstorming` | Produktstrategie, Outcomes und Featurehypothesen: `product_manager`; Anforderungen, User-Issues und fachlicher Scope: `product_owner`; Nutzung, Interaktion und visuelle Gestaltung: `designer`. |
| `code-analysis`, `code-reading` | Architektur, Verträge und übergreifende technische Entscheidungen: `softwareentwicklung_architektur`; Backend- bzw. Frontend-Änderungsscope: `softwareentwicklung_backend` bzw. `softwareentwicklung_frontend`; CI, Deployment, Laufzeit oder Infrastruktur: `softwareentwicklung_infrastruktur`; ausdrücklich unabhängige technische Prüfung: `softwareentwicklung_qualitaetssicherung`. |
| `code-implementation` | Backend: `softwareentwicklung_backend`; Frontend: `softwareentwicklung_frontend`; Infrastruktur: `softwareentwicklung_infrastruktur`; ausdrücklich beauftragte Testautomatisierung: `softwareentwicklung_qualitaetssicherung`. |
| `code-minimization`, `code-refactoring` | Owner des betroffenen Backend- oder Frontend-Änderungssatzes. Gemischte Änderungen werden in getrennte, koordinierte Rollenaufträge geschnitten. |
| `code-diff-review` | Eigene technische Akzeptanzkriterien prüfen: `softwareentwicklung_architektur`; unabhängiger technischer Review: `softwareentwicklung_qualitaetssicherung`. Ohne engere Vorgabe ist eine allgemeine unabhängige Review-Anfrage QA zuzuweisen. |
| `code-testing` | Explizit lokale Verifikation eigener Änderungen: deren Backend-, Frontend- oder Infrastruktur-Owner; technische Kriterienprüfung: `softwareentwicklung_architektur`; allgemeine oder unabhängige Verifikation: `softwareentwicklung_qualitaetssicherung`. Ohne engeren Auftrag gilt QA. Fachliche Black-Box-Abnahme wird als `product-acceptance` an `product_owner` zugewiesen. |
| `issue-reading`, `issue-creation`, `type-setting`, `relationship-setting` | User-Issues und fachliche Hierarchie: `product_owner`; technische Issues einschließlich Technical Tasks, Kriterien und Abhängigkeiten: `softwareentwicklung_architektur`. Gemischte Graphen erhalten getrennte Beiträge im jeweils zugewiesenen Scope. |
| `pr-checks-observation` | In einem freigegebenen Git-/GitHub-Lifecycle-Auftrag: `softwareentwicklung_infrastruktur`; sonst unabhängige Bewertung der Checks: `softwareentwicklung_qualitaetssicherung`. |
| `documentation` | Die operative Rolle, deren bereits zugewiesener fachlicher Inhalt dokumentiert wird. Bei eigenständigen Dokumentationsaufträgen bestimmt der Inhalt den Owner. |
| `research` | Strategie: `product_manager`; fachliche Anforderungen: `product_owner`; technische Architektur: `softwareentwicklung_architektur`; unabhängige Verifikation: `softwareentwicklung_qualitaetssicherung`; Nutzung und Gestaltung: `designer`. |

[MUST] Ein einzelner eindeutig geeigneter Owner wird direkt beauftragt. Fehlt nur Fachkontext zur Zuordnung, lässt der Koordinator ihn durch einen anhand des bekannten Ziels zuständigen Spezialisten klären. Fehlt eine notwendige Nutzerentscheidung oder ist bereits der Auftrag mehrdeutig, wird gezielt rückgefragt. Es werden keine Owner geraten oder Fachaufgaben vom Koordinator übernommen.

## Rollenbasierte Freigabe

[MUST] Die Owner-Spalte ist Routing-Metadatum. Die ausführliche Definition der Rolle steht ausschließlich im jeweiligen [Rollenindex](https://heljens-it-services.github.io/agent-organization/roles/ROLES.md) und der dort verlinkten Rollenregeldatei.

[MUST] Jede Rolle darf nur die Skills lesen und verwenden, die ihr eigener Rollenindex freigibt. Die Katalogtabelle berechtigt nicht zum Laden anderer Rollen-Skills.

[MUST] `koordinator` liest und verwendet `delegation-planning` als eigenen Koordinationsskill. Bei Fachskills nutzt er ausschließlich die Routing-Metadaten und beauftragt den ausgewählten operativen Owner.

[MUST_NOT] Ein aktueller Agent darf fehlende SubAgents oder Tool-Fähigkeiten nicht als Erlaubnis verstehen, eine andere operative Rolle zu übernehmen.

