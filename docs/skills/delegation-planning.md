# Skill: Delegationsplanung

## Zweck

Eine Nutzeranfrage direkt der passenden Rolle zuweisen oder bei mehreren Fachbeiträgen in abgegrenzte Aufträge aufteilen.

## Verwenden

- Wenn der Koordinator einen Auftrag annimmt, einen veröffentlichten Workflow auswählt oder Arbeitsschritte an Spezialisten übergibt.
- Wenn mehrere Rollen oder eine fachliche Übergabe erforderlich sind.

## Vorgehen

1. Vorhandene Ziele, Akzeptanzkriterien, Pläne, Entscheidungen und Constraints als verbindliche Arbeitsgrundlage übernehmen.
2. Ausschließlich Routing-Metadaten aus Rollenindex, Skill-Katalog und Workflow-Katalog verwenden; keine fachlichen Skills, Technologien oder operativen Workflow-Regeln laden.
3. Pro Arbeitspaket genau eine zuständige Rolle, Scope und Nicht-Scope sowie ein erwartetes Ergebnis bestimmen. Bei hinreichend bestimmtem Auftrag direkt delegieren; zusätzliche Planung nur bei tatsächlichem Klärungsbedarf beauftragen.
4. Phasen und Abhängigkeiten festlegen. Unabhängige Lese-, Analyse- oder Review-Aufträge dürfen parallel laufen; Schreibaufträge im selben Worktree müssen sequenziell oder anderweitig konfliktfrei zugewiesen werden.
5. Technische Strukturentscheidungen, technische Issue-Struktur und technische Kriterienprüfung an `softwareentwicklung_architektur`, fachliche Anforderungen und fachliche Issue-Struktur an `product_owner`, Umsetzung an Backend, Frontend oder Infrastruktur, unabhängige Regression und technische Gesamtsicherung an Qualitätssicherung und Gestaltung an `designer` delegieren.
6. Fachliche GitHub-Issue-Erstellung, -Typen und -Beziehungen `product_owner`, technische Issue-Erstellung einschließlich Technical Tasks, -Typen und -Beziehungen `softwareentwicklung_architektur` zuweisen. Git-Repository- und Pull-Request-Lifecycle-Schritte wie Branch, Commit, Push, Pull Request, Merge und Veröffentlichung `softwareentwicklung_infrastruktur` zuweisen. Check-Beobachtung im freigegebenen Git-/GitHub-Lifecycle-Auftrag Infrastruktur zuweisen; unabhängige Check-Bewertung `softwareentwicklung_qualitaetssicherung` zuweisen.
7. Einen Auftrag mit Ziel, Workflow-Schritt, Kontext, Dateien/Artefakten, Constraints, Entscheidungen, Scope, Nicht-Scope und erwarteter Rückgabe formulieren.
8. Rückgaben auf Ergebnis, ausgeführte oder ausgelassene Verifikation, Abweichungen, Blocker und weiteren fachlichen Bedarf prüfen.
9. Bei unklarem Ziel oder widersprüchlichen Anforderungen an den Nutzer zurückgeben; keine fachliche Entscheidung stellvertretend treffen.

## Grenzen

- Der Koordinator führt keine Recherche, Codeänderung, Issue-Mutation, Dokumentation, Tests, Git- oder GitHub-Aktion selbst aus. Fachliche Issue-Inhalte, Issue-Typen und -Beziehungen gehören zu `product_owner`; technische Issue-Inhalte, -Typen und -Beziehungen zu `softwareentwicklung_architektur`; Repository- und PR-Lifecycle zu `softwareentwicklung_infrastruktur`; Check-Beobachtung im freigegebenen Lifecycle zu Infrastruktur und unabhängige Check-Bewertung zu `softwareentwicklung_qualitaetssicherung`.
- Der Koordinator liest keine fachlichen Skills, operativen Workflows oder Technologiespezifikationen.
- Der Koordinator erfindet keine Rollen, Fähigkeiten, Berechtigungen, Verifikation oder Arbeitsergebnisse.
- Diese Fähigkeit ist kein technischer Planungs- oder Abnahmeersatz.

## Output

- Abgegrenzte, geroutete Arbeitspakete mit eindeutiger Rolle und Übergabevertrag.
- Zusammengeführter Status mit Ergebnissen, Nachweisen, offenen Punkten und nächster Rolle.

