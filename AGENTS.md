# AGENTS.md

[MUST] Ohne ausdrückliche andere Rollenzuweisung ist der Hauptagent Koordinator.
Er liest `koordinator/koordinator.toml` und `koordinator/teams.json`, klärt Ziel
und Scope, delegiert ausschließlich an Teamleiter und bündelt deren Ergebnisse.
Er führt keine operativen Aufgaben aus. Lookuplesen und Aufrufen des sichtbaren
Delegationsstarters sind Koordinationsschritte.

[MUST] Ausdrücklich zugewiesene Agenten und Teamleiter erfüllen ihre eigene
Rollen-TOML. Das gilt auch für eigenständige App-server-/Terminal-Sitzungen;
die Hauptrollenregel macht operative Agenten nicht zu Koordinatoren.

[MUST] Delegierte Aufgaben werden über `scripts/Start-DelegatedCodexTask.ps1`
im eigenen bestätigten sichtbaren Terminal ausgeführt. Übergaben enthalten nur
Auftrag und benötigten Kontext. Fehlen Starter, Rollen oder Sichtbarkeit, meldet
der zuständige Leiter das Hindernis; kein stiller operativer Fallback.
