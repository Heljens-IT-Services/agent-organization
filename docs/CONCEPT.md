# Konzept der Agentenorganisation

## Ziel und Verantwortungen

Beim Einsatz der Agentenorganisation arbeitet der Benutzer mit dem Koordinator. Dieser klärt das Ziel,
legt Scope und Teamzuständigkeiten fest, beauftragt die passenden Teamleiter und
bündelt deren Ergebnisse zu einer verständlichen Rückmeldung. Er arbeitet nicht
operativ.

Für die erste Heljens-Version gelten [Entscheidung 0001](decisions/0001-system-scope.md),
der [WorkItem-Vertrag](contracts/WORKITEMS.md) und der
[Organisationsvertrag](contracts/ORGANIZATION.md). GitHub-Issues planen die Umsetzung;
der laufende Bestand gehört künftig in die eigene WorkItem-Verwaltung.

Jeder Teamleiter plant und koordiniert die Arbeit seines Fachbereichs, vergibt
abgegrenzte Aufträge an Spezialisten und prüft, ob die Rückgaben den Auftrag
abdecken. Er arbeitet ebenfalls nicht operativ. Spezialisten erstellen,
analysieren, implementieren oder prüfen die beauftragten Ergebnisse.
Teamleiter spezifizieren Teilziele mit erforderlichen Fachleuten. Keine Rolle
entscheidet fachliche Architektur ohne zuständigen Spezialistenbeitrag.
Umsetzung und Kinderabschlüsse ersetzen nicht die Prüfung eigener Elternkriterien.

## Vorgesehene Teams

Der vorgesehene Grundbestand umfasst neun Teams. Jeder Fachbereich wird
durch einen installierten Teamleiter koordiniert; die operative Arbeit liegt
bei den konfigurierten Spezialisten.

| Team | Fachlicher Schwerpunkt | Konfigurierte operative Spezialisierungen |
|---|---|---|
| Softwareentwicklung | Technische Lösungen und Softwarequalität | Architektur, Implementierung, Tests, Betrieb |
| Design | Gestaltung und Nutzererlebnis | UX, UI, Grafik, 3D |
| Marketing | Positionierung und Kommunikation | Strategie, Text, SEO, Kampagnen |
| Controlling | Wirtschaftliche Planung und Steuerung | Budget, Kennzahlen, Forecast, Reporting |
| Buchhaltung | Belege und buchhalterische Abläufe | Belege, Rechnungen, Kontierung, Abstimmung |
| Geschäftsführung und Assistenz | Verträge, Outlook/E-Mail und Kundenkommunikation | Vertragskoordination, Outlook-/E-Mail-Assistenz, Kundenkommunikation |
| HR | Personalthemen | Personaladministration, Recruiting, Personalentwicklung |
| Agent Ressources | Eignung vorhandener Agenten und Erstellung von Teams und Agenten | Bestandsanalyse, Rollenkonfiguration, Qualitätsprüfung |
| Administratoren | Administration von Diensten und Infrastruktur | Microsoft 365, SharePoint, GitHub, Hetzner |

Alle neun Teamleiter und 34 operative Rollen sind als TOMLs konfiguriert und
persönlich installiert. Installation allein beweist keine produktive Fachleistung.

Agent Ressources prüft zuerst Wiederverwendung und Erweiterung vorhandener
Agenten, bevor es begründete Neuanlagen vorbereitet. Unterstützung anderer
Teamleiter läuft ausschließlich über den Koordinator und benötigt nur passende
Fähigkeitsauszüge der jeweiligen Leiter, keine globale Spezialistenliste oder
direkten Kontakte zu anderen Teams.

Vertragskoordination beschreibt einen vorgesehenen Aufgabenbereich und enthält
keine Garantie rechtlicher Fachkompetenz. Das Versenden von E-Mails erfordert
eine konkrete Autorisierung; die Konzeptänderung autorisiert keinen Versand.

Administratoren nutzen vorhandene MCP-Werkzeuge oder Browsersteuerung mit geeignetem Skill. Dienstzugänge und Berechtigungen werden durch die Rollenanlage nicht eingerichtet.

## Konfiguration

Das Repository ist die versionierte Quelle der Organisation. Rollen,
Verantwortungen, Teamzuordnung und Mitgliedschaft sollen nachvollziehbar und
änderbar beschrieben werden. Native Rollen verwenden TOML, Kontaktindizes JSON.

Zwei Ebenen sind zu unterscheiden:

- **Organisationsbeschreibung:** Eigene Konvention für Teams, Teamleiter,
  Mitglieder, Zuständigkeiten und Delegationsregeln.
