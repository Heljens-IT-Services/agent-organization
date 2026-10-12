# Entscheidung 0001: Heljens-Aufgabenverwaltung v1

Stand: 12. Oktober 2026. Grundlage: Epic #5 und Stories #12/#13.

PowerShell 5.1, Codex, JSON und Markdown bilden die erste Version für Heljens IT
Services. Bestehende Rollen, Fensterstarter und Tokenledger werden wiederverwendet.
Maximal drei Agentenebenen, beliebig tiefe WorkItems. GitHub-Issues planen die
Implementierung; der laufende Aufgabenbestand liegt künftig in der eigenen Verwaltung.

| Bereich | Verbindlicher Ort |
|---|---|
| Rollen/Kontaktindizes | unverändert `koordinator/`, `teams/` |
| Datenverträge und Beispiele | `schemas/`, `examples/` |
| PowerShell und gemeinsame Prüfhelfer | `scripts/`, `scripts/contracts/` |
| Verträge und Abnahmebelege | `docs/contracts/` |
| Lokaler Aufgabenbestand | künftig `runtime/workitems.json`, nicht in Git |
| Hostzustand/Ereignisse | künftig `runtime/host/`, `runtime/events/` |
| Delegation und vorhandener Tokenledger | künftig `runtime/delegations/` |
| Wissen/Workflows | künftig `knowledge/INDEX.md`, `workflows/INDEX.md` mit Markdown-Verweisen |

## Festgelegte Folgearbeiten

- Epic #6: validierte, gesperrte, atomare Speicherung mit Wiederanlauf;
  der gespeicherte Vorzustand dient der Übergangsprüfung.
- Epic #7: genau ein logischer Koordinator im ereignisgesteuerten PowerShell-Host;
  Sitzungen fortsetzen, keine Modellaufrufe im Leerlauf, getrennte langfristige Ziele.
- Epic #8: WorkItems mit vorhandenen sichtbaren Aufträgen und Ergebnissen verbinden.
  Teamleiter planen fachlich mit erforderlichen Spezialisten; der Koordinator
  bestimmt keine operative Besetzung oder interne Zusammenarbeit.
- Epic #9: lokale Web-Oberfläche auf demselben Bestand und ein gemeinsames
  `humanInteraction`-Modell für alle erforderlichen menschlichen Aktionen.
- Epic #10: Wissen/Workflows selektiv laden. Produktive Selbstverbesserung benötigt
  ein WorkItem und vorherige menschliche Freigabe; keine eigenmächtigen produktiven Rollenänderungen.
- Epic #11: vorhandene Tokenmessung WorkItems zuordnen, ohne Doppelzählung;
  integrierten Gesamtpilot einschließlich Wiederanlauf und Mehrzielbetrieb nachweisen.

Diese Orte und Grenzen sind festgelegt, die Folgefunktionen noch nicht implementiert.
Der Koordinator ist für alle Repositoryarbeiten die verpflichtende Top-Level-Rolle
und der Benutzerkontakt, ohne Wartungsausnahme. Ausdrücklich zugewiesene Teamleiter
und Spezialisten behalten ihre eigene Rolle. Fachliche Architektur braucht
Spezialistenbeiträge. Vertrieb bleibt innerhalb vorhandener Teams; neue Besetzung
wird zunächst vorgeschlagen.

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
