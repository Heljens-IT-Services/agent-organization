# Workflow: Ergebnisbericht und Inhaltsreview

**Version:** 2
**Zweck:** Einen klar abgegrenzten fachlichen Arbeitsbeitrag nachvollziehbar umsetzen oder inhaltlich prüfen und Ergebnis, Belege, Grenzen und offene Punkte berichten.  
**Anwendbarkeit:** WorkItems mit autoritativen Anforderungen, selektiv lesbaren Quellen und überprüfbarem Inhalts- oder Dateidiff. Bei fehlender Spezifikation oder erforderlicher Freigabe diese an den zuständigen Verantwortlichen melden; der Ablauf erteilt keine Freigabe.

## Eingaben

- WorkItem und gegebenenfalls Elternkriterien, in der autoritativen Quelle gelesen.
- Zugewiesener Dateiscope, Branch/Basis sowie Projekt- und Prüfvorgaben.
- Für Review: gelieferter Stand, Änderung/Diff und Referenzen.

## Ablauf

1. Anforderungen und Scope vollständig lesen; Reihenfolge, Abhängigkeiten und Grenzen festhalten.
2. Arbeitsbaum, Branch und Basis lesen. Fremde Änderungen und Worktrees erhalten.
3. Nur passende Bestandsquellen und Referenzen heranziehen. Vorhandene Verträge und Pfade wiederverwenden; Unklarheiten nicht eigenmächtig durch Scopeausweitung lösen.
4. Bei Umsetzung zuerst einen abgegrenzten Teil fertigstellen und Inhalt, Diff und Referenzen zurücklesen. Danach erst abhängige Teile bearbeiten.
5. Bei Inhaltsreview Behauptungen auf ihre konkreten Quellen zurückführen; tatsächliche Befunde, historische Belege und nicht geprüfte Laufzeitannahmen auseinanderhalten.
6. Ergebnis mit genauen Dateipfaden, Kriterienbezug, Quellen und Grenzen berichten. Offene Punkte sichtbar lassen. Keine Abnahme aus Implementierung ableiten.

## Optionale Skillverwendung: Tokenbeleg

Benötigt der Auftrag einen Tokenbeleg, den bestehenden ausführbaren Skill
`task-token-usage` verwenden. Optimierer und Qualitätsprüfung können dieselbe
zentrale ID auch direkt wählen; keine Kopie je Rolle. Der Workflow bleibt eine
Anweisung, die ausführbare Grenze ist der bestehende Runner. Ohne Bedarf oder
bei Ausführungsverbot nicht starten; ohne Messung bleibt Eigenverbrauch `null`.
Diese Nutzungsanweisung ist kein Laufzeitbeleg.

1. Konkrete Berechtigungen und Seiteneffekte gegen den aktuellen Auftrag prüfen:
   Ledgerlesen, Runnerprotokoll und temporäre Requestdateien. Nicht genehmigte
   Seiteneffekte oder verbotene Ausführung abweisen und an den bestehenden
   Ansprechpartner melden. Workflow und Registry erteilen keine Zustimmung;
   autorisierte Erstentwicklung ersetzt keine spätere Seiteneffektfreigabe.
2. Nur `task-token-usage` über `scripts/skills/Find-Skill.ps1` mit `-SkillId`
   auflösen, ebenfalls nur bei zulässiger Ausführung. Auch die Discoveryantwort
   nach Schritt 4 auswerten; nur bei Erfolg die Metadaten aus `result` nutzen
   und zum Aufruf übergehen, bei Fehler das strukturierte `exception` melden.
   Voraussetzungen und
   `scriptPath` lesen: `skills/adapters/Get-TaskTokenUsageSkill.ps1` ruft die
   bestehende Ledgerlogik auf. Markdown allein ist kein ausführbarer Skill.
3. Bei zulässiger Ausführung `scripts/skills/Invoke-Skill.ps1` mit `-SkillId`
   `task-token-usage` aufrufen. `-ParametersJson` enthält die registrierten
   Fachparameter `task_id` und `accounting_directory`. Aktuelle Referenzen über
   `-WorkItemRef` und `-ExecutionRef` mitgeben. Freigegebenen absoluten
   `-CoreInterpreterPath`, `-AccountingRoots` und gegebenenfalls `-LogPath`/
   `-InterpreterBindings` aus konkreter Betreiberkonfiguration übernehmen;
   keine Zustimmung oder Pfade erfinden. PowerShell bleibt Skilldefault;
   explizite andere Interpreterbindungen bleiben unverändert verfügbar.
4. Das vollständige einzelne JSON-Antwortobjekt unverändert entgegennehmen und
   als Ergebnisreferenz erhalten. Die case-sensitiven Pflichtfelder
   `isSuccessful`, `exception`, `result` strukturiert auswerten; kein
   Freitext-Parsing, keine Reduktion oder Neuformatierung der Nutzlast.
   Bei `isSuccessful: true` und `exception: null` das fachliche `result` für den
   Tokenbeleg verwenden; unbekannte Messungen bleiben `null`, inklusive
   Kindersummen nicht zusätzlich addieren. Bei `isSuccessful: false` das
   strukturierte `exception` mit `message` und vorhandenen Zusatzfeldern wie
   `code`/Ausführungsbezug berichten; `result` auch im Fehlerfall unverändert
   erhalten und nicht als erfolgreichen Messwert verwenden. Fachfehler und
   Runner-/Parser-/Interpreter-/Timeoutfehler bleiben strukturierte Fehler.
   Keinen Erfolg aus stderr, Exitcode oder Freitext ableiten. Fehlt die
   Vertragsantwort oder widersprechen sich Status und `exception`, keinen
   erfolgreichen Beleg ableiten und den Anschlussfehler melden.

## Ergebnisform

Knappes Ergebnis; Scope und geänderte Dateien; Belege aus Inhalt/Diff/Quellen;
Grenzen und offene Punkte. Verweise relativ zum Repository oder direkt zur
autoritativen Issue-/Dokumentquelle setzen.

## Qualitätskriterien

- Anforderungen und Scope stammen aus autoritativen Quellen.
- Änderungen bleiben im zugewiesenen Scope; bestehende Fremdarbeit bleibt erhalten.
- Quellen stützen die jeweilige Aussage und sind für die nächste Rolle auffindbar.
- Umsetzung, Quellintegration, Prüfung und Abnahme werden nicht gleichgesetzt.
- Nicht ausgeführte Prüfungen werden nicht als bestanden dargestellt.

## Quelle und Stand

Abgeleitet aus `docs/contracts/WORKITEMS.md` (Ergebnisbelege und getrennte
Abnahme), `docs/decisions/0001-system-scope.md` (Wissens-/Workfloworte) und
Issue #47; erstellt am 12.10.2026 im Wissens-WorkItem #47. Version 2 ergänzt
den optionalen Skillanschluss aus #64 (AR-E56-W64-20261013, 13.10.2026).
