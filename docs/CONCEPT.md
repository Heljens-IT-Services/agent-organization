# Konzept der Agentenorganisation

## Ziel und Verantwortungen

Der Benutzer arbeitet ausschließlich mit dem Koordinator. Dieser klärt das Ziel,
legt Scope und Zuständigkeiten fest, beauftragt die passenden Teamleiter und
bündelt deren Ergebnisse zu einer verständlichen Rückmeldung. Er arbeitet nicht
operativ.

Jeder Teamleiter plant und koordiniert die Arbeit seines Fachbereichs, vergibt
abgegrenzte Aufträge an Spezialisten und prüft, ob die Rückgaben den Auftrag
abdecken. Er arbeitet ebenfalls nicht operativ. Spezialisten erstellen,
analysieren, implementieren oder prüfen die beauftragten Ergebnisse.

## Vorgesehene Teams

Der vorgesehene Grundbestand umfasst sieben Teams. Jeder Fachbereich wird
konzeptionell durch einen Teamleiter koordiniert; die operative Arbeit liegt
bei den vorgeschlagenen Spezialisten.

| Team | Fachlicher Schwerpunkt | Mögliche operative Spezialisierungen |
|---|---|---|
| Softwareentwicklung | Technische Lösungen und Softwarequalität | Architektur, Implementierung, Tests, Betrieb |
| Design | Gestaltung und Nutzererlebnis | UX, UI, visuelle Gestaltung, Designprüfung |
| Marketing | Positionierung und Kommunikation | Inhalte, Kampagnen, Kanalbetreuung, Auswertung |
| Controlling | Wirtschaftliche Planung und Steuerung | Kennzahlen, Budgetplanung, Abweichungsanalyse |
| Buchhaltung | Belege und buchhalterische Abläufe | Belegaufbereitung, Abstimmung, Auswertungen |
| Geschäftsführung und Assistenz | Verträge, Outlook/E-Mail und Kundenkommunikation | Vertragskoordination, Outlook-/E-Mail-Assistenz, Kundenkommunikation |
| HR | Personalthemen | Personaladministration, Recruiting, Personalentwicklung |

Die Spezialisierungen sind Vorschläge für eine spätere Konfiguration. Sie sind
keine bereits installierten oder freigegebenen Agentenprofile.

Vertragskoordination beschreibt einen vorgesehenen Aufgabenbereich und enthält
keine Garantie rechtlicher Fachkompetenz. Das Versenden von E-Mails erfordert
eine konkrete Autorisierung; die Konzeptänderung autorisiert keinen Versand.

## Konfiguration

Das Repository soll die versionierte Quelle der Organisation werden. Rollen,
Verantwortungen, Teamzuordnung und Mitgliedschaft sollen nachvollziehbar und
änderbar beschrieben werden. TOML ist ein möglicher Dateityp.

Zwei Ebenen sind zu unterscheiden:

- **Organisationsbeschreibung:** Eigene Konvention für Teams, Teamleiter,
  Mitglieder, Zuständigkeiten und Delegationsregeln.
- **Codex-Agentenprofile:** Nur tatsächlich unterstützte Laufzeitfelder für
  einzelne Agenten, beispielsweise Namen, Beschreibung und Instruktionen nach
  Prüfung des aktuellen Schemas.

Eine eigene Organisationsbeschreibung installiert oder lädt Codex nicht
automatisch. Native Schlüssel wie `team` oder `leader` werden hier nicht
behauptet. Dateistruktur, Schema, Validierung, Synchronisierung und Aktivierung
müssen in einem späteren Umsetzungsschritt konkret festgelegt werden.

`roles/koordinator.toml` enthält die eigenständigen Koordinatorinstruktionen und
ist bytegleich unter `~/.codex/agents/koordinator.toml` installiert. Die TOML
allein aktiviert den App-Hauptchat nicht automatisch. Der Teamleiter
Softwareentwicklung ist nun implementiert und persönlich installiert; seine
fünf operativen Spezialisierungen bleiben geplant. Andere Teamleiter und operative
Agenten sind unimplementiert. Die Repository-`AGENTS.md` ist auf Benutzerwunsch leer.

