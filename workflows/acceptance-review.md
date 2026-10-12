# Workflow: Fachliche Abnahmevorbereitung

**Version:** 1  
**Zweck:** Einer unabhängigen prüfenden Rolle eine nachvollziehbare Prüfung der fachlichen Akzeptanzkriterien ermöglichen.  
**Anwendbarkeit:** Wenn autoritative Kriterien und ein konkreter Umsetzungssnapshot vorliegen. Dieser Ablauf bereitet die Prüfung vor; er erteilt keine Freigabe und trifft keine Elternabnahme.

## Eingaben

- Aktueller Body des WorkItems und eigene Elternkriterien, falls geprüft wird.
- Festgelegter Branch/Commit oder anderer eindeutig identifizierter Implementierungsstand.
- Umsetzungsergebnis, Quellenbelege, Diff und dokumentierte Grenzen.
- Geltende Prüfregeln und freizugebende Voraussetzungen.

## Ablauf

1. Kriterien und Abhängigkeiten aus der maßgeblichen Quelle zurücklesen; Prüfumfang und Snapshot notieren.
2. Jedes Kriterium einzeln einer konkreten Änderung oder Quelle zuordnen. Unbelegte oder widersprüchliche Punkte als offen markieren.
3. Inhalt und Referenzen unabhängig zurücklesen. Nur die laut Projektregeln zulässigen Prüfarten verwenden; keine verbotenen Tests oder Proben ausführen.
4. Implementierung, Quellintegration, Funktionsnachweis und Abnahme als getrennte Aussagen behandeln. Historische Ergebnisse nicht als aktuellen Nachweis verwenden.
5. Befund je Kriterium mit Evidenz und Grenze dokumentieren. Bei fehlendem Nachweis Nacharbeit oder Klärung benennen.
6. Eigene Abnahmeentscheidung ausschließlich der dazu zuständigen Elternrolle überlassen und separat dokumentieren lassen.

## Ergebnisform

Snapshot und Quellen; Befund je Akzeptanzkriterium; verwendete Prüfmethode;
Grenzen, offene Punkte und empfohlene Nacharbeit. Eine Entscheidung wird nur von
der zuständigen Abnahmerolle ergänzt.

## Qualitätskriterien

- Kriterien und Stand sind autoritativ und eindeutig benannt.
- Jeder Befund ist mit konkretem Inhalt, Diff oder Referenz belegt.
- Fehlende, widersprüchliche und nicht geprüfte Nachweise sind ausdrücklich offen.
- Projektregeln, Freigaben und Zuständigkeiten bleiben wirksam.
- Kinderabschluss ersetzt weder eigene Kriterien noch die Elternentscheidung.

## Quelle und Stand

Abgeleitet aus `docs/contracts/WORKITEMS.md` (Abschnitt „Lebenszyklus“),
`docs/evidence/issue61-implementation.md` (klare Grenzen von Quellen- und
Laufzeitbelegen) und Issue #47; Version 1, erstellt am 12.10.2026 im
Wissens-WorkItem #47.
