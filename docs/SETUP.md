# SETUP.md

## GitHub-Basiskonfiguration

[MUST_IF] Ein von Heljens gepflegtes Software-Repository GitHub Issue Forms nutzt, muss es den vollständigen [Issue-Template-Satz](https://heljens-it-services.github.io/agent-organization/setup/github/ISSUE_TEMPLATES.md) unverändert unter `.github/ISSUE_TEMPLATE` übernehmen.

[MUST_IF] Ein von Heljens gepflegtes Software-Repository unterstützte Abhängigkeitsquellen besitzt, muss es `.github/dependabot.yml` gemäß der [Dependabot-Leitplanke](https://heljens-it-services.github.io/agent-organization/setup/github/DEPENDABOT.md) pflegen.

## Codex Agents

[MUST_IF] Wenn ein Repository die gemeinsamen Heljens-Rollen nutzt, muss es die [Projektkonfiguration](setup/codex/config.toml) unter `.codex/config.toml` und alle [Agent-Vorlagen](roles/ROLES.md) unter `.codex/agents/` mit den dort aufgeführten Dateinamen bereitstellen.

## Konfigurationsreferenzen

Die Angular-Qualitätsvorlagen liegen unter `setup/config/angular/quality/`: [Prettier](setup/config/angular/quality/prettier.json), [ESLint](setup/config/angular/quality/eslint.config.mjs) und [dependency-cruiser](setup/config/angular/quality/dependency-cruiser.cjs). Ihre Verwendung richtet sich nach den direkten Quellenfreigaben der eigenen Rolle.

## PROJECT.md

[MUST] Jedes Repository muss im Root eine `PROJECT.md` mit der repositoryweiten Versionsbasis und repositoryweiten Leitplanken besitzen.

[MUST_IF] Wenn ein Repository mehrere eigenständige Teilsolutions enthält, muss jede Teilsolution in ihrem Solution-Root eine lokale `PROJECT.md` mit ausschließlich scopespezifischen Ergänzungen oder Präzisierungen besitzen.

[MUST] Innerhalb einer Teilsolution gelten die Root- und die lokale `PROJECT.md`. Nicht widersprochene Root-Regeln bleiben wirksam.

[MUST] `PROJECT.md` muss diese Struktur verwenden:

```md
# PROJECT.md
## Zweck
## Versionsbasis
## Fachliche Leitplanken
## Technische Leitplanken
```

[MUST_IF] Der Scope einer `PROJECT.md` mehrere eigenständige Teilsolutions enthält, muss sie zusätzlich den Abschnitt `## Teilsolutions` besitzen.

[MUST_IF] `## Teilsolutions` erforderlich ist, muss der Abschnitt alle Teilsolutions vollständig in dieser Struktur aufführen:

```md
| Teilsolution | Pfad | PROJECT.md | Zweck |
|---|---|---|---|
| <Name> | `<relativer-pfad>/` | `<relativer-pfad>/PROJECT.md` | <Scope> |
```

[MUST_IF] Wenn eine Teilsolution hinzugefügt, entfernt, umbenannt oder verschoben wird oder sich Pfad beziehungsweise Scope ihrer `PROJECT.md` wesentlich ändert, muss das Verzeichnis mitgepflegt werden.

[MUST_IF] `PROJECT.md` muss mitgepflegt werden, wenn die Versionsbasis oder fachliche bzw. technische projektspezifische Leitplanken festgelegt, geändert, präzisiert oder dokumentiert werden.

[MUST_NOT] `PROJECT.md` darf keine bereits in [AGENTS.md](https://heljens-it-services.github.io/agent-files/AGENTS.md) oder Rollenregeldateien definierten Standardvorgaben duplizieren.

[MUST_NOT] Eine lokale `PROJECT.md` darf repositoryweite Regeln der Root-`PROJECT.md` nicht duplizieren.

[MUST] `PROJECT.md` muss projektspezifische Leitplanken mit deontischer Aussagenlogik und klaren Regelmarkern formulieren.
