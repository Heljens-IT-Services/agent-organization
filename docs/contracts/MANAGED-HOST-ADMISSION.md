# Verwaltete Hoststarts und Ressourcenlimits

AR37-HOST-IMPLEMENT begrenzt die Ressourcenrechnung auf den Organisationshost,
seine gebuchten Starts und ausdrücklich gebundene Nachkommen. Fremde
accountweite Sitzungen und freie Shell-/MCP-/Pluginstarts außerhalb dieses
Hostpfads werden weder übernommen noch durch diesen Vertrag begrenzt.
Readerorigin ist kein Abstammungsbeleg. Die historischen Aussagen des
InstalledContract über unbekannte Providercompletion und fehlenden nativen
Birthfence bleiben erhalten; sie sperren nicht die lokale Hostreservation.

`executions.json` ist das führende Ledger. `ReserveManaged` prüft unter
`Global\AgentOrganizationCoordinatorExecutions` die gepinnte Root-/Launch-/
Session-/Eltern-/Startauthority, aktuelle Kapazität und Teamslots und schreibt
die Reservation vor der Starterwirkung. Diagnostische Inventorymetadaten
ersetzen dieses Commit nicht. Ein vorhandener eigener Record wird nicht aus
Abwesenheit oder Timeout freigegeben und nicht als neuer Start wiederholt.
Ungebundene Altlasten sperren; eine gebundene unbekannte Execution belegt
weiter ihren Slot und blockiert ihre eigenen Operationen.

Je Execution gelten ein globaler Slot und, außer beim Koordinator, ein
Teamslot. Teamleiterstarts erhalten ihren autorisierten Teamschlüssel;
Spezialisten übernehmen ihn aus dem gebundenen Teamleiter-Elternrecord.
Serielle Turns bleiben in derselben Execution. Neue Threadgeburt/Fork braucht
eine eigene Reservation; ein bereits gebundener Thread darf im selben Record
nicht erneut geboren werden. Ein Resume darf keinen anderen aktiven eigenen
Threadrecord übernehmen. Höchstens drei Rollenebenen bleiben erhalten.

Bei einem Teamlimit größer eins hält die Planung konservativ Platz für den
Teamleiter und eine erste Facharbeit vor (`minimumConcurrentExecutions=2`).
Dieser Platz ist kein geborener Kindslot: das Kind reserviert selbst. Ein
Teamlimit eins erlaubt nur die Elternarbeit. Fünf globale Slots und zwei
Slots je Team ermöglichen Koordinator, zwei Teamleiter und zwei Facharbeiten;
Bei vier globalen Slots darf nach einer bereits gestarteten Facharbeit ein
weiterer Teamleiter den letzten Slot belegen; dessen Facharbeit wartet.
Kleinere Budgets können Facharbeit ausdrücklich warten lassen. Eltern behalten
ihren Slot beim Kinderwarten. Die Launchkonfiguration wird nicht verändert.

`Begin-ManagedOperation` konsumiert unter demselben Mutex eine eindeutige
Operation vor Runtime-/Thread-/Resume-/Turnwirkung. Der Aufrufer muss zur
persistierten Hostsession bzw. bestätigten Runner-PID gehören. Bekannte
Runtimegenerationen werden nicht parallel neu gestartet. Tatsächliche
Runtime-PID/Startzeit und RPC-Request-/Replybytes werden danach gebunden
gesichert. Fehlendes ACK verhindert Wiederholung und Freigabe. Ein Turn-ACK
belegt keinen Turnabschluss: der nächste Turn und Release benötigen die
passende echte `turn/completed`-Nachricht. Receipt-only Recovery kann echte
gesicherte Bytes nach dem Ende des ursprünglichen Aufrufers übernehmen;
Timeout und fehlende Dateien sind keine Ersatzreceipts.

Kapazitätswartearbeit liegt dauerhaft unter `managed-waiting`. Teamaufträge
werden über ihre vorhandenen Automation-Intents wieder betrachtet;
Spezialisten über die exakt gepinnte SSOT-Startauthority ihres Teamleiters.
Der technische Idleconsumer trifft keine Rollenwahl. Geänderte Authority,
neue Store-/Elternkonflikte oder vorhandene Reservation führen zu Recovery,
ohne neuen Prozess. Legacy-Starts ohne SSOT-Authority bleiben für automatische
Wiederaufnahme gesperrt.

Prepared-Isolation prüft Registrybindung, Dispatchzustand und Job-/GO-/
Window-/Resultartefakte. Mehrere wirkungslose Prepared-Intents monopolisieren
die Auswahl nicht. Eine begrenzte gebuchte Wirkung blockiert ihren WorkItem;
eine ungebundene mögliche Wirkung bleibt eine gemeinsame Sperre. Bestehende
WorkItemabhängigkeiten, Prioritätsbänder und Rootcursor bleiben wirksam.

Release benötigt gebundene Result-/Returned-/NoSpawnbelege, Turnende, Ende
aller gebuchten Runtimegenerationen und abgeschlossene eigene Kindrecords.
Terminalstand und unveränderliche Releasepayload werden zusammen im Ledger
geschrieben, auch im NoSpawn-Frühreturn. Pending Release-Wakes werden ohne
verschachtelten Event-/Registrylock idempotent veröffentlicht; der Cursor
folgt erst nach dauerhafter Publikation. Der Consumer speichert seine lokale
Planungsentscheidung vor Event-ACK und erzeugt dafür keinen Modellturn.
Resultänderungen und Payloadkonflikte sperren den Replay.

Diese Anschlüsse versprechen keine Providerexklusivität und keine Kontrolle
beliebiger autonomer nativer Starts außerhalb des verwalteten Pfads. Eine
Migration ungebundener Altlasten oder verlorener echter Receipts benötigt
eine konkrete gebundene Recoveryentscheidung; keine globale Idleinventur.
Implementierung und Inhaltsreview sind keine aktuelle Funktionsabnahme.
