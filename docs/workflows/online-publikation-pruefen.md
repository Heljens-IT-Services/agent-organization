# Workflow: Online-Publikation prüfen

## Owner

`softwareentwicklung_qualitaetssicherung` führt diesen Workflow operativ und ausschließlich lesend aus.

## Ziel

Die über GitHub Pages veröffentlichten Agent Organization gegen den aktuellen GitHub-Stand von `main` auf Quelle, Erreichbarkeit, Vernetzung und Inhaltsgleichheit prüfen.

## Verwenden

- Nach einem Release nach `main`.
- Bei Zweifeln an Erreichbarkeit, Vernetzung oder Aktualität.
- Ausschließlich lesend; Befunde zur Behebung an den Koordinator zurückgeben.

Der kanonische Aufruf lautet `/workflows run online-publication-check`. Der Dateipfad bleibt für bestehende Links unverändert.

## Verwendete Skills

- `research`

## Ablauf

1. Den aktuellen `main`-Commit über die GitHub API lesen und SHA sowie Abrufzeit festhalten. Keine lokalen Branch-Refs aktualisieren.
2. GitHub-Pages-Konfiguration und letzten Build über die GitHub API lesen. Quelle muss `main` mit Pfad `/docs` sein, Status `built`, Build-Commit gleich dem gelesenen `main`-Commit.
3. Den Einstiegspunkt `https://heljens-it-services.github.io/agent-organization/AGENTS.md` per HTTP abrufen; Status muss `200` sein.
4. Aus den internen Markdown-Links ab `docs/AGENTS.md` den Erreichbarkeitsgraphen bilden und mit den Markdown-Dateien vergleichen, die zum erfassten `main`-Commit gehören. Kein Linkziel darf fehlen; jede Markdown-Datei muss erreichbar sein.
5. Jede versionierte Markdown-Datei und Codex-Agent-Vorlage unter `docs/codex/agents/` über die zugehörige Pages-URL abrufen. Jede URL muss HTTP `200` liefern.
6. Online-Inhalte nach Vereinheitlichung der Zeilenenden mit den Inhalten des erfassten `main`-Commits vergleichen. Veröffentlichte Agent-Vorlagen zusätzlich mit den in `.codex/agents/` gespeicherten Vorlagen vergleichen, sofern diese lokal verfügbar sind; andernfalls die Einschränkung benennen.
7. SHA, Build-Commit, Datei- und Linkanzahl sowie Abweichungen getrennt nach Quelle, Erreichbarkeit, Vernetzung und Aktualität dokumentieren.

## Rücksprungregeln

- Wenn Quelle, Build-Status oder Build-Commit abweichen, keine Aktualität behaupten.
- Bei fehlendem Linkziel, HTTP-Fehler oder Inhaltsabweichung konkrete Pfade, URLs sowie erwartete und tatsächliche Commits nennen und den Befund zurückgeben.
- Wenn ein Browser- oder Web-Werkzeug eine URL nicht abruft, vor einem Fehlerurteil Shell-HTTP versuchen.

## Endergebnis

- Quelle und Build-Commit sind eindeutig bewertet.
- Erreichbarkeit und Vernetzung der veröffentlichten Markdown-Dateien sind belegt oder mit konkreten Befunden fehlgeschlagen.
- Inhaltsgleichheit zum erfassten `main`-Commit und den verfügbaren Agent-Vorlagen ist belegt oder mit Abweichungen dokumentiert.

## Grenzen

- Keine lokalen Branch-Refs oder versionierten Dateien ändern.
- Keine GitHub-Pages-Konfigurationen oder anderen externen Zustände ändern.
