# PROJECT.md

## Zweck

Dieses Repository pflegt die versionierten Agent-, Rollen- und Technologie-Regeln, die über GitHub Pages an konsumierende Repositories veröffentlicht werden.

## Versionsbasis

[MUST] Die veröffentlichten Quelldateien liegen unter `docs/`; GitHub Pages veröffentlicht den Inhalt dieses Verzeichnisses aus `main`.

[PRIORITY] Bei Arbeiten an dieser Quellrepository-Version sind `docs/AGENTS.md` und die dort verlinkten Quelldateien maßgeblich. Die online veröffentlichte Fassung kann hinter dem lokalen Arbeitsstand zurückliegen und darf diesen Quellstand nicht überschreiben.

[MUST_IF] Während der Pflege dieses Repositories sind absolute GitHub-Pages-Links auf `https://heljens-it-services.github.io/agent-organization/<pfad>` für die Quelllektüre innerhalb dieses Repositories auf `docs/<pfad>` aufzulösen. Diese lokale Quellauflösung gilt nur für dieses Repository; sie behauptet weder, dass der lokale Rollenstand bereits veröffentlicht ist, noch aktiviert sie Regeln in konsumierenden Repositories.

## Fachliche Leitplanken

[MUST] Regeln und Navigationsindizes müssen innerhalb der veröffentlichten Quelldateien konsistent verlinkt sein; jede Markdown-Datei unter `docs/` muss ausgehend von `docs/AGENTS.md` erreichbar sein.

## Technische Leitplanken

[MUST] Änderungen an veröffentlichten Regeln und Codex-Vorlagen müssen in den Quelldateien unter `docs/` vorgenommen werden.

[MUST] Die veröffentlichte Projektkonfiguration `docs/codex/config.toml` muss inhaltsgleich mit `.codex/config.toml` sein. Die veröffentlichten Codex-Agent-Vorlagen unter `docs/codex/agents/` müssen inhaltsgleich mit den Laufzeitvorlagen unter `.codex/agents/` sein.

[MUST] GitHub Pages verteilt die versionierten Dateien direkt aus `docs/`; die Pflege darf keinen separaten Build- oder Generierungsschritt voraussetzen.

[MUST_IF] Nach einer Veröffentlichung oder bei Zweifeln an der Online-Fassung prüft die Qualitätssicherung Quelle, Erreichbarkeit, Verlinkung und Inhaltsgleichheit mit dem veröffentlichten Commit.
