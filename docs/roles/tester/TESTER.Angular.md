# TESTER.Angular.md

Stand: 2026-08-18

## Zweck

Diese Datei definiert Testregeln für Angular-Anwendungen. Allgemeine Tester-Regeln werden über [TESTER.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.md), weitere technologiespezifische Regeldateien über [technology.index.json](https://heljens-it-services.github.io/agent-organization/know-how/technologies/technology.index.json) aufgelöst.

## Tests

[MUST] Die zu einem Produktionsartefakt gehörende `*.spec.ts` muss direkt neben diesem Artefakt liegen.

[MUST_IF] Benötigt eine Spec eigene Helper, Fixtures, Builder, Mocks, Fakes, Stubs oder Testdaten, müssen diese unter `src/app/spec/` in einer zum Produktionsartefakt passenden Struktur liegen.

[MUST_NOT] Produktivcode darf `src/app/spec/` oder `@spec` importieren.

[MUST] Für Playwright-Tests gilt [TESTER.Angular.Playwright.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.Angular.Playwright.md).
