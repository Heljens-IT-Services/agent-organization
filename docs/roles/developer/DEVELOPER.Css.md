# DEVELOPER.Css.md

Stand: 2026-07-22

## Zweck

Diese Datei gilt für CSS, Styling und präsentationsnahe UI-Regeln. Zugehörige allgemeine Developer-Regeln werden über [DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/developer/DEVELOPER.md), weitere technologiespezifische Regeldateien über [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) aufgelöst.

## Styling, UI und Accessibility

[MUST_IF] Ein bestehendes Design erweitert wird, müssen dessen UI-Konventionen eingehalten werden.

[ALLOW_IF] Eine Neugestaltung beauftragt ist, dürfen Konventionen begründet und konsistent ersetzt werden.

[MUST] Component-SCSS muss lokal, begrenzt und komponentennah bleiben.

[MUST_NOT] Component-SCSS darf keine globalen Seiteneffekte erzeugen.

[MUST_NOT] Globale Styles dürfen nicht für lokale Component-Probleme erweitert werden.

[MUST_NOT] Inline-Styles dürfen nicht verwendet werden, außer für dynamische Werte, die nicht sinnvoll über Klassen oder CSS Custom Properties abbildbar sind.

[MUST_NOT] Styling-Änderungen dürfen keine ungenutzten Klassen, doppelten Regeln oder widersprüchlichen Layout-Mechanismen einführen.

[MUST] Spacing, Typografie, Farben, Radius, Schatten und Breakpoints müssen dem geltenden Designkonzept folgen.

[MUST_NOT_IF] Magic Numbers in CSS dürfen nicht eingeführt werden, wenn bestehende Tokens, Variablen oder Konventionen vorhanden sind.

[MUST_IF] Responsive Verhalten muss bei layoutrelevanten Änderungen berücksichtigt werden.

[MUST] Kontraste, Fokuszustand, Disabled-Zustand, Loading-Zustand und Fehlerzustand müssen visuell nachvollziehbar sein.
