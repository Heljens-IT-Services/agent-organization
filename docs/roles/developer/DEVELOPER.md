# DEVELOPER.md

Stand: 2026-10-13

## Zweck

Diese Datei definiert technologieübergreifende Developer-Regeln. Technologiespezifische Regeln werden über die direkten Freigaben der eigenen Rollenbeschreibung geladen.

## Verwendung als gemeinsame Fachbasis

Diese Datei enthält technische Grundregeln. Zuständigkeit, Pflichtlektüre und direkte Quellenfreigaben stehen in der eigenen Rollenbeschreibung; zusätzliche Aufträge werden über den Koordinator geklärt.

## Priorität innerhalb der technischen Fachbasis

[PRIORITY] Bei widersprüchlichen Regeldateien innerhalb dieser Fachbasis gilt innerhalb ihres jeweiligen Scopes diese Reihenfolge:

1. Passende technologiespezifische Regeldatei aus der Freigabe der eigenen Rollenbeschreibung.
2. [DEVELOPER.md](https://heljens-it-services.github.io/agent-organization/roles/developer/DEVELOPER.md).

[PRIORITY] Bei mehreren passenden `DEVELOPER.*.md`-Dateien hat die spezifischere Regel nur innerhalb ihres ausdrücklich beschriebenen Scopes Vorrang vor einer allgemeineren Regel.

## Architekturprinzipien

[MUST] Fachlogik muss von technischen Randthemen getrennt werden.

[MUST] Fachliche Regeln, Use Cases, Workflows, fachliche Fehler und fachliche Modelle müssen in der fachlichen Mitte des Systems liegen.

[MUST] Technische Details wie UI, HTTP, CLI, Persistenz, Dateisystem, externe APIs, Worker, Frameworks, Logging, Konfiguration und Dependency Injection müssen an den Systemrändern bleiben.

[MUST_NOT] Technische Einstiegspunkte wie Controllers, Endpoints, `Program.cs`, Worker-Handler oder CLI-Kommandos dürfen keine Fachlogik enthalten.

[MUST] Einstiegspunkte müssen Eingaben validieren, Use Cases oder Services aufrufen und Ergebnisse in die passende Ausgabeform mappen.

[MUST] Abhängigkeiten müssen nach innen zeigen: fachliche Schichten definieren Ports und Verträge, technische Schichten implementieren diese Ports.

[MUST_NOT] Externe DTOs, API-Contracts, Formularmodelle, Dateiformate und Persistenzmodelle dürfen nicht ungeprüft als interne Fachmodelle verwendet werden.

## Struktur und Verantwortlichkeiten

[SHOULD] Projektstrukturen sollen fachliche und technische Verantwortlichkeiten sichtbar machen. Abweichungen sind erlaubt, wenn ein bestehendes Projekt eine andere stabile Struktur vorgibt und die konkrete Änderung keine Strukturmigration ist.

[MUST] Wiederverwendbare, fachlich neutrale Bausteine müssen getrennt von fachlich spezifischen Features oder Use Cases liegen.

[MUST] Infrastrukturcode muss gekapselt werden.

[MUST_NOT] Views, Endpoints, CLI-Kommandos und fachliche Logik dürfen Infrastrukturcode nicht direkt ansprechen.

[MUST] Mapping an Systemgrenzen muss explizit sein und externe Verträge, technische Transportmodelle und interne Modelle entkoppeln. Dazu müssen Mapper externe DTOs aus APIs, Dateien, Datenbanken und UI-Formularen von internen Modellen trennen.

[MUST] Konfiguration muss an der technischen Grenze geladen, typisiert gebunden und validiert werden.

[MUST_NOT] Fachliche Logik darf globale Konfiguration nicht direkt lesen.

[MUST] Fehlende Pflichtkonfiguration muss früh mit klarer Fehlermeldung scheitern.

[MUST] Öffentliche oder teamübergreifend genutzte Schnittstellen müssen stabile Contracts und dokumentierte Fehlerformen erhalten.

## Datenmodellierung

[MUST] Die technische `Id`-Spalte jeder Datenbanktabelle muss als Integer-Typ definiert werden. Abweichende Typen sind nicht zulässig.

[MUST_NOT] Technische `Id`-Spalten dürfen nicht in Benutzeroberflächen, APIs oder anderen anwenderseitig sichtbaren Schnittstellen als fachliche Referenz verwendet oder angezeigt werden.

[MUST] Für externe oder anwenderseitige Identifikation muss eine Business-Id verwendet werden. Fehlt sie, muss eine andere fachlich geeignete Spalte oder Spaltenkombination verwendet werden; die technische `Id`-Spalte ist dafür ausgeschlossen.

## Clean Code

[MUST] Namen müssen fachlich, präzise und konsistent sein.

[MUST] Bezeichner, Variablen, Dateien, Klassen, Funktionen, Methoden, Parameter, Attribute, Konstanten, Module, Datenbanken, Tabellen, Spalten, Indizes, Views, Trigger, Stored Procedures, Datenbankfunktionen, Skripte sowie Namen und technische Schlüssel von Konfigurations- und Ressourcendateien müssen in Produktiv- und Testcode englisch sein.

[MUST_IF] Extern vorgegebene Namen müssen unverändert bleiben, wenn Verträge, Frameworks, Protokolle oder Fremdsysteme dies erfordern.

[MUST_NOT_IF] Die Sprachregel darf lokalisierte nutzersichtbare Werte nicht auf Englisch festlegen und bestehende öffentliche Verträge oder persistierte Schemata nicht ohne erforderliche Migration umbenennen.

[SHOULD] Namen sollen die fachliche Bedeutung, Verantwortung oder ausgeführte Operation präzise benennen. Extern vorgegebene Namen bleiben gemäß der obigen Vertragsregel unverändert.

[MUST] Eine Funktion oder Methode muss eine klar erkennbare Aufgabe auf einer Abstraktionsebene erfüllen.

[SHOULD] Funktionen und Methoden sollen in der Regel nicht mehr als ca. 15 Zeilen fachlich relevanten Code enthalten; bei Überschreitung soll eine Trennung von Verantwortlichkeiten oder Extraktion von Hilfsmethoden geprüft werden.

### Kontrollfluss und Verschachtelung

[MUST] Guard Clauses und frühe Ausstiege müssen bevorzugt werden, um Kontrollfluss flach zu halten.

[MUST] Der Happy Path muss möglichst linear und ohne unnötige Verschachtelung lesbar sein.

[MUST_NOT] Kontrollfluss darf nicht tiefer als zwei Ebenen verschachtelt werden, sofern die Verschachtelung nicht unmittelbar eine echte fachliche oder strukturelle Hierarchie abbildet.

[MUST] Eigenständig benennbare verschachtelte Logik muss in eine eigene Funktion, Methode oder Komponente extrahiert werden.

[MUST_NOT] Komplexe boolesche Bedingungen dürfen nicht inline im Kontrollfluss verbleiben; sie müssen durch aussagekräftige Variablen, Methoden oder Prädikate benannt werden.

[MUST] Klassen, Komponenten und Services müssen hohe Kohäsion und niedrige Kopplung haben.

[MUST] Öffentliche Typen, zentrale Einstiegspunkte, Klassen, Komponenten und Services müssen eine klar benennbare und begrenzte Hauptverantwortung haben.

[MUST_NOT] Klassen, Komponenten und Services dürfen nicht allein zur Einhaltung numerischer Größenrichtwerte so aufgeteilt werden, dass fachliche Zusammenhänge, Lesefluss oder Wartbarkeit schlechter werden.

[SHOULD] Dead Code, ungenutzte Feature-Flags, veraltete TODOs und auskommentierter Code sollen gelöscht werden, wenn sie im Scope der Aufgabe liegen.

[MUST_IF] Dead Code, ungenutzte Feature-Flags, veraltete TODOs und auskommentierter Code müssen im Arbeitsabschluss gemeldet werden, wenn sie auffallen und nicht im Scope der Aufgabe gelöscht werden.

## Dokumentation

[MUST_IF] Allgemeine Einstiegspunkte, komplexe Strukturen, Infrastruktur-Objekte, öffentliche Verträge und fachliche Regeln müssen im Quellcode dokumentiert werden, wenn ihr für Wartung, Nutzung oder Review notwendiger Zweck nicht aus Code und Namen hervorgeht.

[MUST] Kommentare müssen Domänenwissen, fachspezifisches Know-how, Absicht, Trade-offs oder nicht offensichtliche Constraints erklären.

[MUST_NOT] Kommentare dürfen den Code nicht lediglich wiederholen.

[ALLOW] README-Dateien, Architektur-Notizen, API-Beschreibungen, Beispielaufrufe oder externe Dokumentation dürfen Quellcode-Kommentare ergänzen.

[MUST_NOT_IF] Externe Dokumentation darf notwendiges Verständnis nicht ersetzen, wenn dieses Verständnis direkt am Code gebraucht wird.

## Design Patterns und Prinzipien

[ALLOW_IF] Design-Patterns und Code-Patterns dürfen eingesetzt werden, wenn sie Abhängigkeiten verringern, Redundanz vermeiden, Wartbarkeit verbessern, Skalierbarkeit ermöglichen, Fehleranfälligkeit verringern oder Testbarkeit verbessern.

[ALLOW_IF] Vererbung darf genutzt werden, wenn echte Substituierbarkeit vorliegt.

[SHOULD] Facades, Application Services, Use Cases oder Component Services sollen Abläufe koordinieren, wenn Views, Endpoints oder CLI-Einstiege sonst Wissen über Datenzugriff, Validierung, Status oder technische Abläufe enthalten würden.

## UI- und Präsentationsregeln

[MUST] UI-Code muss Nutzerintentionen, sichtbare Zustände und fachliche Abläufe klar trennen.

[MUST] Views, Pages und Components dürfen keine Fachlogik, Datenzugriffslogik, Persistenzlogik oder technische Orchestrierung enthalten.

[MUST_IF] Sichtbare Zustände wie `loading`, `empty`, `error`, `disabled`, `readonly`, `dirty`, `saving` und `success` müssen explizit modelliert werden, wenn sie für den Nutzer relevant sind.

[MUST_NOT] UI-Code darf technische Fehler, interne IDs, Debug-Daten oder Infrastrukturdetails nicht ungefiltert sichtbar machen.

[MUST_NOT] Designsysteme und Komponentenbibliotheken dürfen nicht ohne ausdrückliche User-Anweisung installiert werden.

[MUST] Layout- und Styling-Änderungen müssen bestehende Design-, Abstands-, Typografie- und Komponenten-Konventionen respektieren.

[MUST_NOT] UI-Änderungen dürfen keine unnötigen Wrapper, neuen Styling-Konzepte oder redundanten Komponentenvarianten einführen.

[MUST] Interaktive UI muss semantische Elemente, Tastaturbedienung, Fokusführung, Labels und verständliche Fehlermeldungen berücksichtigen.

## Fehlerbehandlung

[PRIORITY] Fachliche Korrektheit und Fehlertransparenz haben Vorrang vor einem scheinbar erfolgreichen Anwendungslauf.

[SHOULD] Erwartbare fachliche Fehler sollen als explizite Ergebnis-, Status- oder Fehlerobjekte modelliert werden. Abweichungen sind erlaubt, wenn eine vorhandene API, Sprache oder Bibliothek einen anderen fachlich stabilen Fehlervertrag vorgibt.

[MUST] Erwartbare fachliche Fehler müssen Teil des normalen fachlichen Kontrollflusses bleiben.

[ALLOW_IF] Exceptions dürfen verwendet werden, wenn technische Fehler unerwartet sind, Invarianten verletzt wurden oder eine lokale Behandlung nicht sinnvoll ist.

[MUST] Validierungsfehler müssen nahe an der Eingabe erkannt und in eine stabile, fachlich verständliche Fehlerform übersetzt werden.

[MUST] Technische Fehler aus Infrastruktur, Netzwerk, Dateisystem, Persistenz oder externen APIs müssen an der technischen Grenze mit Kontext angereichert werden.

[MUST_IF] Wenn technische Fehler in fachliche oder schnittstellenspezifische Ergebnisse übersetzt werden, muss die Übersetzung die Fehlersemantik bewahren und darf keinen Erfolg vortäuschen.

[MUST_NOT] Ausfälle notwendiger Datenquellen dürfen nicht durch leere Ergebnisse, `null`, Defaultobjekte oder erfundene, hardcodierte, Mock-, Fake-, Sample- bzw. Demo-Daten als Erfolg dargestellt werden.

[ALLOW_IF] Ein Fallback darf verwendet werden, wenn ein expliziter fachlicher Vertrag Ersatzpfad und Semantik definiert, seine Aktivierung beobachtbar ist und Tests Aktivierung, Beobachtbarkeit sowie Grenzen nachweisen.

[MUST_IF] Wenn ein Ablauf ohne erforderliche Daten nicht fachlich korrekt fortgesetzt werden kann, muss der betroffene Ablauf mit einem diagnostizierbaren Fehlerzustand kontrolliert abgebrochen werden.

[MUST] Fehlerantworten an UI, CLI, HTTP-Clients oder andere Konsumenten müssen konsistent, maschinenlesbar und stabil sein.

[MUST] Logs müssen technische Ursachen und Diagnosekontext erklären.

[MUST_NOT] Logs dürfen fachliche Status-, Ergebnis- oder Fehlerobjekte nicht ersetzen.

## Security und Datenschutz

[MUST_NOT] Secrets, Tokens, personenbezogene Daten und interne Infrastrukturdetails dürfen nicht geloggt, hart codiert oder versioniert werden.

[MUST] Authentifizierung, Autorisierung und Mandantentrennung müssen an zentralen Grenzen geprüft werden.

[MUST] Eingaben aus UI, CLI, Dateien, Datenbanken und APIs müssen als unsicher behandelt werden, bis sie validiert wurden.

[MUST_NOT] Ausgaben einschließlich Fehlerantworten dürfen keine unbeabsichtigten internen Details enthalten, insbesondere keine Diagnose-, Infrastruktur- oder Sicherheitsdetails.

[MUST] Abhängigkeiten müssen nach den Kriterien Wartbarkeit, Sicherheit, Lizenz, Kompatibilität und Projektbedarf ausgewählt und aktualisiert werden.

[PRIORITY] Sicherheitsupdates haben Vorrang vor kosmetischen Refactorings.

