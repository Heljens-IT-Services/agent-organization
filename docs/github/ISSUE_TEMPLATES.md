# Kanonische Heljens-Issue-Templates

Diese Dateien werden unverändert nach `.github/ISSUE_TEMPLATE/` übernommen:

- [bug.yml](issue-templates/bug.yml)
- [config.yml](issue-templates/config.yml)
- [epic.yml](issue-templates/epic.yml)
- [refactor.yml](issue-templates/refactor.yml)
- [story.yml](issue-templates/story.yml)
- [task.yml](issue-templates/task.yml)

## Story- und Epic-Owner

Die vorhandenen nativen Issue-Types `Story` und `Epic` werden sowohl für fachliche als auch für technische Inhalte verwendet. `product_owner` verantwortet User Stories, User Epics und fachliche Akzeptanzkriterien; `softwareentwicklung_architektur` verantwortet Technical Stories, Technical Epics und technische Akzeptanzkriterien. Owner, Kriterien und Belege müssen im Issue klar erkennbar sein. Daraus entstehen keine neuen nativen Type-IDs.

## Task-Issue-Vertrag

Ein Task ist terminal, wenn er als eigenständig ausführbarer technischer Plan ohne erneute grundlegende Architektur-, Scope- oder Vorgehensentscheidung umgesetzt und verifiziert werden kann. Dafür muss er enthalten:

- eindeutigen Zielzustand und erforderlichen fachlichen sowie technischen Kontext
- verbindlichen Scope und expliziten Nicht-Scope
- bekannte betroffene Bereiche, Schnittstellen und hilfreiche Referenzimplementierungen
- bereits getroffene umsetzungsrelevante Entscheidungen und Constraints
- bei nicht offensichtlichen neuen konzeptionellen Ebenen: Current Driver und heutige Repository-/Task-Evidenz; die bloße Aufnahme in den Plan gilt nicht als Evidenz
- geordnete Arbeitspakete auf direkt ausführbarer, nicht mikrogranularer Ebene
- prüfbare Akzeptanzkriterien und konkrete reproduzierbare Verifikationsschritte
- bekannte Risiken, Abhängigkeiten und Blocker

Wesentliche offene Produkt-, Architektur-, Scope- oder Vorgehensentscheidungen verhindern Terminalität. Widersprechen Task-Plan, Repository-Zustand oder geltende Regeln einander, muss die Umsetzung stoppen und gezielt in Klärung oder Planung zurückspringen.

Globale Agent-, Engineering- und Technologieregeln werden nicht in den Task kopiert. Der Task dokumentiert nur aufgabenspezifischen Kontext und Entscheidungen; der geltende Repository- und Agent-Files-Kontext bleibt separat verbindlich.
