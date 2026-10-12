# Skillvertrag v1 (Task60)

Normativ: [Registry-Schema](../../schemas/skills.schema.json) und
[Antwortschema](../../schemas/skill-response.schema.json). Dies definiert einen
Vertrag, keine produktive Registry und keinen Runner.

Die Registryform ist `{"schemaVersion":"1.0","skills":[]}`. Ein Eintrag hat
die Pflichtfelder `id`, `purpose`, `scriptPath`, `parameters`, `result` und
`prerequisites`; weitere Felder ausser `language` und `interpreter` sind verboten.
IDs folgen dem vorhandenen Pattern `^[a-z0-9][a-z0-9_-]{0,127}$` und sind
innerhalb der Registry eindeutig. `purpose` beschreibt den fachlichen Zweck.

`scriptPath` verwendet repo-relative Pfade mit `/`, ohne absolute Pfade,
Rootausbruch oder Reparsepunkte; Ziel muss eine vorhandene Datei sein.
Markdown und reine Daten sind kein ausfuehrbarer Skill. Bei den bekannten
Kennungen powershell/python/javascript prueft der fokussierte Test die
Endung .ps1/.py/.js. Andere Sprachen bleiben offene Kennungen; fuer sie wird
keine universelle Endungs- oder Ausfuehrbarkeitsgarantie behauptet.

Fehlende `language` bedeutet `powershell`; fehlender Interpreter fuer PowerShell
bedeutet konventionell `powershell.exe`. Das Schema injiziert keine Defaults.
Alternative Sprachen verlangen einen expliziten Interpreter. `interpreter` ist
ein einzelner Executable-Name oder Pfad ohne Argumente, Leerzeichen oder
Shelloperatoren, niemals ein Shellkommandostring. Verfuegbarkeit, Kompatibilitaet
und tatsaechliche Ausfuehrung bleiben Aufgaben einer spaeteren Laufzeitpruefung.

`parameters` ist eine Liste mit eindeutigen `name`-IDs, `type` und Boolean
`required`; optional sind `description` und `default`. Typen sind die JSON-Typen
null, boolean, integer, number, string, object und array. Ein Default muss zum
deklarierten Typ passen; null passt nur zum Typ null. `required` bedeutet, dass
ein Wert vorhanden sein muss; ein passender Default kann diesen Wert liefern.
Es gibt keine Business-Typen oder Sprachallowlist. `result` in den Metadaten
ist eine Vertragsbeschreibung mit Pflichtfeld `description`; optionale
`parameterRefs` verweisen eindeutig und case-sensitiv auf deklarierte Namen.
Dies definiert keine Bindungs-/Ausfuehrungslogik und kein Nutzlastschema.
`prerequisites` ist eine Liste nichtleerer, eindeutiger Beschreibungen von
Voraussetzungen; eine leere Liste ist erlaubt.

Eine Standardantwort ist genau ein JSON-Objekt mit **genau** drei
case-sensitiven Top-Level-Feldern: `isSuccessful` (Boolean), `exception`
(Objekt oder null) und `result` (beliebiger JSON-Wert, auch null).
Bei Erfolg ist exception null. Bei Fehler ist exception ein Objekt mit
nichtleerer, nicht nur aus Leerraum bestehender String-`message`;
weitere exception-Felder sind erlaubt. Auch bei Fehler darf result jeden
JSON-Wert enthalten. Die originalen Issue60-Beispiele werden getestet:

```json
{"isSuccessful":true,"exception":null,"result":{"items":[1,2,3]}}
```

```json
{"isSuccessful":false,"exception":{"message":"Ungültige Eingabe"},"result":null}
```

Stdout enthaelt genau dieses eine JSON-Dokument, ohne Freitext/Progress/Logs.
Diagnostik gehoert auf stderr oder in getrennte Logs. Das Schema validiert die
geparste Struktur; die fokussierte Testfunktion prueft zusaetzlich den Text.
Sie weist doppelte case-sensitive Top-Level-Namen vor Parsernormalisierung
ab, einschliesslich aequivalenter Unicode-Escapes. Verschachtelte result-Namen
unterliegen keiner neuen Eindeutigkeitsregel. Syntaktisch gueltige JSON-Zahlen
wie `1e400` sind auch verschachtelt erlaubt; es gibt keine Zahlenbereichsgrenze.
Die [Runnerfehlervorlage](../task60-evidence/runner-error.json) ist ausschliesslich
Daten: `code: RunnerError`, message und result null. Ihre spaetere Erzeugung bei
Runner-/Parserfehlern ist hier nicht implementiert.

Eine native Codex `SKILL.md` beschreibt Anweisungen und ggf. Hilfsdateien.
Sie ist nicht automatisch ein Skill nach diesem Vertrag: erst ein Metadatensatz
mit vorhandener Skriptdatei und definiertem Antwortvertrag erfuellt die Form.

Pruefung: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File
scripts/tests/contracts/Test-SkillContracts.ps1`. Wiederverwendet wird ausschliesslich der
vorhandene ContractValidation-Helfer plus eng fokussierte Skill-Invarianten.
Der fokussierte Test verwendet vorhandenes Node/native `JSON.parse` als
Standard-JSON-Syntaxwerkzeug, ohne Paketinstallation oder neue Projekt- oder
Plattformabhaengigkeit. Node muss fuer diesen Test verfuegbar sein. PS5-Parser
koennen `1e400` nicht darstellen. Daher wird nach Syntaxpruefung result fuer
die Schemahelferpruefung durch null ersetzt (sein Schema ist leer); sonstige
Zahlen werden zu numerischen Platzhaltern, ohne Typaenderung. Das prueft
Syntax und Antwortsemantik, belegt aber keine verlustfreie Nutzlastkonvertierung.
Die temporaere JavaScript-Fixture wird mit `node --check` auf Syntax geprueft;
Python enthaelt minimalen Quelltext; Managed Python 3.13.15 ist bestaetigt.
Die externe Python-Syntaxkompilierung besteht, ohne Skill-Ausfuehrung.
Beide Draft2020-12-Metaschemas bestehen mit jsonschema 4.25.1, ausschliesslich
im isolierten externen Temp-/uv-Cache; keine Projektruntimeabhaengigkeit.
Einzelbelege: [QA-Review](../task60-evidence/qa-review.json).
Dateiexistenz und Metadatenvaliditaet belegen keine Interpreterverfuegbarkeit,
fachliche Skriptkorrektheit oder erfolgreiche Laufzeitausfuehrung.
