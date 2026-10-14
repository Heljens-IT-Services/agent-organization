# DEVELOPER.Html.md

Stand: 2026-07-22

## Zweck

Diese Datei gilt für HTML und Markup. Zugehörige allgemeine Developer-Regeln werden über [DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/developer/DEVELOPER.md), weitere technologiespezifische Regeldateien über [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) aufgelöst.

## HTML und Markup

[MUST] Markup muss schlank, lesbar und semantisch passend bleiben.

[ALLOW] Markup darf sichtbare Zustände, Nutzeraktionen und einfache UI-Verzweigungen abbilden.

[MUST_NOT] Markup darf keine fachliche Orchestrierung, komplexe Berechnungen, Datenmapping, Filterlogik oder technische Ablaufsteuerung enthalten.

[MUST] Komplexe Darstellungslogik muss aus dem Markup in klar benannte View-Modelle, Properties oder Hilfsstrukturen ausgelagert werden.

[MUST] Kontrollfluss im Markup muss nachvollziehbar bleiben.

[MUST] Jede neue DOM-Ebene muss einen klaren Zweck haben: Semantik, Layout, Zustand, Wiederverwendung oder Accessibility.

[MUST_NOT_IF] Neue Wrapper-Elemente dürfen nicht eingeführt werden, wenn sie keinen klaren Zweck erfüllen.

[MUST] Interaktive Elemente müssen als passende semantische Elemente umgesetzt werden, z. B. `button` für Aktionen und `a` für Navigation.

[MUST_NOT_IF] Klickbare `div`- oder `span`-Elemente dürfen nicht eingeführt werden, wenn ein semantisches Element verwendet werden kann.

[MUST] Formularfelder müssen programmatisch erkennbare Labels, Fehlermeldungen und Hilfetexte haben.

[MUST_IF] Bedingte Darstellung muss alle relevanten Nutzerzustände abdecken, sofern diese im Flow auftreten können: Laden, leerer Zustand, Fehler, nicht erlaubt, nicht verfügbar und regulärer Inhalt.
