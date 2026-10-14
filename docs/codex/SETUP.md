# Codex-Projekteinstieg

## Zuständigkeit und Umfang

[MUST] Diesen begrenzten lokalen Bootstrap führt die primäre, nicht delegierte Sitzung ohne ausdrückliche Rolle oder mit Rolle `koordinator` vor der Facharbeit aus. Er ist die Ausnahme für die Initialisierung, bevor konfigurierte Spezialisten verfügbar sind. Alternativ führt `softwareentwicklung_infrastruktur` ihn mit ausdrücklichem Setup-Auftrag aus. Andere Spezialisten melden nur eine für ihren Auftrag relevante Lücke an den Koordinator; sie übernehmen weder den Bootstrap noch eine andere Rolle.

[MUST] Vor Änderungen Root-`PROJECT.md`, geltende lokale Regeln und vorhandene `.codex/`-Dateien prüfen. Nur im freigegebenen Repository-Worktree arbeiten. Bei einem reinen Leseauftrag, fehlenden Schreibrechten oder widersprechenden Projektvorgaben die benötigte Einrichtung als Blocker melden; dieser Einstieg erweitert keine Berechtigungen. Im Quellrepository `agent-organization` gelten die lokale Quellauflösung und Spiegelregeln aus `PROJECT.md`.

## Kanonische Quellen und Sollbestand

