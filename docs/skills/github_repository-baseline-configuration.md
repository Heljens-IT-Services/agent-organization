# Skill: GitHub Repository-Basiskonfiguration

## Zweck

Die GitHub-Basiskonfiguration eines Repositorys kontrolliert gegen die zentralen Heljens-Referenzen prüfen und innerhalb eines erlaubten Repository-Pflegeauftrags gezielt ergänzen oder korrigieren.

## Verwenden

- Wenn ein Repository für GitHub-Basiskonfiguration gepflegt wird.
- Wenn `.github/ISSUE_TEMPLATE` fehlt, unvollständig ist oder gegen den kanonischen Heljens-Satz geprüft werden soll.
- Wenn eine fehlende oder unvollständige `.github/dependabot.yml` aus dem tatsächlichen Repository-Bestand abgeleitet werden soll.
- Wenn der projektbezogene Codex-Sollbestand unter `.codex/agents/` geprüft oder innerhalb eines erlaubten Repository-Pflegeauftrags ergänzt werden soll.
- Nicht verwenden, wenn nur ein einzelnes GitHub-Issue erstellt wird und keine Repository-Pflege erlaubt ist.

## Vorgehen

1. Prüfen, dass der Auftrag Änderungen an der Repository-Basiskonfiguration erlaubt.
2. Den Sollbestand aus der [kanonischen Template-Referenz](https://heljens-it-services.github.io/agent-organization/github/ISSUE_TEMPLATES.md) bestimmen: `bug.yml`, `config.yml`, `epic.yml`, `refactor.yml`, `story.yml`, `task.yml`.
3. `.github/ISSUE_TEMPLATE` einschließlich aller vorhandenen Dateien inventarisieren und jeden Sollbestand inhaltlich mit der kanonischen Quelle vergleichen.
4. Fehlende Dateien unverändert aus der kanonischen Quelle ergänzen.
5. Abweichende vorhandene Dateien sichtbar machen. Sie nur ersetzen, wenn die verbindliche zentrale Leitplanke die Korrektur verlangt und der Auftrag Repository-Pflege umfasst; sonst Rückfrage halten.
6. Nach der Änderung Dateinamen, Inhalte und YAML-Syntax erneut prüfen. Zusätzliche, nicht kanonische Dateien nur dann entfernen, wenn der Auftrag dies ausdrücklich umfasst.
7. Ergebnis mit erkannten Abweichungen, ergänzten oder korrigierten Dateien sowie bewusst unveränderten Dateien kompakt dokumentieren.

## Kommandos

```powershell
Get-ChildItem .github/ISSUE_TEMPLATE -File
Get-FileHash .github/ISSUE_TEMPLATE/<template-datei> -Algorithm SHA1
Get-Content .github/ISSUE_TEMPLATE/<template-datei>
git diff --check
```

## Grenzen

- Repository-Dateien nur ändern, wenn der Auftrag die Repository-Pflege erlaubt.
- Keine abweichenden vorhandenen Templates stillschweigend überschreiben.
- Keine GitHub-Issues, Labels, nativen Issue-Types oder Relationships pflegen.
- Den Sollbestand ausschließlich aus der zentralen Referenz ableiten, nicht aus einer lokalen Variante oder einer einzelnen Fremdquelle.
- Fehlende Rechte, nicht erreichbare zentrale Referenz oder nicht prüfbare YAML-Syntax als Blocker melden.

## Output

- erkannter Soll- und Istbestand
- ergänzte oder korrigierte Dateien
- bewusst unveränderte Abweichungen mit Grund
- Ergebnis der Inhalts- und YAML-Prüfung

## Qualitätskriterien

- Der vollständige kanonische Satz wird geprüft, nicht nur die für ein aktuelles Issue gewählte Form.
- Jede Mutation wird durch einen erneuten Inhalts- und Bestandsabgleich nachgewiesen.
- Issue-Erstellung und Repository-Pflege bleiben getrennte, konsistente Aufgaben.

## Codex-Custom-Agents

### Vorgehen

1. Den vom Koordinator ausgewählten Sollbestand mit Rollen-IDs, Zielpfaden und Referenzquellen übernehmen. Fehlende Auswahl oder Freigaben dem Koordinator melden.
2. Vorhandene Dateien inventarisieren und nur ausdrücklich ausgewählte fehlende Vorlagen unter `.codex/agents/<role-id>.toml` ergänzen. Die Vorlagen werden als Konfigurationsdaten geprüft; die ausführende Rolle behält ihren zugewiesenen Kontext.
3. Bestehende abweichende Dateien als Konflikt melden. Ersetzen oder Entfernen braucht eine ausdrückliche Freigabe für die betroffenen Dateien.
4. Für jede ausgewählte Vorlage Pflichtfelder, Rollen-ID, TOML-Syntax und Verweise auf die mitgelieferte Rollenquelle prüfen.
5. Ergebniszustand mit ausgewähltem Sollbestand erneut vergleichen und Änderungen sowie offene Konflikte zurückgeben.

### Grenzen

- Der ausgewählte Sollbestand und die ausdrückliche Freigabe bestimmen den Änderungsumfang.
- Zusätzliche projektbezogene Agent-Dateien bleiben erhalten, solange ihre Änderung nicht ausdrücklich beauftragt ist.

### Ergebnis

- ausgewählter Sollbestand und tatsächlich vorhandene Vorlagen
- ergänzte Dateien und unveränderte Konflikte mit Begründung
- Ergebnis des Inhalts-, Syntax- und Bestandsabgleichs

## Dependabot-Konfiguration

### Vorgehen

1. Zuerst die [Dependabot-Leitplanke](https://heljens-it-services.github.io/agent-organization/github/DEPENDABOT.md) lesen und prüfen, dass der Auftrag die Pflege der `.github/dependabot.yml` erlaubt.
2. Alle relevanten Paket- und Infrastrukturquellen inventarisieren: `package.json` und Lockfiles, Paketverweise in .NET-Projekten oder zentralen Paketdateien, `Dockerfile`, Compose-Dateien sowie Workflows unter `.github/workflows`.
3. Pro tatsächlichem Ökosystem die zugehörigen Verzeichnisse aus den gefundenen Dateien ableiten. Multi-Directory-, Monorepo- und Multi-Solution-Strukturen vollständig berücksichtigen.
4. Eine vorhandene `.github/dependabot.yml` vor jeder Mutation lesen: ihre Ökosysteme, Verzeichnisse, Zeitpläne, Zeitzonen, Limits, Gruppen und Cooldowns gegen den Inventarbestand prüfen.
5. Fehlt die Konfiguration, nur für nachgewiesene Ökosysteme ein passendes `updates`-Profil erzeugen. Fehlende Einträge einer vorhandenen Konfiguration gezielt ergänzen; vorhandene spezifischere Einträge nur bei belegter Inkonsistenz ändern.
6. Für jeden neuen oder geänderten Eintrag einen sinnvollen Zeitplan, `Europe/Berlin`, ein bewusstes PR-Limit sowie bei Bedarf Gruppen oder Cooldowns festlegen. Major-Updates und zusammengehörige Framework-Pakete bewusst behandeln.
7. Nach der Mutation YAML-Syntax, jeden konfigurierten Verzeichniswert und die Vollständigkeit gegen den Inventarbestand erneut prüfen.
8. Ergebnis kompakt dokumentieren: erkannte Ökosysteme, abgedeckte Verzeichnisse, bewusst nicht konfigurierte Bereiche und Abweichungen vom einfachen Profil.

### Kommandos

```powershell
Get-ChildItem -Recurse -File | Where-Object { $_.Name -in @('package.json', 'package-lock.json', 'npm-shrinkwrap.json', 'Directory.Packages.props') -or $_.Extension -in @('.csproj', '.fsproj') -or $_.Name -like 'Dockerfile*' -or $_.Name -match '(docker-)?compose.*\.ya?ml$' }
Get-ChildItem .github/workflows -File
Get-Content .github/dependabot.yml
git diff --check
```

### Grenzen

- Keine `.github/dependabot.yml` erzeugen, bevor Ökosysteme und Verzeichnisse aus dem Repository gelesen wurden.
- Keine vorhandene spezifischere Konfiguration ohne belegte Lücke oder Inkonsistenz vereinfachen oder überschreiben.
- Keine nicht vorhandenen Ökosysteme oder Verzeichnisse konfigurieren.
- Bei nicht prüfbarer YAML-Syntax oder mehrdeutiger Repository-Topologie vor der Mutation stoppen und den Blocker nennen.

