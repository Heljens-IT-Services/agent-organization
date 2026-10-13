# Unabhängiger Vertragsabschluss R4 / QA71-04-contract-hash

Adressat: **teamleiter_agent_ressources**. Rolle: agent_ressources_qualitaetspruefung.
WorkItem: QA71-04-contract-hash unter epic71-contract-hash-rework. Datum: 2026-10-13.

**R4: Pass im beauftragten Inhaltsreview. QA71-04-contract-hash ist geschlossen; der technische R4-Pass bleibt erhalten. R1–R3 Pass werden aus qa-completion-review.md/json übernommen und nicht erneut geprüft.** Kein konkreter Restdefekt im geprüften Einzeilendelta oder seiner Hashbindung. Dies ist ein Quellenbefund, kein aktueller Funktionsbeweis und keine eigene Elternabnahme.

Der vorherige QA-Task 6c69008f113344599282f57f1655472c und der Vertragswriter 98563bc4af134927adc92259fb4975cf sind laut Übergabe completed. Keine zusätzliche Statuskampagne, kein doppelter Reviewerauftrag und keine Delegation.

## Scope und unabhängiger Befund

Ausschließlich docs/contracts/PRODUCTMANAGEMENT.md:37 gegen :45, den neuen contract-rework.diff und die übergebenen Referenzen geprüft. Zeile 37 verlangt jetzt `product-decision-sha256:<hash>` und verweist ausdrücklich auf die normative Umschlaghash-Definition im Abschnitt „Ereignisse, Backlog und Wirkung“ samt `Get-ProductDecisionEnvelope` und `Get-LCBytes`. Der Abschnitt steht in :43, die Definition in :45. Die frühere reine Decision-Hashformel ist aus :37 entfernt.

Die normative Definition bindet den geordneten Umschlag `kind=product-decision-envelope-v1`, `solutionId`, `pmIdentity`, `configuration={path,hash}`, `decision`. ProductManagement.psm1:78–79 bildet genau diesen Umschlag. Save:228–229 hasht dessen Get-LCBytes-Serialisierung; :234 übergibt den Digest an den Reviewhelper; :260 archiviert Umschlag und Digest. Der Helper :82–87 verlangt den angenommenen Review und dessen exakten Beleg sowie dieselbe Solution-/PM-/Konfigurationsbindung. New-ProductFeature.ps1:37–39 prüft Umschlagart, Identitäten, Konfigurationspfad/-hash, erneut gebildeten Digest und denselben Reviewhelper. Lifecycle.Persistence.ps1:10–11 beschreibt kompaktes JSON (Depth 100), striktes UTF8 ohne BOM und SHA256. Save-ProductDecision.ps1:14–20 bindet Konfiguration/Solution und ruft den bestehenden Savepfad auf. Alle Stellen wurden nur gelesen; kein Helper, Wrapper oder Produktcode ausgeführt.

Der fünfzeilige contract-rework.diff enthält genau einen Hunk `@@ -37 +37 @@`. Seine neue vollständige Zeile entspricht der aktuellen Zeile 37 und kommt im Vertrag genau einmal vor. Die Rückersetzung dieser Zeile durch die alte Diffzeile ergibt **2a1e54ab5c67903f3eaa32934838f0de2affc07d2fb23991d28abfc1ad817b2b**, den bisherigen Primärhash. UTF8-Rückkodierung des unveränderten aktuellen Textes ergibt wieder den aktuellen Originalbytehash. Damit sind innerhalb dieser Hashbindung die übrigen Bytes einschließlich Zeile 45, BOM und Zeilenenden erhalten. Aktuell 12240 Bytes, rekonstruierter Ausgang 12128 Bytes. Keine Rekonstruktion auf Datenträger geschrieben.

## Primärhashes und erhaltener technischer Pass

| Quelle im implementation-Verzeichnis | Aktueller SHA256 | Einordnung |
|---|---|---|
| docs/contracts/PRODUCTMANAGEMENT.md | 15c9736cc78d4615b90d95ab1210b46fc8bc40a8bdc83253f602978e8ca11bef | Erwarteter neuer Vertraghash; Pass |
| scripts/productmanagement/ProductManagement.psm1 | e2976cd2cde52e7915ba3afc0f018d474509fdebd7f1c09da5f5e456472ab820 | Bisheriger Code-Primärhash unverändert |
| scripts/productmanagement/Get-ProductRecovery.ps1 | da36414fa85d4ab3dede8c9329f16144744a67e29034bc8e07cf0f9f364cf193 | Nur Hashabgleich; kein neues R2-Review |
| scripts/productmanagement/New-ProductFeature.ps1 | 0f272b52b2f2ac6f6f7bfc198c1f0779d0aea0125478b30a21511ad2275df25c | Bisheriger Code-Primärhash unverändert |

