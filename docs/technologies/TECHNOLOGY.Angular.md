# TECHNOLOGY.Angular.md

Stand: 2026-08-12

## Zweck

Diese Datei gilt für Angular. Allgemeine Developer-Regeln werden über [TECHNOLOGY.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.md), weitere technologiespezifische Regeldateien über [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) aufgelöst.

## Architektur

[MUST] Components sind auf Darstellung, Nutzerinteraktion und lokalen UI-State beschränkt und greifen über Facades oder Component Services auf fachliche Abläufe zu.

[MUST] Feature State liegt im Feature; globaler State ist auf app-weite Zustände beschränkt.

[MUST] HTTP-Requests liegen unter `src/app/core/data-access/`; lokale Persistenz und Hintergrundarbeit werden über eigene Services gekapselt.

[MUST_NOT] Components dürfen HTTP, Persistenz, globalen State oder Worker nicht direkt ansprechen.

## Struktur

[SHOULD] Angular-Projekte sollen dieser Grundstruktur folgen:

```text
src/app/
  core/
  features/<feature>/
  shared/
  spec/
    core/
    features/<feature>/
    shared/
  app.routes.ts
  app.config.ts
```

[MUST] `core/` enthält app-weite Infrastruktur, `shared/` fachlich neutrale Bausteine und `features/` fachliche Features.

[MUST] Jedes Feature hat seinen Einstiegspunkt unter `<feature>/page/`; weitere Feature-Komponenten liegen jeweils unter `<feature>/components/<component-name>/`.

[MUST] `src/app/spec/` enthält ausschließlich ausgelagerte Test-Hilfsartefakte.

[SHOULD] Standalone Components und funktionale Provider sollen verwendet werden, sofern das Projekt nichts anderes erfordert.

## TypeScript-Pfad-Aliase

[MUST] `compilerOptions.paths` muss `@core`, `@shared`, `@spec` und einen eigenen Alias je Feature inklusive `/*` definieren.

[MUST] Imports über diese Architekturgrenzen müssen die Aliase verwenden.

[MUST_IF] Neue oder umbenannte Features müssen ihren Alias im selben Task anlegen oder anpassen.

## State und Datenzugriff

[SHOULD] Signals sollen für synchronen UI-State verwendet werden.

[MUST_NOT] RxJS darf nicht als Anwendungs-State- oder Datenfluss-Primitive verwendet werden.

[ALLOW_IF] Angular-/RxJS-Interop darf genutzt werden, wenn Angular APIs oder externe Bibliotheken Observables erfordern.

[SHOULD] Einmalige HTTP-Requests sollen Promise-basiert sein.

[ALLOW_IF] Observable-basierte HTTP-Requests sind zulässig, wenn Cancellation, Progress, Streams oder eine verwendete API sie erfordern.

[MUST] DTOs müssen an der Systemgrenze in interne Modelle gemappt werden.

## Forms

[SHOULD] Signal Forms sollen verwendet werden, wenn sie im verwendeten Angular-Setup stabil unterstützt werden.

[MUST] Geteilte fachliche Validierung muss außerhalb der Component liegen.

## Qualitätssicherung

[MUST] Angular-Projekte müssen [Prettier](https://heljens-it-services.github.io/agent-organization/config/angular/quality/prettier.json), [ESLint](https://heljens-it-services.github.io/agent-organization/config/angular/quality/eslint.config.mjs), [dependency-cruiser](https://heljens-it-services.github.io/agent-organization/config/angular/quality/dependency-cruiser.cjs) und Knip verwenden.

[MUST_IF] Die Referenzkonfigurationen müssen nur bei Projekt-Setup, fehlender QA-Konfiguration oder Änderungen an der QA-Konfiguration gelesen werden.

[MUST] `package.json` muss `format`, `format:check`, `lint`, `architecture:check` und `dead-code:check` bereitstellen.

[MUST] `dead-code:check` muss Knip ausschließlich zur Erkennung verwenden und sowohl den normalen Scan als auch den Production-Scan ausführen; eine äquivalente Skriptdefinition ist `knip --no-exit-code && knip --production --no-exit-code`.

[MUST] Knip ist aktuell ausschließlich ein Detection Tool. Ein Knip-Finding ist ein Analysehinweis und allein kein ausreichender Grund, Code, Exports, Dateien oder Dependencies zu verändern oder zu entfernen.

[MUST] Der Agent muss Knip-Findings einzeln im Projektkontext bewerten und darf je Finding entscheiden, ob es im aktuellen Task behoben, weiter untersucht oder bewusst unverändert gelassen wird.

[MUST_NOT] Knip-Auto-Fixes oder automatische Löschungen dürfen nicht verwendet oder in Skripten hinterlegt werden; insbesondere sind `--fix`, `--fix-type` und `--allow-remove-files` für die automatisierte Ausführung durch den Agenten nicht zulässig.

[MUST] Vor Abschluss eines Code-Tasks müssen `format:check`, `lint` und `architecture:check` erfolgreich laufen; `dead-code:check` muss ausgeführt und seine Findings müssen bewertet werden. Findings aus `dead-code:check` blockieren den Abschluss nicht automatisch.

[MUST_NOT] Explizites `any` darf in Angular-Code nicht verwendet werden.
