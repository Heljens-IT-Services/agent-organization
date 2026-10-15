# TECHNOLOGIES.md

## Zweck

Diese Datei enthält Navigationsmetadaten zu technologiespezifischen Regeldateien. Freigabe und Voraussetzungen stehen ausschließlich im Index der ausdrücklich zugewiesenen Rolle; dieses Inventar aktiviert keine Regeldatei, Rolle oder Agent.

Spezialisten verwenden dieses Inventar bei Bedarf für die Mappings ihrer eigenen Rolle. Sie erkennen vorhandene Technologien selbständig aus auftragsrelevanten Projektdateien und laden die direkt freigegebenen Regeln einschließlich Voraussetzungen. Der Koordinator weist den Fachauftrag zu; die konkrete Kontextauswahl trifft die ausführende Rolle. Ein Stackwechsel bleibt eine gesonderte Entscheidung innerhalb der Projekt- und Freigabegrenzen.

Die Command-Semantik steht in [COMMANDS.md](https://heljens-it-services.github.io/agent-organization/COMMANDS.md).

## Verwendung

[MUST] `/technologies show <technology-id>` muss die für den angefragten Rollenscope freigegebenen Mappings der Technologie vollständig ausgeben, ohne damit eine Rolle oder Regeldatei zu aktivieren.

[MUST] Der Agent darf eine technologiespezifische Datei nur lesen, wenn sein eigener Rollenindex sie direkt aufführt oder sie dort als ausdrückliche Voraussetzung aufgeführt ist und die Technologie im beauftragten Scope relevant ist.

[MUST_NOT] Ein Einleitungstext oder Link innerhalb einer technologiespezifischen Datei darf keine weitere Regeldatei automatisch freigeben. Weitere Dateien müssen im eigenen Rollenindex als passende Technologie oder ausdrückliche Voraussetzung stehen.

[MUST] Beim Laden technologiespezifischer Regeln werden die in der eigenen Rollenbeschreibung freigegebenen gemeinsamen Fachbasen und Voraussetzungen mitgeladen.

[MUST_NOT] Dieses Inventar darf Regeln aus den verlinkten Fachbasen oder Rollenbeschreibungen nicht duplizieren.

## Technologien

| ID | Technologie | Rolle | Regeldatei | Lesen und verwenden, wenn | Zweck |
|---|---|---|---|---|---|
| `angular` | Angular | `software-architect` | [TECHNOLOGY.Angular.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.Angular.md) | Angular-Verträge oder Architekturgrenzen im Architekturauftrag betroffen sind. | Angular-spezifische technische Randbedingungen. |
| `angular` | Angular | `software-architect` | [TESTER.Angular.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.Angular.md) | Angular-Testregeln für technische Kriterienprüfung betroffen sind und Architektur sie im eigenen Index freigibt. | Angular-Testspezifische technische Kriterien. |
| `angular` | Angular | `frontend-developer` | [TECHNOLOGY.Angular.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.Angular.md) | Angular-Oberfläche oder clientseitiges Verhalten im Implementierungsauftrag betroffen ist. | Angular-Entwicklungsregeln. |
| `angular` | Angular | `frontend-developer` | [TESTER.Angular.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.Angular.md) | Angular-Testregeln für die lokale Verifikation eigener Änderungen erforderlich sind und der Rollenindex die Datei freigibt. | Angular-Testregeln für lokale Entwicklerverifikation. |
| `playwright` | Playwright | `frontend-developer` | [TESTER.Angular.Playwright.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.Angular.Playwright.md) | Playwright-E2E-Regeln für die lokale Verifikation eigener Änderungen erforderlich sind und der Rollenindex die Datei freigibt. | Angular-E2E-Regeln für lokale Entwicklerverifikation. |
| `angular` | Angular | `infrastructure-engineer` | [TECHNOLOGY.Angular.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.Angular.md) | Ein beauftragtes Angular-Projekt-Setup, Build oder Laufzeitverhalten betroffen ist. | Angular-Projektgrenzen bei Infrastrukturarbeit. |
| `angular` | Angular | `quality-assurance-engineer` | [TESTER.Angular.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.Angular.md) | Angular-Verhalten oder Angular-Qualitätschecks geprüft werden. | Angular-spezifische Testregeln. |
| `csharp-net` | C# und .NET | `software-architect` | [TECHNOLOGY.CSharpNet.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.CSharpNet.md) | C#/.NET-Verträge oder Abhängigkeiten im Architekturauftrag betroffen sind. | C#/.NET-Randbedingungen für technische Entwürfe. |
| `csharp-net` | C# und .NET | `backend-developer` | [TECHNOLOGY.CSharpNet.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.CSharpNet.md) | C#/.NET-Backend-Code oder Verträge betroffen sind. | C#/.NET-Entwicklungsregeln. |
| `csharp-net` | C# und .NET | `infrastructure-engineer` | [TECHNOLOGY.CSharpNet.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.CSharpNet.md) | Ein beauftragter C#/.NET-Build, Deployment oder Runtime-Scope betroffen ist. | C#/.NET-Randbedingungen für Betrieb und Bereitstellung. |
| `css` | CSS | `frontend-developer` | [TECHNOLOGY.Css.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.Css.md) | Styling oder UI-nahe Präsentation implementiert wird. | CSS- und Präsentationsregeln. |
| `html` | HTML | `frontend-developer` | [TECHNOLOGY.Html.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.Html.md) | Markup implementiert oder geändert wird. | HTML- und Markup-Regeln. |
| `net-application` | .NET Application | `software-architect` | [TECHNOLOGY.NetApplication.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetApplication.md) | Architektur einer geschichteten .NET-Anwendung betroffen ist. | Strukturregeln für .NET-Anwendungsarchitektur. |
| `net-application` | .NET Application | `backend-developer` | [TECHNOLOGY.NetApplication.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetApplication.md) | Eine geschichtete .NET-Anwendung umgesetzt wird. | Regeln für geschichtete .NET-Anwendungen. |
| `net-application` | .NET Application | `infrastructure-engineer` | [TECHNOLOGY.NetApplication.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetApplication.md) | Deployment oder Laufzeit einer geschichteten .NET-Anwendung betroffen ist. | .NET-Anwendungsgrenzen bei Betriebsarbeit. |
| `net-console` | .NET Console | `software-architect` | [TECHNOLOGY.NetConsole.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetConsole.md) | Architektur eines .NET-Konsoleneinstiegs betroffen ist. | .NET-Console-Randbedingungen für technische Entwürfe. |
| `net-console` | .NET Console | `backend-developer` | [TECHNOLOGY.NetConsole.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetConsole.md) | Eine .NET-Konsolenanwendung umgesetzt wird. | Regeln für .NET-Konsolenanwendungen. |
| `net-console` | .NET Console | `infrastructure-engineer` | [TECHNOLOGY.NetConsole.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetConsole.md) | Build oder Laufzeit einer .NET-Konsolenanwendung betroffen ist. | .NET-Console-Randbedingungen für Betrieb. |
| `net-web-api` | .NET Web API | `software-architect` | [TECHNOLOGY.NetWebApi.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetWebApi.md) | Architektur oder Verträge einer .NET-Web-API betroffen sind. | Web-API-Randbedingungen für technische Entwürfe. |
| `net-web-api` | .NET Web API | `backend-developer` | [TECHNOLOGY.NetWebApi.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetWebApi.md) | Eine .NET-Web-API umgesetzt wird. | Regeln für .NET-Web-APIs. |
| `net-web-api` | .NET Web API | `infrastructure-engineer` | [TECHNOLOGY.NetWebApi.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.NetWebApi.md) | Deployment oder Runtime einer .NET-Web-API betroffen ist. | Web-API-Randbedingungen für Betrieb. |
| `playwright` | Playwright | `quality-assurance-engineer` | [TESTER.Angular.Playwright.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.Angular.Playwright.md) | Angular-E2E- oder visuelle Verifikation mit Playwright beauftragt ist. | Playwright-Regeln für Angular. |
| `playwright` | Playwright | `software-architect` | [TESTER.Angular.Playwright.md](https://heljens-it-services.github.io/agent-organization/roles/tester/TESTER.Angular.Playwright.md) | Eine technische Angular-E2E-Prüfung mit Playwright ausdrücklich beauftragt ist und der eigene Rollenindex die Datei freigibt. | Playwright-Regeln für technische Angular-Kriterienprüfung. |
| `typescript` | TypeScript | `frontend-developer` | [TECHNOLOGY.TypeScript.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.TypeScript.md) | Clientseitiger TypeScript-Code umgesetzt wird. | TypeScript-Entwicklungsregeln. |
| `typescript` | TypeScript | `backend-developer` | [TECHNOLOGY.TypeScript.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.TypeScript.md) | TypeScript-Code, -Verträge oder Buildskripte im zugewiesenen technischen Scope betroffen sind. | TypeScript-Grundregeln im eigenen Scope. |
| `typescript` | TypeScript | `software-architect` | [TECHNOLOGY.TypeScript.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.TypeScript.md) | TypeScript-Code, -Verträge oder Buildskripte im zugewiesenen technischen Scope betroffen sind. | TypeScript-Grundregeln im eigenen Scope. |
| `typescript` | TypeScript | `infrastructure-engineer` | [TECHNOLOGY.TypeScript.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.TypeScript.md) | TypeScript-Code, -Verträge oder Buildskripte im zugewiesenen technischen Scope betroffen sind. | TypeScript-Grundregeln im eigenen Scope. |
| `typescript` | TypeScript | `quality-assurance-engineer` | [TECHNOLOGY.TypeScript.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.TypeScript.md) | TypeScript-Testcode im ausdrücklich zugewiesenen QA-Code-Scope implementiert oder gepflegt wird; TECHNOLOGY.md wird als direkt freigegebene Voraussetzung geladen. | Entwicklungsregeln ausschließlich für beauftragten QA-Testcode. |
| `csharp-net` | C# und .NET | `quality-assurance-engineer` | [TECHNOLOGY.CSharpNet.md](https://heljens-it-services.github.io/agent-organization/technologies/TECHNOLOGY.CSharpNet.md) | C# und .NET-Testcode im ausdrücklich zugewiesenen QA-Code-Scope implementiert oder gepflegt wird; TECHNOLOGY.md wird als direkt freigegebene Voraussetzung geladen. | Entwicklungsregeln ausschließlich für beauftragten QA-Testcode. |
