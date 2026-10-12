# Eigene Elternabnahme Story #14

Entscheidung teamleiter_softwareentwicklung am 12.10.2026: Story #14 im abgegrenzten Scope mit #30 und #31 accepted. Dies ist die eigene fachliche Elternentscheidung nach Prüfung der unabhängigen Ergebnisse, nicht die Übernahme eines Kinderabschlusses. Epic #6 ist nicht abgenommen.

Basis: develop 84d7d4a99b3d3f5a661f262b12c0f7bbec21637c, feature/story14-atomic-storage. Final geprüftes WorkItemStore.psm1 SHA256 C4AAE2CB7AE8B100D7B98918B1E3AC98053CB144C0EF557070852DB728F41C89. Fachbeiträge: Architektur, Backend, unabhängige Qualitätssicherung; QA-01 und QA-02 korrigiert und unabhängig nachgeprüft.

## Eigene Kriterienentscheidung

- Genau ein Gewinner: zwei echte Prozesse an Ready/Go-Barriere, Timeout 0, ein Besitzer und ein LockTimeout. Tatsächliche GUID/SID/Name/PID/Startzeit/Host verifiziert. Kriterium erfüllt.
- Fremde aktive Freigabe: kopierter Kontext, ID und manipuliertes Released=true ergeben LockNotOwned, direkte Löschung verweigert, Besitzer bleibt arbeitsfähig. Kriterium erfüllt.
- Konkurrenz ohne verlorene Änderungen: zwei R0-Writer, erster R1, zweiter RevisionConflict mit unveränderten Zielbytes; erneutes Lesen und zweite Änderung erhält beide Ergebnisse. Zusätzlich 80 kurze konkurrierende Sperrerwerbe ohne Fehler. Kriterium erfüllt.
- Schreibabbruch: isolierte Kopien mit Throw direkt vor/nach File.Replace ergeben vollständigen alten/neuen UTF-8-JSON-Bestand, jeweils vertragsgültig. Kriterium im beauftragten kontrollierten Fehlermodell erfüllt. Betriebscrash-/Wiederanlauftests ausdrücklich Folgeauftrag.
- Ungültige Mutationen einschließlich Schema, Übergang, Timestamp, Graph sowie veraltete Revision abgewiesen, Zielbytes erhalten. Bestehende Vertragsregression 75/75, fokussierte Storeprüfung 14/14, beide Exitcode 0. Kriterium erfüllt.

## Reproduktion

powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-WorkItemStore.ps1 -ResultPath <separater Testnachweis.json>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/Test-Contracts.ps1 -ResultPath <separater Vertragsnachweis.json>

Unabhängiger finaler Storelauf: Windows PowerShell 5.1.26100.9549, lokales NTFS, 2026-10-12T08:53:06.5925819Z; Quellhash vor/nach identisch. Vergleichsdaten in lokalem QA-Bericht und maschinenlesbaren Nachweisen, Ergebnisse hier für dauerhafte PR-Prüfung dokumentiert.

## Grenzen und Folgeabhängigkeit

Lokales Windows/NTFS geprüft; keine Netzshares, verteilten Hosts, Stromausfallhaltbarkeit oder Crash-Recovery zugesichert. Keine Wiederherstellung verwaister Sperren oder produktive Dienste/Autostarts. #15 mit #32/#33 bleibt nächster Auftrag durch Koordinator, Epic #6 bleibt offen. Neue Funktionen und Tests verwenden den bestehenden WorkItem-Vertrag unverändert. Rollen/Indizes/Fensterschutz/Tokenledger/CI bleiben unverändert. PR-Merge erfolgt ausschließlich koordiniert nach dieser Ergebnisübergabe.

Publikationsentscheidung: explizite sieben Story-Dateien plus dieses Abnahmeprotokoll committen/pushen, PR auf develop mit Closes #14/#30/#31 und Issue-Nachweisen autorisiert. PR nicht selbst mergen.