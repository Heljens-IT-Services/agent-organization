# Fachbeitrag: Epic #71 Produktmanagement-Architektur

Adressat: `teamleiter_agent_ressources`  
Rolle: `agent_ressources_rollenkonfiguration`  
Ergebnisart: read-only Facharchitektur; keine Implementierung und keine Abnahme.

## Entscheidungsvorschlag

Übernimm die vorhandene PM/PO-Aufteilung aus dem angenommenen PM-Artefakt (TEMP `agent-org-productmanagement-76-72-20261012-173049/final/draft/`):

1. `koordinator` (fachliche Gesamt-/Cross-Team-Steuerung)
2. `teamleiter_produktmanagement` (PM-Teamleitung und Routing, kein weiterer operativer Produktakteur)
3. `produktmanagement_pm_strategie` und `produktmanagement_po_backlog` als Geschwisterrollen

PM erstellt Vision, Strategie, Roadmap und begründete Featurehypothesen. PO übersetzt eine ausdrücklich freigegebene Strategie in priorisierte Backlogelemente, Abhängigkeiten und fachliche Akzeptanzkriterien. Beide geben Ergebnisse ausschließlich über ihre Teamleitung aneinander weiter; PO erzeugt keine ungeprüfte Strategie und PM steuert keine Fachteamumsetzung direkt. Bei Auswirkung auf Fachbereiche erstellt/aktualisiert PO ein begrenztes WorkItem; der bestehende Koordinator routet es an die zuständige Teamleitung. Das hält die Hierarchie bei maximal drei Ebenen und erhält den Organisationsvertrag „Koordinator → Teamleiter → Optimierer“ für geschützte Änderungen.

Defaults aus dem angenommenen Vorschlag beibehalten: Teamleitung `gpt-6.1-sol`, operative PM/PO `gpt-6-luna`, jeweils `medium` reasoning/verbosity, `web_search=cached`; Agenten für Teamleitung aktiviert und für die beiden nicht delegierenden Fachrollen deaktiviert. Keine neue Rolle oder Skill/MCP-Erweiterung ist fachlich erforderlich.

## Solutionidentität, Index und Ground

Die neue Solution braucht eine konfigurierbare, dauerhafte `solutionId` als fachlichen Schlüssel, getrennt von Anzeigename, Repositorypfad, WorkItem-ID, Laufzeitthread und Session-ID. PM-Identität muss ebenfalls konfigurierbar und stabil sein. Beide Werte gehören in die bestehende Solution-/PM-Konfiguration und müssen in Session-, Ereignis- und Gedächtnisrecords unverändert referenziert werden. Nicht aus Arbeitsverzeichnis, Rollenname, Thread-ID oder temporären Identifikatoren ableiten. Format, konkrete ID, Speicherort/Owner der Solutionkonfiguration und Identitätsautorität sind im bereitgestellten Paket nicht festgelegt; keine Beispiel-ID als Produktentscheidung übernehmen.

Der kanonische Ground-Index darf ausschließlich tatsächlich vorhandene HELJOS/Heljens-Belege enthalten und pro Eintrag mindestens Quelle/Originalpfad, gelesene Identität, Änderungs-/Versionsbezug sowie einen klaren Unknown-/Missing-Status binden. Keine erfundenen Produktpfade, Strategieinhalte, Ziele oder Fähigkeiten auffüllen. Das hier zugängliche PM-Paket enthält einen PM-Vorschlag, aber keine konkret zugeordnete HELJOS/Heljens Solution und keinen lesbaren Ground-Katalog. Issue-Inventar wurde nicht erneut erhoben. Daher ist der Index als Datenquelle ein Implementierungs-Gate: erst freigegebene Solution-Zuordnung und autorisierter Owner-/Lesepfad; bis dahin leere/unbekannte Beleglage, keine Produktbehauptung.

## Persistente Aktivierung, Serialisierung und Recovery

Re-use der persistenten CoordinatorHost-Sitzung und ihrer Store-/Event-/Registrypfade. Ein Solution-Sessionrecord referenziert `solutionId`, PM-Identität, Rootjob und Hash, Coordinator-Launchkonfiguration und Hash, `LogicalSessionId`, tatsächliche Runtime-Threadbindung, Eventjournal, WorkItem-Store-Revision, Generation/Owner sowie Zustand. Die PM-Aktivierung ist ein serialisierter Auftrag mit idempotenter Effect-ID: vor Dispatch immutable Input-/Hashbeleg schreiben, danach Dispatch/Owner registrieren und erst dann Status/Receipt veröffentlichen. Exakte Wiederholung liefert denselben Receipt; Konflikt oder unbestätigter Commit bleibt gesperrt und verlangt Recovery, nicht einen zweiten Start.

