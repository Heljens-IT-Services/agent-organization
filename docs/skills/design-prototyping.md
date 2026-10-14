# Skill: Design Prototyping

## Zweck

Eine Designidee mit möglichst wenig technischer Reibung in ein tatsächlich renderbares und visuell beurteilbares Artefakt übersetzen.

## Verwenden

- Wenn eine Designrichtung vor einer produktiven Implementierung sichtbar oder interaktiv erfahrbar gemacht werden soll.
- Wenn mehrere Designrichtungen schnell vergleichbar visualisiert werden sollen.
- Wenn ein UI-, Web-, Informations- oder Interaktionskonzept mit einem leichten Prototyp bewertet werden kann.
- Nicht verwenden, wenn direkt produktionsreifer Code im bestehenden Technologie-Stack implementiert werden soll. Der Umsetzungsbedarf wird mit Design-Handoff an den Koordinator gegeben.
- Nicht verwenden, wenn nur ein bestehendes visuelles Ergebnis bewertet werden soll. Dann `design-review` nutzen.

## Vorgehen

1. Gestalterisches Ziel, relevante Constraints und die zu demonstrierenden Aspekte aus dem vorhandenen Kontext übernehmen.
2. Das reibungsärmste geeignete renderbare Format wählen.
3. Für browserdarstellbare Konzepte standardmäßig einen eigenständigen Single-File-HTML-Prototyp mit eingebettetem CSS und JavaScript bevorzugen.
4. Nur so viel Struktur, Inhalt und Interaktion umsetzen, wie für die aktuelle Designentscheidung oder den Vergleich erforderlich ist.
5. Falls nötig Mock-Daten, Beispielinhalte, SVG, Canvas oder simulierte Zustände direkt im Prototyp verwenden und als Explorationsmaterial behandeln.
6. Keine unnötige Produktionsarchitektur, Build-Pipeline oder Abhängigkeit einführen.
7. Das Artefakt mit verfügbaren Browser-, Preview-, Rendering- oder Visualisierungstools tatsächlich darstellen.
8. Renderbarkeit, wesentliche Interaktionen und offensichtliche Darstellungsfehler prüfen.
9. Das visualisierte Artefakt für `design-review` bereitstellen.

## Grenzen

- Explorative Prototypen sind keine Produktionsimplementierung.
- Produktivcode darf durch diesen Skill nicht stillschweigend ersetzt oder erweitert werden.
- Neue Packages, Frameworks oder Designsysteme dürfen nicht allein für eine frühe Exploration installiert werden.
- Inline-CSS, Inline-JavaScript, harte Beispielwerte und Mock-Daten sind in wegwerfbaren Prototypen erlaubt, müssen aber vom Produktionsstandard getrennt bleiben.
- Ein Prototyp darf bewusst unvollständig sein, wenn die ausgelassenen Bereiche für die aktuelle Designfrage nicht relevant sind.
- Keine Produktionsreife, Barrierefreiheitskonformität oder technische Integrationsreife behaupten, wenn diese nicht separat geprüft wurden.

## Output

- renderbares Designartefakt oder klar benannter Prototyp-Pfad
- kurze Beschreibung der dargestellten Designrichtung
- verwendete Annahmen, Mock-Daten oder bewusst vereinfachte Bereiche
- relevante Hinweise für den anschließenden `design-review`

## Qualitätskriterien

- Das Artefakt muss die zu bewertende Designidee klar sichtbar machen.
- Der Prototyp muss schneller verwerfbar und änderbar bleiben als eine produktive Implementierung.
- Für browserdarstellbare frühe Entwürfe soll kein Build-Schritt erforderlich sein, wenn eine Single-File-Lösung ausreicht.
- Technische Komplexität darf die Designexploration nicht dominieren.
- Mock- und Produktionsrealität müssen unterscheidbar bleiben.

