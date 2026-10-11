# Agent Organization

Versionierte Agentenorganisation für Heljens IT Services: Ein Koordinator nimmt
Anfragen entgegen, Teamleiter koordinieren Fachbereiche und Spezialisten führen
die operative Arbeit aus.

Vorgesehen sind sieben Teams: Softwareentwicklung, Design, Marketing,
Controlling, Buchhaltung, Geschäftsführung und Assistenz sowie HR.

**Status:** Koordinatorprofil und ausdrücklicher CLI-Hauptstart sind implementiert.
Die [Installations- und Startanleitung](docs/COORDINATOR.md) beschreibt die
persönlichen Kopien und offenen Grenzen zum App-Hauptchat. Teamleiter und
Spezialisten sind noch nicht als Agentenprofile implementiert.

Zusätzliche Soll-Anforderung: Jeder Auftrag an einen Teamleiter oder
Spezialisten soll vor Arbeitsbeginn automatisch ein eigenes Codex-App-Fenster
mit seinem sichtbaren Auftragskontext öffnen und nach gesichertem Abschluss
wieder schließen. Diese Fenstersteuerung ist unimplementiert; ihre technische
Machbarkeit bleibt offen.

Das [Konzept](docs/CONCEPT.md) beschreibt Hierarchie, Teams, Konfigurationsidee
und offene Umsetzungspunkte. Die [Projektleitplanken](PROJECT.md) begrenzen den
aktuellen Scope. [AGENTS.md](AGENTS.md) ist auf Benutzerwunsch leer; die
Koordinatorinstruktionen liegen eigenständig in den TOML-Dateien.

Voraussetzungen für Installation und CLI-Start: Windows PowerShell und eine
Codex-Version mit separaten Profil-Dateien. Build und CI sind nicht vorhanden;
GitHub Actions sind deaktiviert.