Der vorhandene CoordinatorHost bindet bereits Rootjob, Launchkonfiguration, Store, Eventjournal, Registry und persistierte Session; Abweichungen münden in `BlockedRecovery` (siehe `scripts/Start-CoordinatorHost.ps1`, insbesondere Initialisierung und Rootgruppenabgleich). `scripts/coordinator/CoordinatorHost.Core.psm1` bindet Requests an `LogicalSessionId`, Thread und Turn. `scripts/coordinator/Resume.Automation.ps1` setzt bereits ereignisgebundene WorkItems nach belegtem terminalem Turn, CAS-Store-Receipt und Resume-Receipt fort. Diese Schiene für PM/PO-WorkItemfortsetzung erweitern, statt zweiten Host oder separate Sessionmechanik einzuführen.

Lokaler Quellbefund belegt keine unterstützte allgemeine Codex-CLI-Threadfortsetzung für einen dauerhaft weiterlaufenden PM-Dialog. `Resume.Automation.ps1` ist eine WorkItem-/Coordinator-Automation mit Providerhistory-Bindung und keine CLI `--resume`-Freigabe. Der Host verwendet Runtime-/App-Server-Protokollierung und verlangt bei fehlender History/Bindung kontrollierte Recovery. Daher: zulässige Fortsetzung nur über den bestehenden Host/App-Server-Owner und belegte Thread-/Turnrecords; bevor ein produktiver Pfad eine Codex-Threadfortsetzung behauptet, muss der zuständige Runtime-/Providerowner die lokale unterstützte API/Version und tatsächliche History-Zuordnung liefern. Keine nicht belegte CLI-Option hinzufügen.

Recovery ist dokument- und quellenbasiert: Job/Launch/session/event/dispatch/turn/receipt/store-Revision anhand gespeicherter Originalbytes und Hashes vergleichen; eindeutigen letzten committed Zustand rekonstruieren; bei fehlendem/mehrdeutigem Owner, Thread, Turn oder Commit `BlockedRecovery` erhalten. Wiederaufnahme erfordert einen dokumentierten Recoveryreceipt mit Quelle, Hash, Entscheidung und neuer Generation; keine Fake-ACKs, keine synthetische Session und keine stille Lease-/Lockfreigabe. Vorhandene Prestart-Recovery in `scripts/workitems/WorkItemPrestartRecovery.psm1` und `Recover-WorkItemPrestartFailure.ps1` sowie CAS-/Outboxverträge in `WorkItemStore.psm1` wiederverwenden.

## Selektives Produktgedächtnis und Entscheidungen

Produktgedächtnis ist kein Gesprächstranskript. Pro `solutionId` werden nur explizit ausgewählte, freigegebene und quellengebundene Fakten, Entscheidungen, verworfene Optionen, offene Annahmen/Risiken und Outcome-/Review-Beobachtungen fortgeschrieben. Ein Eintrag trägt mindestens Typ, Inhalt, Quelle/WorkItem/Review, Status (angenommen/ersetzt/offen), Zeit-/Versionbezug und Hash. PM darf strategische Entscheidungsvorschläge erstellen; PO darf Backlogableitungen daran binden. Nur ein explizites Review-/Freigabeereignis kann eine Entscheidung als angenommen markieren. Neue Evidence ergänzt/verweist auf Historie und ersetzt nie stillschweigend den alten Entscheidungsbeleg. Beim Promptaufbau nur aktive solution-relevante Einträge samt Herkunft laden; keine globalen Agentenmemorys oder fremden Solutions einbeziehen.

Minimale Erweiterung: den vorhandenen WorkItem-/Effectreceipt- und Eventjournalmechanismus als Source-of-Truth und Outbox nutzen; keine zweite Datenbank, keine dauerhafte Transcriptablage und keine Dokumentationskampagne. Ein eng begrenzter Solution-Konfigurations-/Memory-Record ist nur dann neu anzulegen, wenn kein vorhandenes WorkItem-/Sessionfeld diese Identitäten und Referenzen verlustfrei abbilden kann.

## Ereignis-/Review-getriebener PM → PO → Fachteam-Pfad

