# Skill: Anforderungsklärung

## Zweck

Unklare Anforderungen, Ziele, Nicht-Ziele und Scope-Grenzen in eine belastbare Arbeitsgrundlage überführen.

## Verwenden

- Wenn ein Vorhaben fachlich, technisch oder organisatorisch noch unscharf ist.
- Wenn Ziel, Scope, Nicht-Ziele, Akzeptanzkriterien oder Prioritäten geklärt werden müssen.
- Wenn ein Issue, Feature, Bugfix oder Konzept vor Planung oder Umsetzung konkretisiert werden soll.
- Standardmäßig interaktiv verwenden.
- Stillen Modus nur verwenden, wenn der User ihn explizit verlangt oder ein Workflow nur Kontextstrukturierung braucht.
- Nicht verwenden, wenn mehrere Lösungsoptionen kreativ oder strategisch abgewogen werden sollen. Dann `brainstorming` nutzen.
- Nicht verwenden, wenn Code nur gelesen werden soll. Dann `code-reading` nutzen.
- Nicht verwenden, wenn bereits ein umsetzbarer technischer Plan erstellt werden soll. Dann `code-implementation-planning` nutzen.

## Vorgehen

1. Ausgangswunsch, Zielbild und bekannten Kontext knapp zusammenfassen.
2. Scope, Nicht-Ziele, Abhängigkeiten und Randbedingungen trennen.
3. Akzeptanzkriterien oder Erfolgskriterien ableiten.
4. Widersprüche, Lücken und implizite Annahmen markieren.
5. Plausible Annahmen vorschlagen, damit der User sie bestätigen oder ablehnen kann.
6. Wenige gezielte Klärungsfragen an den Koordinator geben; dieser vermittelt notwendige Nutzerentscheidungen.
7. Vom Koordinator übermittelte User-Antworten in eine geschärfte Arbeitsgrundlage überführen.
8. Abschließen, wenn die Anforderungen als belastbare Arbeitsgrundlage geklärt sind.
9. Im stillen Modus keine Rückfragen stellen, sondern vorhandene Anforderungen strukturieren und offene Punkte markieren.

## Grenzen

- Keine Dateien ändern.
- Keine technische Umsetzung planen, bevor Ziel und Scope ausreichend klar sind.
- Keine Anforderungen stillschweigend erweitern.
- Keine Issues, Research-Ergebnisse oder Code-Analysen selbst lesen. Nur vorhandenen Kontext verwenden.
- Wenn Kontext fehlt, vorgelagert `issue-reading`, `research`, `code-reading` oder `code-analysis` nutzen.
- Annahmen dürfen vorgeschlagen, aber nicht stillschweigend als bestätigt behandelt werden.
- Im stillen Modus keine offenen Punkte klären, sondern nur markieren.
- Wenn entscheidende Informationen fehlen und nicht geklärt werden können, mit `BLOCKED` enden.
- `BLOCKED` muss die konkreten fehlenden Entscheidungen oder Informationen nennen.
- Keine nachgelagerte Planung oder Umsetzung empfehlen, solange der Klärungsstatus blockiert ist.

## Artefakt

- Nur erstellen, wenn der User es explizit verlangt.
- Dateiname: `docs/requirements-<scope>.md`.
- Inhalt entspricht dem Output dieses Skills.

## Output

- geschärftes Zielbild
- Scope und Nicht-Ziele
- Akzeptanz- oder Erfolgskriterien
- bekannte Randbedingungen
- offene Fragen
- im stillen Modus: strukturierte Anforderungen ohne Rückfrage
- `BLOCKED` mit konkreten fehlenden Informationen, falls Klärung nicht möglich war

## Qualitätskriterien

- Ziel, Scope und Nicht-Ziele klar trennen.
- Annahmen explizit markieren.
- Fragen müssen klärungsrelevant und auf wenige pro Antwort begrenzt sein.
- Keine Lösung vorwegnehmen, wenn die Anforderung noch unklar ist.
- Knapp und interaktiv arbeiten.

