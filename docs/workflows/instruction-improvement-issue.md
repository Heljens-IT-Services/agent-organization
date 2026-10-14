# Workflow: Instruction Improvement Issue

## Owner und Modus

`koordinator` liest diesen Ablauf als Delegationsplan. Inhalt, Scope und Issue-Struktur delegiert er für fachliche User-Issues an `product_owner` und für technische Issues einschließlich Technical Tasks an `softwareentwicklung_architektur`; die Prüfung betroffener Fachregeln an deren jeweilige Owner-Rolle. Issue-Inhalts-, Type- und Relationship-Mutationen führt die für diesen Scope beauftragte Owner-Rolle aus.

## Ziel

Schwachstellen und Verbesserungsvorschläge an Agent-Files, Leitplanken, Skills oder Workflows als GitHub-Issue in diesem Repository erfassen.

## Verwenden

- Wenn während der Nutzung der zentralen `agent-organization` ein Verbesserungsvorschlag entsteht.
- Wenn ein Agent eine Schwachstelle, Lücke, unklare Regel, widersprüchliche Leitplanke oder kontraproduktiven Workflow erkennt.
- Wenn der Vorschlag aus einem konsumierenden Repository kommt, das diese Instruktionen referenziert.
- Nicht verwenden für projektspezifische Agent- oder Developer-Instruktionen anderer Repositories.
- Nicht verwenden, wenn direkt an den Instruktionsdateien gearbeitet werden soll. Dann passenden Skill oder Workflow im `agent-organization`-Repository verwenden.

## Verwendete Skills

- `requirements-clarification`
- `issue-creation`
- `type-setting`
- `relationship-setting`

## Ablauf

1. Verbesserungsvorschlag oder Schwachstelle, betroffene Instruktion und Ursprungskontext erfassen.
2. Aktuelle Regelbefolgung und zukünftige Regelverbesserung trennen: Die geltende Leitplanke bleibt für den aktuellen Task bindend, solange keine höherrangige Vorgabe entgegensteht.
3. Reflexionskriterium bestimmen: unsinnig, kontraproduktiv, widersprüchlich, zielverfehlend oder nicht ausreichend operationalisierbar.
4. Bei unscharfem Vorschlag mit `requirements-clarification` interaktiv nachfragen, bis Ziel, Scope, betroffene Instruktion und gewünschter Zielzustand ausreichend klar sind.
5. Ziel-Repository explizit auf `Heljens-IT-Services/agent-organization` setzen.
6. Im Issue das konsumierende Repository, die betroffene referenzierte Datei oder URL und den konkreten Nutzungskontext verlinken oder beschreiben, wenn bekannt.
7. GitHub-Issue-Type passend zum Kontext bestimmen: `Task`, `Story`, `Spike` oder `Epic`.
8. Relationships bestimmen, wenn aus dem Kontext ein Parent, Child oder Blocker hervorgeht.
9. Mit `issue-creation` eigenständig ein strukturiertes Issue in `Heljens-IT-Services/agent-organization` erstellen.
10. Mit `type-setting` den nativen GitHub-Issue-Type setzen.
11. Mit `relationship-setting` native Relationships setzen, wenn sie aus dem Kontext hervorgehen.

## Reflexionskriterien

Ein Issue ist sinnvoll, wenn eine Leitplanke oder ein Workflow mindestens eines davon zeigt:

- kein klarer Zweck für Sicherheit, Qualität, Wartbarkeit, Governance oder Nutzerziel
- schlechtere Ergebnisse, höheres Risiko, unnötige Reibung oder schlechtere Nachvollziehbarkeit
- Widerspruch zu gleich- oder höherpriorisierten Regeln
- Ziel wird nicht erreicht oder wichtige Fälle bleiben offen
- Begriffe, Ausnahmen, Prioritäten oder Abschlussbedingungen sind nicht operationalisierbar

## Vorschlagsformat

Ein Instruction-Improvement-Issue soll mindestens enthalten:

- betroffene Datei, Regel, Skill oder Workflow
- Ursprungskontext und beobachtetes Problem
- Art des Befunds: Verbesserungsvorschlag, Schwachstelle, Widerspruch, Lücke, Risiko oder unklare Operationalisierung
- aktuelles Verhalten oder aktuelle Regelwirkung
- erwarteter Zielzustand
- vorgeschlagene Änderungsrichtung
- Risiken, Nicht-Ziele und offene Fragen
- Hinweis, dass die geltende Regel im aktuellen Task weiterhin befolgt wurde oder warum eine höherrangige Vorgabe abweichendes Verhalten erzwungen hat

## Rücksprungregeln

- Bei unklarem Verbesserungsvorschlag zurück zu `requirements-clarification`.
- Wenn Ziel, Scope, betroffene Instruktion oder Zielzustand nicht klärbar sind, Workflow blockieren.
- Bei fehlenden GitHub-Rechten oder unklarer Repository-Zuordnung stoppen und Blocker melden.
- Bei möglichem Duplikat den Duplikatregeln aus `issue-creation` folgen.
- Bei unklarem GitHub-Issue-Type oder unklarer Relationship-Richtung zurück zu `requirements-clarification`.

## Endergebnis

- GitHub-Issue im Repository `Heljens-IT-Services/agent-organization`
- Issue-Link
- gesetzter GitHub-Issue-Type
- gesetzte Relationships, falls vorhanden
- dokumentierter Reflexionsgrund, Vorschlagsformat und Review-Bedarf

## Grenzen

- Das Issue ausschließlich in `Heljens-IT-Services/agent-organization` erstellen.
- Keine Änderungen an Instruktionsdateien vornehmen.
- Keine Umsetzung planen, wenn nur ein Verbesserungsvorschlag erfasst werden soll.
- Keine geltende Leitplanke im aktuellen Task umgehen, nur weil ein Verbesserungsvorschlag erstellt wird.
- Keine Verbesserungsvorschläge erzeugen, die nur die eigene Bequemlichkeit optimieren und Sicherheit, Qualität, Nachvollziehbarkeit oder Nutzerziel verschlechtern.
- Kein Spam: ähnliche Beobachtungen bündeln oder vorhandene offene Issues weiterverwenden, wenn sie denselben Verbesserungsbedarf abdecken.
- Fehlendes konsumierendes Repository, fehlende Referenzdatei oder fehlender Nutzungskontext blockiert die Issue-Erstellung nicht.
