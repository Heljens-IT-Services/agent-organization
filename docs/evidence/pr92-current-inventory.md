# PR92 – aktuelles zugängliches Skriptinventar

Stand der Quellenlesung: 2026-10-12, 17:12:05–17:14:55 Europe/Berlin. Quellenbefund für `teamleiter_softwareentwicklung`, keine Funktionsprüfung oder Abnahme.

## Umfang und Grenzen

Ausgangspunkt war PR92-Head `39de9cf36dbe118f0aede552b29990e626d49db0`, integriert mit `develop` `3114a8f628ca4866dfc1d144400d3f07bc1e6316`. Die Pfadaufnahme umfasste Skriptquellen beider Trees (18 im PR-Head, 16 in develop, 24 vereinigt) sowie elf zugängliche lokale `agent-organization*`-Arbeitskopien, `agent-files`, `codex-worker` und `.codex/skills/.system`. Fremdkopien sind Kandidaten-/Referenzquellen, kein autoritativer oder stabiler develop-Snapshot. Gelesen wurden relevante Quellen, Schnittstellen und Seiteneffekte; keine umfassende Grundlagenprüfung.

Erfasste Sprachen: PowerShell (`.ps1`, `.psm1`), Python, JavaScript (CommonJS/ESM), Shell/Bash einschließlich des endungslosen `resolve-latest-model-info` sowie eingebettetes C#-Interop in PowerShell. Die bestehende P1-Ausführung bindet PowerShell und Python; das Inventar behauptet keine Unterstützung aller gefundenen Sprachen. Keine relevante eigenständige TypeScript- oder Batch-Skriptfunktion festgestellt. Kompilierte C#-Anwendungsprojekte sind keine Skriptkandidaten.

Zusätzliche relevante Quellen: sechs neue Runner-/Runtimequellen seit PR88 (`Find-Skill.ps1`, `Invoke-Skill.ps1`, `Invoke-PowerShellAdapter.ps1`, `PS-Bootstrap.ps1`, `skill_runtime.py`, `validate_response.py`) plus `scripts/skills/README.md`; sechs Coordinatorquellen in develop (`Start-CoordinatorHost.ps1`, `Start-CoordinatorConsole.ps1`, `Register-CoordinatorAutostart.ps1`, `Invoke-CoordinatorTurn.ps1`, `CoordinatorHost.Core.psm1`, `CoordinatorSupervisor.psm1`). Ferner relevant: lokale Installer-/Creator-Skripte, Bildhilfen, Angular-Konfigurationen und `codex-worker`-Entry-/Qualitätsskripte.

Abgegrenzt zugänglich waren diese lokalen Arbeitskopien und genannten Verzeichnisse. Nicht erfasst: unbekannte Rechner-/Remotequellen, fachfremde Produktrepositories, Paket-/Plugin-Caches als Gesamtbestand und generierte Abhängigkeiten. Kein Vollständigkeitsanspruch außerhalb dieser Quellen; laufende Fremdarbeiten können den Bestand ändern.

## Kandidaten und Gründe

- **P1 beibehalten:** `Get-TaskTokenUsage.ps1` mit vorhandenem Adapter liest Ledgerdaten und dedupliziert, ohne Buchungslogik zu duplizieren. `github_utils.py::github_api_contents_url` mit vorhandenem Adapter erzeugt eine URL ohne HTTP-Aufruf; der bestehende Caller bleibt maßgeblich. Beide waren zum historischen Inventar quellseitig unverändert; Quellgleichheit ist kein Laufzeitbeleg.
- **P2 zurückstellen:** `Get-WorkItems.ps1` berührt Sperrdateien und temporäre Validierung; `ContractValidation.ps1` ist als gemeinsame Bibliothek nutzbar, ein Skilladapter hat hier keine Priorität. `Test-WorkItems.ps1` ist ein produktiver Snapshot-/Lifecyclevalidator, kein Testharness oder zusätzlich nötiges Beispiel.
- **P3 zurückstellen:** `Import-RolloutTaskUsage.ps1` schreibt Ledgerzustand; vor einer späteren Bindung wäre Mutation von Transformation zu trennen.
- **Nicht für minimale Auswahl:** Store-Schreib-/Recoveryfunktionen und `Test-Organization.ps1` wegen Mutation, Recovery oder Organisationskopplung. Coordinator-Host/Supervisor starten Prozesse und schreiben Session-/Accountingzustand; Autostart registriert optional Aufgaben; Turnclient ist Session-/Pipe-gebunden. Installer/Creator schreiben Dateien oder nutzen Git/Netzwerk; Bildhilfen haben SDK-/Dateivoraussetzungen; Node-/Angular-/Workerquellen haben CLI-, Netzwerk-, Projekt-, Docker- oder .NET-Abhängigkeiten. Das bietet keinen gleichartigen zusätzlichen Bedarf für die zwei P1-Funktionen.

## Issue-Scopeentscheidungen

- **#67:** Die ältere PR92-Dokumentation räumte eine neue Inventur ausdrücklich aus. Dieses aktuelle Quelleninventar behebt die Recherche-/Dokumentationslücke nach seiner Aufnahme in den integrierten Stand; bei Nichtaufnahme `Closes #67` entfernen.
- **#68:** Die begründete minimale Wiederverwendung ist durch beide vorhandenen P1-Adapter abgedeckt; neue Quellen begründen keine weitere Migration. Die Entscheidung hängt von der Aufnahme des #67-Abgleichs ab. Keine frische Runtimeevidenz.
- **#66:** Der Quellenumfang ist nach Inventaraufnahme beschreibbar, aber Elternstory und eigene Elternabnahme bleiben offen. Kinderbefund ist keine Abnahme; ohne Aufnahme oder eigene Abnahme `Closes #66` entfernen.

Gültige frühere Quellenannahmen und datierte Evidenz bleiben unverändert. Belegmethode: Inhalts-, Pfad-, Git-Diff-/Referenz- und vorhandener SHA-256-Readback. Keine Tests, Parser, Validatoren, Compiler, Interpreter, Skills, Runner, Runtime, CI oder GitHub-Writes. Aktuelles Fehler-/Ausgabeverhalten, vollständiger Gesamtbestand und Laufzeitkompatibilität bleiben unbelegt.

