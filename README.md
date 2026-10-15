# agent-organization

`agent-organization` pflegt die gemeinsamen Regeln, Rollen, Technologien, Commands und Codex-Vorlagen von Heljens IT Services für die Verwendung in Projekt-Repositories.

[GitHub Pages](https://heljens-it-services.github.io/agent-organization/) veröffentlicht die Dateien direkt aus `docs/` auf `main` unter festen URLs. Konsumierende Projekte verwenden diese veröffentlichte Fassung; Änderungen auf einem Feature-Branch werden erst nach der Veröffentlichung verfügbar.

## Struktur

| Pfad | URL | Zweck |
|---|---|---|
| `docs/AGENTS.md` | [AGENTS.md](https://heljens-it-services.github.io/agent-organization/AGENTS.md) | Gemeinsame Regeln und Quellen für alle Agenten. |
| `docs/roles/ROLES.md` | [ROLES.md](https://heljens-it-services.github.io/agent-organization/roles/ROLES.md) | Kompaktes Rollenverzeichnis für den Koordinator. |
| `docs/roles/developer/DEVELOPER.md` | [DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/developer/DEVELOPER.md) | Allgemeine technologieübergreifende Entwicklungsregeln. |
| `docs/roles/developer/DEVELOPER.*.md` | [Developer-Rollen](https://heljens-it-services.github.io/agent-organization/roles/ROLES.md) | Technologiespezifische Entwicklungsregeln. |

## Pflege

Regeln werden direkt unter `docs/` bearbeitet. Codex-Konfiguration und Agent-Vorlagen werden gemäß `PROJECT.md` in `docs/codex/` und `.codex/` inhaltsgleich gepflegt.

Die Regeln verwenden dazu Marker wie `MUST`, `MUST_IF`, `MUST_NOT`, `ALLOW`, `ALLOW_IF`, `SHOULD`, `OPTIONAL` und `PRIORITY`, damit die normative Bedeutung jeder Anweisung möglichst eindeutig bleibt.

Agenten wählen ihr Vorgehen nach bestem Wissen und Gewissen aus Ziel, Rolle und Projektkontext. Fachliche Regeln, Technologiequellen und erforderliche Berechtigungen bilden den Rahmen. Commands benennen Ziele und zuständige Rollen.

Formulierungen bleiben knapp und konkret.

## Verwendung in Projekten

Für Codex genügt als regelbasierter Einstieg eine lokale Root-`AGENTS.md`, die die veröffentlichten [gemeinsamen Regeln](https://heljens-it-services.github.io/agent-organization/AGENTS.md) laden lässt. Projektregeln in vorhandenen Dateien bleiben erhalten. Eine eigene Root-`PROJECT.md` und bei eigenständigen Teilsolutions deren lokale `PROJECT.md` müssen den Projektkontext bereitstellen.

Die primäre Sitzung führt vor der Rollenpflicht den [Codex-Projekteinstieg](https://heljens-it-services.github.io/agent-organization/codex/SETUP.md) aus. Sie lädt fehlende `.codex/config.toml` und `.codex/agents/*.toml` aus den kanonischen veröffentlichten Quellen herunter und speichert sie lokal. Vorhandene Projektanweisungen werden gezielt zusammengeführt; lokale Einstellungen und abweichende Agent-Dateien bleiben erhalten, Konflikte werden gemeldet. Ein reiner Leseauftrag oder fehlende Schreibrechte erlauben keine Einrichtung.

Die Einrichtung ist ein instruktionsgesteuerter Dateiabgleich, kein automatischer URL-Import durch Codex. Projektvertrauen gibt der Nutzer frei. Neue Konfigurationsdateien werden beim passenden nächsten Sitzungs- beziehungsweise Agentenstart geladen; die eingesetzte Codex-Version muss eigenständige Agent-TOMLs unterstützen. Tatsächliche Rollenverfügbarkeit wird vor der Delegation geprüft.

Aktuelle Codex-Versionen erkennen eigenständige Agent-TOMLs automatisch; siehe [Custom Agents](https://learn.chatgpt.com/docs/agent-configuration/subagents#custom-agents) und die [Konfigurationsreferenz](https://learn.chatgpt.com/docs/config-file/config-reference) für `developer_instructions`.

Der gemeinsame Einstieg und die Projektkonfiguration weisen ausschließlich der primären, nicht delegierten Sitzung ohne ausdrückliche Rollenzuweisung die Rolle `koordinator` zu. Diese Sitzung liest die lokale `.codex/agents/koordinator.toml` und befolgt deren `developer_instructions`. Eine ausdrücklich zugewiesene Spezialistenrolle bleibt auch bei geerbten Projektanweisungen erhalten. Fehlende Rollenzuweisungen oder Pflichtquellen werden als konkrete Blocker gemeldet.

Dieses Lesen ist ein instruktionsgesteuerter Rollenstart. Codex importiert dabei weder eine entfernte Markdown-Datei noch die TOML-Datei als Konfiguration. Insbesondere übernimmt die primäre Sitzung dadurch keine Modell-, Reasoning- oder Werkzeugeinstellungen aus der Koordinator-TOML. Solche Einstellungen wirken, wenn Codex die jeweilige Agent-Datei als Laufzeitkonfiguration lädt; die Rollen-Markdown-Dateien regeln Zuständigkeiten und Quellen.

Die TOMLs verweisen auf die veröffentlichten Rollen- und gemeinsamen Regeln. Im Quellrepository werden diese Links gemäß `PROJECT.md` auf `docs/` aufgelöst.
