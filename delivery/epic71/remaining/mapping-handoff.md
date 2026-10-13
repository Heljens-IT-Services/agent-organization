# WI E71-R-IMPL – HELJOS-Mapping und Fachübergabe #75

Adressat: `teamleiter_agent_ressources`. Weitergabe erforderlicher Produktentscheidungen ausschließlich über Koordinator. Kein fremder Kontakt oder Unterauftrag wurde gestartet.

Der konkrete Index ist `productmanagement/solutions.json`: HELJOS erhält im vorhandenen Inventurbereich `solutionId=heljos`, normalisierte Dokument-IDs und Originalhashes. Die autorisierte Erstentwicklung deckt diese Routinebindung ab; es wird keine neue allgemeine Freigabe für Schlüssel oder Pfadreferenzen benötigt. `solutions` bleibt leer, weil tatsächliche PM-Identität, verantwortlicher Owner und Produkt-WorkItem-Linie sachlich nicht zugeordnet sind. Die vorhandenen Strategie-PM-/PO-Profile sind als verfügbare Profile dokumentiert, keine fingierte Produktbesetzung. Ground bleibt unverändert ungeklärt.

## Gezielt zurückgelesene bestehende Einstiege

| Dokument-ID | Bestehendes Ziel unter `C:/Users/Tom-OliverMarek/source/repos/heljos` | Inhaltsbefund und Grenze |
| --- | --- | --- |
| `heljos-readme` | `README.md` | Konzeptionsstand; verweist auf geplante `docs/product-concept/produktkonzept-ki-mitarbeiter-plattform.md`. Dieses Ziel wurde am benannten Pfad nicht gefunden und wird nicht als Dokument registriert. |
| `heljos-project` | `PROJECT.md` | Versionierter Prozess und eigene Prozessinstanz sind zentrale Regeln; Codex app-server/stdio als Produktsteuerweg. Regeln und versionsbezogene Angaben sind Produktdokumentinhalt, keine aktuelle Runtimeverifikation. |
| `heljos-concept` | `docs/konzept/produktkonzept-ki-mitarbeiter-plattform.md` | Vorhandenes fachliches Arbeitsdokument, Stand 30.07.2026: digitale Mitarbeiter, Prozesse, Versionen, Instanzen; §7.3 beschreibt Freitext plus schreibgeschützte Interpretation, §7.4 gemeinsame Bestätigung. Enthält offene Festlegungen; kein aktueller #75-Featurebeschluss. |
| `heljos-mvp` | `docs/konzept/konzept-mvp.md` | Vorhandene Markierung vom 07.08.2026 unterscheidet MVP, reduziert, später und Konflikt. Ist fachlicher Input für Priorisierung, keine durch diesen Auftrag gewählte Priorität. |
| `heljos-appserver-adr` | `docs/architecture/adr/0008-codex-app-server-steuerung.md` | Bestehende technische Entscheidung/Protokollgrenze; Status vorgeschlagen, vollständiger kostenpflichtiger Lauf ausdrücklich nicht durchgeführt. Historische Teilbelege gelten hier nicht als heutige Funktion. |

Alle fünf Ziele wurden nur im übergebenen Inventur-/README-/PROJECT-Rahmen gelesen; Originalbyteshashes stehen direkt im Index und Liefermanifest. Kein neuer Produkttext, keine Rollenkopie, kein synthetisches Feature. Alle Quellen sind Markdown unter dem beobachteten Workspace; Auswahl/Hash/Pfad-/Größenprüfungen der späteren Runtime bleiben bestehender Code. Es wurde keine neue umfassende Roadmap-/Indexsuche durchgeführt.

## Kleinste sachliche Zuordnung für #74/#78

Koordinator benötigt die verantwortliche menschliche Owner-ID und die konkrete Strategie-PM-Identität für die reale Solution `heljos`, sowie den bestehenden oder zu beauftragenden Produkt-WorkItem-Wurzelpunkt. Diese Entscheidung verbindet vorhandene Profile mit dieser Solution; sie ist keine IDnormalisierung. Nach der Entscheidung kann genau dieser Bestandsdatensatz mit den bereits gesicherten Dokumentreferenzen in `solutions` überführt und am vorhandenen Launchvertrag gebunden werden. Für Ground bleibt nur die bereits gestellte Frage nach Workspace/Repository, Owner und kanonischem Dokumenteinstieg offen; keine neue Suche.

## Konkreter PM-Fachauftrag #75

Auftragsvorschlag zur Weitergabe **Koordinator → Produktmanagement-Teamleitung**, gebunden an `solutionId=heljos`, den obigen Checkout und die gehashten Dokument-IDs:

1. Nach tatsächlicher PM-/Owner-/Produkt-WorkItem-Zuordnung ein reales Nutzerproblem aus `heljos-concept` und `heljos-mvp` auswählen und mit Abschnitten/Originalhashes belegen. PROJECT/ADR begrenzen Machbarkeit; vorhandene offene Punkte und Konflikte sichtbar behandeln.
2. Ein konkretes begrenztes Feature priorisieren: Zielnutzer, Problem, Gründe gegenüber mindestens einer verworfenen Alternative, MVP-Einordnung, Roadmapbezug und Abnahmekriterien dokumentieren. Dieses Paket wählt kein Feature vorweg.
3. Die Entscheidung über den vorhandenen `Save-ProductDecision.ps1`-/Reviewvertrag quellengebunden annehmen lassen; echte Produkt-WorkItem-Elternlinie und aktuelle Store-CAS binden.
4. Mit dem vorhandenen `New-ProductFeature.ps1` genau das fachlich angenommene Feature und sein gesondertes Outcome-Review als echte WorkItems führen: Hypothese, messbare Metrik/Ziel, Quellen und Beobachtungs-/Reviewtermin. Keine Messwerte oder Wirkung erfinden; Strategie/PO-Übergabe entscheidet die Produktteamleitung, Fachteambedarf geht über Koordinator.
5. Bei späteren ereignisgetriebenen Aktivierungen Roadmap/Entscheidung und beobachtete Wirkung fortschreiben. Lieferung und beobachtete Produktwirkung getrennt bewerten. Kein Idle-Polling, keine Produktprobe als Ersatz.

Erwarteter PM-Rücklauf: konkrete angenommene Entscheidung mit Belegen, Feature-/Review-WorkItem-IDs, Solution-/PM-/Ownerbindung und Roadmap-/Wirkungsplan. Bis dahin bleiben #75 und die tatsächliche Aktivierung der HELJOS-Zuordnung offen. Die Übergabe ist fertig formuliert, aber weder versandt noch als Auftrag ausgeführt oder abgenommen.