- **Codex-Agentenprofile:** Nur tatsächlich unterstützte Laufzeitfelder für
  einzelne Agenten, beispielsweise Namen, Beschreibung und Instruktionen nach
  Prüfung des aktuellen Schemas.

Eine eigene Organisationsbeschreibung installiert oder lädt Codex nicht
automatisch. Native Schlüssel wie `team` oder `leader` werden hier nicht
behauptet. Dateistruktur, Schema, Validierung, Synchronisierung und Aktivierung
sind durch die folgende eigene Lookupkonvention beschrieben.

`koordinator/koordinator.toml` enthält die eigenständigen Koordinatorinstruktionen und
ist bytegleich unter `~/.codex/agents/koordinator.toml` installiert. Die TOML
allein aktiviert den App-Hauptchat nicht automatisch. Zehn koordinierende Rollen
(Koordinator und neun Teamleiter) sowie 34 operative Rollen sind implementiert
und persönlich installiert. Repositorypflege erfolgt als normale Entwicklungsassistenz; der Koordinator wird nur ausdrücklich aktiviert. Zugewiesene Rollen folgen ihrer TOML.

[MUST] Weitere Rollen verwenden dieselbe kompakte Struktur und die technischen
Defaults `gpt-6-luna`, Reasoning `medium`, Antwortlänge `medium`,
`danger-full-access`, `never` und `cached`.
Koordinator, alle Teamleiter, Softwarearchitektur, Software-Qualitätssicherung,
Agent-Ressources-Qualitätsprüfung und Vertragskoordination verwenden abweichend
`gpt-6.1-sol`; Reasoning bleibt `medium`.
`name`, `description` und `developer_instructions` bleiben rollenspezifisch.
[MUST] Rollenbeschreibungen bleiben ein kurzer Satz; Instruktionen enthalten
nur die präzisen Zuständigkeiten, Übergaben und notwendigen Grenzen.
`agents.enabled` ist beim Koordinator und Teamleitern `true`, bei operativen Rollen ohne
Delegationsberechtigung `false`. MCP und `skills.config` werden individuell
konfiguriert. Die zehn Optionen bilden die Basis, keine Pflicht zu zehn
Kommentarblöcken. `tool_output_token_limit` bleibt ungesetzt: Vererbung oder
Laufzeitdefault, kein behauptetes unbegrenztes Budget.

[MUST] Rollen kennen standardmäßig nur ihre direkten Nachbarn: Der Koordinator
kennt die neun Teamleiter, keine Spezialistenliste. Ein Teamleiter kennt den
Koordinator und ausschließlich seine eigenen operativen Agenten; ein operativer
Agent kennt ausschließlich seinen eigenen Teamleiter. Der Koordinator liest keine operativen Indizes, kontaktiert keine Spezialisten und schreibt weder deren Auswahl noch deren Interaktionen vor. Fachdetails und Besetzung
liegen beim Teamleiter, Ergebnisse gehen über ihn an den Koordinator.
Teamübergreifende Anliegen werden über den Koordinator vermittelt. Diese
Kontextregel ist keine technische Zugriffssperre und erfindet keine nativen
Beziehungsfelder.

[MUST] Übergaben enthalten nur den Auftrag und benötigten Kontext, keine
vollständige Organisations-/Agentenliste und keinen ungefilterten Verlauf.

[MUST] `koordinator/teams.json` ist die einzige Kontaktquelle des Koordinators und wird
bytegleich unter `$CODEX_HOME/agents/koordinator/teams.json` installiert (Standard:
`~/.codex/agents/koordinator/teams.json`). Dieser eigene JSON-Index ist kein natives
Codex-Schema. Änderungen an Teams, Namen, Teamleitern, Beschreibungen oder Aufgaben
müssen im selben Änderungssatz den Index und seine persönliche Kopie pflegen.
`team_id` und `leader_id` sind stabile organisatorische Kennungen. Verfügbarkeit
wird ausschließlich durch `role_file` ausgedrückt: `null` bedeutet fehlende Rolle;
eine Rollenreferenz muss auf eine tatsächlich vorhandene, geprüfte Datei zeigen.
`role_file` bezeichnet dann eine Datei relativ zum persönlichen `agents`-Verzeichnis.
Der Index enthält keine Spezialistenliste.

[MUST] Ein Teamleiter erhält nur seinen eigenen Teameintrag und Auftrag, nicht
den vollständigen `koordinator/teams.json`-Index. `teams/<team_id>/agenten.json` ist die eigene
Kontaktquelle des jeweiligen Teamleiters und wird bytegleich unter
`$CODEX_HOME/agents/<team_id>/agenten.json` installiert. Rollenreferenzen einschließlich
`coordinator_role_file` sind relativ zum persönlichen `agents`-Verzeichnis. Änderungen an eigener
Besetzung oder Rollenreferenzen pflegen Quelle und persönliche Kopie im selben
Änderungssatz. Fehlende operative Rollen haben `role_file: null`.