1. Ein echtes Ereignis (neues/geändertes WorkItem, gültige menschliche Antwort, fällige Erinnerung, Rücklauf/Review) wird im bestehenden Eventjournal publiziert und mit Solution/WorkItem/Revision gebunden.
2. Coordinator beansprucht Ereignis einmalig; auf unverändertem Snapshot erzeugt PM bei Strategiebedarf oder PO bei Backlog-/Reviewbedarf einen begrenzten Auftrag. Kein Modellaufruf bei leerem Queue, unverändertem Revision-/Eventstand oder bereits abgeschlossenem Effect.
3. PM-Ausgabe geht als quellengebundener Vorschlag an Teamleitung. Nach Review/Freigabe erzeugt PO die Backlogänderung bzw. präzise Fachteam-WorkItems mit Abhängigkeiten und prüfbaren fachlichen Kriterien.
4. Coordinator routet diese WorkItems an vorhandene Fachteamleitungen über den vorhandenen sichtbaren Starter und dokumentiert Dispatch-/Return-/Reviewereignisse. Rückläufe erzeugen nur bei neuem fachlichem Informationsstand einen PM-/PO-Folgeauftrag.
5. Abschlüsse, Reviewentscheidungen und Fehler werden über vorhandene terminale Turn-/Store-/Effectreceipts verknüpft. `Complete` erst nach belegtem Effekt und Triggerabschluss.

Kein Polling, das bei jedem Leerlauf ein Modell startet. Host darf technisch auf Events warten; Modellarbeit entsteht nur aus beanspruchtem, noch nicht verarbeitetem fachlichen Ereignis oder explizitem Review.

## Ausführbarer Umsetzungsscope und Dateianker für Optimierer

Erst bestehenden Stand gegen die isolierten Vorschläge/den bestätigten Implementierungsbranch abgleichen; nichts aus TEMP unbesehen anwenden. Minimaler Scope:

- PM-Team-/Rollenmaterial: die fünf vorhandenen PM-Vorschlagsdateien (Koordinator-Teamindexergänzung, Teamleitung, Agentenindex und zwei TOMLs) nur dann in den vorgesehenen persönlichen Organisations-Setup-Pfad überführen, wenn dieser Pfad/Owner explizit autorisiert und im WorkItem enthalten ist; keine globale Aktivierung durch diesen Fachbeitrag.
- `scripts/Start-CoordinatorHost.ps1`, `scripts/coordinator/CoordinatorHost.Core.psm1`: vorhandene persistente Session-/Hostbindung um optionale, rückwärtskompatible `solutionId`/PM-Identität ergänzen; unveränderte Legacy-Sessions weiter lesen, neue Starts vollständig und konsistent binden.
- `scripts/coordinator/Resume.Automation.ps1`: nur Event-/Reviewtrigger um PM/PO-Scope und selektive Memory-Receipts ergänzen; vorhandene terminale Turn-, CAS-, Generation- und Idempotenzprüfungen erhalten.
- `scripts/delegation/Start-DelegatedCodexTask.ps1` plus `scripts/workitems/CoordinatorExecutionContext.psm1`: dieselbe vollständige Root-/Parent-/Session-/Solutionbindung durchreichen; keine Teilgruppe oder gemischte Caller-/Environment-Werte akzeptieren.
- `scripts/workitems/WorkItemStore.psm1`, vorhandene Prestart-Recoverymodule: nur falls der bestehende Receipt-/Outboxvertrag Solution-Metadaten oder dokumentierte Resume-Recovery nicht abbildet, additive Felder/Receipts ergänzen. Store-Revision/CAS und vorhandene Originalbelege sind maßgeblich.
- `scripts/coordinator/CoordinatorHost.Core.psm1`/`Resume.Automation.ps1`: Event-Claim/Complete und Review-driven dispatch dort einhängen; keine parallele Scheduler-/DB-Architektur.

Abgrenzung: kein neuer allgemeiner Coordinator, keine neue PM-Fachrolle, keine globale Aktivierung/Installation, keine Produktrepositoryänderung, keine erfundene Codex-CLI-Fortsetzung. Externe Provider-Handoff-Consumer/Producer aus `agent-org-handoff-proposal-20261013` sind separat und ausdrücklich nur Vorschlag; der Producer/Owneranschluss und dessen technische Pins sind nicht geliefert. Dieser Epic-Beitrag kann deren Ownerfunktion nicht stillschweigend voraussetzen.

## Abnahmekriterien (spätere Umsetzung; keine Tests hier ausgeführt)

