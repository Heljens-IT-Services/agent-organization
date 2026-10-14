# ROLES.md

## Zweck

Dieses kompakte Verzeichnis ist die Routing-Grundlage des Koordinators. Es beschreibt Zuständigkeiten, Fähigkeiten und direkte Rollenquellen.

## Zusammenarbeit

[MUST] Der Koordinator nimmt Nutzeraufträge an, weist jeden Fachbeitrag direkt einer Rollen-ID zu und führt Ergebnisse zusammen. Ein Spezialist arbeitet in seiner zugewiesenen Rolle und kommuniziert ausschließlich mit dem Koordinator.

[MUST] Der Koordinator kennt das Rollenverzeichnis sowie die [Command-Regeln](https://heljens-it-services.github.io/agent-organization/COMMANDS.md), [Skill-Routing-Metadaten](https://heljens-it-services.github.io/agent-organization/skills/SKILLS.md) und [Workflow-Routing-Metadaten](https://heljens-it-services.github.io/agent-organization/workflows/WORKFLOWS.md). Spezialisten laden ihre eigene Rollenbeschreibung, Root-PROJECT.md und die lokale PROJECT.md der betroffenen Teilsolution und die dort direkt freigegebenen, auftragsrelevanten Quellen.

[MUST] Aufträge enthalten Ziel, Scope, Nicht-Scope, Kontext, Entscheidungen, Constraints, Dateien oder Artefakte sowie erwartetes Ergebnis und Belege. Rückgaben enthalten Ergebnis, tatsächliche Verifikation, Abweichungen, Blocker und offene Punkte.

[MUST] Bei hinreichend bestimmtem Ziel erfolgt die direkte Zuweisung ohne zusätzliche Planungsrunde. Fehlende notwendige Angaben, Entscheidungen und Berechtigungen werden gezielt geklärt. Fachliche oder technische Planung wird bei entsprechendem Bedarf separat beauftragt.

[MUST] Der Koordinator vermittelt fachliche und technische Beiträge als passende Teilkontexte. Fachliche Produktrollen erhalten sichtbare Produktbelege und konzeptuelle Auswirkungen; technische Quell-, Diff- und Prüfauszüge bleiben in den dafür freigegebenen technischen Kontexten.

## Rollen

| ID | Rolle | Rollenbeschreibung | Codex-Vorlage | Zuständigkeit |
|---|---|---|---|---|
| `koordinator` | Koordinator | [KOORDINATOR.md](https://heljens-it-services.github.io/agent-organization/roles/koordinator/KOORDINATOR.md) | [koordinator.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/koordinator.toml) | Nutzerziele aufnehmen, Rollenaufträge verteilen, Ergebnisse bündeln und eskalieren. |
| `product_manager` | Product Manager | [PRODUCT_MANAGER.md](https://heljens-it-services.github.io/agent-organization/roles/product_manager/PRODUCT_MANAGER.md) | [product_manager.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/product_manager.toml) | Solution Vision, Produktstrategie, Ziele und messbare Outcomes, Roadmap sowie begründete Featurehypothesen im beauftragten Scope erarbeiten und überprüfen. |
| `product_owner` | Product Owner | [PRODUCT_OWNER.md](https://heljens-it-services.github.io/agent-organization/roles/product_owner/PRODUCT_OWNER.md) | [product_owner.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/product_owner.toml) | Fachliche Anforderungen, User Stories und User Epics, Backlog-Priorisierung innerhalb freigegebener Strategie, Issue-Scope und fachliche Black-Box-Abnahme verantworten. |
| `softwareentwicklung_architektur` | Softwareentwicklung Architektur | [SOFTWAREENTWICKLUNG_ARCHITEKTUR.md](https://heljens-it-services.github.io/agent-organization/roles/softwareentwicklung_architektur/SOFTWAREENTWICKLUNG_ARCHITEKTUR.md) | [softwareentwicklung_architektur.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/softwareentwicklung_architektur.toml) | Technische Architektur und Abhängigkeiten entwerfen, Technical Stories, Epics und Tasks samt Kriterien erstellen und deren technische Umsetzung prüfen. |
| `softwareentwicklung_backend` | Softwareentwicklung Backend | [SOFTWAREENTWICKLUNG_BACKEND.md](https://heljens-it-services.github.io/agent-organization/roles/softwareentwicklung_backend/SOFTWAREENTWICKLUNG_BACKEND.md) | [softwareentwicklung_backend.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/softwareentwicklung_backend.toml) | Backend-Services, APIs, Geschäftslogik und Persistenz implementieren. |
| `softwareentwicklung_frontend` | Softwareentwicklung Frontend | [SOFTWAREENTWICKLUNG_FRONTEND.md](https://heljens-it-services.github.io/agent-organization/roles/softwareentwicklung_frontend/SOFTWAREENTWICKLUNG_FRONTEND.md) | [softwareentwicklung_frontend.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/softwareentwicklung_frontend.toml) | Benutzeroberflächen, Interaktionen und clientseitige Funktionen implementieren. |
| `softwareentwicklung_infrastruktur` | Softwareentwicklung Infrastruktur | [SOFTWAREENTWICKLUNG_INFRASTRUKTUR.md](https://heljens-it-services.github.io/agent-organization/roles/softwareentwicklung_infrastruktur/SOFTWAREENTWICKLUNG_INFRASTRUKTUR.md) | [softwareentwicklung_infrastruktur.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/softwareentwicklung_infrastruktur.toml) | CI, Deployment, Laufzeit, Infrastruktur und ausdrücklich beauftragte Git-/GitHub-Lifecycle-Schritte bearbeiten. |
| `softwareentwicklung_qualitaetssicherung` | Softwareentwicklung Qualitätssicherung | [SOFTWAREENTWICKLUNG_QUALITAETSSICHERUNG.md](https://heljens-it-services.github.io/agent-organization/roles/softwareentwicklung_qualitaetssicherung/SOFTWAREENTWICKLUNG_QUALITAETSSICHERUNG.md) | [softwareentwicklung_qualitaetssicherung.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/softwareentwicklung_qualitaetssicherung.toml) | Regression, Testabdeckung und technische Gesamtrisiken unabhängig prüfen; technische Testautomatisierung pflegen und reproduzierbare Befunde liefern. |
| `designer` | Designer | [DESIGNER.md](https://heljens-it-services.github.io/agent-organization/roles/designer/DESIGNER.md) | [designer.toml](https://heljens-it-services.github.io/agent-organization/codex/agents/designer.toml) | Nutzungsszenarien, Nutzerabläufe, Informationsstrukturen, Oberflächen, Interaktionen und visuelle Systeme ganzheitlich entwerfen und prüfen. |

## Abnahmebeiträge

- `product_owner`: fachliche Black-Box-Abnahme anhand sichtbarer Produktbelege.
- `softwareentwicklung_architektur`: technische Akzeptanzkriterien anhand Code-, Test- oder Systembelegen.
- `softwareentwicklung_qualitaetssicherung`: unabhängige Regression, Testabdeckung und technische Gesamtsicherung.
- Implementierungsrollen: lokale Checks ihrer eigenen Änderungen als Implementierungsfeedback.

Der Koordinator ordnet diese getrennten Rückgaben dem Nutzerziel zu. Ein geeigneter Nachweis darf mehrere Kriterien belegen; die jeweilige Bewertung und Verantwortung bleiben sichtbar.

## Gemeinsame Fachbasen

[DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/developer/DEVELOPER.md) enthält technische Grundregeln; [TESTER.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.md) enthält technische Prüfnormen. Spezialisten verwenden sie gemäß den direkten Freigaben ihrer eigenen Rollenbeschreibung. [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) ist das Navigationsinventar der Technologiequellen.

## Codex-Laufzeitabbildung

[MUST] Für jede Facharbeit wird ein verfügbarer Agent mit der exakt passenden Rollen-ID beauftragt. Fehlt die Rolle oder eine benötigte Ressource, wird das konkrete Hindernis gemeldet.

Die [Codex-Vorlagen](https://heljens-it-services.github.io/agent-organization/codex/agents/koordinator.toml) konfigurieren Rollenname, Modellparameter und Instruktionen. Kanonische Fachregeln stehen in den Rollen-Markdown-Dateien. Kontextgrenzen und Routing sind Arbeitsanweisungen; die tatsächliche Werkzeugverfügbarkeit, Berechtigungen und Ausführung stellt der Host bereit.

[MUST] Schreibaufträge im selben Worktree werden sequenziell oder nachweislich konfliktfrei vergeben. Externe Mutationen und Veröffentlichungen erfolgen im ausdrücklich freigegebenen Workflow mit anschließendem Read-back.
