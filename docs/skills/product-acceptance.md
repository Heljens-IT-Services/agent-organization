# Skill: Fachliche Produktabnahme

## Zweck

Fachliche Akzeptanzkriterien anhand des von Nutzern sichtbaren Produktverhaltens bewerten.

## Verwenden

- Wenn ein Product Owner geklärte fachliche Akzeptanzkriterien am aktuellen Produktstand prüfen soll.
- Wenn eine Produkt- oder Feature-Abnahme nach Nutzerziel, sichtbarem Verhalten und fachlichem Ergebnis erforderlich ist.
- Nicht verwenden, um Code, Testimplementierungen, Architektur oder technische Qualitätsmerkmale zu prüfen.

## Vorgehen

1. Übergebene Kriterien, erwartetes Nutzerergebnis, Produktstand, Prüfumgebung und freigegebene Zugänge erfassen.
2. Kriterien anhand des zugewiesenen fachlichen Kontexts und vorhandener Produktunterlagen selbst auf konkrete, beobachtbare Ergebnisse abbilden. Wenn dafür eine notwendige Nutzerentscheidung fehlt, den Klärungsbedarf an den Koordinator melden; Spezialisten kontaktieren Nutzer nicht direkt.
3. Die freigegebene Oberfläche wie ein Nutzer bedienen oder geeignete, ausdrücklich bereitgestellte und bereits ausgeführte E2E-Ergebnisse anhand ihrer sichtbaren Ausgabe bewerten.
4. Keine Produktiv- oder Testquellcodes, Code-Diffs, technischen Testskripte, CI-Konfigurationen oder Implementierungsdetails lesen oder verändern. Keine technischen Prüfungen ausführen.
5. Pro Kriterium `PASS`, `FAIL`, `BLOCKED` oder `UNVERIFIED` ausweisen und konkrete Beobachtung, Beleg, Produktstand sowie Umgebung nennen.
6. Fehlende Oberfläche, Testausgabe, Zugang oder Prüfvoraussetzung als `BLOCKED` oder `UNVERIFIED` melden. Keine Ergebnisse aus Status, Commit, Entwicklerangabe oder fehlender Fehlermeldung ableiten.

## Grenzen

- Keine technische Testplanung oder -implementierung. Technischer Prüf- oder Automatisierungsbedarf wird an den Koordinator gemeldet.
- Keine Regression-, Code-, Architektur-, Sicherheits-, Performance-, CI- oder Diff-Prüfung.
- Keine Issue-, Produktivcode- oder Testcode-Mutation.
- Eine fachliche `PASS`-Bewertung ersetzt keine technische Verifikation durch Qualitätssicherung und begründet keine User- oder Release-Freigabe.

## Rückgabe

- Kriterium und beobachtetes fachliches Ergebnis
- Status `PASS`, `FAIL`, `BLOCKED` oder `UNVERIFIED`
- verwendete Oberfläche oder bereitgestellte E2E-Ausgabe, Produktstand und Prüfumgebung
- offene fachliche Fragen und fehlende Belege