- Statische Inhalts-/Diff-/Referenzprüfung zeigt genau die bestehende 3-Ebenen-Hierarchie und übernommenen Model/defaults; keine vierte operative Ebene.
- Konkrete Solution-ID, PM-Identität und ihre autoritativen Quellen sind konfigurierbar, persistent, über Host/Starter/Reader/Receipts identisch gebunden und über Neustart/Resume nicht aus Pfaden/Threadnamen abgeleitet.
- Ground-Indexeinträge lassen sich ausschließlich auf tatsächlich gelesene HELJOS/Heljens-Originalquellen zurückführen; ungelöste Identität/Quelle ist explizit unknown.
- Serialisierte Aktivierung hat immutable Intent/Dispatch/Receipt, eindeutige Generation, idempotenten Replay und konfliktgesperrte unklare Commitpfade.
- Unterstützte Runtime-Fortsetzung ist anhand echter lokaler Provider-/App-Server-Quelle benannt; tatsächliche Thread-/Turnhistory ist gebunden. Ohne diesen Beleg bleibt das Kriterium offen, keine CLI-Behauptung.
- Recovery lässt sich aus gespeicherten Job-, Launch-, Session-, Event-, Turn-, Store- und Receiptbelegen nachvollziehen; mehrdeutige Zuordnung bleibt `BlockedRecovery`.
- Produktgedächtnis ist selektiv, solutiongebunden, herkunfts-/statusmarkiert und entscheidungshistorisch append-only; bloße Modellantwort wird nicht als angenommen gespeichert.
- PM/PO-Aufrufe erfolgen nur nach neuem beanspruchtem Ereignis oder Review; bei leerem/unverändertem Queue entsteht kein Modellaufruf. Fachteamdispatch nutzt den bestehenden sichtbaren Starter und Return-/Reviewpfad.
- Keine Tests, Parser-Testläufe, Validatorausführung oder Probeaktivierung als Nachweis; Nachweis ist Inhalt/Diff/Referenzen. Unabhängige Prüfung und Teamleiter-Elternabnahme bleiben getrennt.

## Konkrete offene Punkte an Teamleitung/Koordinator

1. Welche konkrete `solutionId` repräsentiert HELJOS bzw. welches Produkt gehört zu Epic #71? Der PM-Vorschlag ist generisch; das WorkItem-/Paket spezifiziert die Zuordnung nicht.
2. Wer ist autoritativer HELJOS/Heljens-Ground-Owner und welcher konkrete lesbare Ablage-/Connectorpfad ist für dessen vorhandene Primärquellen freigegeben? Ohne diesen Ownerzugriff kann der kanonische Index nicht befüllt oder als vollständig bestätigt werden.
3. Welcher persistente PM-Identitätsschlüssel und welches bestehende Konfigurationsartefakt sind für diese Solution autoritativ? Das PM-Paket benennt Rollenidentität, aber keinen solution-spezifischen stabilen Schlüssel.
4. Welcher lokale Codex Runtime-/App-Server-Owner bestätigt die unterstützte Fortsetzung und darf tatsächliche Thread-/Turnhistory für den Solution-PM lesen? Vorhandene Repoquellen reichen für WorkItem-Resume, aber nicht als Beleg einer allgemeinen CLI-Threadfortsetzung.
5. Owner-/Providerseite für den separat vorgeschlagenen Coordinator-Handoff-Producer ist nicht verfügbar/bestätigt. Der Consumer-Vorschlag allein ist kein lauffähiger Handoff.

## Quellen und Grenzen

- Übergebener Auftrag in `%TEMP%\epic71-ar-package\architektur.json.job.json` und `architektur.json.public.txt`; Elternauftrag `%TEMP%\agent-org-epic71-package-leader.json.job.json`.
- PM-Vorschlag: `%TEMP%\agent-org-productmanagement-76-72-20261012-173049\final\uebergabe.md` und `final/draft/teams/produktmanagement/{teamleiter.toml,agenten/produktmanagement_pm_strategie.toml,agenten/produktmanagement_po_backlog.toml}`. Proposal behauptet keine produktive Einrichtung; offene Issues/Reviews daraus wurden nicht live validiert.
- Lokale Repositoryquellen gelesen: `scripts/Start-CoordinatorHost.ps1`, `scripts/coordinator/CoordinatorHost.Core.psm1`, `scripts/coordinator/Resume.Automation.ps1`, `scripts/delegation/Start-DelegatedCodexTask.ps1`, `scripts/workitems/CoordinatorExecutionContext.psm1`, `scripts/workitems/WorkItemStore.psm1`, `scripts/workitems/WorkItemPrestartRecovery.psm1`, `scripts/workitems/Recover-WorkItemPrestartFailure.ps1`.
- Handoff-Consumer-Vorschlag: `%TEMP%\agent-org-handoff-proposal-20261013\proposal\handoff.md` und `change-effects.md`; noch nicht produktiv, kein Providerfunktionsnachweis.
- Repo war bei Einsicht `develop...origin/develop`, sauber. Keine Issues/Agentenindizes/globalen Rollenindizes gelesen; keine Tests, Parser, Validatoren, Runtime oder Probeaktivierung ausgeführt.
- Keine tatsächliche HELJOS/Heljens Groundquelle, konkrete Solutionzuordnung oder Provider-Ownerbestätigung im bereitgestellten Zugriff. Daher sind diese Anforderungen offen, nicht erfüllt.
- Eigener gemessener Tokenverbrauch: `null` (in diesem Ausführungskontext keine native Verbrauchsmessung verfügbar). Unteraufträge: keine.