# Agent Organization

Versionierte Agentenorganisation für Heljens IT Services: Ein Koordinator nimmt
Anfragen entgegen, Teamleiter koordinieren Fachbereiche und Spezialisten führen
die operative Arbeit aus.

Vorgesehen sind sieben Teams: Softwareentwicklung, Design, Marketing,
Controlling, Buchhaltung, Geschäftsführung und Assistenz sowie HR.

**Status:** [roles/koordinator.toml](roles/koordinator.toml) ist implementiert und
bytegleich unter `~/.codex/agents/koordinator.toml` installiert. Die TOML allein
aktiviert den App-Hauptchat nicht automatisch. Teamleiter und Spezialisten sind
noch nicht als Agentenprofile implementiert.

Rollen-TOMLs enthalten standardmäßig zehn wichtige technische Optionen als
kommentierte Beispiele. Nur bewusst gewählte Einstellungen werden aktiviert;
die drei Pflichtfelder werden separat geführt.

Beim Koordinator sind Modell, Reasoning, Antwortlänge, vollständiger Zugriff,
Freigabemodus, effiziente Websuche und Delegation bewusst gesetzt. Ein
unbegrenztes Tool-Ausgabelimit ist nicht dokumentiert; das Feld bleibt ungesetzt
und verwendet Vererbung beziehungsweise Laufzeitdefault.

Zusätzliche Soll-Anforderung: Jeder Auftrag an einen Teamleiter oder
Spezialisten soll vor Arbeitsbeginn automatisch ein eigenes Codex-App-Fenster
mit seinem sichtbaren Auftragskontext öffnen und nach gesichertem Abschluss
wieder schließen. Diese Fenstersteuerung ist unimplementiert; ihre technische
Machbarkeit bleibt offen.

Das [Konzept](docs/CONCEPT.md) beschreibt Hierarchie, Teams, Konfigurationsidee
und offene Umsetzungspunkte. Die [Projektleitplanken](PROJECT.md) begrenzen den
aktuellen Scope. [AGENTS.md](AGENTS.md) ist auf Benutzerwunsch leer; die
Koordinatorinstruktionen liegen eigenständig in der Rollen-TOML.

Voraussetzung ist Codex mit standalone Custom Agents. Build und CI sind nicht
vorhanden; GitHub Actions sind deaktiviert.
