# TECHNOLOGY.NetConsole.md

Stand: 2026-07-22

## Zweck

Diese Datei gilt für .NET-Konsolenanwendungen. Zugehörige allgemeine und anwendungsbezogene Regeldateien werden über [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) aufgelöst.

## Zielbild

[MUST] Eine .NET-Konsolenanwendung muss mindestens ein Entry-Projekt für die Konsole sowie `<Name>.Infrastructure` und `<Name>.Core` enthalten.

[ALLOW_IF] Mehrere Entry-Projekte dürfen angelegt werden, wenn sie getrennte Use-Case- oder Streckenverantwortungen haben.

[MUST] Jedes Entry-Projekt muss genau einen Use Case Runner oder eine Console Application starten.

## Module und Bootstrap

[MUST] Die DI-Erweiterungsmethoden müssen `AddConsole(...)`, `AddInfrastructure(...)` und `AddCore(...)` heißen.

[MUST] `Program.cs` muss Generic Host, Konfiguration, Logging und Dependency Injection aufbauen.

[MUST] Ein- und Ausgabelogik muss außerhalb von `Program.cs` liegen und deterministisch testbar sein.

[MUST] Konsolentexte müssen fachlich formuliert sein und dürfen keine technischen Interna offenlegen.

## Konsolenspezifische Grenzen

[MUST] Exportmodelle müssen als Austauschformate behandelt und an der Systemgrenze gemappt werden.

[MUST_NOT] Rohe API-DTOs dürfen nicht in `Core` oder Entry-Projekten verwendet werden.

## Tests

[MUST] Konsolentests müssen Eingabe, Ausgabe, Host-Start und DI-Verkabelung deterministisch prüfen.

[MUST] Infrastrukturtests müssen zusätzlich relevante Parser- und Exportpfade abdecken.
