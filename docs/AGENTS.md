# AGENTS.md

## Zweck

Diese Datei definiert verbindliche Arbeitsregeln für AI-/Code-Agents.

## Rollen

[MUST_IF] Bei unbekannter Rollenzuweisung muss die Sitzung in der Rolle als `Koordinator` arbeiten.

[MUST] Jeder Agent hat genau eine aktive Rolle und arbeitet ausschließlich in dieser Rolle. Andere Rollenbeschreibungen dürfen nicht gelesen oder als eigene Instruktionen übernommen werden.

[MUST_IF] Erkennt ein Agent mehrere eigene aktive Rollen, muss er sofort hart stoppen: keine weiteren Arbeitsschritte oder Toolaufrufe, ausschließlich den Konflikt und die betroffenen Rollen melden. Er darf den Konflikt nicht selbst durch einen Rollenwechsel auflösen.

[ALLOW_IF] Weitere Dateien dürfen gelesen werden, soweit die geltenden Regeln dies erlauben.

[MUST] Jede Agenten-Rollenbeschreibung kennzeichnet den Typ mit `Agententyp: <Agententyp>`.

## Pflichtlektüre

Zu Beginn eines Tasks gelten diese Einstiegsdateien:

| Pfad | Geltung | Zweck |
|---|---|---|
| [AGENTS.md](https://heljens-it-services.github.io/agent-files/AGENTS.md) | Pflicht | Allgemeine Arbeitsregeln |
| [AGENTS.Coordinator.md](https://heljens-it-services.github.io/agent-organization/AGENTS.Coordinator.md) | Pflicht nur für Koordinator-Rolle | Repository-Setup, Rollenverzeichnis und Delegation. |
| [AGENTS.Specialist.md](https://heljens-it-services.github.io/agent-organization/AGENTS.Specialist.md) | Pflicht nur für Spezialisten | Eigene Rollenregeln und Rückmeldung an den Koordinator. |
| [REGELMARKER.md](https://heljens-it-services.github.io/agent-files/REGELMARKER.md) | Pflicht | Regelmarker und deren Anwendung. |
| [PRIORITY.md](https://heljens-it-services.github.io/agent-files/AGENTS.md) | Pflicht | Prioritätslogik zu den Leitplanken. |
| `PROJECT.md` im Repository-Root | Pflicht | Repositoryweite Versionsbasis und Leitplanken. |
| `README.md` | Bei Relevanz | Menschlicher Schnelleinstieg in Projekt, Setup und Kommandos. |

[MUST] Der Agent muss alle als Pflicht gekennzeichneten Einstiegsdateien zu Beginn eines Tasks im aktuellen Kontext vollständig und aktuell genug kennen und befolgen.

[MUST_IF] Wenn der Agent innerhalb einer eigenständigen Teilsolution aktiv wird, muss er vor jeder lesenden oder schreibenden Aktivität, jedem Kommando und jeder Prüfung zusätzlich deren lokale `PROJECT.md` vollständig und aktuell genug kennen und befolgen.

[MUST_IF] Wenn die in der Spalte `Geltung` genannte Bedingung eintritt, muss der Agent die betreffende Einstiegsdatei im aktuellen Kontext vollständig und aktuell genug kennen und befolgen.

[ALLOW_IF] Bereits gelesene verbindliche Regeldateien dürfen wiederverwendet werden, wenn kein Hinweis auf eine zwischenzeitliche Änderung besteht.

[MUST_IF] Der Agent muss eine verbindliche Regeldatei erneut abrufen, wenn die vorhandene Kontextfassung fehlt, unvollständig, offensichtlich veraltet oder nicht eindeutig identifizierbar ist.

[MUST_IF] Wenn der Agent eine Regeldatei einliest oder erneut abruft, muss er dem User unmittelbar kurz den Dokumenttitel mitteilen.

[ALLOW_IF] Mehrere gleichzeitig eingelesene optionale Regeldateien dürfen in einer Rückmeldung zusammengefasst werden, wenn jeder Dokumenttitel genannt wird.

## Sprache

[MUST] Quellcode-Kommentare und Dokumentation müssen standardmäßig auf Deutsch verfasst werden und Umlaute sowie `ß` korrekt verwenden.

[ALLOW_IF] Von dieser Sprache oder Schreibweise darf nur abgewichen werden, wenn ein Format, Protokoll, fremddefinierter Inhalt oder eine technische Einschränkung dies erfordert.

## Arbeiten mit README.md

[SHOULD] `README.md` soll kurz und auf den menschlichen Schnelleinstieg fokussiert bleiben. Abweichungen sind erlaubt, wenn der User ausdrücklich eine ausführlichere README-Dokumentation verlangt.

[SHOULD] `README.md` soll Titel, Kurzbeschreibung, Voraussetzungen, Setup, Start, Build, Tests und eine knappe technische Orientierung enthalten, soweit diese Punkte für das Repository relevant sind.

[ALLOW_IF] Der Agent darf `README.md` nur autonom mitpflegen, wenn ausdrücklich verlangt.

[MUST_NOT_IF] `README.md` darf keine Inhalte duplizieren, die in [AGENTS.md](https://heljens-it-services.github.io/agent-files/AGENTS.md) oder andere veröffentlichte Agent Files gehören.
