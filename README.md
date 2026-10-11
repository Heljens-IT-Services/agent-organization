# Agent Organization

Versionierte Agentenorganisation für Heljens IT Services: Ein Koordinator nimmt
Anfragen entgegen, Teamleiter koordinieren Fachbereiche und Spezialisten führen
die operative Arbeit aus.

Vorgesehen sind acht Teams: Softwareentwicklung, Design, Marketing,
Controlling, Buchhaltung, Geschäftsführung und Assistenz, HR sowie Agent Ressources.

**Status:** [koordinator/koordinator.toml](koordinator/koordinator.toml) ist implementiert und
bytegleich unter `~/.codex/agents/koordinator.toml` installiert. Die TOML allein
aktiviert den App-Hauptchat nicht automatisch. Alle acht Teamleiter und 30
operative Rollen sind implementiert und persönlich installiert: neun
koordinierende Rollen einschließlich Koordinator, insgesamt 39 TOMLs.
Die Teamleiter nutzen ihre jeweiligen `teams/<team_id>/agenten.json`-Indizes.

[Fensterdelegation](docs/FENSTERDELEGATION.md) startet einen parametrischen Auftrag
im eigenen sichtbaren PowerShell-Fenster, zeigt Kontext vor Arbeitsbeginn und
schließt nach gesichertem Ergebnis. Der Ablauf wurde mit einer tatsächlichen
QA-Aufgabe geprüft. Die automatische Anbindung sämtlicher Delegationen ist offen.

Das [Konzept](docs/CONCEPT.md) beschreibt Hierarchie, Teams, Konfigurationsidee
und offene Umsetzungspunkte. Die [Projektleitplanken](PROJECT.md) begrenzen den
aktuellen Scope. [AGENTS.md](AGENTS.md) legt ohne ausdrückliche andere
Rollenzuweisung den Koordinator als Hauptrolle fest; ausdrücklich zugewiesene
Agenten erfüllen ihre eigene TOML, auch in eigenständigen Terminal-Sitzungen.

Voraussetzung ist Codex mit standalone Custom Agents. Build und CI sind nicht
vorhanden; GitHub Actions sind deaktiviert.
