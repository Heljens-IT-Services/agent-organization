# DEVELOPER.TypeScript.md

Stand: 2026-07-22

## Zweck

Diese Datei gilt für TypeScript. Zugehörige allgemeine Developer-Regeln werden über [DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/developer/DEVELOPER.md), weitere technologiespezifische Regeldateien über [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) aufgelöst.

## Qualität und Code

[MUST] TypeScript `strict` muss aktiviert bleiben.

[ALLOW_IF] `any` darf nur an technischen Grenzen mit begründeter Kapselung verwendet werden.

[MUST] TypeScript-Modelle, DTOs und Objektverträge müssen als `type` definiert werden, außer ein technischer Grund liegt vor und das aktive Lint-Regelwerk erlaubt ein `interface`.

[MUST] Die `type`-Konvention muss über `@typescript-eslint/consistent-type-definitions` erzwungen werden.
