# Gebundener persönlicher Rollenabgleich

AR-41-PERSONAL-SYNC erweitert den vorhandenen Organisationsänderungsweg aus
[ORGANIZATION.md](ORGANIZATION.md) und [WORKITEMS.md](WORKITEMS.md).
Die [Konzept-Pfadtafel](../CONCEPT.md) bleibt verbindlich. Der Starter ist
ein Verbraucher persönlicher Rollen, kein Installationsmechanismus. AR55 ist
ein historischer manueller Änderungsbeleg. Ein gezielter Synchronisierer war
im eng gelesenen Bestand nicht vorhanden; deshalb ergänzt
[Sync-PersonalOrganization.ps1](../../scripts/organization/Sync-PersonalOrganization.ps1)
nur den fehlenden Mutationsanschluss. HumanInteraction.ps1 und WorkItemStore.psm1
werden direkt wiederverwendet; Delegation, Kontext, Resume und Admission bleiben
unverändert. Es entsteht keine neue Rolle und keine automatische Discovery.

## Konkrete Freigabe für Folgeänderungen

Ein bestehendes WorkItem in `in_progress` oder `rework` mit Owner
`agent_ressources_optimierer` benötigt
eine echte, bereits persistierte Humanentscheidung `approved` über den bestehenden
Human-Anschluss. `ExpectedRevision`, Request-ID, verantwortlicher Mensch,
Proposalpfad und SHA-256 werden durch die vorhandenen Funktionen gebunden.
Das Skript schreibt weder WorkItems noch Humanantworten und hat keinen
Freigabe-Bypass. Ein nach der Humanantwort weiterhin blockiertes WorkItem wird
nicht umgangen; der vorhandene gesonderte Resumeanschluss bleibt zuständig.
Der Auftragspfad bleibt Koordinator -> Teamleitung -> Optimierer.
Umsetzung, Delta-Review und eigene Elternabnahme bleiben getrennt.

Die Proposaldatei ist ein konkretes JSON-Artefakt mit `format` gleich
`personal-organization-change/v1`, `workItemId`, `teamId`, absoluten
`repositoryRoot`/`codexHome`, `repositoryBaseSha` und `entries`.
Jeder Eintrag enthält `source`, `target`, `sourceBaselineBlob`, `sourceSha256`,
`targetBeforeSha256`, `diffPath`, `diffSha256`, `targetDiffPath`,
`targetDiffSha256` und konkrete `impact`. Die Diffdateien liegen relativ zum
Repository; der Repositorydiff ist UTF-8 ohne BOM mit LF und abschließendem LF.
Die freigegebene Proposal bindet sowohl diesen Diff als auch den vollständigen
gewünschten Quellinhalt und die exakten persönlichen Vorherbytes. Die persönliche
Diffdatei macht auch ältere, ausdrücklich einzubeziehende Änderungen sichtbar.

Der eng unterstützte Scope umfasst einen geänderten eigenen Teamindex und
bereits im gebundenen Commit vorhandene, daraus referenzierte Agenten-TOMLs.
Quelle und Ziel folgen exakt `teams/<team>/agenten.json` ->
`agents/<team>/agenten.json` und `teams/<team>/agenten/<rolle>.toml` ->
`agents/<team>_<rolle>.toml`. Teamleiter-/Koordinatoränderungen, neue Rollen,
Löschungen, fehlende persönliche Dateien und Erstinstallationen liegen außerhalb
dieses Anschlusses. Er liest keine fremden Indizes und nutzt keinen Index zum
Routing. Kein Entry ohne wirklichen Repositorydiff; keine Gesamtkopie oder
Skillmutation. Ein nicht passender Zielhash stellt den ganzen zusammengehörigen
Abgleich zurück. Bereits passende Ziele bleiben ohne erneute Mutation erhalten.

## Dateimutationen und Ergebnisgrenzen

Alle Quell- und Zieldateien bleiben während des Abgleichs gegen konkurrierende
Schreibzugriffe gesperrt. Pfade, Baselinecommit, Quellblob, konkreter Diff,
Quellbytes, Indexzuordnung und Rollenname werden vor der ersten Mutation gebunden.
Vor allen Zielwrites entstehen exakte Vorherkopien in einem neuen
`EvidenceDirectory` außerhalb von Repository und CODEX_HOME. Danach wird die
vorhandene Freigabe nochmals zurückgelesen. Jede echte Mutation wird geflusht
und bytebezogen zurückgelesen; result.json nennt Zustand und Hashes.

Dies ist keine atomare Transaktion über mehrere Dateien. Bei Schreibfehler oder
Prozessabbruch kann ein Teilstand verbleiben; Vorherkopien sind vor dem ersten
Write gesichert. Kein automatisches Zurücksetzen fremder Folgemutationen.
Wiederherstellung und erneuter Abgleich benötigen einen konkret gebundenen
Folgeauftrag. Ergebnisdateien sind mutative Inhaltsbelege, keine Laufzeit-
oder Abnahmebelege. Kein Agentenstart, Fensterneustart oder Aktivierungsversuch.

## Autorisierte Erstentwicklung AR-41

Die hier ausdrücklich autorisierte Erstentwicklung und die zwei passenden
persönlichen Mutationen werden als direkte Dateimutationen geführt. Der neue
Produktanschluss wird unter der aktuellen Prüfregel nicht ausgeführt oder
erprobt. Die ursprüngliche Auftragsautorisierung wird dokumentiert, ohne eine
synthetische Humanantwort in einen produktiven Store zu schreiben.
[Gebundenes WorkItem](../workitems/AR-41-PERSONAL-SYNC.md) und zugehörige
Proposal-/Diff-/Readbackartefakte beschreiben den konkreten Änderungssatz.
Die Erstautorisierung ist keine pauschale Zustimmung für Folgeänderungen.
