# Abnahme Epic #5

Historischer Abnahme-/Implementierungsbeleg: Skriptpfade und Befehle dokumentieren den damaligen Stand. Aktuelle Pfade stehen in README.md des Repositorys und docs/WORKITEM-STORAGE.md.

Implementierte Hierarchie: Epic #5 → Stories #12/#13 → Tasks #26/#27/#28/#29.
Die Epics #6–#11 sind Folgeumfang und werden hier nicht geschlossen.

Der historische Epic-5-Vertragsumfang bleibt erhalten. Der aktualisierte
Rollenbestand und die AR55-Umsetzungsnachweise stehen in
[AR55-IMPLEMENTATION.md](AR55-IMPLEMENTATION.md); unabhängige AR55-Prüfung und
eigene Elternabnahme sind noch ausstehend.

## Nachweise

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Contracts.ps1 `
  -ResultPath "$env:TEMP\agent-org-epic5-acceptance.json"
.\scripts\Test-Organization.ps1
```

75 Prüfungen bestanden unter Windows PowerShell 5.1.26100.9549. Der optionale
JSON-Bericht enthält jede Einzelprüfung. Eine separate Gegenprüfung mit
`jsonschema` 4.26.0 bestätigte drei Draft-2020-12-Metaschemas, 15 gültige
Strukturbeispiele/Indizes und zwei ungültige Strukturen. ID-Duplikate und Graphzyklen
sind bewusst zusätzliche semantische Prüfungen, keine Schema-Eigenschaften.
Python ist nur für diese Gegenprüfung benutzt, keine Laufzeitabhängigkeit.

| Issue | Abnahmebeleg |
|---|---|
| #26 | WorkItem-Schema, Übergangsliste, gültiges Ziel mit zwei Teilaufgaben, menschliche Blockade; ungültige Status-, ID-, Referenz- und Zyklusfälle |
| #27 | Vollständiger Pfad geplant → Bearbeitung → Umsetzung → fehlgeschlagene Elternprüfung → Nacharbeit → erneute Umsetzung → erfolgreiche eigene Elternabnahme; unveränderte Prüfhistorie und getrennte Zeiten |
| #12 | Umgesetzte Aufgaben bleiben offen, Kinderabschlüsse schließen kein Elternziel; Eltern prüfen eigenen Geschäftsnutzen zusätzlich zu technischen Kinderkriterien; 121 Aufgabenebenen validieren |
| #28 | Alle zehn bestehenden Indizes mit neun Teams und 35 Spezialisten validieren; falsche/fehlende Rollen, Teamzuordnung und verschachtelte `status`-Felder werden abgewiesen; `role_file:null` bleibt erlaubt |
| #29 | Koordinator priorisiert WorkItems; alle neun Teamleiter verlangen zuständige Fachbeiträge und eigene Elternprüfung; operative Rollen liefern Facharbeit; drei Agentenebenen, Vertrieb und Folgeentscheidungen sind dokumentiert |
| #13 | Bestehende Indexstruktur bleibt erhalten; WorkItem-/Host-/Wissens-/Workflow-/Freigabeentscheidungen und endgültige Orte stehen in Entscheidung 0001 |
| #5 | Verbindliche Schemas, gültige/ungültige Beispiele, gemeinsame PowerShell-Prüfung und konsistente Rollen-/Konzeptregeln liegen vor |

Alle 45 TOMLs wurden zusätzlich geparst. Technische Defaults bleiben unverändert;
45 Rollen und zehn Indizes sind bytegleich persönlich installiert. Neue Artefakte
sind UTF-8; alle PowerShell-Dateien wurden durch den PowerShell-5.1-Parser geprüft.
GitHub Actions bleiben deaktiviert; es wird kein CI-Erfolg behauptet.

## Grenzen

Diese Abnahme ist ein Datenvertrags-/Lebenszyklustest, kein produktiver Gesamtpilot.
Der gemeinsame PowerShell-Prüfer unterstützt den dokumentierten Schemaumfang;
fachliche Evidenz muss ein zuständiger Prüfer beurteilen. Ohne Vorzustand kann
historische Übergangstreue nicht bewiesen werden. Die sichere Schreibschnittstelle,
Host, Web-Oberfläche und integrierte Freigaben gehören zu den Folge-Epics.
