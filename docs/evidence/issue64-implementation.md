# #64 – optionaler Workflow-Skill-Anschluss

AR-E56-W64-20261013, 13.10.2026. Autorisierter Auftragspfad: Koordinator →
Teamleiter Agent Ressources → Optimierer. Basis `develop`/PR112:
`50191757d0e8bb9bed956d89c42afbac5ef0674d`. Implementierungsbeitrag zur
unabhängigen Prüfung; keine eigene Elternabnahme oder Laufzeitbehauptung.

Der [Workflowindex](../../workflows/INDEX.md) ergänzt optionale registrierte
IDs. Der [Kontextreader](../../scripts/context/WorkContext.psm1) reicht diese
bei selektiver Suche und beim Lesen eines ausgewählten Workflows weiter;
vier Spalten sowie leere Referenzen bleiben unterstützt. Der
[Starter](../../scripts/delegation/Start-DelegatedCodexTask.ps1) ergänzt nur
Auswahl-/Vertragshinweise, lädt keinen vollständigen Skill-/Rollenkontext und
startet keinen Skill automatisch. Keine Workflow-Engine.

Der [Ergebnisbericht](../../workflows/evidence-report.md) beschreibt Aufruf,
unveränderte JSON-Annahme, `result` im Erfolgsfall und strukturiertes `exception`
im Fehlerfall. [Optimierer](../../teams/agent_ressources/agenten/optimierer.toml)
und [Qualitätsprüfung](../../teams/agent_ressources/agenten/qualitaetspruefung.toml)
können denselben bestehenden `task-token-usage` direkt oder über diese Anweisung
wählen. Beide benötigen Tokenbelege für ihre Ergebnisberichte, ohne eigene
Ledgerlogik. Der skillfreie Abnahmevorbereitungsworkflow bleibt unverändert.
Der [Anschlussvertrag](../contracts/SKILLS.md) erhält konkrete Freigaben,
Seiteneffektgrenzen und aktuelle Ausführungsverbote; er erfindet keine Zustimmung.

| Quelle / eigenes Kriterium | Inhaltsbeleg | Grenze |
|---|---|---|
| #64: `result` bei Erfolg, strukturiertes `exception` bei Fehler | Ergebnisbericht, Schritt 4; beide Rollen; Anschlussvertrag | Anweisung und Quellanschluss, nicht ausgeführt |
| #64: zwei Rollen, ein referenzierter Skill, skillfreie Workflows | Beide AR-Rollen; Index mit `task-token-usage` und leerer zweiter Referenz | Keine Aktivierung oder Laufzeitprobe |
| #64: Berechtigungen/Freigaben erhalten, nicht autorisierte Seiteneffekte abweisen | Ergebnisbericht Schritt 1; Anschlussvertrag; Starterhinweis | Abweisung durch handelnden Agenten, keine neue technische Sandbox |
| #59: Workflow und Direktaufruf mit JSON einschließlich Fehlern | Ergebnisbericht und beide Rollen; bestehender Invoke-Skill-Pfad | Keine Freitextinterpretation; vollständige Antwort erhalten |
| #59: Workflow ruft Skill auf und bleibt Anweisung | Ergebnisbericht Schritt 3 verweist auf vorhandenen Runner | Workflow enthält keinen Dispatcher |
| #59: Skills ohne Workflow auswählen | Beide Rollen und Starter; vorhandene Find-Skill-Discovery | Bedarfsgesteuerte Auswahl |
| #59: Berechtigungen/menschliche Freigaben nicht umgehen | Anschlussvertrag und Schritt 1 | Kein globales Enablement |
| #56: JSON für Erfolg, Fach-/Runner-/Parserfehler | Bestehende `skill_runtime.py::validate_response`, `run`, `main`; `PS-Bootstrap.ps1`; PR92 | Wiederverwendeter Quellenbefund, keine neue Runtimeevidenz |
| #56: Registry bindet ausführbare Dateien, kein Markdown | `skills/registry.json`, beide vorhandenen Adapter; `skill_runtime.py::_repo_script` | Pfad-/Quellenreadback |
| #56: begründete aktuelle Bestandsprüfung und Wiederverwendung | PR92-Inventar und Elternannahme; hier bestehender Reader/Runner/Adapter vor Änderung gelesen | Keine erneute Vollkampagne; keine neue Skillfachlogik |
| #56: PowerShelldefault und explizite andere Interpreter | Registry ohne language für Token-Skill; Python-Eintrag; vorhandener Runner/Bootstrap unverändert | Aufrufbarkeit quellseitig, nicht ausgeführt |
| #56: selektive Auswahl, validierte Parameter, Ergebnis/Fehler/Ausführungsbezug | Find-Skill, Invoke-Skill, Runtime; Workflow mit WorkItemRef/ExecutionRef | Vorhandene Parametervalidierung/Logs nicht ausgeführt |

Autoritative Kriterien: aktuelle Bodys von [#64](https://github.com/Heljens-IT-Services/agent-organization/issues/64),
[#59](https://github.com/Heljens-IT-Services/agent-organization/issues/59) und
[#56](https://github.com/Heljens-IT-Services/agent-organization/issues/56), jeweils
eigenständig gelesen. Rekursiver Scope: #56 → #57(#60,#61), #58(#62,#63),
#59(#64), #66(#67,#68). Alle nativen sub_issues-Listen beim Readback leer;
explizite Aufgaben/Umsetzung verwendet, dedupliziert. #65 gestrichen und
ausgeschlossen. Dependencies #13/#18/#22/#23 sowie vorherige Skills-Stories
getrennt; #47 ist der wiederverwendete Anschluss, kein neues Epic-Kind.

Vorbeiträge: gemergtes PR92 mit Registry, Runner, Discovery, Migration und
datierter Quellenannahme; [PR92-Inventar](pr92-current-inventory.md) bleibt
historisch. Die aktuelle Auswahl benötigt keine neuen Skills oder Adapter.
Failed-Elternakte `23df7d1f25c84c489e8a376226d9ee58` enthält keinen fachlichen
Beitrag, `error=null`; Ursache nicht belegt. Detailakten einschließlich Scope,
Snapshotstates und Diff liegen in der beauftragten Temp-Lieferakte.

Belegmethode ausschließlich Inhalt, Diff und Referenzreadback. Keine Tests,
Parserläufe, Validatoren, Runtime-/Browser-/native Produktproben, Demos oder
Fixtures. Keine eigenständig festgestellte verbleibende Code-/Anschlusslücke
von #64; unabhängige Prüfung steht aus. Bekannte Integrationsüberschneidung
mit PM: Starter und Optimiererrolle; fremde Änderungen unverändert erhalten.
Keine Commits, Pushes, PRs oder Issuewrites. Fehlende formale Abnahme und
Laufzeitbelege sind kein eigenständiges Closuregate. Eigenverbrauch unbekannt:
`null`; keine Schätzung.
