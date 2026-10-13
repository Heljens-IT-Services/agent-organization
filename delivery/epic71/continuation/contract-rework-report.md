# Vertragskorrektur QA71-04-contract-hash

Adressat: teamleiter_agent_ressources. Rolle: agent_ressources_optimierer.
WorkItem: epic71-contract-hash-rework unter epic71-source-delivery.

**Umgesetzt; unabhängige Prüfung und eigene Elternabnahme offen.** Ausschließlich docs/contracts/PRODUCTMANAGEMENT.md:37 geändert.

## Änderung und Hashbindung

Vorher SHA256: 2a1e54ab5c67903f3eaa32934838f0de2affc07d2fb23991d28abfc1ad817b2b
Nachher SHA256: 15c9736cc78d4615b90d95ab1210b46fc8bc40a8bdc83253f602978e8ca11bef
Der vorgegebene Vorherhash stimmt exakt. Nur die reine Decision-Hashformel wurde durch einen eindeutigen Verweis auf die normative Umschlaghash-Definition in „Ereignisse, Backlog und Wirkung“ ersetzt. Zeile 45 bleibt unverändert.

Vorher, vollständige Zeile 37:
`Save-ProductDecision.ps1` speichert nur explizite Records mit `id`, `date`, `context`, `reasons`, `alternatives`, `consequences`, `status`, gehashten JSON-Quellbelegen `sources` und `supersedes` (null oder Vorgängerhash). `proposed` ist ein Vorschlag. Für `accepted`/`rejected` muss der bestehende Reader ein akzeptiertes Review-WorkItem mit exakt `product-decision-sha256:<SHA256(kompaktes UTF8 JSON der Decision)>` im Ergebnisbeleg lesen. Der Record archiviert diese Reviewbytes und Store-Revision. Eine bloße Antwort oder Modellbehauptung reicht nicht. Dies übernimmt die vorhandene WorkItem-Reviewautorität; es führt keine neue authentifizierte Humanidentity ein.

Nachher, vollständige Zeile 37:
`Save-ProductDecision.ps1` speichert nur explizite Records mit `id`, `date`, `context`, `reasons`, `alternatives`, `consequences`, `status`, gehashten JSON-Quellbelegen `sources` und `supersedes` (null oder Vorgängerhash). `proposed` ist ein Vorschlag. Für `accepted`/`rejected` muss der bestehende Reader ein akzeptiertes Review-WorkItem mit exakt `product-decision-sha256:<hash>` gemäß der normativen Umschlaghash-Definition im Abschnitt „Ereignisse, Backlog und Wirkung“ (`Get-ProductDecisionEnvelope` und `Get-LCBytes`) im Ergebnisbeleg lesen. Der Record archiviert diese Reviewbytes und Store-Revision. Eine bloße Antwort oder Modellbehauptung reicht nicht. Dies übernimmt die vorhandene WorkItem-Reviewautorität; es führt keine neue authentifizierte Humanidentity ein.

## Readback und Referenzen

Geschriebener Inhalt entspricht exakt der vorgesehenen Einzelersetzung. Geänderte Zeilen: 37. Rückersetzung ergibt den vollständigen Ausgangsinhalt. Bestehende UTF8-Bytes außerhalb der Ersetzung einschließlich BOM und Zeilenenden bleiben erhalten. contract-rework.diff enthält ausschließlich diesen Einzeilendelta.

ProductManagement.psm1:78–79 bildet den geordneten Umschlag kind, solutionId, pmIdentity, configuration={path,hash}, decision. :228–229 berechnet Get-LCHash (Get-LCBytes $envelope); :234 prüft denselben Digest, :260 archiviert ihn. :82–87 bindet den exakten Reviewbeleg. New-ProductFeature.ps1:36–39 liest den Umschlag, prüft dessen Identitäten/Konfiguration und denselben Hash und verwendet denselben Reviewhelper. Diese Stellen wurden nur gelesen.

ProductManagement.psm1 SHA256: e2976cd2cde52e7915ba3afc0f018d474509fdebd7f1c09da5f5e456472ab820
New-ProductFeature.ps1 SHA256: 0f272b52b2f2ac6f6f7bfc198c1f0779d0aea0125478b30a21511ad2275df25c

QA-Quelle: qa-completion-review.md:53–65 sowie qa-completion-review.json:308–325; vorheriger QA-Task laut Übergabe completed. R1–R3 Pass und technischer R4 Pass sind historische QA-Befunde, keine eigene neue Abnahme. Quellenhashes stehen im JSON-Bericht.

## Grenzen und offene Punkte

- Nur Inhalt, Diff, Hashbindung und Referenzreadback; kein aktueller Funktionsnachweis.
- Keine Tests, Parser, Validatoren, Runtime-, native oder Browserproduktproben; kein Modulimport, keine Fixtures, Installation, Aktivierung oder Actions.
- Keine Organisationsindizes geladen, keine Delegation, keine Gitmutation oder externe Schreibaktion.
- Unabhängige Prüfung von Vertrag und neuer Hashbindung sowie eigene Elternabnahme bleiben offen.
- Keine Gesamtpaketabnahme; parallele Integrationsdateien und reserviertes Resultat liegen außerhalb dieses Beitrags.
- Get-LCBytes/Get-LCHash wurden nicht ausgeführt; Bytevorgabe wird durch unveränderte normative Zeile 45 und gelesene Aufrufstellen gebunden.
- Hashreadback ist eine Momentaufnahme ohne Dateisystemsperre.

Historische Manifeste, QA und Diffs bleiben erhalten. Die vier contract-rework-Artefakte sind getrennte neue Belege. Keine Stage/Stash/Commit/Push/PR/Issuewrite-Aktion. Eigenverbrauch unbekannt; keine Unteraufträge.
