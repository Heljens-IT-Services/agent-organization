# WorkItem-Speicher: Betrieb und Wiederanlauf

## Voraussetzungen und Datenort

Die Skripte sind für Windows PowerShell unter Windows mit einem lokalen NTFS-
Datenordner ausgelegt. SMB/UNC, Netzlaufwerke, Cloud-Synchronisation, weitere
Hosts oder Plattformen sowie Haltbarkeit bei Stromausfall sind nicht zugesagt.
Der Ordner muss vor dem Aufruf existieren. Bewahre ihn außerhalb des Git-
Checkouts an einem lokalen, gesicherten Ort auf, zum Beispiel:

```powershell
$repositoryRoot = (Resolve-Path .).Path
$dataDirectory = Join-Path $env:LOCALAPPDATA 'Heljens\WorkItems'
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
$storePath = Join-Path $dataDirectory 'workitems.json'
```

Lege den Ordner auf einem lokalen NTFS-Volume an und stelle sicher, dass die
aufrufende Windows-Identität dort lesen, schreiben und Dateien anlegen kann.
Das Beispiel `New-Item` legt nur den Ordner an; es initialisiert keinen
WorkItem-Bestand. Verwende einen für Sicherung und Aufbewahrung geeigneten
Ordner. `RepositoryRoot` bleibt stets der Repository-Checkout, damit Validator,
Verträge und Markdown-Referenzen von dort bezogen werden. Ein alternatives
`Path` ändert diese Basis nicht.

## Öffentliche Befehle und Revisionen

Die Caller sind `scripts/Get-WorkItems.ps1`, `scripts/New-WorkItem.ps1` und
`scripts/Set-WorkItem.ps1`. Ihre öffentlichen Parameter sind:

| Skript | Parameter |
| --- | --- |
| `Get-WorkItems.ps1` | `-Path`, `-RepositoryRoot` (Standard: Repository-Root), `-TimeoutMilliseconds` (Standard 5000; 0–60000) |
| `New-WorkItem.ps1` | `-Path`, `-Item`, `-ExpectedRevision`, `-RepositoryRoot` (Standard: Repository-Root), `-TimeoutMilliseconds` (0–60000) |
| `Set-WorkItem.ps1` | `-Path`, `-Id`, `-Item`, `-ExpectedRevision`, `-RepositoryRoot` (Standard: Repository-Root), `-TimeoutMilliseconds` (0–60000) |

Lies vor jeder Änderung frisch und verwende genau die dabei gelesene Revision.
Ein fehlender Bestand hat `Exists = $false` und Revision `absent`. Ein vorhandener
Bestand liefert eine Revision `sha256:<hash>` über seine gespeicherten Bytes.
`New` erwartet für die erstmalige Anlage `absent`, einen neuen Eintrag mit
Status `planned` und eine eindeutige ID. `Set` erwartet die vollständige
aktualisierte Instanz sowie deren stabile ID. Zum Beispiel:

```powershell
$snapshot = .\scripts\Get-WorkItems.ps1 `
    -Path $storePath -RepositoryRoot $repositoryRoot

if ($snapshot.Exists) {
    $snapshot.Revision
    $snapshot.Document
} else {
    'Noch nicht angelegt; vor New muss die geplante Änderung vorbereitet sein.'
}

