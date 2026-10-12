# PROJECT.md

## Zweck

Versionierte Quelle für eine persönliche Agentenorganisation mit Koordinator,
Teamleitern und operativen Spezialisten. Die Koordinator-TOML ist implementiert
und persönlich installiert. Sie aktiviert den App-Hauptchat nicht automatisch.

## Versionsbasis

- Dokumentationsstand: 12. Oktober 2026.
- Formate: Markdown, TOML und JSON in UTF-8.
- Aufgabenverträge: JSON Schema 2020-12 mit PowerShell-5.1-Prüfung des verwendeten
  Schlüsselumfangs, ohne zusätzliche Laufzeitabhängigkeit.
- Zielplattform: Codex mit konfigurierbaren Agenten; konkrete Integration und
  unterstützte Konfigurationsfelder sind vor der Umsetzung zu prüfen.
- Aktuelle Sitzung: vier gleichzeitig verfügbare Agentenplätze einschließlich
  Hauptagent. Dies ist eine Laufzeitbeobachtung, keine dauerhafte Produktgrenze.

## Fachliche Leitplanken

[MUST] Bei Einsatz der Agentenorganisation kommuniziert der Benutzer mit dem
Koordinator. Repositorypflege erfolgt als normale Entwicklungsassistenz.

[MUST] Der Koordinator delegiert Arbeit an Teamleiter und führt keine operativen
Aufgaben aus. Teamleiter koordinieren ihren Fachbereich und delegieren die
operative Arbeit an Spezialisten.

[MUST] Maximal drei Agentenebenen; WorkItems dürfen beliebig tief sein.
Teamleiter spezifizieren Teilziele mit erforderlichen Fachleuten. Fachliche
Architekturentscheidungen brauchen deren Beitrag. Umsetzung ist keine Abnahme:
Elternziele benötigen eigene Geschäftskriterien und Prüfnachweise.

[MUST] Die neun Teams Softwareentwicklung, Design, Marketing, Controlling,
Buchhaltung, Geschäftsführung und Assistenz, HR, Agent Ressources und Administratoren bilden den vorgesehenen
Grundbestand.

[MUST] Revisionssicherheit bezeichnet hier versionierte Nachvollziehbarkeit.
Es wird keine Unveränderbarkeitsgarantie zugesichert.

## Technische Leitplanken

[MUST] Die geplante Teamhierarchie und Codex-Laufzeitkonfiguration bleiben
begrifflich getrennt. Eigene Organisationsfelder dürfen nicht als native
Codex-Konfigurationsschlüssel ausgegeben werden.

[MUST] Der implementierte Scope umfasst Koordinator, neun Teamleiter, 34 operative
Agenten und ihre Lookupindizes mit bytegleichen persönlichen Kopien. Der sichtbare
Terminalstarter ist implementiert; native Delegation besitzt keinen automatischen
Fensterhook.

[MUST] Die Repository-`AGENTS.md` aktiviert den Koordinator nur bei ausdrücklicher
Zuweisung oder Rollenstart. Er kontaktiert nur Teamleiter und bestimmt keine
operativen Rollen oder Interaktionen. Teamleiter entscheiden selbst über ihre
Agenten. Persönliche AGENTS und globale Konfiguration werden nicht geändert.

[MUST] [WorkItem-Vertrag](docs/contracts/WORKITEMS.md),
[Organisationsvertrag](docs/contracts/ORGANIZATION.md) und
[Entscheidung 0001](docs/decisions/0001-system-scope.md) bestimmen Datenstruktur,
Lebenszyklus und endgültige Orte. Laufzeitstatus gehört zu WorkItems, nicht Indizes.
Speicherung, Host, Oberfläche und Wissen/Workflows folgen in Epics #6–#11.

[MUST] Änderungen müssen auf den jeweils ausdrücklich zugewiesenen Scope
begrenzt bleiben; vorhandene fremde Arbeiten dürfen nicht überschrieben werden.
