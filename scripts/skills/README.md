# Skill Discovery und Runner

`Find-Skill.ps1` liest die zentrale `skills/registry.json`. Suche nach ID ist
exakt; Zweckssuche liefert nur bei genau einem Treffer einen Skill. Bei
Mehrdeutigkeit nennt die Diagnose die Kandidaten und startet nichts.

`Invoke-Skill.ps1` nimmt `SkillId`, ein JSON-Objekt in `ParametersJson`,
`WorkItemRef` und `ExecutionRef`. Betreiberkonfiguration erfolgt separat:
`RepositoryRoot`, `AccountingRoots`, `TrustedSourceRoots`, optional
`SourcePath`/`LogPath` und `TimeoutSeconds` (Default 60).

Beispielaufrufe:

```powershell
$python = 'C:/Users/Tom-OliverMarek/AppData/Roaming/uv/python/cpython-3.13-windows-x86_64-none/python.exe'
./scripts/skills/Find-Skill.ps1 -SkillId task-token-usage -CoreInterpreterPath $python
./scripts/skills/Find-Skill.ps1 -Purpose 'Contents-URL' -CoreInterpreterPath $python
./scripts/skills/Invoke-Skill.ps1 -SkillId task-token-usage -CoreInterpreterPath $python `
  -ParametersJson '{"task_id":"00000000-0000-0000-0000-000000000000","accounting_directory":"C:/ledger"}' `
  -WorkItemRef '#62' -ExecutionRef 'run-1' -AccountingRoots 'C:/ledger'
./scripts/skills/Invoke-Skill.ps1 -SkillId github-contents-url -CoreInterpreterPath $python `
  -ParametersJson '{"repo":"Heljens-IT-Services/agent-organization","path":"README.md","ref":"develop"}' `
  -WorkItemRef '#63' -ExecutionRef 'run-2' `
  -SourcePath "$env:USERPROFILE/.codex/skills/.system/skill-installer/scripts/github_utils.py" `
  -TrustedSourceRoots "$env:USERPROFILE/.codex/skills/.system/skill-installer/scripts"
```

Beide Wrapper benoetigen `-CoreInterpreterPath` mit dem vollstaendigen absoluten
Pfad zur freigegebenen Python-Executable. Absolute Registry-Interpreter muessen
identisch gebunden werden; der Coreinterpreter kann ein anderer sein, dann muss
der Aufrufer `-InterpreterBindings @{ '<absoluter Registry-Pfad>' = '<Derselbe Registry-Pfad>' }`
angeben. Nur Namensbindungen koennen betreibergesteuert auf eine freigegebene
vollstaendige Executable zeigen. Es wird keine beliebige gefundene Executable verwendet.
Der gemeinsame Runtimekern prueft den verbindlichen Request- und Responsevertrag
einschliesslich Parameterformen. PowerShell transportiert die Requestdaten und
gibt die vollstaendige Core-Ausgabe unveraendert weiter; stderr bleibt Diagnose.
`CoreInterpreterPath` ist betriebliche Pflichtkonfiguration und wird als
vollstaendiger Interpreter-Key sowie fuer `python` gebunden. Absolute
Registry-Interpreter muessen identisch gebunden werden; der Coreinterpreter kann
ein anderer sein, dann muss der Aufrufer
`-InterpreterBindings @{ '<absoluter Registry-Pfad>' = '<Derselbe Registry-Pfad>' }`
angeben. Nur Namensbindungen koennen betreibergesteuert auf eine freigegebene
vollstaendige Executable zeigen. Interpreter werden durch explizite Bindungen
und Reparsepruefungen begrenzt. Diese Dokumentation enthaelt keine aktuellen
Laufzeitbelege.
