# Skill: Research

## Zweck

Frei recherchieren, um externen, repo-übergreifenden oder issue-bezogenen Kontext belastbar zusammenzufassen.

## Verwenden

- Wenn aktuelle, externe oder nicht lokal vorhandene Informationen gebraucht werden.
- Wenn Web, Online-Dokumentation, Anbieterinformationen, Standards, Releases, Preise, Marktinformationen, andere GitHub-Repositories, Issues oder PRs relevant sind.
- Wenn vorhandener lokaler Kontext durch externe Quellen ergänzt oder verifiziert werden soll.
- Nicht verwenden, wenn nur lokaler Code gelesen werden soll. Dann `code-reading` nutzen.
- Nicht verwenden, wenn Optionen interaktiv entwickelt werden sollen. Dann `brainstorming` nutzen.
- Nicht verwenden, wenn Code oder Laufzeitverhalten bewertet werden soll. Dann `code-analysis` nutzen.

## Vorgehen

1. Recherchefrage und benötigten Aktualitätsgrad klären.
2. Relevante Quellentypen bestimmen: offizielle Dokumentation, Spezifikationen, Release Notes, GitHub-Repositories, Issues, PRs, Blogposts oder Marktquellen.
3. Primärquellen bevorzugen, besonders bei technischen, rechtlichen, finanziellen oder sicherheitsrelevanten Themen.
4. Quellen lesen, vergleichen und Widersprüche mit beteiligten Quellen markieren.
5. Ergebnisse knapp nach Fakten, Einordnung und Unsicherheiten strukturieren.
6. Quellen standardmäßig in der Antwort nennen.

## Kommandos

```powershell
gh repo view <owner>/<repo>
gh issue view <issue-number> --repo <owner>/<repo> --comments
gh pr view <pr-nummer> --repo <owner>/<repo> --comments
gh search issues "<suchbegriff>" --repo <owner>/<repo>
```

Websuche oder Browser-Werkzeuge verwenden, wenn Online-Quellen benötigt werden.

## Grenzen

- Keine Dateien ändern.
- Keine unsicheren Informationen als Fakt darstellen.
- Keine veralteten Informationen verwenden, wenn Aktualität für die Frage relevant ist.
- Bei aktuellen oder zeitkritischen Themen Online-Recherche durchführen.
- Keine umfangreiche Marktrecherche starten, wenn eine gezielte Quellenprüfung reicht.
- Bei widersprüchlichen Quellen keine eigene Rangentscheidung erzwingen.

## Artefakt

- Nur erstellen, wenn der User es explizit verlangt.
- Dateiname: `docs/research-<scope>.md`.
- Inhalt entspricht dem Output dieses Skills.

## Output

- Kurzantwort oder strukturierte Zusammenfassung
- relevante Fakten
- Quellen mit Links oder konkreten Referenzen
- Widersprüche oder Unsicherheiten
- offene Punkte, falls die Quellenlage nicht reicht

## Qualitätskriterien

- Primärquellen vor Sekundärquellen.
- Aktualität explizit beachten.
- Fakten, Interpretation und Annahmen trennen.
- Keine Quellen aufblasen; nur relevante Quellen nennen.
- Widersprüche klar benennen und den jeweiligen Quellen zuordnen.
- Bei technischen Fragen offizielle Dokumentation oder Repository-Quellen bevorzugen.
