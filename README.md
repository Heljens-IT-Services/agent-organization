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

Für Codex genügt als regelbasierter Einstieg eine lokale Root-`AGENTS.md`, die die veröffentlichten [gemeinsamen Regeln](https://heljens-it-services.github.io/agent-organization/AGENTS.md) laden lässt. Projektregeln in vorhandenen Dateien bleiben erhalten. Eine eigene Root-`PROJECT.md` und bei eigenständigen Teilsolutions deren lokale `PROJECT.md` müssen den Projektkontext bereitstellen.

Die primäre Sitzung führt vor der Rollenpflicht den [Codex-Projekteinstieg](https://heljens-it-services.github.io/agent-organization/codex/SETUP.md) aus. Sie lädt fehlende `.codex/config.toml` und `.codex/agents/*.toml` aus den kanonischen veröffentlichten Quellen herunter und speichert sie lokal. Vorhandene Projektanweisungen werden gezielt zusammengeführt; lokale Einstellungen und abweichende Agent-Dateien bleiben erhalten, Konflikte werden gemeldet. Ein reiner Leseauftrag oder fehlende Schreibrechte erlauben keine Einrichtung.

Die Einrichtung ist ein instruktionsgesteuerter Dateiabgleich, kein automatischer URL-Import durch Codex. Projektvertrauen gibt der Nutzer frei. Neue Konfigurationsdateien werden beim passenden nächsten Sitzungs- beziehungsweise Agentenstart geladen; die eingesetzte Codex-Version muss eigenständige Agent-TOMLs unterstützen. Tatsächliche Rollenverfügbarkeit wird vor der Delegation geprüft.

Aktuelle Codex-Versionen erkennen eigenständige Agent-TOMLs automatisch; siehe [Custom Agents](https://learn.chatgpt.com/docs/agent-configuration/subagents#custom-agents) und die [Konfigurationsreferenz](https://learn.chatgpt.com/docs/config-file/config-reference) für `developer_instructions`.

Der gemeinsame Einstieg und die Projektkonfiguration weisen ausschließlich der primären, nicht delegierten Sitzung ohne ausdrückliche Rollenzuweisung die Rolle `koordinator` zu. Diese Sitzung liest die lokale `.codex/agents/koordinator.toml` und befolgt deren `developer_instructions`. Eine ausdrücklich zugewiesene Spezialistenrolle bleibt auch bei geerbten Projektanweisungen erhalten. Fehlende Rollenzuweisungen oder Pflichtquellen werden als konkrete Blocker gemeldet.

Dieses Lesen ist ein instruktionsgesteuerter Rollenstart. Codex importiert dabei weder eine entfernte Markdown-Datei noch die TOML-Datei als Konfiguration. Insbesondere übernimmt die primäre Sitzung dadurch keine Modell-, Reasoning- oder Werkzeugeinstellungen aus der Koordinator-TOML. Solche Einstellungen wirken, wenn Codex die jeweilige Agent-Datei als Laufzeitkonfiguration lädt; die Rollen-Markdown-Dateien regeln Zuständigkeiten und Quellen.

Die TOMLs verweisen auf die veröffentlichten Rollen- und gemeinsamen Regeln. Im Quellrepository werden diese Links gemäß `PROJECT.md` auf `docs/` aufgelöst.
