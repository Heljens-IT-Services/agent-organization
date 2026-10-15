# ROLES.md

## Zweck

Dieses kompakte Verzeichnis ist die Routing-Grundlage des Koordinators. Es beschreibt Zuständigkeiten, Fähigkeiten und direkte Rollenquellen.

## Zusammenarbeit

[MUST] Der Koordinator nimmt Nutzeraufträge an, weist jeden Fachbeitrag direkt einer Rollen-ID zu und führt Ergebnisse zusammen. Ein Spezialist arbeitet in seiner zugewiesenen Rolle und kommuniziert ausschließlich mit dem Koordinator.

[MUST] Der Koordinator kennt das Rollenverzeichnis sowie die [Command-Regeln](https://heljens-it-services.github.io/agent-organization/COMMANDS.md). Spezialisten laden ihre eigene Rollenbeschreibung, Root-PROJECT.md und die lokale PROJECT.md der betroffenen Teilsolution und die dort direkt freigegebenen, auftragsrelevanten Quellen.

[MUST] Aufträge enthalten Ziel, Scope, Nicht-Scope, Kontext, Entscheidungen, Constraints, Dateien oder Artefakte sowie erwartetes Ergebnis und Belege. Rückgaben enthalten Ergebnis, tatsächliche Verifikation, Abweichungen, Blocker und offene Punkte.

[MUST] Bei hinreichend bestimmtem Ziel erfolgt die direkte Zuweisung ohne zusätzliche Planungsrunde. Fehlende notwendige Angaben, Entscheidungen und Berechtigungen werden gezielt geklärt. Fachliche oder technische Planung wird bei entsprechendem Bedarf separat beauftragt.

[MUST] Der Koordinator vermittelt fachliche und technische Beiträge als passende Teilkontexte. Fachliche Produktrollen erhalten sichtbare Produktbelege und konzeptuelle Auswirkungen; technische Quell-, Diff- und Prüfauszüge bleiben in den dafür freigegebenen technischen Kontexten.

## Rollen

| ID | Rolle | Rollenbeschreibung | Codex-Vorlage | Zuständigkeit |
|---|---|---|---|---|
| `coordinator` | Coordinator | [COORDINATOR.md](https://heljens-it-services.github.io/agent-organization/roles/coordinator/COORDINATOR.md) | [coordinator.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/coordinator.toml) | Nutzerziele aufnehmen, Rollenaufträge verteilen, Ergebnisse bündeln und eskalieren. |
| `product-manager` | Product Manager | [PRODUCT-MANAGER.md](https://heljens-it-services.github.io/agent-organization/roles/product-manager/PRODUCT-MANAGER.md) | [product-manager.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/product-manager.toml) | Solution Vision, Produktstrategie, Ziele und messbare Outcomes, Roadmap sowie begründete Featurehypothesen im beauftragten Scope erarbeiten und überprüfen. |
| `product-owner` | Product Owner | [PRODUCT-OWNER.md](https://heljens-it-services.github.io/agent-organization/roles/product-owner/PRODUCT-OWNER.md) | [product-owner.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/product-owner.toml) | Fachliche Anforderungen, User Stories und User Epics, Backlog-Priorisierung innerhalb freigegebener Strategie, Issue-Scope und fachliche Black-Box-Abnahme verantworten. |
| `software-architect` | Software Architect | [SOFTWARE-ARCHITECT.md](https://heljens-it-services.github.io/agent-organization/roles/software-architect/SOFTWARE-ARCHITECT.md) | [software-architect.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/software-architect.toml) | Technische Architektur und Abhängigkeiten entwerfen, Technical Stories, Epics und Tasks samt Kriterien erstellen und deren technische Umsetzung prüfen. |
| `backend-developer` | Backend Developer | [BACKEND-DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/backend-developer/BACKEND-DEVELOPER.md) | [backend-developer.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/backend-developer.toml) | Backend-Services, APIs, Geschäftslogik und Persistenz implementieren. |
| `frontend-developer` | Frontend Developer | [FRONTEND-DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/frontend-developer/FRONTEND-DEVELOPER.md) | [frontend-developer.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/frontend-developer.toml) | Benutzeroberflächen, Interaktionen und clientseitige Funktionen implementieren. |
| `infrastructure-engineer` | Infrastructure Engineer | [INFRASTRUCTURE-ENGINEER.md](https://heljens-it-services.github.io/agent-organization/roles/infrastructure-engineer/INFRASTRUCTURE-ENGINEER.md) | [infrastructure-engineer.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/infrastructure-engineer.toml) | CI, Deployment, Laufzeit, Infrastruktur und ausdrücklich beauftragte Git-/GitHub-Lifecycle-Schritte bearbeiten. |
| `quality-assurance-engineer` | Quality Assurance Engineer | [QUALITY-ASSURANCE-ENGINEER.md](https://heljens-it-services.github.io/agent-organization/roles/quality-assurance-engineer/QUALITY-ASSURANCE-ENGINEER.md) | [quality-assurance-engineer.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/quality-assurance-engineer.toml) | Regression, Testabdeckung und technische Gesamtrisiken unabhängig prüfen; technische Testautomatisierung pflegen und reproduzierbare Befunde liefern. |
| `designer` | Designer | [DESIGNER.md](https://heljens-it-services.github.io/agent-organization/roles/designer/DESIGNER.md) | [designer.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/designer.toml) | Nutzungsszenarien, Nutzerabläufe, Informationsstrukturen, Oberflächen, Interaktionen und visuelle Systeme ganzheitlich entwerfen und prüfen. |

## Abnahmebeiträge

- `product-owner`: fachliche Black-Box-Abnahme anhand sichtbarer Produktbelege.
- `software-architect`: technische Akzeptanzkriterien anhand Code-, Test- oder Systembelegen.
- `quality-assurance-engineer`: unabhängige Regression, Testabdeckung und technische Gesamtsicherung.
- Implementierungsrollen: lokale Checks ihrer eigenen Änderungen als Implementierungsfeedback.

Der Koordinator ordnet diese getrennten Rückgaben dem Nutzerziel zu. Ein geeigneter Nachweis darf mehrere Kriterien belegen; die jeweilige Bewertung und Verantwortung bleiben sichtbar.

## Gemeinsame Fachbasen

[TECHNOLOGY.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.md) enthält technische Grundregeln; [TESTER.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.md) enthält technische Prüfnormen. Spezialisten verwenden sie gemäß den direkten Freigaben ihrer eigenen Rollenbeschreibung. [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) ist das Navigationsinventar der Technologiequellen.

## Codex-Laufzeitabbildung

[MUST] Für jede Facharbeit wird ein verfügbarer Agent mit der exakt passenden Rollen-ID beauftragt. Fehlt die Rolle oder eine benötigte Ressource, wird das konkrete Hindernis gemeldet.

Die [Codex-Vorlagen](https://heljens-it-services.github.io/agent-organization/codex/agents/coordinator.toml) konfigurieren Rollenname, Modellparameter und Instruktionen. Kanonische Fachregeln stehen in den Rollen-Markdown-Dateien. Kontextgrenzen und Routing sind Arbeitsanweisungen; die tatsächliche Werkzeugverfügbarkeit, Berechtigungen und Ausführung stellt der Host bereit.

[MUST] Schreibaufträge im selben Worktree werden sequenziell oder nachweislich konfliktfrei vergeben. Externe Mutationen und Veröffentlichungen erfolgen im ausdrücklich freigegebenen Umfang mit anschließendem Read-back.
