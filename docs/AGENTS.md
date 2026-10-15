# AGENTS.md

## Einstieg vor der Rollenpflicht

[MUST_IF] In einer primären, nicht delegierten Codex-Sitzung ohne ausdrückliche Rolle oder mit Rolle `koordinator` führe zuerst den [Codex-Projekteinstieg](https://heljens-it-services.github.io/agent-organization/codex/SETUP.md) aus: fehlende lokale Projekt- und Agent-TOMLs prüfen, herunterladen und speichern; vorhandene Konfiguration gezielt zusammenführen und lokale Einstellungen erhalten. Dieser begrenzte Bootstrap löst die Einrichtung vor der Rollenpflicht und erlaubt keine weitere Facharbeit oder Veröffentlichung.

[MUST_IF] Nur wenn dieser primären Sitzung keine Rolle ausdrücklich zugewiesen ist, starte anschließend `koordinator` durch Lesen der lokalen Koordinator-Instruktionen gemäß Projekteinstieg. Eine ausdrückliche Rolle bleibt maßgeblich. Delegierte Agenten ohne Rolle melden die Kontextlücke; Spezialisten starten weder allgemein den Bootstrap noch den Koordinator. Infrastruktur darf die Einrichtung mit ausdrücklichem Setup-Auftrag ausführen.

## Gemeinsame Regeln

Diese Regeln gelten für alle Agenten. Die zugewiesene Rolle bestimmt Zuständigkeit, Quellenfreigaben und Kommunikation.

[MUST] Erfülle deinen Auftrag nach bestem Wissen und Gewissen. Wähle das Vorgehen selbständig anhand von Ziel, Rolle, Projektkontext und verfügbaren Werkzeugen. Beachte fachliche Regeln, Scope und Berechtigungen; belege das Ergebnis mit angemessener Verifikation.

[MUST] Lade die Rollenbeschreibung deiner zugewiesenen Rolle und die geltenden Root- und lokalen `PROJECT.md`-Dateien. Nutze die direkten, auftragsrelevanten Quellenfreigaben der Rolle. Der Koordinator verwendet zusätzlich das Rollenverzeichnis und die Command-Routing-Regeln; Spezialisten kommunizieren über den Koordinator.

[MUST_IF] Die Rollenzuweisung oder eine erforderliche Rollenquelle fehlt, melde die konkrete Kontextlücke vor der betroffenen Arbeit.

[MUST] Benötigte Regeln müssen im aktuellen Kontext vollständig und identifizierbar sein. Eine bereits gelesene Fassung darf bei unverändertem Stand wiederverwendet werden; fehlende, unvollständige oder veraltete Quellen werden erneut geladen.

[MUST_IF] Ein erforderlicher Abruf scheitert, wird ein anderer verfügbarer, zulässiger Abrufweg versucht. Bleibt die Pflichtquelle unerreichbar, wird der betroffene Auftrag mit konkretem Blocker zurückgegeben.

## Quellen und Navigation

Die Rollenbeschreibungen stehen unter `roles/<rollen-id>/<ROLLEN-ID>.md`. Der [Koordinator](https://heljens-it-services.github.io/agent-organization/roles/koordinator/KOORDINATOR.md) verwendet das [Rollenverzeichnis](https://heljens-it-services.github.io/agent-organization/roles/ROLES.md) und die [Command-Regeln](https://heljens-it-services.github.io/agent-organization/COMMANDS.md) für direkte Zuweisungen. Zuständigkeiten, fachliche Regeln und Quellenfreigaben stehen in der jeweiligen Rollenbeschreibung.

[MUST] Im Quellrepository `agent-organization` gilt zusätzlich `PROJECT.md`: Veröffentlichungslinks werden für die Quelllektüre auf die versionierten Dateien unter `docs/` aufgelöst.

## Projektkontext und Vorrang

[MUST] Lade zu Beginn des Auftrags die `PROJECT.md` im Repository-Root. Bei Arbeit in einer eigenständigen Teilsolution lade zusätzlich deren lokale `PROJECT.md` im Solution-Root, bevor du dort fachliche Dateien liest, Änderungen vornimmst, Kommandos ausführst oder Prüfungen startest. Ermittle den betroffenen Teilsolution-Scope aus dem Auftrag, dem vorhandenen Projektverzeichnis und der Repository-Struktur.

[MUST] Prüfe bei einem Wechsel des Repositorys oder der Teilsolution erneut, welche Root- und lokalen PROJECT-Regeln gelten. Bereits gelesene, vollständige und identifizierbare Fassungen dürfen bei unverändertem Stand wiederverwendet werden; fehlende, unvollständige oder veraltete Fassungen werden nachgeladen. Fehlt eine erforderliche PROJECT-Quelle oder bleibt ihr Scope unklar, melde die konkrete Kontextlücke vor der betroffenen Arbeit.

[PRIORITY] Für projektspezifische fachliche und technische Regeln gilt im jeweiligen Scope: lokale `PROJECT.md` der Teilsolution vor Root-`PROJECT.md` vor allgemeinen Rollenregeln. Nicht widersprochene Root-Regeln bleiben wirksam. Projektdokumente erweitern weder den zugewiesenen Auftrag noch Rollenbefugnisse, Quellenfreigaben oder Berechtigungen; direkte Nutzeranweisungen und höherrangige Sicherheits-, Datenschutz- und Plattformvorgaben bleiben maßgeblich.
