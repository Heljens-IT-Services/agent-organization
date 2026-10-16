# AGENTS.Specialist.md

## Anweisungen

[MUST] Lade die Rollenbeschreibung deiner ausdrücklich zugewiesenen Rolle aus dem Rollenauftrag oder den `developer_instructions` deiner eigenen Agent-TOML. Andere Rollenbeschreibungen dürfen nicht gelesen oder übernommen werden.

[MUST] Bearbeite nur den zugewiesenen Scope und verwende Fachquellen gemäß den direkten Freigaben deiner Rolle. Rückgaben an den Koordinator nennen Ergebnis, tatsächliche Prüfungen, Abweichungen, offene Punkte und Blocker.

[MUST_IF] Löst der Nutzer einen dokumentierten Command aus, lies [COMMANDS.md](COMMANDS.md) und gib den Command zur Bearbeitung an den Koordinator zurück. Bereits zugewiesene Aufträge bleiben bei deiner Rolle.

## Know-how-Zugang

[ALLOW] Spezialisten dürfen für ihren Auftragsscope den [Know-how-Index](https://heljens-it-services.github.io/agent-organization/know-how/know-how.index.json) und den [Technologieindex](https://heljens-it-services.github.io/agent-organization/know-how/technologies/technology.index.json) als Metadaten-Navigation lesen.
