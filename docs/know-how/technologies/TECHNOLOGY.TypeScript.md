# TECHNOLOGY.TypeScript.md

Stand: 2026-07-22

## Zweck

Diese Datei gilt für TypeScript. Zugehörige allgemeine Developer-Regeln werden über [TECHNOLOGY.md](https://heljens-it-services.github.io/agent-organization/know-how/technologies/TECHNOLOGY.md), weitere technologiespezifische Regeldateien über [technology.index.json](https://heljens-it-services.github.io/agent-organization/know-how/technologies/technology.index.json) aufgelöst.

## Qualität und Code

[MUST] TypeScript `strict` muss aktiviert bleiben.

[ALLOW_IF] `any` darf nur an technischen Grenzen mit begründeter Kapselung verwendet werden.

[MUST] TypeScript-Modelle, DTOs und Objektverträge müssen als `type` definiert werden, außer ein technischer Grund liegt vor und das aktive Lint-Regelwerk erlaubt ein `interface`.

[MUST] Die `type`-Konvention muss über `@typescript-eslint/consistent-type-definitions` erzwungen werden.
