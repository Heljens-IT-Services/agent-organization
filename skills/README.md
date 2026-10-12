# Skills und selektive Registry

`registry.json` ist ein manuell gepflegtes Verzeichnis ausführbarer Beispiele.
Es gibt hier weder Discovery noch Runner. Neue Einträge müssen dem Vertrag in
[`docs/contracts/SKILLS.md`](../docs/contracts/SKILLS.md) und
[`schemas/skills.schema.json`](../schemas/skills.schema.json) entsprechen;
`scriptPath` zeigt auf vorhandenen Code. Fehlendes `language` verwendet den
PowerShell-Default. Alternative Sprachen benötigen einen Interpreter als
einzelnen Executable-Pfad ohne Argumente.

## Beispiele aufrufen

PowerShell-Default:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File skills/adapters/Get-TaskTokenUsageSkill.ps1 `
  -TaskId '<task-guid>' -AccountingDirectory '<ledger-directory>'
```

Python mit JSON-Eingabe auf stdin:

```powershell
'{"repo":"Heljens-IT-Services/agent-organization","path":"schemas/skills.schema.json","ref":"develop"}' |
  & '<interpreter aus registry.json>' skills/adapters/github_contents_url.py
```

Beide Adapter schreiben bei Erfolg und behandelbarem Fehler genau ein JSON-
Antwortobjekt nach Vertrag v1 auf stdout. PowerShell-Parameter `TaskId` und
`AccountingDirectory` entsprechen den Registryparametern `task_id` und
`accounting_directory`; die Python-Eingabe enthält `repo`, `path` und `ref`.
Fehlende oder leere Pflichtwerte werden als Fehlerantwort ausgegeben.

## Voraussetzungen und Grenzen

Der Token-Adapter verwendet ausschließlich
`scripts/accounting/Get-TaskTokenUsage.ps1`. Er liest den Accountingbestand;
unbekannte Messungen und inklusive Summen bleiben gemäß dessen bestehender
Semantik unbekannt. Die bestehende Ledger-Fachlogik ist nicht dupliziert.

Der Python-Adapter importiert `github_api_contents_url` aus der bestehenden
externen `github_utils.py`. Er sucht unter
`CODEX_HOME/skills/.system/skill-installer/scripts/github_utils.py`, danach
unter `USERPROFILE/.codex/skills/.system/skill-installer/scripts/github_utils.py`.
Alternativ kann der optionale Prozessparameter `--source-path <datei>` den
Quellpfad festlegen. Fehlt die Datei, ist der Import unbrauchbar oder fehlt
`github_api_contents_url`, antwortet der Adapter mit dem Fehlerumschlag.
Die externe Datei wird weder kopiert noch durch eine neue URL-Implementierung
ersetzt. Registry und Adapter transportieren keinen absoluten Quellenpfad;
Verfügbarkeit, Version und Ablageort dieser lokalen Voraussetzung müssen je
Rechner bereitgestellt werden. Der Registry-Interpreter ist der bei Umsetzung
lokal mit `uv python find --no-python-downloads` gefundene Python-Pfad; `uv`
selbst ist kein Interpretereintrag und es wird kein Download ausgelöst.

`scripts/tests/skills/Test-SkillExamples.ps1` prüft selektiv Registryschema,
Referenzen und echte Aufrufe der beiden Beispiele; es ist keine volle
Testsuite und kein Runtime-Runner.
