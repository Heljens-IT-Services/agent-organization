# Skill: Code Diff Review

## Zweck

Einen Änderungssatz auf Scope, Korrektheit und Risiken prüfen.

Der Review bewertet wesentliche semantische Änderungseinheiten zusätzlich auf ihre aktuelle Notwendigkeit. Nicht belastbar begründete Einheiten werden als `UNPROVEN` eingestuft und blockieren die Versandbereitschaft.

## Verwenden

- Vor Commit oder Pull Request.
- Nach riskanten oder größeren Änderungen.
- Wenn unbeabsichtigte Neben- oder Formatierungsänderungen möglich sind.

## Vorgehen

1. Diff gegen Ziel sowie vorhandenen technischen Plan, Scope, Nicht-Scope und Akzeptanzkriterien abgleichen.
2. Arbeitsstatus und Diff lesen, z. B. `git status --short --branch`, `git diff --stat`, `git diff`, `git diff --cached --stat`, `git diff --cached` oder `git diff -- <pfad>`.
3. Staged und unstaged Änderungen getrennt betrachten, wenn beides vorhanden ist.
4. Unerwartete Dateien, Hunks, Formatierungs-, Whitespace-, Line-ending-, Encoding-Änderungen und Nebeneffekte suchen.
5. Jedes vorhandene Akzeptanzkriterium und jeden vorgesehenen Verifikationsschritt gegen den realen Änderungs- und Teststatus prüfen.
6. Regressionen, fehlende Prüfungen, Scope-Abweichungen und riskante Annahmen markieren.
7. Den Diff in semantische Änderungseinheiten gruppieren, zum Beispiel Adapter plus Registrierung, Config plus Consumer, Fallback, Interface plus Implementierung, Dependency plus Nutzung, Parallelpfad oder nicht triviale Dokumentation.
8. Für jede wesentliche Einheit die aktuelle Existenzbegründung klassifizieren:
   - `REQUIRED`: direkter Nachweis durch Acceptance, erforderliches Verhalten, Regression, Invariante oder expliziten Task-Constraint.
   - `JUSTIFIED`: konkret benennbarer heutiger technischer oder architektonischer Constraint, etwa Boundary, Migration, Kompatibilität, Security, Performance oder Datenintegrität.
   - `UNPROVEN`: weder `REQUIRED`- noch `JUSTIFIED`-Evidenz ist belastbar erkennbar.
9. Abstraktionen, Dependencies, Config-/API-Erweiterungen, Fallbacks, Parallelpfade und nicht triviale Dokumentationsänderungen ausdrücklich prüfen. Ein grüner Teststatus allein ist kein Notwendigkeitsnachweis.
10. Mindestens einmal die Gegenfrage stellen: „Welche semantische Änderungseinheit könnte aus diesem Diff entfernt werden, ohne den heutigen Vertrag zu verschlechtern?“
11. Versandbereitschaft dreistufig bewerten: `versandbereit`, `versandbereit mit Hinweisen` oder `nicht versandbereit`.

## Notwendigkeitsevidenz und Routing

[MUST] Für `JUSTIFIED` muss die Begründung auf konkrete vorhandene Repository-Struktur, Invariante, Boundary, Migration, Kompatibilität, Security, Performance, Datenintegrität oder einen gleichwertigen realen Constraint zeigen. Allgemeine Qualitätswörter reichen nicht.

[MUST] Ein `UNPROVEN`-Befund ist blockierend und führt zu `nicht versandbereit`, solange die Änderung weder entfernt noch konkret begründet wurde.

[MUST] `UNPROVEN` wird zur mutierenden Nacharbeit bevorzugt an `code-minimization` geroutet, sofern keine neue Anforderung oder Architekturentscheidung erforderlich ist. Bei einer echten Plan- oder Anforderungslücke an `code-implementation-planning` oder `requirements-clarification` routen.

[MUST] Wenn zur Rechtfertigung eines `UNPROVEN`-Elements eine neue Anforderung erfunden werden müsste, bleibt es `UNPROVEN`; der Scope darf nicht nachträglich erweitert werden.

[MUST_NOT] „Tests sind grün“, „Best Practice“, „sauberer“, „flexibler“, „besser erweiterbar“ oder „könnte später nützlich sein“ dürfen allein keine Änderung von `UNPROVEN` zu `JUSTIFIED` bewirken.

[MUST_NOT] Diff-Größe, Datei-Anzahl oder LOC allein dürfen zur Einstufung `UNPROVEN` führen. Notwendigkeit wird semantisch bewertet.

[MUST_NOT] Eine notwendige Security-, Validierungs- oder Fehlerbehandlung darf nicht allein wegen fehlender eigener Tests als `UNPROVEN` abgewertet werden; bekannte Invarianten und reale Failure Modes sind Evidenz.

## Versandbereitschaft

- `versandbereit`: keine blockierenden Befunde und keine `UNPROVEN`-Einheiten.
- `versandbereit mit Hinweisen`: nur echte nicht-blockierende Risiken; diese Bewertung darf keinen `UNPROVEN`-Befund verdecken.
- `nicht versandbereit`: mindestens ein `UNPROVEN` oder ein anderer blockierender Befund.

## Grenzen

- Read-only arbeiten.
- Keine Dateien ändern.
- Die Bewertung `nicht versandbereit` blockiert Commit, Push, Pull Request und andere extern wirksame Folgeschritte.
- Bei `versandbereit mit Hinweisen` müssen die Hinweise im Arbeitsabschluss sichtbar bleiben.
- Keine Tests, Builds oder Anwendungen ausführen. Das gehört zu `code-testing`.
- Keine Fehler beheben. Dafür `code-implementation` oder `code-refactoring` nutzen.
- Keine Formatierungs-, Whitespace-, Line-ending- oder Encoding-Probleme selbst korrigieren.
- Keine breite Analyse ersetzen. Tiefergehende Ursachen- oder Risikoanalyse gehört zu `code-analysis`.
- Die Beseitigung eines `UNPROVEN`-Befunds gehört zu `code-minimization`, die Klärung einer neuen Anforderung oder Architekturentscheidung zum passenden vorgelagerten Skill.
- Untracked files müssen im Arbeitsstatus benannt und bei Task-Relevanz separat gelesen und reviewt werden, weil sie im regulären Git-Diff fehlen.

## Output

- Bewertung: `versandbereit`, `versandbereit mit Hinweisen` oder `nicht versandbereit`
- relevante Befunde
- staged/unstaged-Einordnung, wenn relevant
- Risiken
- semantische Änderungseinheiten mit `REQUIRED`/`JUSTIFIED`/`UNPROVEN` und konkreter Evidenz
- gestellte Counterfactual-Frage und Ergebnis
- notwendige Nacharbeit

## Qualitätskriterien

- Echte Risiken vor Stilfragen.
- Scope-Abweichungen klar benennen.
- Nicht nur zusammenfassen, sondern bewerten.
- Blockierende und nicht-blockierende Befunde klar trennen.
- Unerwartete Formatierungs- oder Encoding-Änderungen als Scope-Risiko markieren.
- Fehlende Tests risikobasiert bewerten, nicht pauschal als blockierend einstufen.
- `UNPROVEN` immer als blockierend bewerten; `versandbereit mit Hinweisen` nicht als Umgehung verwenden.
