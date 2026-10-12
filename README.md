# Agent Organization

Versionierte Agentenorganisation für Heljens IT Services: Ein Koordinator nimmt
Anfragen entgegen, Teamleiter koordinieren Fachbereiche und Spezialisten führen
die operative Arbeit aus.

Es gibt neun Teams: Softwareentwicklung, Design, Marketing, Controlling,
Buchhaltung, Geschäftsführung und Assistenz, HR, Agent Ressources und Administratoren.

**Status:** [koordinator/koordinator.toml](koordinator/koordinator.toml) ist implementiert und
bytegleich unter `~/.codex/agents/koordinator.toml` installiert. Die TOML allein
aktiviert den App-Hauptchat nicht automatisch. Alle neun Teamleiter und 35
operative Rollen sind implementiert und persönlich installiert: zehn
koordinierende Rollen einschließlich Koordinator, insgesamt 45 TOMLs.
Die Teamleiter nutzen ihre jeweiligen `teams/<team_id>/agenten.json`-Indizes.

[Fensterdelegation](docs/FENSTERDELEGATION.md) startet einen parametrischen Auftrag
im eigenen sichtbaren PowerShell-Fenster, zeigt Kontext vor Arbeitsbeginn und
schließt nach gesichertem Ergebnis. Der Ablauf wurde mit einer tatsächlichen
QA-Aufgabe geprüft. Die automatische Anbindung sämtlicher Delegationen ist offen.

Das [Konzept](docs/CONCEPT.md) beschreibt Hierarchie, Teams, Konfigurationsidee
und offene Umsetzungspunkte. Die [Projektleitplanken](PROJECT.md) begrenzen den
aktuellen Scope. [AGENTS.md](AGENTS.md) macht den Koordinator für alle Repositoryarbeiten zur
verpflichtenden Top-Level-Rolle; ausdrücklich zugewiesene Teamleiter und
Spezialisten behalten ihre eigene Rolle. Der Koordinator beauftragt ausschließlich
Teamleiter; diese entscheiden selbst über ihre operative Besetzung.
Empfindliche Organisationsstrukturen werden ausschließlich über
Koordinator -> zuständiger Teamleiter -> Optimierer geändert, mit abgegrenztem
WorkItem und vorheriger menschlicher Freigabe; [AR55](docs/contracts/AR55-IMPLEMENTATION.md)
belegt die lokale Umsetzung und die noch ausstehende unabhängige Abnahme.

Koordinator, alle Teamleiter, Softwarearchitektur, Software-Qualitätssicherung,
Agent-Ressources-Qualitätsprüfung, Optimierer und Vertragskoordination verwenden `gpt-6.1-sol`;
die übrigen Rollen `gpt-6-luna`. Reasoning bleibt überall `medium`. Administratoren nutzen
vorhandene MCP-Werkzeuge oder Browsersteuerung; Dienstzugänge sind separat nötig.

Voraussetzung ist Codex mit standalone Custom Agents. Build und CI sind nicht
vorhanden; GitHub Actions sind deaktiviert.

[WorkItem-Verträge](docs/contracts/WORKITEMS.md) trennen Umsetzung und Abnahme;
[Organisationsverträge](docs/contracts/ORGANIZATION.md) validieren die bestehenden
Indizes. [Entscheidung 0001](docs/decisions/0001-system-scope.md) legt Struktur und
Folgeumfang fest. Prüfung unter Windows PowerShell 5.1:

```powershell
.\scripts\tests\contracts\Test-Contracts.ps1
.\scripts\contracts\Test-Organization.ps1
```
