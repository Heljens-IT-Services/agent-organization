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

[MUST] Der Koordinator ist für alle Arbeiten in diesem Repository die verpflichtende
Top-Level-Rolle und der Benutzerkontakt; es gibt keine Wartungsausnahme.
Ausdrücklich zugewiesene Teamleiter und Spezialisten behalten ihre eigene Rolle.

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

[MUST] Der implementierte Scope umfasst Koordinator, neun Teamleiter, 35 operative
Agenten und ihre Lookupindizes mit bytegleichen persönlichen Kopien. Der sichtbare
Terminalstarter ist implementiert; native Delegation besitzt keinen automatischen
Fensterhook.

[MUST] Die Repository-`AGENTS.md` legt die verpflichtende Koordinatorrolle fest.
Er kontaktiert nur Teamleiter und bestimmt keine
operativen Rollen oder Interaktionen. Teamleiter entscheiden selbst über ihre
Agenten. Persönliche AGENTS und globale Konfiguration werden nicht geändert.

[MUST] [WorkItem-Vertrag](docs/contracts/WORKITEMS.md),
[Organisationsvertrag](docs/contracts/ORGANIZATION.md) und
[Entscheidung 0001](docs/decisions/0001-system-scope.md) bestimmen Datenstruktur,
Lebenszyklus und endgültige Orte. Laufzeitstatus gehört zu WorkItems, nicht Indizes.
Speicherung, Host, Oberfläche und Wissen/Workflows folgen in Epics #6–#11.

[MUST] Änderungen müssen auf den jeweils ausdrücklich zugewiesenen Scope
begrenzt bleiben; vorhandene fremde Arbeiten dürfen nicht überschrieben werden.

Empfindliche Organisationsstrukturen (Organisationsdateien, Rollenregeln,
Indizes und zugehörige Verträge) werden ausschließlich über den Auftragspfad
Koordinator -> zuständiger Teamleiter -> Optimierer geändert, im abgegrenzten
WorkItem mit vorheriger menschlicher Freigabe. Der Koordinator beauftragt nur
Teamleiter mit Zielen, Rahmenbedingungen und Abnahmekriterien; er kontaktiert
oder wählt keine operativen Agenten und schreibt deren Interaktionen nicht vor.
Der Teamleiter bestimmt die interne Besetzung und Zusammenarbeit eigenständig.
Der Optimierer kommuniziert ausschließlich mit teamleiter_agent_ressources,
erhält fremde Änderungen und liefert Konsistenz-, Referenz- und Funktionsbelege.
Unabhängige Qualitätsprüfung und dokumentierte eigene Elternabnahme folgen getrennt.
