# Dependabot-Leitplanke

[MUST_IF] Ein Repository npm-, NuGet-, Docker-, Docker-Compose- oder GitHub-Actions-Abhängigkeiten nutzt, muss `.github/dependabot.yml` diese Quellen abdecken.

[MUST] Ökosysteme und Verzeichnisse müssen vor der Konfiguration aus dem Repository abgeleitet und danach verifiziert werden. Vorhandene spezifischere Konfigurationen dürfen nur bei nachgewiesenen Lücken geändert werden.

[MUST] Jeder `updates`-Eintrag benötigt einen sinnvollen Zeitplan, `Europe/Berlin` und ein `open-pull-requests-limit`. Gruppen, Cooldowns sowie die Trennung von Major-Updates sind nach Bedarf zu verwenden.

[MUST] Die YAML-Syntax und die abgedeckten sowie bewusst ausgelassenen Bereiche müssen nach jeder Änderung dokumentiert geprüft werden.