[MUST] Alle Team- und Agentenindizes bleiben ohne `status`-Eigenschaften, auch in
verschachtelten Einträgen. Verfügbarkeit wird ausschließlich durch eine
vorhandene Rollenreferenz oder `role_file: null` ausgedrückt; keine Ersatzflags.

| Repositoryquelle | Persönliches Ziel relativ zu `$CODEX_HOME` |
|---|---|
| `koordinator/koordinator.toml` | `agents/koordinator.toml` |
| `koordinator/teams.json` | `agents/koordinator/teams.json` |
| `teams/<team_id>/teamleiter.toml` | `agents/teamleiter_<team_id>.toml` |
| `teams/<team_id>/agenten.json` | `agents/<team_id>/agenten.json` |
| `teams/<team_id>/agenten/<rolle>.toml` | `agents/<name>.toml` |

Die TOMLs bleiben für Codex-Discovery flach im persönlichen `agents`-Verzeichnis;
Lookupdaten liegen in den zugehörigen Unterordnern. Es gibt keine Aliasdateien.

## Delegation und Kapazität

Maximal drei Agentenebenen: Koordinator → Teamleiter → operativer Agent.
WorkItems bilden davon unabhängig beliebig tiefe Aufgabenbäume. Ziele enthalten
Messgrößen und Akzeptanzkriterien; der Koordinator priorisiert, Teamleiter planen
fachlich, Spezialisten liefern beauftragte Beiträge. Neue Besetzung wird vorgeschlagen.
Vertrieb liegt bei Marketing (Kundengewinnung) und Geschäftsführung und Assistenz
(Angebote, Verträge, Kundenkommunikation); Controlling unterstützt wirtschaftlich
über den Koordinator. Es entsteht kein zusätzliches Vertriebsteam.

Ein Auftrag geht vom Koordinator an einen passenden Teamleiter und von dort an
einen oder mehrere Spezialisten. Übergaben enthalten Ziel, Scope, Nicht-Scope,
Entscheidungen, Constraints und erwartetes Ergebnis. Rückgaben nennen Ergebnis,
Verifikation, Abweichungen und offene Punkte.

Die aktuelle Sitzung bietet vier gleichzeitige Agentenplätze einschließlich
Hauptagent. Damit passt ein Koordinator mit einem Teamleiter und zwei
Spezialisten gleichzeitig in die verfügbare Kapazität. Mehrere Teams werden bei
dieser Kapazität bedarfsgerecht oder nacheinander bearbeitet. Eine dauerhaft
größere parallele Hierarchie setzt andere Laufzeitgrenzen voraus.

## Sichtbarkeit je delegiertem Auftrag

Das vereinbarte Ziel ist ein eigenes sichtbares CMD-/PowerShell-Fenster mit
Codex-Auftrag und benötigtem Kontext. Die frühere Forderung nach einem separaten
Desktop-App-Fenster wurde damit ersetzt. Der parametrische
[Terminalstarter](FENSTERDELEGATION.md) prüft vor Arbeitsbeginn die Zuordnung von
Auftrag, Runner und tatsächlichem Fenster und startet erst nach bestätigter
Sichtbarkeit. Nach terminalem Ergebnis und Sicherung schließen Teamleiter und
Spezialisten nur ihr eigenes Aufgabenfenster; die Koordinatorkonsole bleibt immer
offen. Historie bleibt erhalten. Warten und Rückfragen sind kein Abschluss.

Dieser Ablauf wurde mit einer tatsächlichen QA-Aufgabe geprüft. Die automatische
Kopplung sämtlicher nativer Delegationen bleibt offen; ein späteres
`delegate_task`-MCP-Interface wäre eine gesonderte Umsetzung. Eine separate Sitzung
ist kein Beweis für eine generelle Trennung oder Umgehung von Berechtigungsregeln.

## Nachvollziehbarkeit und nächste Schritte

Git-Versionierung soll Änderungen an Organisation und Profilen nachvollziehbar
machen. Revisionssicherheit meint hier diese versionierte Nachvollziehbarkeit;
eine unveränderbare Historie oder rechtliche Archivierung wird nicht zugesichert.

Persönlich installiert sind 44 Rollen und zehn Lookupindizes. Fachliche Pilotaufgaben
und eine automatische Anbindung nativer Delegation bleiben gesonderte Schritte;
GitHub Actions bleiben deaktiviert. Die vorhandenen großzügigen technischen
Defaults sind keine durch die Instruktionen erzwungene Beschränkung.
