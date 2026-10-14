# Skill: Code Lesen

## Zweck

Bestehenden Code gezielt lesen, damit relevante Dateien, Symbole und Abläufe im Agenten-Kontext sind.

## Verwenden

- Wenn Orientierung in einem unbekannten Codebereich gebraucht wird.
- Wenn Code als Grundlage für weitere Arbeit in den Kontext geladen werden soll.
- Wenn der User knapp wissen will, welche Dateien, Einstiegspunkte oder Abläufe relevant sind.
- Nicht verwenden, wenn Ursachen, Risiken, Qualität oder Lösungen bewertet werden sollen. Dann `code-analysis` nutzen.

## Vorgehen

1. Relevante Dateien und Einstiegspunkte finden.
2. Angrenzenden lokalen Kontext lesen, wenn er das Verständnis verbessert: README, Docs, Konfiguration, Tests, Git-Diff oder Git-Historie.
3. Verwandte Tests mitlesen, wenn sie Nutzung, erwartetes Verhalten oder Schnittstellen sichtbar machen.
4. Code, Symbole, Kontrollfluss, Datenfluss und Abhängigkeiten lesen.
5. Bei Backend-Code Verantwortlichkeiten, Schnittstellen, Seiteneffekte und Datenfluss erfassen.
6. Bei HTML/CSS DOM-Struktur, Semantik, Selektoren, Layout-Verantwortung und Verschachtelung erfassen.
7. Bei Bedarf reine Lese- und Suchkommandos verwenden, z. B. `rg`, `Get-Content`, `git diff`, `git log` oder `git show`.

## Grenzen

- Kein Artefakt erstellen.
- Keine Codeänderungen vornehmen.
- Keine Bewertung, Ursachenanalyse oder Lösungsempfehlung ausgeben.
- Keine externe Recherche verwenden.
- Keinen GitHub-Issue- oder PR-Kontext lesen.
- Keine Docker-Logs, laufenden App-Logs oder Datenbankinhalte lesen.
- Keine Tests, Builds oder Anwendungen starten.
- Bei unklarem Scope selbstständig naheliegende Einstiegspunkte suchen.
- Bei Folgearbeit den gelesenen Kontext still nutzen, statt ihn ausführlich zu dokumentieren.

## Output

- Keine eigene Ausgabe, wenn der Skill nur Kontext für Folgearbeit lädt; direkt mit dem nächsten angefragten Schritt weitermachen.
- Oder eine knappe Chat-Antwort mit:
  - gelesenen Dateien/Symbolen, wenn sie für die Folgearbeit hilfreich sind
  - relevantem Ablauf
  - Annahmen zum Scope, falls der Auftrag unklar war
  - offenen Kontextlücken

## Qualitätskriterien

- Nur den relevanten Scope erklären.
- Beobachtung und Vermutung trennen.
- Konkrete Dateipfade oder Symbole nur nennen, wenn sie hilfreich sind.
- Kurz bleiben und keine Analyse simulieren.
- Keine langen Erklärungen ausgeben, wenn nur Kontextaufnahme gebraucht wird.
- Keine Lösungen vorschlagen.
- Keine Bewertung einschmuggeln.
- Keine irrelevanten Dateien breit lesen.
- Nicht behaupten, Code verstanden zu haben, ohne relevante Dateien tatsächlich gelesen zu haben.
