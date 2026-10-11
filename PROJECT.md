# PROJECT.md

## Zweck

Versionierte Quelle für eine persönliche Agentenorganisation mit Koordinator,
Teamleitern und operativen Spezialisten. Der Koordinator ist als Profil mit
gezielter persönlicher Installation und CLI-Start implementiert. Die vollständige
Agentenorganisation und der App-Hauptchat sind nicht als aktiviert nachgewiesen.

## Versionsbasis

- Dokumentationsstand: 11. Oktober 2026.
- Formate: Markdown, TOML und PowerShell in UTF-8.
- Verifizierte CLI-Basis: Codex CLI 0.162.1; Profile benötigen die separate
  Dateistruktur ab Codex 0.134.0.
- Zielplattform: Codex mit konfigurierbaren Agenten; konkrete Integration und
  unterstützte Konfigurationsfelder sind vor der Umsetzung zu prüfen.
- Aktuelle Sitzung: vier gleichzeitig verfügbare Agentenplätze einschließlich
  Hauptagent. Dies ist eine Laufzeitbeobachtung, keine dauerhafte Produktgrenze.

## Fachliche Leitplanken

[MUST] Der Benutzer kommuniziert ausschließlich mit dem Koordinator.

[MUST] Der Koordinator delegiert Arbeit an Teamleiter und führt keine operativen
Aufgaben aus. Teamleiter koordinieren ihren Fachbereich und delegieren die
operative Arbeit an Spezialisten.

[MUST] Die sieben Teams Softwareentwicklung, Design, Marketing, Controlling,
Buchhaltung, Geschäftsführung und Assistenz sowie HR bilden den vorgesehenen
Grundbestand.

[MUST] Revisionssicherheit bezeichnet hier versionierte Nachvollziehbarkeit.
Es wird keine Unveränderbarkeitsgarantie zugesichert.

## Technische Leitplanken

[MUST] Die geplante Teamhierarchie und Codex-Laufzeitkonfiguration bleiben
begrifflich getrennt. Eigene Organisationsfelder dürfen nicht als native
Codex-Konfigurationsschlüssel ausgegeben werden.

[MUST] Der implementierte Scope bleibt auf Koordinatorprofil, persönlichen
Installationsweg und Startdokumentation beschränkt. Teamleiter, Spezialisten
und Fensterautomatik werden nicht als implementiert oder aktiviert dargestellt.

[MUST] Die Repository-`AGENTS.md` bleibt auf ausdrücklichen Benutzerwunsch leer.
Sie dient nicht der Installation oder Aktivierung des Koordinatorprofils.

[MUST] Änderungen müssen auf den jeweils ausdrücklich zugewiesenen Scope
begrenzt bleiben; vorhandene fremde Arbeiten dürfen nicht überschrieben werden.
