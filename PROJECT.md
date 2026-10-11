# PROJECT.md

## Zweck

Versionierte Quelle für eine persönliche Agentenorganisation mit Koordinator,
Teamleitern und operativen Spezialisten. Die Koordinator-TOML ist implementiert
und persönlich installiert. Sie aktiviert den App-Hauptchat nicht automatisch.

## Versionsbasis

- Dokumentationsstand: 12. Oktober 2026.
- Formate: Markdown, TOML und JSON in UTF-8.
- Zielplattform: Codex mit konfigurierbaren Agenten; konkrete Integration und
  unterstützte Konfigurationsfelder sind vor der Umsetzung zu prüfen.
- Aktuelle Sitzung: vier gleichzeitig verfügbare Agentenplätze einschließlich
  Hauptagent. Dies ist eine Laufzeitbeobachtung, keine dauerhafte Produktgrenze.

## Fachliche Leitplanken

[MUST] Der Benutzer kommuniziert ausschließlich mit dem Koordinator.

[MUST] Der Koordinator delegiert Arbeit an Teamleiter und führt keine operativen
Aufgaben aus. Teamleiter koordinieren ihren Fachbereich und delegieren die
operative Arbeit an Spezialisten.

[MUST] Die acht Teams Softwareentwicklung, Design, Marketing, Controlling,
Buchhaltung, Geschäftsführung und Assistenz, HR sowie Agent Ressources bilden den vorgesehenen
Grundbestand.

[MUST] Revisionssicherheit bezeichnet hier versionierte Nachvollziehbarkeit.
Es wird keine Unveränderbarkeitsgarantie zugesichert.

## Technische Leitplanken

[MUST] Die geplante Teamhierarchie und Codex-Laufzeitkonfiguration bleiben
begrifflich getrennt. Eigene Organisationsfelder dürfen nicht als native
Codex-Konfigurationsschlüssel ausgegeben werden.

[MUST] Der implementierte Scope umfasst Koordinator, acht Teamleiter, 30 operative
Agenten und ihre Lookupindizes mit bytegleichen persönlichen Kopien. Der sichtbare
Terminalstarter ist implementiert; native Delegation besitzt keinen automatischen
Fensterhook.

[MUST] Die Repository-`AGENTS.md` weist ohne ausdrückliche andere Rollenzuweisung
die Hauptrolle Koordinator zu. Ausdrücklich zugewiesene Rollen bleiben operativ
oder koordinierend gemäß ihrer TOML. Persönliche AGENTS und globale Konfiguration
werden dadurch nicht geändert.

[MUST] Änderungen müssen auf den jeweils ausdrücklich zugewiesenen Scope
begrenzt bleiben; vorhandene fremde Arbeiten dürfen nicht überschrieben werden.
