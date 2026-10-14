# TESTER.Angular.Playwright.md

Stand: 2026-08-18

## Zweck

Diese Datei definiert Playwright-Regeln für Angular-Anwendungen. Allgemeine Tester- und Angular-Regeln werden über [TESTER.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.md) und [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) aufgelöst.

## Funktionale Tests

[MUST] Alle fachlichen Nutzerflows müssen durch Playwright-E2E-Tests abgedeckt sein.

[MUST] Jede interaktive Nutzeraktion muss mindestens einmal über ihren von außen beobachtbaren Effekt getestet werden.

[MUST] Navigation, Sichtbarkeits- und Zustandsänderungen, Eingaben und Validierung, Tastaturbedienung, unterstützte Gesten, persistierende Aktionen sowie Fehler-, Loading- und Disabled-Zustände müssen getestet werden, wenn sie Teil der Anwendung sind.

[MUST_IF] Unterscheiden sich Verhalten oder Interaktion zwischen Themes oder Viewports, müssen die betroffenen funktionalen Tests diese Varianten abdecken.

[MUST] Tests müssen das Nutzerergebnis statt interner Implementierungsdetails prüfen.

[SHOULD] Nutzerorientierte Selektoren wie `getByRole`, `getByLabel` und `getByText` sollen bevorzugt werden.

[ALLOW_IF] `data-testid` darf verwendet werden, wenn kein robuster semantischer Selektor verfügbar ist.

[MUST_NOT] Feste Wartezeiten wie `waitForTimeout` dürfen nicht verwendet werden.

## Visuelle Tests

[MUST] Das Projekt muss seine unterstützten Themes und relevanten Viewports definieren.

[MUST] Für jede visuell relevante Component muss für jede unterstützte Kombination aus Component, Viewport und Theme ein Playwright-Referenzbild existieren.

[MUST] Visuelle Tests müssen das tatsächlich im Browser gerenderte Ergebnis einschließlich Styles von Frameworks und UI-Bibliotheken prüfen.

[MUST_IF] Eine UI-Änderung betrifft eine Referenzkombination, muss deren visueller Test ausgeführt und das Referenzbild nur bei beabsichtigter Designänderung aktualisiert werden.

[MUST_NOT] Fehlgeschlagene visuelle Vergleiche dürfen nicht ungeprüft durch neue Referenzbilder ersetzt werden.