# Vor der Änderung in den Caller aufnehmen, frisch lesen, dann:
# $created = .\scripts\New-WorkItem.ps1 -Path $storePath `
#     -RepositoryRoot $repositoryRoot -Item $plannedItem `
#     -ExpectedRevision $snapshot.Revision
```

Bei `RevisionConflict` Bestand erneut lesen, die fachliche Änderung auf Basis
des neuen Dokuments bewusst anwenden und mit dessen Revision erneut aufrufen.
Es gibt kein automatisches Merge oder Force. Ist die Antwort eines Schreib-
Aufrufs ausgeblieben, ist der Commitstatus zunächst unbekannt: zuerst frisch
lesen. Bei `Set` kann dieselbe vollständige Änderung erneut mit der frisch
gelesenen Revision aufgerufen werden; eine bereits erreichte identische
Änderung ist idempotent. Bei `New` zeigt ein bereits angelegter Eintrag
`DuplicateWorkItemId`; diesen Bestand lesen und prüfen, nicht eine zweite ID
erfinden oder blind erneut anlegen.

## Sperren und verständliche Fehler

Operationen verwenden eine exklusive Sperre neben der Bestandsdatei. Die
Wartezeit ist nur ein Wartebudget, keine Besitzdauer. Ein aktiver Besitzer wird
niemals wegen seines Alters oder eines abgelaufenen Zeitraums übernommen.
Eine sicher bestätigte tote lokale Prozessidentität kann wiederhergestellt
werden. Eine Legacy-, fremde, beschädigte oder nicht verlässlich prüfbare
Identität bleibt geschützt und wird nicht gelöscht. Die Sperrprüfung verwendet
Windows-Hostidentität, PID und Prozessstart; ein freier oder nicht lesbarer
Lockdateipfad allein beweist keinen toten Besitzer.

Relevante Fehler-IDs und nächste Schritte:

| Fehler-ID | Bedeutung und Vorgehen |
| --- | --- |
| `LockTimeout` | Sperre blieb innerhalb des Wartebudgets belegt. Nicht löschen; später erneut lesen/aufrufen und den Besitzer klären. |
| `LockOwnerUncertain` | Besitzer ist unklar oder konnte nicht zuverlässig geprüft werden. Sperrdatei und Daten unverändert erhalten; Caller kontrolliert anhalten und Identität manuell klären. Zeitablauf rechtfertigt keine Löschung. |
| `LockIdentityUnavailable` | Windows-MachineGuid konnte nicht sicher gelesen werden. Umgebung/Identität durch zuständige Administration klären. |
| `RevisionConflict` | Gelesene Revision ist nicht mehr aktuell. Frisch lesen und Änderung fachlich neu anwenden. |
| `StoreRecoveryRequired` | Bestand fehlt, während Veröffentlichungsartefakte vorhanden sind. Caller anhalten, Dateien sichern und Revision manuell klären. |
| `InvalidStoredDocument` | Gespeicherte Bytes lassen sich nicht als striktes UTF-8 oder JSON decodieren. Der vorhandene Bestand wird nicht ersetzt; Dateien sichern und Ursache klären. |
| `PublishFailed` | Veröffentlichung schlug fehl; vorhandene Kandidaten/Backups sind Belege und bleiben erhalten. Ziel und Artefakte sichern und manuell klären. |
| `TemporaryCleanupFailed` | Veröffentlichung kann bereits erfolgreich sein, obwohl eigenes temporäres Material nicht entfernt werden konnte. Zuerst frisch lesen; gemeldete Datei als Beleg erhalten. |
| `StoreDirectoryMissing`, `UnsafeStorePath` | Ordner fehlt oder der geprüfte Pfad ist ein Reparse Point. Pfad korrigieren; nicht durch Umleiten auf ein anderes Ziel umgehen. |

Syntaktisch gültiges JSON kann dennoch gegen den WorkItem-Vertrag oder das
Schema verstoßen. Solche Validierungsfehler werden nicht zwingend als
`InvalidStoredDocument` verpackt: Der Validatorfehler kann direkt propagieren,
zum Beispiel `Schema const at $.schemaVersion`. Die QA-Triage zu #33 belegt
diesen Fehlerpfad beim Lesen und Schreiben für ein ungültiges `schemaVersion`;
beide Vorgänge lehnten den Inhalt ab und die Zielbytes blieben identisch. Das
ist ein Nachweis für diesen geprüften Fall, kein Reparatur- oder allgemeines
Recoveryversprechen. Weitere Validierungs- und Eingabefehler werden mit ihren
jeweiligen ErrorIds ausgegeben, etwa `ValidationFailed`, `ItemNotFound` oder
`DuplicateWorkItemId`. Meldung und Fehlerdetails protokollieren; vor einer
manuellen Korrektur den WorkItem-Vertrag prüfen.

## Recovery und manuelle Klärung

Temporäre `read`, `previous`, `candidate` und `replace-backup` Dateien sind
Belege. Dateiname und Alter beweisen weder Herkunft noch die richtige Revision.
Der Store wählt daraus nicht automatisch einen Replay- oder Rollback-Kandidaten
aus. Ein gültiger vorhandener Bestand bleibt maßgeblich; ein Backup wird nicht
automatisch über ihn zurückgespielt.

Wenn der Bestand fehlt und Veröffentlichungsartefakte vorhanden sind, oder wenn
der Bestand ungültig ist, keine Dateien löschen, verschieben, umbenennen,
veröffentlichen oder anhand des jüngsten Zeitstempels auswählen. Stoppe die
aufrufenden WorkItem-Caller geordnet, ohne fremde Prozesse zu beenden. Sichere
den vollständigen Datenordner einschließlich Lock- und Artefaktdateien als
Kopie und dokumentiere Pfade, Zeitpunkte, ErrorId sowie Hashes der gesicherten
Dateien. Lass Besitzeridentität und beabsichtigte Revision klären. Prüfe
Kandidaten vor einer ausdrücklich geplanten manuellen Wiederherstellung gegen
die bestehenden WorkItem-Verträge und gegebenenfalls Übergangsvalidierung.
Dokumentiere die gewählte Revision und mögliche verlorene Änderungen. Erst
nach Klärung und Sicherung darf eine verantwortliche Person die Wiederherstellung
manuell durchführen. Diese Anleitung autorisiert weder pauschales Löschen noch
das Beenden anderer Prozesse.

Nach einem Fehler oder einer ausgebliebenen Antwort stets über `Get-WorkItems`
frisch lesen. Ein vollständiger gültiger Zielbestand zeigt den derzeitigen
Commitzustand; vorhandene Sidecars bleiben separat zu sichern und zu klären.
Ein fehlender Bestand ohne Veröffentlichungsartefakte wird vom Leseaufruf als
`Exists = $false`, Revision `absent` gemeldet; `Get` legt ihn nicht an. Initiales
`New` nur dann ausführen, wenn tatsächlich noch kein Bestand erwartet wird.

## Grenzen und Nachweisstand

`Flush(true)` sowie der atomare Dateischritt sind keine Zusage gegen
Stromausfall, Controller-/Cacheverlust, Datenträgerkorruption oder einen
Neustart mitten im Dateisystemvorgang. Diese Anleitung verspricht keine
SMB-/Netz-, Cloud-, verteilte oder plattformübergreifende Nutzung. Verwende
kooperierende Caller auf demselben Windows-Host und einem lokalen NTFS-Ordner.

Die finalen QA-Ergebnisse und relative Reproduktionsbefehle sind in
[docs/story15-evidence/run-manifest.json](story15-evidence/run-manifest.json)
zusammengefasst; maschinenlesbare Ausführungs- und Quellenbelege liegen
daneben. Absolute TEMP-Pfade in den Ausführungsdaten sind historische Angaben
zu den damaligen Läufen. Die Übernahme der Belege ist keine erneute Ausführung
und keine Abnahme.

Für QA-Abschluss und Elternabnahme sind die vorgesehenen
[Story-15-Abnahmekriterien](STORY15-ACCEPTANCE.md) und
[Epic-6-Abnahmekriterien](EPIC6-ACCEPTANCE.md) maßgeblich. Die
Abnahmeentscheidung bleibt dem Teamleiter vorbehalten.
