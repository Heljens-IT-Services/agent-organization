# TECHNOLOGY.NetWebApi.md

Stand: 2026-08-12

## Zweck

Diese Datei gilt für .NET-Web-APIs. Zugehörige allgemeine und anwendungsbezogene Regeldateien werden über [technology.index.json](https://heljens-it-services.github.io/agent-organization/know-how/technologies/technology.index.json) aufgelöst.

## Zielbild

[MUST] Eine .NET-Web-API muss die produktiven Hauptprojekte `<Name>.WebApi`, `<Name>.Infrastructure` und `<Name>.Core` enthalten.

[MUST] `WebApi` muss Composition Root für Host, Konfiguration, Dependency Injection, Middleware, Routing und HTTP-Verträge sein.

## Module und Bootstrap

[MUST] Die DI-Erweiterungsmethoden müssen `AddWebApi(...)`, `AddInfrastructure(...)` und `AddCore(...)` heißen.

[MUST] `Program.cs` muss Host, Konfiguration, Logging, Dependency Injection, Middleware-Pipeline und Routing aufbauen.

[ALLOW_IF] Middleware und Filter dürfen HTTP-nahe Querschnittsthemen wie Fehlerabbildung, Authentifizierung, Correlation IDs, Request Logging und CORS behandeln, wenn sie keinen fachlichen Use Case ersetzen.

## Endpoint-Struktur

[MUST] Fachliche und ressourcenorientierte HTTP-Endpunkte müssen als ASP.NET Core MVC Controller implementiert werden.

[MUST] Controller müssen `[ApiController]` verwenden, von `ControllerBase` ableiten und ihre Routen über Controller- oder Action-Attribute definieren.

[MUST] `WebApi` muss Controller über `AddControllers(...)` registrieren und `Program.cs` muss sie über `MapControllers()` in die Routing-Pipeline einbinden.

[MUST_NOT] Minimal APIs dürfen für fachliche oder ressourcenorientierte HTTP-Endpunkte nicht verwendet werden. Insbesondere dürfen solche Endpunkte nicht direkt über `MapGet`, `MapPost`, `MapPut`, `MapPatch`, `MapDelete`, `MapMethods` oder `MapGroup` definiert werden.

[MUST_NOT] API-Routen dürfen nicht als Lambda- oder Delegate-Handler in `Program.cs` oder in Endpoint-Registrierungserweiterungen definiert werden, wenn sie Controller-Actions ersetzen.

## HTTP-Verträge

[MUST] Controller müssen Requests validieren, Use Cases aufrufen und Ergebnisse in HTTP-Antworten mappen.

[MUST] Endpoints müssen ressourcen- oder use-case-orientiert benannt werden und passende HTTP-Methoden, Statuscodes und Routen verwenden.

[MUST] Request- und Response-DTOs müssen in `WebApi/Contracts/` liegen.

[MUST_NOT] Domain- oder Core-Modelle dürfen nicht direkt als HTTP-Verträge veröffentlicht werden.

[SHOULD] Fehlerantworten sollen eine Problem-Details-nahe Struktur verwenden. Abweichungen sind erlaubt, wenn ein bestehender stabiler API-Vertrag ein anderes Format vorgibt.

[MUST] API-Fehler müssen zentral in HTTP-Antworten gemappt werden.

[MUST_IF] Fällt eine notwendige Infrastruktur- oder Upstream-Abhängigkeit ohne fachlich definierten Fallback aus, muss die API den stabilen Fehlervertrag mit einem passenden Nicht-2xx-Statuscode zurückgeben.

[MUST] Der Cancellation-Token eines HTTP-Requests muss an aufgerufene Use Cases und Infrastrukturports weitergereicht werden.

## Auth, Security und Observability

[MUST] Authentifizierung, Autorisierung und CORS müssen explizit konfiguriert werden.

[MUST_NOT] Unsichere Defaults dürfen nicht verwendet werden.

[MUST_IF] Correlation IDs, strukturierte Logs und Health Checks müssen vorhanden sein, wenn die Web API produktionsnah betrieben wird.

## OpenAPI und API-Versionierung

[MUST] Öffentliche oder teamübergreifend genutzte APIs müssen Routen, Statuscodes sowie Request- und Response-Verträge über OpenAPI dokumentieren.

[MUST_NOT] Breaking Changes dürfen nicht stillschweigend eingeführt werden.

[MUST] Breaking Changes müssen eine API-Versionierung oder dokumentierte Migration erhalten.

[MUST_IF] Beispiele, Fehlerantworten und Auth-Anforderungen müssen dokumentiert sein, wenn Clients sie für die Integration benötigen.

## Tests

[MUST] WebApi-Tests müssen Routing, Statuscodes, Authentifizierung, Validierung, Fehlerantworten, HTTP-Verträge und DI-Verkabelung deterministisch prüfen.

[MUST_IF] Tests geänderter oder neuer WebApi-Fehlerpfade müssen nachweisen, dass Ausfälle notwendiger Abhängigkeiten nicht als erfolgreiche `2xx`-Antwort erscheinen.
