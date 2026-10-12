# Agent Organization

Versionierte Agentenorganisation für Heljens IT Services: Ein Koordinator nimmt
Anfragen entgegen, Teamleiter koordinieren Fachbereiche und Spezialisten führen
die operative Arbeit aus.

Es gibt neun Teams: Softwareentwicklung, Design, Marketing, Controlling,
Buchhaltung, Geschäftsführung und Assistenz, HR, Agent Ressources und Administratoren.

**Status:** [koordinator/koordinator.toml](koordinator/koordinator.toml) ist implementiert und
bytegleich unter `~/.codex/agents/koordinator.toml` installiert. Die TOML allein
aktiviert den App-Hauptchat nicht automatisch. Alle neun Teamleiter und 35
operative Rollen sind implementiert und persönlich installiert: zehn
koordinierende Rollen einschließlich Koordinator, insgesamt 45 TOMLs.
Die Teamleiter nutzen ihre jeweiligen `teams/<team_id>/agenten.json`-Indizes.

[Fensterdelegation](docs/FENSTERDELEGATION.md) startet einen parametrischen Auftrag
im eigenen sichtbaren PowerShell-Fenster, zeigt Kontext vor Arbeitsbeginn und
schließt nach gesichertem Ergebnis. Der Ablauf wurde mit einer tatsächlichen
QA-Aufgabe geprüft. Die automatische Anbindung sämtlicher Delegationen ist offen.

Das [Konzept](docs/CONCEPT.md) beschreibt Hierarchie, Teams, Konfigurationsidee
und offene Umsetzungspunkte. Die [Projektleitplanken](PROJECT.md) begrenzen den
aktuellen Scope. [AGENTS.md](AGENTS.md) macht den Koordinator für alle Repositoryarbeiten zur
verpflichtenden Top-Level-Rolle; ausdrücklich zugewiesene Teamleiter und
Spezialisten behalten ihre eigene Rolle. Der Koordinator beauftragt ausschließlich
Teamleiter; diese entscheiden selbst über ihre operative Besetzung.
Empfindliche Organisationsstrukturen werden ausschließlich über
Koordinator -> zuständiger Teamleiter -> Optimierer geändert, mit abgegrenztem
WorkItem und vorheriger menschlicher Freigabe; [AR55](docs/contracts/AR55-IMPLEMENTATION.md)
belegt die lokale Umsetzung und die noch ausstehende unabhängige Abnahme.

Koordinator, alle Teamleiter, Softwarearchitektur, Software-Qualitätssicherung,
Agent-Ressources-Qualitätsprüfung, Optimierer und Vertragskoordination verwenden `gpt-6.1-sol`;
die übrigen Rollen `gpt-6-luna`. Reasoning bleibt überall `medium`. Administratoren nutzen
vorhandene MCP-Werkzeuge oder Browsersteuerung; Dienstzugänge sind separat nötig.

Voraussetzung ist Codex mit standalone Custom Agents. Build und CI sind nicht
vorhanden; GitHub Actions sind deaktiviert.

[WorkItem-Verträge](docs/contracts/WORKITEMS.md) trennen Umsetzung und Abnahme;
[Organisationsverträge](docs/contracts/ORGANIZATION.md) validieren die bestehenden
Indizes. [Entscheidung 0001](docs/decisions/0001-system-scope.md) legt Struktur und
Folgeumfang fest. Der frühere Test-Contracts-Aufruf ist aufgehoben; technische
Testinfrastruktur wird nicht mehr mitgeführt. Der produktive
Organisationsvertragsvalidator bleibt verfügbar:
`scripts/contracts/Test-Organization.ps1`.

## Zentraler Skillzugriff

`scripts/skills/Find-Skill.ps1` und `Invoke-Skill.ps1` verwenden den gemeinsamen
Pythonkern `scripts/skills/skill_runtime.py`. Discovery sucht zentral in der
Registry; mehrdeutige Zwecksuche startet keinen Skill. Für beide Aufrufe ist ein
freigegebener Python-Interpreter als vollständiger `CoreInterpreterPath`
anzugeben:

```powershell
$repo = (Resolve-Path '.').Path
$python = 'C:/Users/Tom-OliverMarek/AppData/Roaming/uv/python/cpython-3.13-windows-x86_64-none/python.exe'

# Zentrale Discovery
./scripts/skills/Find-Skill.ps1 -RepositoryRoot $repo -CoreInterpreterPath $python `
  -SkillId 'task-token-usage'
./scripts/skills/Find-Skill.ps1 -RepositoryRoot $repo -CoreInterpreterPath $python `
  -Purpose 'Contents-URL'

# Bestehender P1-PowerShell-Adapter; Accounting-Verzeichnis freigeben.
./scripts/skills/Invoke-Skill.ps1 -RepositoryRoot $repo -CoreInterpreterPath $python `
  -SkillId 'task-token-usage' `
  -ParametersJson '{"task_id":"00000000-0000-0000-0000-000000000000","accounting_directory":"C:/agent-data/ledger"}' `
  -WorkItemRef '#63' -ExecutionRef 'run-ps-1' `
  -AccountingRoots @('C:/agent-data/ledger') `
  -LogPath 'C:/agent-data/logs/skill-runs.jsonl' -TimeoutSeconds 60

# Bestehender P1-Python-Adapter; Quelle und Quellwurzel explizit freigeben.
./scripts/skills/Invoke-Skill.ps1 -RepositoryRoot $repo -CoreInterpreterPath $python `
  -SkillId 'github-contents-url' `
  -ParametersJson '{"repo":"Heljens-IT-Services/agent-organization","path":"README.md","ref":"develop"}' `
  -WorkItemRef '#63' -ExecutionRef 'run-py-1' `
  -SourcePath "$env:USERPROFILE/.codex/skills/.system/skill-installer/scripts/github_utils.py" `
  -TrustedSourceRoots @("$env:USERPROFILE/.codex/skills/.system/skill-installer/scripts") `
  -LogPath 'C:/agent-data/logs/skill-runs.jsonl' -TimeoutSeconds 60
```

`AccountingRoots` und `TrustedSourceRoots` begrenzen freigegebene Daten- und
Quellpfade; `LogPath` legt das Ausführungsprotokoll fest. Der Timeout-Default
des Skill-Runners ist 60 Sekunden. Der vollständige Coreinterpreterpfad wird
als Registry-Key und als Wert für `python` gebunden. Absolute
Registry-Interpreter müssen identisch gebunden werden; der Coreinterpreter kann
ein anderer sein, dann muss der Aufrufer
`-InterpreterBindings @{ '<absoluter Registry-Pfad>' = '<Derselbe Registry-Pfad>' }`
angeben. Nur Namensbindungen können betreibergesteuert auf eine freigegebene
vollständige Executable zeigen. PowerShell kann explizit zugeordnet werden.
Zusätzliche Bindungen müssen auf absolute Executablepfade zeigen. Die Anfrage wird als UTF-8-Datei an den
Kern übergeben, damit PowerShell 5.1 kein `StandardInputEncoding` benötigt.
Die Beispiele beschreiben Bedienung, sie sind keine aktuellen Laufzeitbelege;
die Wrapper wurden in diesem Auftrag nicht ausgeführt.