Der frühere Vertraghash wird durch den eng begrenzten neuen Vertraghash ersetzt. Der technische Pass stammt aus der erhaltenen QA, die drei Code-Primärhashes wurden unabhängig zurückgelesen. R1–R3 wurden weder neu bewertet noch als Laufzeitnachweis dargestellt. Zusätzliche Referenzhashes: scripts/coordinator/Lifecycle.Persistence.ps1 = 8c75f5981e852e0a984ea74ff5270303102a7354f0f624179f7c7572e5860085; scripts/productmanagement/Save-ProductDecision.ps1 = b4f1038fb715079653527895189aac306ea29dbbbcae9e863bf3fa17beb5998c. Beide entsprechen der bisherigen QA.

## Begleitartefakte und Hashbindung

| Datei im Paket | Unabhängig gelesener SHA256 |
|---|---|
| qa-completion-review.md | fc2d35e6b8ba8ac1050df5c90fde6fbdf61248f3c3208781c3a7a63209866a5c |
| qa-completion-review.json | fbdfa0b67fc7721960ca1a7654da0415426290f2249b440716ea68bd8ec056c2 |
| contract-rework-report.md | c9d681dadfe47ea5271c19331cde15681dbdf7e7c0381e1969a429db79f72e21 |
| contract-rework-report.json | d77888e0fcdb69d81d19a1d1c03a67ab969d860e1e1bf513576d2aa6d73b8fe5 |
| contract-rework-manifest.json | 79b650fc488348227bfb7ec177203352739109f0ca68812e9ab151ba8f245a7d |
| contract-rework.diff | e347fb28113cff9ac6288a40004d778e06d3b39b8033bf8cbaa323b749ab472a |

Beide Berichte und Manifest nennen denselben Vorher-/Nachherhash und Einzeilendelta. Die drei im Manifest gebundenen Artefakthashes stimmen mit den tatsächlich gelesenen Dateien überein; ebenso beide dort gebundenen QA-Hashes und beide Codereferenzhashes. Bericht, Manifest und Diff entsprechen dem unabhängig zurückgelesenen Vertrag. Historische QA und Lieferartefakte bleiben historische Belege; sie werden nicht nachträglich umgeschrieben.

## Grenzen und getrennte offene Kriterien

- Owner: Verbindliche Solution-/PM-/Owneridentitäten, Originalquellen und Zugriff bleiben extern offen.
- Provider: Aktuell installierte API-/History-/Completion-/Restartunterstützung und autorisierte Registryfreigabe bleiben offen; historische Belege ersetzen dies nicht.
- Produkt: Reale Strategie-/PO-/Handoff-/Outcomeabnahme und Messwerte bleiben offen.
- Ground: Identität, Quellen und Zugriff bleiben offen; keine Zuordnungen erfunden.
- Laufzeit: Annahme/Featureanlage, Erstaktivierung, Fortsetzung, Recovery, Reminder/Outbox/CAS und Teilpublikationsauflösung nicht ausgeführt. Reviewsnapshot bleibt Beobachtungsstand; keine atomare Store-/Memorytransaktion bewiesen. Die aus R1–R3 erhaltenen Grenzen, insbesondere Dateisystemnebenläufigkeit und zwei nicht atomare Feature-/Outcome-Publikationen, bleiben bestehen.
- Elternabnahme und weitere externe Kriterien: Eigene Elternabnahme durch die zuständige Instanz und externe Abnahmen bleiben offen. Index-/Integrationsfragen liegen außerhalb dieses Auftrags; kein neuer Befund dazu.

Hashreadback ist eine Momentaufnahme ohne Dateisystemsperre oder Zukunftsgarantie. Keine Gesamtpaket-, Bestands- oder Integrationskampagne und kein Gitstatus-/HEAD-Abgleich. Keine Tests, Parser-/Validatorläufe, Produkt-Runtime-/native-/Browserproben, Fixtures, Installation, Aktivierung, Modulimporte oder Actions. Organisationsindex nicht geladen; keine Gitwrites oder Delegation. Das einmalige Lesen eines irrtümlichen Lifecycle-Pfads schlug fehl; anschließend wurde der in der erhaltenen QA genannte Pfad scripts/coordinator/Lifecycle.Persistence.ps1 erfolgreich gelesen. Keine Produktdiagnose aus diesem Lesefehler abgeleitet.

Nur qa-contract-final-review.md/json geschrieben. Reserviertes Resultat, Produktquellen, fremde Arbeit und alle Fenster erhalten. Eigenverbrauch nicht gemessen (null); keine Unteraufträge. Memory-Quick-Pass lieferte keinen einschlägigen Vertragsbefund; keine Memoryfakten verwendet.
