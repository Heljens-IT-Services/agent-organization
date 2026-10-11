# Koordinator installieren und starten

## Lieferumfang

`roles/koordinator.toml` definiert den Koordinator mit den unterstützten Feldern
`name`, `description` und `developer_instructions`. Die persönliche Kopie unter
`~/.codex/agents/koordinator.toml` wird bytegleich installiert. Standalone
Agentenprofile konfigurieren gestartete Unteragenten; die Datei wählt nicht
automatisch die Rolle des Hauptchats.

`profiles/koordinator.config.toml` enthält dieselben Instruktionen als
zusätzliche `developer_instructions`. Die persönliche Kopie
`~/.codex/koordinator.config.toml` bildet den ausdrücklich auswählbaren
CLI-Hauptstart. Modell, Reasoning, Berechtigungen und andere bestehende
Einstellungen werden in diesem Profil nicht überschrieben.

Für neue lokale Hauptchats wurden dieselben Instruktionen zusätzlich als
einzelner Root-Key `developer_instructions` in der persönlichen `config.toml`
installiert. Dabei wurde vorher ein privates Backup unter `~/.codex/backups/`
angelegt. Alle anderen TOML-Werte und ursprünglichen Inhaltsbytes bleiben
erhalten. Das setzt keinen globalen Profil-Selector und ändert weder Modell
noch Berechtigungen. Persönliche Konfiguration und Backup werden nicht versioniert.

Die Beschränkung auf Koordination gilt für den Hauptchat. Ein Unteragent mit
einer explizit delegierten eigenen Rolle darf diese ausführen; Spezialisten
bleiben operativ. Instruktionen sind keine technische Tool-Sperre.

## Installation

Im Repository-Root mit Windows PowerShell ausführen:

```powershell
.\scripts\Install-Coordinator.ps1
```

Der Installer verwendet `CODEX_HOME`, wenn gesetzt, andernfalls das persönliche
`.codex`-Verzeichnis. Er erstellt nur die beiden beschriebenen Kopien. Bei
abweichenden vorhandenen Zieldateien stoppt er vor dem Kopieren; identische
Dateien werden wiederverwendet und per SHA-256 geprüft. `config.toml` und
persönliche `AGENTS.md` werden durch diesen Installer nicht verändert. Die
zusätzliche globale Instruktionsinstallation war ein gesondert autorisierter,
gezielter Schritt; der Installer wiederholt oder überschreibt sie nicht.

## Belegter CLI-Start und Grenze zum App-Hauptchat

```powershell
codex --profile koordinator
```

Der CLI-Start lädt die bestehende persönliche `config.toml` und darüber
`koordinator.config.toml`. Seit Codex 0.134.0 werden Profile aus solchen
separaten Dateien geladen; ein globaler `profile = "koordinator"`-Selector
ist nicht unterstützt. Dieser Start öffnet die CLI, kein eigenständiges
Codex-App-Fenster. Die Profilauswahl wird nicht automatisch auf einen bereits
laufenden App-Hauptchat übertragen.

Neue Konfigurationsdateien ändern die aktuelle Sitzung nicht rückwirkend.
Die globale Instruktionsbasis ist für neue lokale Sitzungen installiert. Das
Laden im konkreten App-Hauptchat muss nach neuem Chat beziehungsweise Neustart
separat durch einen tatsächlichen Laufzeitnachweis bestätigt werden. Lokales
Konfigurationsladen beweist keine Übernahme durch einen Cloud-Orchestrator.
Die Installation allein beweist keine vollständige Aktivierung in der App.

## Offene Bootstrap-Schritte

Die sieben Teamleiter und operativen Spezialisten sind noch nicht als Profile
implementiert. Fehlende Teamleiter werden als Bootstrap-Bedarf gemeldet;
ein operativer Hauptagent oder direkte Spezialistenbeauftragung sind keine
stille Ersatzlösung.

Die eigene sichtbare App-Fensterdarstellung vor jedem delegierten Auftrag und
das schadlose automatische Schließen nach Abschluss bleiben unimplementiert.
Der aktuelle Einrichtungsauftrag ist trotz dieser Lücke ausdrücklich autorisiert.
Für spätere normale Aufträge gilt die Fensterregel ohne pauschale Ausnahme.

## Rücknahme

Die beiden persönlichen Kopien können gezielt entfernt werden, sofern ihre
Hashes noch den installierten Quellen entsprechen. Vorhandene spätere Änderungen
dürfen nicht überschrieben oder gelöscht werden. Ohne Profilauswahl verwendet
die CLI ihre globale Konfiguration, die aktuell ebenfalls Koordinatorinstruktionen
enthält. Für vollständige Rücknahme ist zusätzlich ausschließlich der installierte
Root-Key `developer_instructions` aus der persönlichen `config.toml` zu entfernen.
Das private Backup dokumentiert den Vorzustand; bei späteren Konfigurationsänderungen
darf es nicht blind über die aktuelle Datei kopiert werden. Historie und Ergebnisse
bleiben erhalten.

## Quellen

- [OpenAI Docs: Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents#custom-agents): standalone Agenten und ihre Pflichtfelder.
- [OpenAI Docs: Profiles](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles): separate Profil-Dateien und CLI-Auswahl.
- [OpenAI Docs: Configuration Reference](https://learn.chatgpt.com/docs/config-file/config-reference): zusätzliche `developer_instructions`.

Lokal geprüft: Codex CLI 0.162.1. Die CLI-Hilfe beschreibt `--profile` als Layer
`$CODEX_HOME/<name>.config.toml` oberhalb der Benutzerkonfiguration.
`codex debug prompt-input` bestätigte die globalen Instruktionen und
`codex --profile koordinator debug prompt-input` das zusätzliche Profil ohne
Modellturn. Das sind lokale Ladebelege, kein App-Neuchat-Funktionsnachweis.
