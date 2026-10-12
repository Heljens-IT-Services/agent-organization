# Organisationsverträge v1

| Bestehende Quelle | Verbindliches Schema |
|---|---|
| `koordinator/teams.json` | [teams.schema.json](../../schemas/teams.schema.json) |
| `teams/<team_id>/agenten.json` | [agents.schema.json](../../schemas/agents.schema.json) |

Keine Laufzeitzustände, `status`-Felder oder zusätzlichen Felder in Indizes,
auch nicht verschachtelt. `role_file: null` bezeichnet eine nicht verfügbare Rolle.
Vorhandene Referenzen benennen exakt `<Rollen-ID>.toml`, relativ zur persönlichen
Installation. Der Prüfer löst sie auf bestehende Repositoryquellen auf und prüft
Existenz, TOML-`name`, eindeutige IDs, Teamzuordnung und Koordinatorverweis.
Ein fehlendes Ziel oder ein nicht verzeichnetes Team wird gemeldet.

```powershell
.\scripts\Test-Organization.ps1
.\scripts\Test-Organization.ps1 -RepositoryRoot C:\anderer\checkout
```

Die Prüfung verändert und installiert keine Dateien. Sie prüft keine Dienstzugänge
und nicht sämtliche nativen TOML-Laufzeitoptionen. [Beispiele](../../examples/organization)
zeigen `null`-Referenzen und verbotene Zustandsfelder. Der unterstützte Schemaumfang
steht in [WORKITEMS.md](WORKITEMS.md).

Der Koordinator lädt nur den Teamleiterindex, delegiert Ziele und entscheidet
weder Besetzung noch interne Zusammenarbeit. Teamleiter laden nur ihren Index,
spezifizieren Teilziele mit benötigten Fachleuten und bündeln deren Beiträge.
Die Pflege eigener WorkItems ist Koordination, keine operative Facharbeit.
Fachliche Architekturentscheidungen brauchen einen zuständigen Spezialistenbeitrag.
Maximal drei Ebenen: Koordinator → Teamleiter → operativer Agent.

Vertrieb nutzt vorhandene Teams: Marketing übernimmt Positionierung und
Kundengewinnung, Geschäftsführung und Assistenz Angebote, Verträge und
Kundenkommunikation. Wirtschaftlichkeitsfragen gehen über den Koordinator an
Controlling. Neue Besetzung wird zunächst vorgeschlagen.
