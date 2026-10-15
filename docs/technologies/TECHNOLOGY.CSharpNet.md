# TECHNOLOGY.CSharpNet.md

Stand: 2026-08-22

## Zweck

Diese Datei gilt für C#- und .NET-Projekte aller Einstiegstypen. Anwendungs- und hostspezifische Regeldateien werden über [TECHNOLOGIES.md](https://heljens-it-services.github.io/agent-organization/TECHNOLOGIES.md) aufgelöst.

## Sprach- und Coderichtlinien

[MUST] File-scoped namespaces müssen verwendet werden.

[MUST] Alle Namespaces müssen ausschließlich über `GlobalUsings.cs` verwaltet werden.

[SHOULD] Primäre Konstruktoren sollen wann immer möglich bevorzugt verwendet werden.

[MUST] Jeder öffentliche Typ muss in einer eigenen Datei liegen.

[SHOULD] Records sollen für immutable DTOs, Value Objects und Ergebnisobjekte verwendet werden. Abweichungen sind erlaubt, wenn Framework-Binding, Serialisierung oder bestehende API-Verträge Klassen erfordern.

## Datenbankzugriff

[MUST] C#-Anwendungen müssen Entity Framework Core für Datenbank-Anbindungen und datenbankbezogene Implementierungen verwenden.

[ALLOW_IF] Eine projektspezifische Regel darf ausdrücklich eine abweichende Technologie oder Vorgehensweise vorgeben.

## Repository-Pattern und Persistenzgrenze

[MUST] Für datenbankgestützte Persistenz in C#/.NET muss das Repository-Pattern als technische Persistenzgrenze verwendet werden.

[MUST] Repository-Verträge müssen fachlich oder use-case-orientiert nur die tatsächlich benötigten Operationen exponieren und fachliche, anwendungsinterne DTOs, Modelle, Value Objects oder fachlich geeignete primitive Werte verwenden.

[MUST] Repository-Implementierungen müssen das Mapping zwischen EF-Core-Entities und den anwendungsinternen Vertragsmodellen an der technischen Persistenzgrenze durchführen.

[MUST_NOT] Repository-Verträge dürfen EF-Core-Entities oder technische Adapter- beziehungsweise Persistenztypen nach außen exponieren.

[MUST_NOT] Ein generisches `IRepository<TEntity>`-Framework darf nicht pauschal als Standard vorgeschrieben werden.

[MUST] Anwendungscode mit datenbankgestützter Persistenz muss die Factory-Regeln einhalten: Repository-Implementierungen konsumieren `IDbContextFactory<TContext>` und die Composition Root registriert `AddDbContextFactory<TContext>(...)`.

[MUST_NOT] Anwendungscode darf `TContext : DbContext` nicht direkt injizieren. Die durch `AddDbContextFactory` zusätzlich registrierte Scoped-Instanz ist kein erlaubter Konsumweg.

[MUST] Jeder Factory-erzeugte Context muss pro fachlicher Unit of Work erzeugt und deterministisch disposed werden; in Async-Code mit `CreateDbContextAsync(cancellationToken)` und `await using`.

[MUST_NOT] Ein Context darf nicht parallel verwendet oder über Requests, Jobs, Messages oder unabhängige Operationen hinweg gehalten werden. Zusammengehörige Vorgänge dürfen denselben Context innerhalb einer Unit of Work verwenden.

[MUST_IF] Context-Konfiguration von scoped oder tenantabhängigen Daten abhängt, muss die Lifetime von `AddDbContextFactory` bewusst passend gewählt werden.

## Module.cs und DI

[MUST] Produktive .NET-Projekte mit eigener DI-Registrierung müssen eine `Module.cs` als zentralen Einstiegspunkt für diese Registrierungen verwenden.

[MUST] Wiederverwendbare Schichten oder Projekte mit eigener Registrierungsverantwortung müssen ihre DI-Registrierung über klar benannte Erweiterungsmethoden kapseln.

[MUST] Der Methodenname einer DI-Erweiterungsmethode muss zur Projektrolle passen, zum Beispiel `AddCore(...)`, `AddInfrastructure(...)`, `AddConsole(...)`, `AddWebApi(...)` oder `AddWorker(...)`.

[ALLOW] `Program.cs` oder ein anderer Composition Root darf Module wegen transitiver Referenzierung explizit registrieren.

[MUST] Direkte Projektreferenzen müssen die vorgesehenen Architekturgrenzen respektieren und dürfen nicht allein für bequeme DI-Registrierung aufgeweicht werden.