[MUST] Weitere Rollen verwenden dieselbe kompakte Struktur und die technischen
Defaults `gpt-6.1-sol`, Reasoning `medium`, Antwortlänge `medium`,
`danger-full-access`, `never` und `cached`.
`name`, `description` und `developer_instructions` bleiben rollenspezifisch.
`agents.enabled` ist beim Koordinator `true`, bei operativen Rollen ohne
Delegationsberechtigung `false`. MCP und `skills.config` werden individuell
konfiguriert. Die zehn Optionen bilden die Basis, keine Pflicht zu zehn
Kommentarblöcken. `tool_output_token_limit` bleibt ungesetzt: Vererbung oder
Laufzeitdefault, kein behauptetes unbegrenztes Budget.

[MUST] Rollen kennen standardmäßig nur ihre direkten Nachbarn: Der Koordinator
kennt die sieben Teamleiter, keine Spezialistenliste. Ein Teamleiter kennt den
Koordinator und ausschließlich seine eigenen operativen Agenten; ein operativer
Agent kennt ausschließlich seinen eigenen Teamleiter. Fachdetails und Besetzung
liegen beim Teamleiter, Ergebnisse gehen über ihn an den Koordinator.
Teamübergreifende Anliegen werden über den Koordinator vermittelt. Diese
Kontextregel ist keine technische Zugriffssperre und erfindet keine nativen
Beziehungsfelder oder bereits verfügbaren Teamleiterprofile.

[MUST] Übergaben enthalten nur den Auftrag und benötigten Kontext, keine
vollständige Organisations-/Agentenliste und keinen ungefilterten Verlauf.

[MUST] `teams.json` ist die einzige Kontaktquelle des Koordinators und wird
bytegleich unter `$CODEX_HOME/agents/teams.json` installiert (Standard:
`~/.codex/agents/teams.json`). Dieser eigene JSON-Index ist kein natives
Codex-Schema. Änderungen an Teams, Namen, Teamleitern, Beschreibungen oder Aufgaben
müssen im selben Änderungssatz den Index und seine persönliche Kopie pflegen.
`team_id` und `leader_id` sind stabile organisatorische Kennungen. Geplante
Teamleiter haben `status: planned` und `role_file: null`; `configured` ist erst
mit einer tatsächlich vorhandenen, geprüften Rollenreferenz zulässig.
`role_file` bezeichnet dann eine Datei relativ zum persönlichen `agents`-Verzeichnis.
Der Index enthält keine Spezialistenliste.

[MUST] Ein Teamleiter erhält nur seinen eigenen Teameintrag und Auftrag, nicht
den vollständigen `teams.json`-Index. `softwareentwicklung.json` ist die eigene
Kontaktquelle des Softwareteamleiters und wird bytegleich im persönlichen
`agents`-Verzeichnis installiert. Rollenreferenzen einschließlich
`coordinator_role_file` sind relativ zu diesem Verzeichnis. Änderungen an eigener
Besetzung oder Rollenreferenzen pflegen Quelle und persönliche Kopie im selben
Änderungssatz. Geplante operative Agenten bleiben `planned` mit `role_file: null`.

## Delegation und Kapazität

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

**Status: verbindliche Soll-Anforderung, unimplementiert.** Die aktuelle Sitzung
erfüllt die automatische Fenstersteuerung bislang nicht. Ihre technische
Machbarkeit ist offen.

Jede neue Aufgabe an einen Agenten außer dem Koordinator soll automatisch ein
eigenständiges Codex-App-Fenster öffnen. Das gilt für Teamleiter und Spezialisten
sowie für jeden neuen Auftrag an einen wiederverwendeten Agenten. Das Fenster
muss vor Arbeitsbeginn sichtbar sein und den zugehörigen sichtbaren
Auftragskontext beziehungsweise Thread zum Mitlesen zeigen. Auftrag, Agent und
Fenster müssen eindeutig einander zugeordnet sein.

