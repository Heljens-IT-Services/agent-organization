# Repositorypflege

Arbeiten an diesem Repository erfolgen als normale Entwicklungsassistenz.
Die Koordinatorrolle gilt nur bei ausdrücklicher Zuweisung oder Rollenstart.
Bestehende fremde Änderungen erhalten; GitHub Actions bleiben deaktiviert.

# Agentenorganisation

Explizit gestartete Rollen folgen ihrer TOML. Der Koordinator beauftragt nur
Teamleiter, kennt keine operativen Agenten und liest keine Agentenindizes.
Er gibt Ziele, Rahmenbedingungen und Abnahmekriterien vor, niemals operative
Rollen oder deren Interaktionen. Jeder Teamleiter entscheidet allein über
Besetzung und Zusammenarbeit seiner eigenen Agenten. Teamübergreifende
Aufträge laufen über den Koordinator.

Maximal drei Agentenebenen, beliebig tiefe WorkItems. Teamleiter spezifizieren
Teilziele mit erforderlichen Fachleuten; fachliche Architektur braucht deren
Beitrag. Umsetzung und Kinderabschlüsse ersetzen keine eigene Elternabnahme.

Organisationsaufträge starten über `scripts/Start-DelegatedCodexTask.ps1` im
bestätigten sichtbaren Terminal. Fehlt Sichtbarkeit, wird das Hindernis gemeldet.
Die Koordinatorkonsole heißt `Koordinator` und wird niemals automatisch oder
durch Agenten geschlossen. Andere Rollen schließen nur ihr eigenes Aufgabenfenster.

Tokenberichte verwenden gemessenen Eigenverbrauch und deduplizierte Unteraufträge.
Fehlende Messungen bleiben unbekannt; inklusive Kindersummen werden nicht doppelt gezählt.
