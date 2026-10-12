# Workflow: Ergebnisbericht und Inhaltsreview

**Version:** 1  
**Zweck:** Einen klar abgegrenzten fachlichen Arbeitsbeitrag nachvollziehbar umsetzen oder inhaltlich prüfen und Ergebnis, Belege, Grenzen und offene Punkte berichten.  
**Anwendbarkeit:** WorkItems mit autoritativen Anforderungen, selektiv lesbaren Quellen und überprüfbarem Inhalts- oder Dateidiff. Bei fehlender Spezifikation oder erforderlicher Freigabe diese an den zuständigen Verantwortlichen melden; der Ablauf erteilt keine Freigabe.

## Eingaben

- WorkItem und gegebenenfalls Elternkriterien, in der autoritativen Quelle gelesen.
- Zugewiesener Dateiscope, Branch/Basis sowie Projekt- und Prüfvorgaben.
- Für Review: gelieferter Stand, Änderung/Diff und Referenzen.

## Ablauf

1. Anforderungen und Scope vollständig lesen; Reihenfolge, Abhängigkeiten und Grenzen festhalten.
2. Arbeitsbaum, Branch und Basis lesen. Fremde Änderungen und Worktrees erhalten.
3. Nur passende Bestandsquellen und Referenzen heranziehen. Vorhandene Verträge und Pfade wiederverwenden; Unklarheiten nicht eigenmächtig durch Scopeausweitung lösen.
4. Bei Umsetzung zuerst einen abgegrenzten Teil fertigstellen und Inhalt, Diff und Referenzen zurücklesen. Danach erst abhängige Teile bearbeiten.
5. Bei Inhaltsreview Behauptungen auf ihre konkreten Quellen zurückführen; tatsächliche Befunde, historische Belege und nicht geprüfte Laufzeitannahmen auseinanderhalten.
6. Ergebnis mit genauen Dateipfaden, Kriterienbezug, Quellen und Grenzen berichten. Offene Punkte sichtbar lassen. Keine Abnahme aus Implementierung ableiten.

## Ergebnisform

Knappes Ergebnis; Scope und geänderte Dateien; Belege aus Inhalt/Diff/Quellen;
Grenzen und offene Punkte. Verweise relativ zum Repository oder direkt zur
autoritativen Issue-/Dokumentquelle setzen.

## Qualitätskriterien

- Anforderungen und Scope stammen aus autoritativen Quellen.
- Änderungen bleiben im zugewiesenen Scope; bestehende Fremdarbeit bleibt erhalten.
- Quellen stützen die jeweilige Aussage und sind für die nächste Rolle auffindbar.
- Umsetzung, Quellintegration, Prüfung und Abnahme werden nicht gleichgesetzt.
- Nicht ausgeführte Prüfungen werden nicht als bestanden dargestellt.

## Quelle und Stand

Abgeleitet aus `docs/contracts/WORKITEMS.md` (Ergebnisbelege und getrennte
Abnahme), `docs/decisions/0001-system-scope.md` (Wissens-/Workfloworte) und
Issue #47; Version 1, erstellt am 12.10.2026 im Wissens-WorkItem #47.
