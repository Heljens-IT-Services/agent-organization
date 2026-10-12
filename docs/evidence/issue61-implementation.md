# WorkItem 61.B – Umsetzung und gezielte Prüfevidenz

Stand: 2026-10-12. Umsetzung auf `feature/skill61-directory-examples`, Basis
`8aacf071aa5ab7468acb1fe308c2ae61826cb528`. Dieser Ergebnisbeleg ersetzt keine
Abnahme durch QA, keine Elternabnahme von #57 und keinen Abschluss von #67/#66.

## Umsetzung

Das selektive Verzeichnis besteht aus `skills/registry.json`, den zwei
Adapterdateien und `skills/README.md`. Der PowerShell-Eintrag verwendet den
#60-Default ohne `language` und ruft `scripts/accounting/Get-TaskTokenUsage.ps1`
auf. Der Python-Eintrag nennt den bei `uv python find --no-python-downloads`
gefundenen Python 3.13-Interpreter als Executable-Pfad ohne Argumente. Sein
Adapter importiert die vorhandene externe Funktion
`github_api_contents_url` aus `github_utils.py`; er kopiert oder implementiert
keine URL-Fachlogik. `source_path` ist optional als Prozessargument
`--source-path` verfügbar; Standardquellen sind `CODEX_HOME` und
`USERPROFILE/.codex`. Ein fehlender oder unbrauchbarer Quellpfad wird in den
#60-JSON-Fehlerumschlag übersetzt.

Beide Adapter antworten mit genau einem JSON-Objekt (`isSuccessful`,
`exception`, `result`) und behandeln leere/fehlende Pflichtwerte als Fehler.
Die selektive Registry enthält nur diese zwei Beispiele und keinen Runner oder
Discovery-Mechanismus. Details zu Aufruf, Eintragsmetadaten, Selektivität,
Quelle und Portabilitätsgrenzen stehen in `skills/README.md`.

## Gezielte echte Prüfungen

Ausgeführt wird ausschließlich:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/tests/skills/Test-SkillExamples.ps1
```

Der Prüfer validiert Registry gegen das vorhandene #60-Schema, prüft reale
Skriptpfade und Interpreterdatei und startet beide Adapter als Prozesse. Er
prüft Erfolg, ungültige/fehlende Pflichtparameter, fehlende Python-Quelle,
Antwortschema und stdout auf exakt eine JSON-Zeile ohne zusätzliche Meldungen.
Ein leeres temporäres Ledger belegt den Adapteraufruf; es ist kein Ledger- oder
Summenfunktionstest. Maschinenlesbare Einzelergebnisse:
[`issue61-example-tests.json`](issue61-example-tests.json).

Vorhandene #60-Vertragslogik und Evidenz werden wiederverwendet. Keine volle
Testfolge; bestehende Quellen/Tests wurden nicht geändert. Das Ergebnis ist
Implementierungs- und Beispielausführungsevidenz, keine unabhängige Abnahme.

## Offene Punkte

- Die externe `github_utils.py` bleibt eine lokale Voraussetzung. Ablage und
  Version müssen auf dem jeweiligen Rechner bereitgestellt werden; dieser
  Commit fügt sie absichtlich nicht ins Repository ein.
- Inventar/Kreis #61 wurde auf der akzeptierten #60-Basis aktualisiert. #67
  und #66 bleiben offen; dieses WorkItem nimmt ihre Inventur-/QA-Abnahme nicht
  vorweg.
- Die Elternabnahme der Story #57 bleibt separat offen.
