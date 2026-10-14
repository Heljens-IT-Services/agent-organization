# agent-organization

`agent-organization` pflegt die gemeinsamen Regeln, Rollen, Skills, Workflows und Codex-Vorlagen von Heljens IT Services für die Verwendung in Projekt-Repositories.

[GitHub Pages](https://heljens-it-services.github.io/agent-organization/) veröffentlicht die Dateien direkt aus `docs/` auf `main` unter festen URLs. Konsumierende Projekte verwenden diese veröffentlichte Fassung; Änderungen auf einem Feature-Branch werden erst nach der Veröffentlichung verfügbar.

## Struktur

| Pfad | URL | Zweck |
|---|---|---|
| `docs/AGENTS.md` | [AGENTS.md](https://heljens-it-services.github.io/agent-organization/AGENTS.md) | Gemeinsame Regeln und Quellen für alle Agenten. |
| `docs/roles/ROLES.md` | [ROLES.md](https://heljens-it-services.github.io/agent-organization/roles/ROLES.md) | Kompaktes Rollenverzeichnis für den Koordinator. |
| `docs/roles/developer/DEVELOPER.md` | [DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/developer/DEVELOPER.md) | Allgemeine technologieübergreifende Entwicklungsregeln. |
| `docs/roles/developer/DEVELOPER.*.md` | [Developer-Rollen](https://heljens-it-services.github.io/agent-organization/roles/ROLES.md) | Technologiespezifische Entwicklungsregeln. |
| `docs/skills/SKILLS.md` | [SKILLS.md](https://heljens-it-services.github.io/agent-organization/skills/SKILLS.md) | Lookup-Datei für atomare Agenten-Skills. |
| `docs/workflows/WORKFLOWS.md` | [WORKFLOWS.md](https://heljens-it-services.github.io/agent-organization/workflows/WORKFLOWS.md) | Lookup-Datei für Workflows. |

## Pflege

Regeln werden direkt unter `docs/` bearbeitet. Codex-Konfiguration und Agent-Vorlagen werden gemäß `PROJECT.md` in `docs/codex/` und `.codex/` inhaltsgleich gepflegt.

Die Regeln verwenden dazu Marker wie `MUST`, `MUST_IF`, `MUST_NOT`, `ALLOW`, `ALLOW_IF`, `SHOULD`, `OPTIONAL` und `PRIORITY`, damit die normative Bedeutung jeder Anweisung möglichst eindeutig bleibt.

### Skills und Workflows pflegen

Skills bilden einzelne, klar abgegrenzte Fähigkeiten ab. Sie führen benötigte Vor- oder Nacharbeit nicht stillschweigend aus. Workflows kombinieren Skills in einer festgelegten Reihenfolge und definieren Bedingungen sowie Rücksprünge, ohne Skill-Regeln zu duplizieren, abzuschwächen oder zu überschreiben.

| Dateityp | Verbindliche Abschnitte | Bedingte Abschnitte |
|---|---|---|
| Skill | `Zweck`, `Verwenden`, `Vorgehen`, `Grenzen`, `Output`, `Qualitaetskriterien` | `Kommandos`, wenn konkrete Tool- oder CLI-Aufrufe relevant sind; `Artefakt`, wenn Dateien entstehen. |
| Workflow | `Ziel`, `Verwenden`, `Verwendete Skills`, `Ablauf`, `Ruecksprungregeln`, `Endergebnis` | `Verwendete Workflows` bei Orchestrierung weiterer Workflows; `Grenzen` bei besonderen Stop- oder Verbotsregeln. |

`Zweck` beziehungsweise `Ziel` beschreibt den Nutzen in ein bis zwei Sätzen. `Verwenden` grenzt Trigger und Nicht-Trigger ab; `Vorgehen` beziehungsweise `Ablauf` ordnet die Schritte. `Grenzen` benennt erlaubte und verbotene Aktionen, `Output` beziehungsweise `Endergebnis` den Abschlusszustand und `Qualitaetskriterien` kurze, prüfbare Regeln. Ein `Artefakt` legt Pfad, Namensschema, Inhalt und Stil fest.

Zusätzliche fachliche Steuerungsabschnitte wie `Reifekriterien`, `Schnittkriterien`, `Entscheidungskriterien` oder `Priorisierung` sind erlaubt, wenn sie konkrete Entscheidungen prüfbar machen.

Für die Pflege gelten folgende Konventionen:

- Skill-Dateinamen beschreiben den fachlichen Scope; die Präfixe `code_` und `github_` kennzeichnen den jeweiligen Kontext.
- Command-IDs verwenden Kleinbuchstaben und Bindestriche. Bestehende Unterstrich-Konventionen in Dateinamen dürfen erhalten bleiben.
- Referenzierte Skills müssen vollständig aufgeführt und befolgt werden; ihre Grenzen gelten auch für extern wirksame Workflow-Schritte. Fehlt ein benötigter Skill, wird der Workflow nachgeschärft oder die Abweichung begründet. Bei blockierten Schritten gilt die Rücksprungregel oder der Blocker wird gemeldet.
- Formulierungen bleiben knapp und operativ, bevorzugen Listen und vermeiden allgemeine Agentenphilosophien.

## Verwendung in Projekten

Für Codex werden die Vorlagen lokal in das konsumierende Repository übernommen:

1. [Projektkonfiguration](https://heljens-it-services.github.io/agent-organization/codex/config.toml) als `.codex/config.toml` und die Agent-TOMLs aus `docs/codex/agents/` als `.codex/agents/*.toml` kopieren. Eine vorhandene Konfiguration samt `developer_instructions` gezielt zusammenführen und ihre übrigen Einstellungen erhalten.
2. Die gemeinsamen [AGENTS.md-Regeln](https://heljens-it-services.github.io/agent-organization/AGENTS.md) über die lokale Root-`AGENTS.md` laden lassen. Eine vorhandene `AGENTS.md` um diesen Einstieg ergänzen und ihre Projektregeln erhalten.
3. Eine eigene Root-`PROJECT.md` und bei eigenständigen Teilsolutions deren lokale `PROJECT.md` mit Versionsbasis und projektspezifischen Regeln bereitstellen.
4. Das Projekt in Codex als vertrauenswürdig freigeben, damit seine `.codex/config.toml` geladen wird. Die eingesetzte Codex-Version muss die automatische Erkennung eigenständiger Agent-TOMLs unter `.codex/agents/` unterstützen.

Aktuelle Codex-Versionen erkennen eigenständige Agent-TOMLs automatisch; siehe [Custom Agents](https://learn.chatgpt.com/docs/agent-configuration/subagents#custom-agents) und die [Konfigurationsreferenz](https://learn.chatgpt.com/docs/config-file/config-reference) für `developer_instructions`.

Die Projektkonfiguration weist ausschließlich der primären, nicht delegierten Sitzung ohne ausdrückliche Rollenzuweisung die Rolle `koordinator` zu. Sie lässt die lokale `.codex/agents/koordinator.toml` lesen und deren `developer_instructions` befolgen. Eine ausdrücklich zugewiesene Spezialistenrolle bleibt auch bei geerbten Projektanweisungen erhalten. Fehlende Rollenzuweisungen oder Pflichtquellen werden als konkrete Blocker gemeldet.

Dieses Lesen ist ein instruktionsgesteuerter Rollenstart. Codex importiert dabei weder eine entfernte Markdown-Datei noch die TOML-Datei als Konfiguration. Insbesondere übernimmt die primäre Sitzung dadurch keine Modell-, Reasoning- oder Werkzeugeinstellungen aus der Koordinator-TOML. Solche Einstellungen wirken, wenn Codex die jeweilige Agent-Datei als Laufzeitkonfiguration lädt; die Rollen-Markdown-Dateien regeln Zuständigkeiten und Quellen.

Die TOMLs verweisen auf die veröffentlichten Rollen- und gemeinsamen Regeln. Im Quellrepository werden diese Links gemäß `PROJECT.md` auf `docs/` aufgelöst.