Scheitert das Öffnen des vorgesehenen Fensters, darf der Auftrag nicht
unbemerkt starten. Der Koordinator muss das Hindernis melden. Eine Aktivierung
dieses Ablaufs setzt einen erfolgreichen Funktionsnachweis voraus.

Nach terminalem Aufgabenstatus und Sicherung des Ergebnisses soll ausschließlich
das zugehörige Fenster automatisch geschlossen werden. Ein Wartezustand oder
eine offene Rückfrage bedeutet keinen Abschluss. Historie und Ergebnisse müssen
erhalten bleiben; Fenster schließen darf sie nicht löschen. Sichtbarer Kontext
umfasst keine Authentifizierungsdaten, Secrets oder verborgenen Modellgedanken.

Ein separates App-Fenster, ein Terminalfenster und eine Threadansicht sind
unterschiedliche Oberflächen. Terminal, Threadliste, Link oder zusätzlicher Tab
sind keine stillschweigende Ersatzlösung für die geforderte Fensterdarstellung.
Ein Thread-Lifecycle-Ereignis ist kein Nachweis für ein geschlossenes App-Fenster.

### Dokumentierter technischer Befund

Prüfstand: 11. Oktober 2026, offizielle OpenAI Docs und lokale CLI-Hilfe.

- Die [App-Kommandoreferenz](https://learn.chatgpt.com/docs/reference/commands#deep-links)
  beschreibt `codex://threads/<thread-id>` zum Öffnen lokaler Chats und
  Tastaturbefehle für einen neuen eigenständigen Chat sowie das Schließen des
  aktuellen Tabs oder Fensters. Damit sind UI-Funktionen und Thread-Links belegt.
  Eine automatische, eindeutige Zuordnung eines bestehenden Subagenten zu einem
  neuen App-Fenster und dessen gezieltes Schließen ist damit nicht belegt.
- Der [Codex App Server](https://learn.chatgpt.com/docs/app-server#api-overview)
  dokumentiert Thread-Erstellung, Lesen, Ereignisse und Subagentfilter. Das sind
  mögliche Integrationsbausteine für Auftragsbeobachtung, kein dokumentierter
  Desktop-Fenstercontroller. `thread/closed` bezeichnet das Entladen eines
  Threads nach fehlenden Abonnenten und Inaktivität; es bedeutet nicht, dass ein
  App-Fenster geschlossen wurde. `thread/delete` löscht dagegen gespeicherte
  Threads samt Nachkommen und ist für Fensterschließung ungeeignet.
- Die lokal gelesenen Hilfen `codex --help` und `codex app --help` beschreiben
  den App-Start mit einem Workspace-Pfad. Sie belegen keine Optionen für
  auftragsspezifische Fenstererstellung, Fenster-IDs oder gezieltes Schließen.

In diesen geprüften öffentlichen Quellen ist keine native Schnittstelle für
den vollständigen geforderten Fensterablauf belegt. Das ist keine Behauptung,
dass die Umsetzung grundsätzlich unmöglich ist. Vor Umsetzung sind ein
unterstützter Integrationsweg, Zugriff auf delegierte Threads, verlässliche
Fensteridentität sowie eine schadlose Abschlussbehandlung nachzuweisen. TOML
allein aktiviert diesen Ablauf nicht; native Fensterschlüssel werden nicht
angenommen.

## Nachvollziehbarkeit und nächste Schritte

Git-Versionierung soll Änderungen an Organisation und Profilen nachvollziehbar
machen. Revisionssicherheit meint hier diese versionierte Nachvollziehbarkeit;
eine unveränderbare Historie oder rechtliche Archivierung wird nicht zugesichert.

Vor vollständiger Aktivierung sind Organisationsschema, weitere Agentenprofile, Integrationsweg,
Rechte und eine prüfbare Pilotaufgabe festzulegen. Persönlich installiert sind
Koordinator, Teamleiter Softwareentwicklung und ihre Indizes; GitHub Actions
bleiben deaktiviert.
