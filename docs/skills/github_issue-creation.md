# Skill: GitHub Issue Erstellen

## Zweck

Aus vorhandenem Kontext ein strukturiertes GitHub-Issue erstellen.

## Verwenden

- Wenn ein neues GitHub-Issue aus belastbarem Kontext erstellt werden soll.
- Nicht verwenden, wenn Anforderungen oder Scope erst geklärt werden müssen. Dann `requirements-clarification` nutzen.
- Nicht verwenden, um den nativen Issue-Type oder Relationships zu setzen. Dafür `type-setting` bzw. `relationship-setting` nachlagern.

## Vorgehen

1. Repository, Ziel und zugrundeliegenden Kontext prüfen.
2. Vorhandene Templates aus `.github/ISSUE_TEMPLATE` lesen und das passende Template bestimmen. Fehlt der kanonische Satz oder ist er unvollständig, die Abweichung dem Koordinator melden. Eine beauftragte Repository-Pflege wird separat erledigt; andernfalls die Standardstruktur verwenden.
3. Gezielte Suche nach offenen Duplikaten oder sehr ähnlichen Issues durchführen.
4. Bei einem möglichen Duplikat die Alternativen benennen und die über den Koordinator vermittelte User-Entscheidung abwarten.
5. Titel und Body aus dem vorhandenen Kontext formulieren; bei fehlendem Template mindestens Problem, Ziel, Scope, Nicht-Ziele und Akzeptanzkriterien abbilden.
6. Den zugewiesenen fachlichen oder technischen Issue-Scope und Inhalt klar ausweisen. Stories und Epics verwenden die tatsächlich vorhandenen nativen Typen `Story` und `Epic`; neue Issue-Type-IDs dürfen nicht erfunden werden.
7. Technical Tasks einschließlich Erstellung und späterer beauftragter Inhalts-, Type- und Relationship-Mutationen gehören zu `softwareentwicklung_architektur`; User-Tasks bleiben bei `product_owner` und übernehmen technische Pläne nur aus dem Architekturbeitrag. Bei einem Task den [kanonischen Task-Issue-Vertrag](../github/ISSUE_TEMPLATES.md#task-issue-vertrag) vollständig abbilden. Fehlende wesentliche Entscheidungen nicht erfinden; den Task stattdessen als nicht terminal kennzeichnen und die fehlende Klärung benennen.
8. Issue erstellen und Ergebnis lesen.

## Kommandos

```powershell
Get-ChildItem .github/ISSUE_TEMPLATE -File
Get-Content .github/ISSUE_TEMPLATE/<template-datei>
gh issue list --search "<suchbegriff>" --state open
gh issue create --title "<titel>" --body-file <body-datei>
gh issue view <issue-number> --json id,number,title,url
```

## Grenzen

- Extern wirksam arbeiten: Das Issue wird tatsächlich erstellt.
- Keine Anforderungen, Metadaten oder Beziehungen erfinden.
- Einen Task nicht als terminal darstellen, solange sein technischer Ausführungsplan wesentliche offene Entscheidungen enthält.
- Bei möglichem Duplikat nicht ohne User-Entscheidung erstellen.
- Bestehende Issues nur nach expliziter User-Anweisung aktualisieren oder schließen.
- Keine Repository-Basiskonfiguration ändern, wenn der aktuelle Auftrag Repository-Pflege oder entsprechende Änderungen nicht erlaubt.
- Labels nur setzen, wenn der User oder das verwendete Template sie explizit vorgibt.
- Fehlende Authentifizierung, Repository-Zuordnung oder Rechte als Blocker melden.

## Output

- Issue-Titel und URL
- verwendetes Template oder Standardstruktur
- sichtbare Kontextlücken

## Qualitätskriterien

- Issue-Body entspricht dem Template oder der definierten Standardstruktur.
- Ein terminaler Task erfüllt den kanonischen Task-Issue-Vertrag.
- Kontextlücken werden nicht erfunden oder versteckt.
- Ein mögliches Duplikat wird vor der Erstellung geklärt.

