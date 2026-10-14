# Skill: Design Review

## Zweck

Ein tatsächliches visuelles oder interaktives Ergebnis betrachten, kritisch bewerten und konkrete nächste Designentscheidungen für eine Iteration oder Finalisierung ableiten.

## Verwenden

- Wenn ein Designprototyp, eine Oberfläche, ein visueller Entwurf oder eine Designvariante gerendert vorliegt.
- Wenn mehrere Designrichtungen anhand ihres tatsächlichen visuellen Ergebnisses verglichen werden sollen.
- Wenn nach einer Designänderung geprüft werden soll, ob die beabsichtigte gestalterische Verbesserung sichtbar erreicht wurde.
- Nicht verwenden, wenn erst ein renderbares Artefakt erzeugt werden muss. Dann `design-prototyping` nutzen.
- Nicht als Ersatz für formale Testverifikation, Regression oder Akzeptanzprüfung verwenden. Entsprechender Prüfbedarf geht an den Koordinator.

## Vorgehen

1. Das tatsächliche Artefakt oder die relevante Anwendung mit verfügbaren Visualisierungswerkzeugen öffnen oder rendern.
2. Zuerst den primären Nutzungskontext und die zentrale Designabsicht prüfen.
3. Wenn Interaktion relevant ist, wesentliche Aktionen, Zustände, Hover-, Fokus-, Lade-, Leer-, Fehler- oder Erfolgszustände ausprobieren, soweit sie für das Design vorhanden sind.
4. Wenn Darstellungsgrößen relevant sind, die wichtigsten Zielgrößen oder Viewports prüfen statt nur eine einzelne Ansicht zu bewerten.
5. Den Entwurf mindestens nach folgenden Dimensionen bewerten, soweit sie relevant sind:
   - Zielerfüllung und Nutzerfokus
   - visuelle Hierarchie und Fokusführung
   - Komposition, Abstände und Informationsdichte
   - Typografie und Lesbarkeit
   - Farbe, Kontrast und visuelle Konsistenz
   - Interaktionsklarheit, Affordances und Feedback
   - relevante Zustände und Nutzerflüsse
   - responsives Verhalten
   - Barrierefreiheit und Bedienbarkeit
   - unnötige Komplexität oder dekorative Ablenkung
   - produktspezifische Identität statt austauschbarer Standardmuster
   - Zweck auffälliger Gestaltungselemente
6. Objektiv erkennbare Probleme von subjektiven Stilpräferenzen trennen.
7. Bei mehreren Richtungen deren wesentliche Stärken, Schwächen und Trade-offs vergleichbar zusammenfassen.
8. Review-Funde nach Wirkung priorisieren und konkrete nächste Änderungen ableiten.
9. Wenn relevante Änderungen umgesetzt wurden, die geänderte Fassung erneut rendern und die betroffenen Review-Punkte verifizieren.

## Werkzeugwahl

[SHOULD] Verfügbare native Browser-, Preview- oder Visualisierungstools sollen bevorzugt werden, wenn sie das Artefakt zuverlässig darstellen und inspizieren können.

[ALLOW_IF] Browser-Automation, Screenshots, Playwright, DevTools oder vergleichbare Werkzeuge dürfen verwendet werden, wenn sie für Interaktion, Viewports, Zustände oder visuelle Inspektion zusätzlichen Nutzen liefern.

[MUST_NOT] Der Skill darf nicht von einem bestimmten Herstellerwerkzeug abhängig gemacht werden, wenn eine gleichwertige verfügbare Visualisierung den Review ermöglicht.

[MUST_NOT_IF] Eine visuelle Darstellung technisch verfügbar ist, darf der Review nicht ausschließlich aus HTML, CSS, Quellcode oder einer textuellen Beschreibung abgeleitet werden.

## Output

- betrachtete Variante oder Varianten
- priorisierte Review-Funde
- Stärken, Schwächen und Trade-offs
- konkrete nächste Designänderungen
- begründete Richtungs- oder Finalisierungsentscheidung, wenn sie Teil des Auftrags ist
- nicht prüfbare visuelle Aspekte oder Werkzeuglücken

## Qualitätskriterien

- Aussagen müssen auf dem tatsächlich betrachteten Ergebnis beruhen.
- Kritik muss auf Ziel, Nutzungskontext oder nachvollziehbaren Designprinzipien beruhen.
- Subjektive Geschmacksurteile müssen als solche erkennbar bleiben.
- Wesentliche Probleme müssen vor kosmetischen Detailwünschen priorisiert werden.
- Nach einer relevanten Iteration muss die geänderte Fassung erneut visuell geprüft werden.

