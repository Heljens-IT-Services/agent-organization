# Skill: GitHub Issue Lesen

## Zweck

Ein GitHub-Issue und seine Kommentare atomar lesen und den enthaltenen Kontext strukturiert wiedergeben. Bei explizitem Graph-Lesefokus relevante native Issue-Beziehungen kontrolliert und zyklussicher erfassen.

## Verwenden

- Wenn Inhalt, Kommentare, Status oder Metadaten eines GitHub-Issues gelesen werden sollen.
- Vor Anforderungsklärung, Planung oder Implementierung eines Issues.
- Wenn ein übergeordneter Workflow ausdrücklich den Issue-Graphen, Parent/Children oder blockierende Issues lesen lässt.
- Nicht verwenden, um fehlende Anforderungen zu klären. Dann `requirements-clarification` nutzen.
- Nicht verwenden, um ein Issue in einen technischen Plan zu überführen. Dann `code-implementation-planning` nutzen.

## Vorgehen

1. Issue-Nummer, Repository und Lesefokus bestimmen.
2. Issue-Body, Kommentare und relevante GitHub-Metadaten lesen.
3. Im Default nur Ausgangs-Issue, Kommentare und direkt sichtbare Metadaten lesen.
4. Bei expliziter Anweisung wie "Graph lesen", "Parent/Children lesen" oder "blockierende Issues lesen" den angeforderten Beziehungskontext nach den Regeln des Graph-Lesemodus lesen.
5. Lange Kommentarverläufe zusammenfassen, statt jeden Kommentar einzeln wiederzugeben.
6. Standardmäßig still in den Agenten-Kontext laden.
7. Nur bei explizit verlangtem Output Inhalt strukturiert nach vorhandenen Informationen wiedergeben.
8. Widersprüche, fehlende Informationen, Zyklen oder offene Stellen markieren, ohne sie zu klären.

## Graph-Lesemodus

Wenn ein übergeordneter Workflow ausdrücklich einen Issue-Graphen anfordert:

1. Das Ausgangs-Issue als Startknoten lesen.
2. Direkt angeforderte Relationship-Typen getrennt erfassen, insbesondere Parent, Children und Blocked-by.
3. Child-Beziehungen rekursiv verfolgen, wenn der aufrufende Workflow den Child-Graphen oder vollständigen Issue-Graphen verlangt.
4. Blocked-by-Beziehungen für jeden vom aufrufenden Workflow als relevant bezeichneten oder während der Child-Traversierung erreichten Knoten lesen.
5. Parent-Beziehungen oberhalb des Ausgangs-Issues standardmäßig nur kontextuell nach oben lesen; daraus keine Geschwister oder weiteren Parent-Teilbäume traversieren, sofern dies nicht ausdrücklich verlangt wird.
6. Eine besuchte Menge anhand stabiler Repository-/Issue-Identität führen. Bereits besuchte Knoten nicht erneut expandieren.
7. Erkannte Zyklen als Relationship-Zyklus wiedergeben und die Traversierung an der bereits besuchten Kante fortsetzen, ohne Endlosschleife.
8. Je gelesenen Knoten mindestens Nummer, Titel, Status, URL und die angeforderten Relationship-Kanten erfassen; Body und Kommentare lesen, soweit sie für den angeforderten Kontext relevant sind.
9. Geschlossene Issues und externe Issues nicht ausblenden, sondern mit ihrem tatsächlichen Status beziehungsweise Repository-Kontext wiedergeben.
10. Der Graph-Lesemodus erzeugt ausschließlich Beobachtungsdaten. Scope, Ausführungsreihenfolge, Aufnahme externer Blocker und Container-Semantik werden vom aufrufenden Workflow entschieden.

## Kommandos

```powershell
gh issue view <issue-number> --comments
gh issue view <issue-number> --json title,body,state,labels,assignees,milestone,comments,url
gh issue view <issue-number> --json id,number,title,body,state,comments,url
```

Für explizit angeforderten Beziehungskontext passende `gh api`- oder GraphQL-Leseaufrufe nutzen.

## Grenzen

- Read-only arbeiten.
- Keine GitHub-Änderungen vornehmen.
- Keine Anforderungen erfinden oder stillschweigend erweitern.
- Keine technische Planung, Analyse oder Umsetzung durchführen.
- Ohne explizite Anweisung keine Issue-Beziehungen aktiv verfolgen.
- Auch im Graph-Lesemodus Beziehungen und Status nur wiedergeben, nicht Scope oder Reihenfolge daraus ableiten.
- Externe Blocker nicht automatisch als Umsetzungsscope interpretieren.
- PRs nur lesen, wenn der User oder der aufrufende Workflow sie explizit als Kontext nennt.
- Fehlende GitHub-Authentifizierung, fehlende Repository-Zuordnung oder nicht auffindbare Issues als Blocker melden.

## Output

- Standard: keine eigene Ausgabe, sondern Kontext laden.
- Bei explizit verlangtem Output: Kurzfassung, vorhandene Informationen aus Body und Kommentaren, relevante Metadaten, gelesene Issue-Beziehungen, Status je Knoten sowie sichtbare Zyklen, Widersprüche oder fehlende Informationen.

## Qualitätskriterien

- Ticket nicht stillschweigend erweitern.
- Fehlende Informationen explizit benennen.
- Kommentare berücksichtigen.
- Graph-Traversierung darf nicht durch Zyklen oder mehrfach erreichbare Knoten dupliziert werden.
- Beobachtung und Ableitung trennen.
