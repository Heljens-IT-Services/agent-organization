# Workflowindex

Vor einem Arbeitsablauf diesen Index nach Zweck und Suchworten durchsuchen und
nur den passenden Workflow lesen. Geeignete Anweisungen auf den konkreten Auftrag
anwenden. Gibt es keinen passenden Workflow, kann die Arbeit anhand des Auftrags
und der geltenden Projektregeln weitergehen. Workflows schaffen keine Berechtigung,
ersetzen keine fehlende Spezifikation und umgehen keine erforderliche Freigabe.

Die optionale Spalte `Skillreferenzen` nennt kommagetrennte IDs aus
`skills/registry.json`. Eine leere Zelle oder ein bestehender Index mit nur vier
Spalten bleibt gültig. `SkillReferences` im Readerergebnis sind Auswahlhinweise,
keine automatischen Aufrufe oder Freigaben. Nur die benötigte ID über
`scripts/skills/Find-Skill.ps1` auflösen; Skriptdatei und Voraussetzungen gelten
gemäß [Skillvertrag](../docs/contracts/SKILLS.md). Markdown allein ist kein Skill.

| Workflow | Zweck und Suchworte | Anwendbarkeit | Pfad | Skillreferenzen |
|---|---|---|---|---|
| Ergebnisbericht und Inhaltsreview | Quellen, Ergebnisbeleg, Diff, Grenzen, offene Punkte, unabhängige Inhaltsprüfung, Tokenverbrauch | Umsetzung oder Review eines klar abgegrenzten WorkItems mit lesbaren Quellen und Änderungen | [evidence-report.md](evidence-report.md) | task-token-usage |
| Fachliche Abnahmevorbereitung | Akzeptanzkriterien, Nachweise, Abhängigkeiten, Nacharbeit, Elternabnahme | Vorbereitung einer unabhängigen fachlichen Abnahme anhand autoritativer Kriterien; keine Abnahmeentscheidung durch den Workflow | [acceptance-review.md](acceptance-review.md) | |