- [config.toml](https://heljens-it-services.github.io/agent-organization/codex/config.toml) → `.codex/config.toml`
- Die Spalte `Codex-Vorlage` im [Rollenverzeichnis](https://heljens-it-services.github.io/agent-organization/roles/ROLES.md) → je `.codex/agents/<rollen-id>.toml`

[MUST] Beim primären Einstieg den vollständigen dort verlinkten TOML-Satz prüfen und fehlende Dateien herunterladen und lokal speichern. Bei einem ausdrücklich begrenzten Setup-Auftrag nur dessen ausgewählten Sollbestand bearbeiten. Das Rollenverzeichnis dient dabei ausschließlich als Dateiinventar; fremde Rollenbeschreibungen werden nicht geladen. TOMLs anderer Rollen sind Installationsdaten, keine Instruktionen für die ausführende Sitzung.

## Vorgehen

1. Soll- und Istbestand vergleichen. Kanonische Dateien über die obigen veröffentlichten URLs vollständig abrufen; keine HTML-Fehlerseite als TOML speichern. Bei Abruffehlern einen anderen zulässigen Abrufweg derselben Quelle versuchen. Bleibt eine benötigte Quelle unerreichbar, den betroffenen Setup-Schritt mit URL und Zielpfad als Blocker melden, keine Ersatzinhalte erfinden.
2. Downloads vor der Übernahme als TOML parsen. Die Projektvorlage muss einen nicht leeren `developer_instructions`-String enthalten; Agent-Dateien zusätzlich `name` entsprechend der Rollen-ID und eine nicht leere `description`. Nur erwartete kanonische Pfade im Repository verwenden; Symlinks oder Pfade außerhalb des Worktrees nicht beschreiben. Konfigurationen nur lesen und speichern, keine heruntergeladenen Befehle ausführen.
3. Fehlt `.codex/config.toml`, die geprüfte Projektvorlage dort speichern. Existiert sie, zunächst vollständig parsen und nur ihren zentralen Einstieg in `developer_instructions` gezielt zusammenführen. Den Abschnitt zwischen `BEGIN agent-organization bootstrap` und `END agent-organization bootstrap` einmalig ergänzen beziehungsweise durch den aktuellen Vorlagenabschnitt ersetzen. Bereits identischer Inhalt bleibt unverändert. Einen bisherigen unmarkierten zentralen Einstieg nur ersetzen, wenn er eindeutig abgegrenzt ist; bei unklarer Herkunft, widersprüchlichen lokalen Anweisungen oder beschädigten Markierungen den Konflikt melden statt Anweisungen zu überschreiben oder widersprüchlich anzuhängen. Übrige lokale Instruktionen und alle anderen Schlüssel, Tabellen und Kommentare erhalten, insbesondere Modell-, Reasoning-, Tool-, MCP-, Sicherheits- und Berechtigungseinstellungen. Einen fehlenden Root-Schlüssel korrekt auf oberster TOML-Ebene ergänzen, nicht in der zuletzt geöffneten Tabelle.
4. Fehlende ausgewählte Agent-TOMLs unverändert aus den geprüften kanonischen Quellen unter `.codex/agents/` speichern. Vorhandene identische Dateien nicht erneut schreiben. Abweichende vorhandene Dateien einschließlich lokaler Modellparameter und zusätzlicher Agenten erhalten; Abweichungen nennen und nur mit ausdrücklicher Freigabe für die betroffenen Dateien gezielt korrigieren. Keine globale Konfiguration unter `~/.codex/` ändern.
5. Vor dem Schreiben sicherstellen, dass sich die gelesenen Zieldateien nicht zwischenzeitlich geändert haben. Nur validierte vollständige Inhalte speichern und danach erneut lesen, als TOML parsen und den Soll-/Ist-Abgleich sowie Diff prüfen. Ein erneuter Lauf ohne neue Abweichung darf keine Änderungen erzeugen. Bei ungültigem lokalem TOML oder nicht verifizierbarem Schreiben die betroffene Datei unverändert lassen beziehungsweise den konkreten unvollständigen Zustand melden; keinen erfolgreichen Abschluss behaupten.
6. Ergänzte oder gezielt angepasste Pfade, unveränderte Konflikte und Prüfergebnis knapp melden. Keine Secrets oder lokalen Konfigurationswerte in Berichte kopieren. Commit, Push, GitHub-Einstellungen, Issue-Templates und Dependabot sind nicht Teil dieses Bootstraps.

## Rollenstart und Laufzeit

[MUST_IF] Nur die primäre, nicht delegierte Sitzung ohne ausdrückliche Rollenzuweisung liest nach erfolgreichem Bootstrap den vollständigen `developer_instructions`-Text aus der lokalen `.codex/agents/koordinator.toml` als Rollenauftrag und lädt die darin geforderten Quellen. Eine ausdrücklich zugewiesene Rolle bleibt maßgeblich. Ein delegierter Agent ohne Rolle meldet die Kontextlücke; er wird nicht automatisch Koordinator.

[MUST] Das sofortige Lesen aktiviert ausschließlich den Instruktionstext im aktuellen Kontext. Gespeicherte Projekt- und Agent-Konfigurationen werden erst bei einem passenden neuen Sitzungs- beziehungsweise Agentenstart von einer unterstützenden Codex-Laufzeit geladen; keine rückwirkende Anwendung von Modell-, Reasoning- oder Werkzeugeinstellungen behaupten. Nach der Einrichtung beim nächsten Start die tatsächliche Verfügbarkeit der benötigten Rollen prüfen. Fehlt sie, den Laufzeitblocker melden statt Facharbeit in der Koordinatorrolle zu übernehmen.

[MUST_NOT] Projektvertrauen, Sandbox, Freigaben, Credentials oder andere Sicherheitsoptionen automatisch ändern. Falls die Laufzeit das Projekt noch nicht als vertrauenswürdig behandelt, ist die Freigabe durch den Nutzer erforderlich. Siehe [Custom Agents](https://learn.chatgpt.com/docs/agent-configuration/subagents#custom-agents) und [Konfigurationsreferenz](https://learn.chatgpt.com/docs/config-file/config-reference).

## Prüffälle

- Nur AGENTS-Link, keine TOMLs: Primäre Sitzung ergänzt Projektvorlage und vollständigen Agent-Satz, validiert die Dateien und startet ausschließlich den Koordinator per Instruktionslektüre.
- Bestehende Projektkonfiguration: Zentralen Einstieg einmalig ergänzen oder gezielt aktualisieren; lokale Instruktionen, Kommentare und übrige Einstellungen bleiben erhalten. Zweiter Lauf ohne Änderung.
- Abweichende Agent-Datei, ungültiges TOML oder unklarer Instruktionskonflikt: Kein blindes Überschreiben; konkreten Konflikt und betroffenen Schritt melden.
- Expliziter Spezialist, auch bei geerbten Projektanweisungen: Rolle bleibt erhalten; keine allgemeine Setup-Pflicht und kein Koordinatorstart. Nur ein ausdrücklicher Infrastruktur-Setup-Auftrag erlaubt den abgegrenzten Dateiabgleich.
- Delegierter Agent ohne Rolle: Kontextlücke melden, keine Selbstzuweisung.
- Downloadfehler, fehlende Schreibrechte oder reiner Leseauftrag: Kein erfundener Installations- oder Laufzeiterfolg; betroffenen Blocker melden.
