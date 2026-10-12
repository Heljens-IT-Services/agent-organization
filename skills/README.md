# Skills und selektive Registry

`registry.json` ist ein manuell gepflegtes Verzeichnis ausführbarer Beispiele.
Es gibt hier weder Discovery noch Runner. Neue Einträge müssen dem Vertrag in
[`docs/contracts/SKILLS.md`](../docs/contracts/SKILLS.md) und
[`schemas/skills.schema.json`](../schemas/skills.schema.json) entsprechen;
`scriptPath` zeigt auf vorhandenen Code. Fehlendes `language` verwendet den
PowerShell-Default. Alternative Sprachen benötigen einen Interpreter als
einzelnen Executable-Pfad ohne Argumente.

## Einträge

Die Registry enthält derzeit genau zwei selektive Beispiele: den bestehenden
Task-Tokenledger-Leser und die vorhandene reine GitHub-Contents-URL-Funktion.
Beide Adapter verwenden den #60-Antwortvertrag: genau ein JSON-Objekt mit den
case-sensitiven Feldern `isSuccessful` (Boolean), `exception` (Objekt oder
`null`) und `result` (beliebiges JSON einschließlich `null`). Bei Erfolg ist
`exception` `null`; bei behandelbarem Fehler enthält es `message`. Adapter-
Diagnostik beziehungsweise unerwartete Prozessfehler können die Ausgabe des
Vertrags verhindern.

## Aufruf

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

Die PowerShell-Parameter `TaskId` und `AccountingDirectory` besitzen die
Aliase `task_id` und `accounting_directory` aus der Registry. Die Python-Eingabe
enthält `repo`, `path` und `ref`. Fehlende oder leere Pflichtwerte ergeben,
sofern der Adapter gestartet wird, eine Fehlerantwort. Ungültiges Python-JSON
wird ebenfalls als Fehlerantwort behandelt. Python-CLI-Parsefehler innerhalb
des Adapters (etwa `--source-path` ohne Wert) werden als reguläre
`exception.message`-Fehlerantwort ausgegeben; der Parser ersetzt dafür seinen
`SystemExit`-Fehlerpfad durch `ValueError`. Der Prozessstart selbst und Fehler
vor Eintritt in den Adapter bleiben außerhalb dieser Grenze. Stdout enthält
im Adapterpfad genau ein Vertragsobjekt.

## Voraussetzungen und Nachweisgrenzen

Der Token-Adapter ruft ausschließlich
`scripts/accounting/Get-TaskTokenUsage.ps1` auf. Er liest den Accountingbestand;
unbekannte Messungen bleiben gemäß bestehender Semantik sichtbar und können
die inklusive Summe auf `null` setzen. Die Ledger-Fachlogik wird nicht
wiederholt.

Der Python-Adapter importiert `github_api_contents_url` aus der externen,
lokal bereitgestellten `github_utils.py`. Als Quelle ist nur die
vertrauenswürdige lokale Skill-Installer-Datei vorgesehen; die aktuell
quellgelesene Datei
`C:/Users/Tom-OliverMarek/.codex/skills/.system/skill-installer/scripts/github_utils.py`
enthält genau `github_api_contents_url(repo, path, ref)` und hatte beim Lesen
SHA-256 `2F9702AFB9F0DA740181FA4A3214F663E460F80CD5CEA2E7DCAAB00AD269082E`.
Dies ist ein Quellenfingerabdruck, keine zur Laufzeit erzwungene Integritäts-
oder Sicherheitsplattform. Standardquellen sind
`CODEX_HOME/skills/.system/skill-installer/scripts/github_utils.py` und danach
`USERPROFILE/.codex/skills/.system/skill-installer/scripts/github_utils.py`.
`--source-path <datei>` kann den lokalen Quellpfad explizit setzen. Fehlt die
Datei, kann sie nicht geladen werden oder fehlt die Funktion, wird ein
Fehlerumschlag ausgegeben. Die externe Datei wird weder kopiert noch durch
neue URL-Fachlogik ersetzt. Registry und Adapter transportieren keinen
absoluten Quellenpfad. `--source-path` ist ein Prozessstartargument und kein
registrierter Fachparameter. Ein Standardimport kann neben der Quelldatei
Python-Bytecode-Cache (`__pycache__`) schreiben. Der registrierte
Python-Executable-Pfad
`C:/Users/Tom-OliverMarek/AppData/Roaming/uv/python/cpython-3.13-windows-x86_64-none/python.exe`
wurde per Dateireferenzlesen als vorhanden festgestellt; Python 3.13.15 ist
nur historisch dokumentiert. Der Interpreter wurde hier nicht gestartet und
die aktuelle Version nicht ermittelt.

Die vorhandenen Dateien und Verträge wurden per Quellenlesen geprüft. Eine
frühere Dokumentation behauptete Adaptertests, doch der Recovery-Bericht hält
fest, dass kein terminaler Abschluss dieser Testausführung belegt ist. Daher
wird hier kein PASS oder bestätigter Laufzeitnachweis behauptet. Lokale
Adapterausführung bleibt ungeprüft; Implementierung und Abnahme sind getrennt.
