# Skill: GitHub PR Erstellen

## Zweck

Einen vorhandenen Pull Request wiederverwenden oder einen neuen Pull Request mit passendem Titel, Body, Base und Head in GitHub erstellen.

## Verwenden

- Wenn ein gepushter Branch als Pull Request bereitgestellt werden soll.
- Wenn Reviewer Kontext, Änderung, Tests und Risiken schnell verstehen müssen.
- Nicht verwenden, wenn Commit und Push noch fehlen. Dann den Workflow `commit-push.md` nutzen.

## Vorgehen

1. Aktuellen Branch, Remote, Base-Branch und Push-Status prüfen.
2. Base-Branch nach Priorität bestimmen: User-Vorgabe, Workflow-/Issue-Vorgabe, eindeutiger Upstream-/Tracking-Kontext, Remote-Default, `develop`, `main`, `master`.
3. Ziel, Ausgangsproblem und verknüpfte Issues aus vorhandenem Kontext bestimmen.
4. Commits und relevanten Diff-Kontext lesen.
5. Bestehende offene Pull Requests für den aktuellen Branch suchen.
6. Wenn ein offener PR für den Branch existiert, bei zusätzlichem Kontext einen Kommentar ergänzen, einen vorhandenen Draft bei ausdrücklicher Anweisung als Ready markieren, die PR-URL melden und die Erstellung beenden.
7. Wenn kein offener PR existiert, PR-Titel und Body mit Issue-Verknüpfungen formulieren.
8. Teststatus, Risiken und Review-Hinweise nennen.
9. Pull Request standardmäßig als Draft, bei ausdrücklicher Ready-for-Review-Anweisung direkt als Ready erstellen.
10. Mehrzeilige Texte gemäß [Texttransport und Inhaltsprüfung](#texttransport-und-inhaltsprüfung) vorbereiten und übergeben.
11. Den auf GitHub gespeicherten Body beziehungsweise Kommentar zurücklesen und den ordinalen Soll-/Ist-Vergleich erst erfolgreich melden, wenn keine Abweichung besteht.
12. Pull Request mit URL, Base, Head und Draft-/Ready-Status sowie dem bestätigten Formatierungsstatus ausgeben.

## Texttransport und Inhaltsprüfung

Mehrzeilige PR-Bodies und PR-Kommentare müssen über `--body-file <pfad>` übergeben werden. Die lokale Datei wird ausdrücklich als UTF-8 ohne BOM geschrieben; Markdown-Backticks, Backslashes, Umlaute und `ß` bleiben dabei Bestandteil des Solltexts. Inline-`--body` ist für mehrzeilige Markdown-Texte kein Standardweg.

```powershell
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gh-pr-body-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $body = @'
## Änderung

- Umlaute: äöü ÄÖÜ
- Sonderzeichen: ß
- Backtick: `gh pr view`
- Backslash: C:\temp\body.md
'@

    $bodyPath = Join-Path $tempRoot "body.md"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($bodyPath, $body, $utf8NoBom)

    Assert-TransportText $body "Solltext"
    gh pr create --draft --title $title --body-file $bodyPath --base $base --head $head
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
```

`--body-file -` darf nur verwendet werden, wenn die konkrete Agent-Laufzeit den stdin-Transport nachweislich unverändert überträgt: UTF-8, Umlaute, `ß`, Backticks, Backslashes und den Textanfang ohne BOM. Die Laufzeit muss diesen Nachweis mit einem repräsentativen mehrzeiligen Testtext führen; andernfalls ist eine temporäre Body-Datei zu verwenden. Temporäre Dateien dürfen keine Secrets enthalten, müssen auf einen eng begrenzten temporären Ordner beschränkt und im `finally`-Pfad bereinigt werden.

Vor der Mutation ist der Solltext zu prüfen. Zulässig sind nur normale Unicode-Zeichen sowie CR und LF als Zeilenenden. Tabs und sonstige Steuerzeichen, ein führendes BOM (`U+FEFF`) und unbeabsichtigte literale Escape-Sequenzen wie `\n`, `\r` oder `\t` müssen als Abweichung sichtbar gemeldet werden. Ein solches Muster ist nur dann zulässig, wenn es im erwarteten Solltext selbst enthalten ist.

Nach jeder PR-Erstellung oder anderweitig autorisierten Body-Änderung wird der tatsächlich gespeicherte Inhalt zurückgelesen. Kommentare werden über die von `gh pr comment` zurückgegebene `issuecomment`-URL beziehungsweise deren Kommentar-ID gelesen. Der Vergleich wird ausschließlich durch kontrollierte CRLF-zu-LF-Normalisierung vorbereitet und danach ordinal ausgeführt: kein Trimmen, keine Leerraum-, Unicode- oder Escape-Normalisierung.

```powershell
function Normalize-LineEndings([string] $text) {
    return $text.Replace("`r`n", "`n")
}

function Get-TextDiagnostics([string] $text) {
    $diagnostics = @()
    if ($text.IndexOf([char]0xFEFF) -ge 0) {
        $diagnostics += "BOM U+FEFF erkannt"
    }
    for ($index = 0; $index -lt $text.Length; $index++) {
        $codePoint = [int][char]$text[$index]
        $isDisallowedControl = ($codePoint -lt 0x20 -and $codePoint -ne 0x0A -and $codePoint -ne 0x0D) -or ($codePoint -ge 0x7F -and $codePoint -le 0x9F)
        if ($isDisallowedControl) {
            $diagnostics += ("unzulässiges Steuerzeichen U+{0:X4} an Position {1}" -f $codePoint, $index)
        }
    }
    return $diagnostics
}

function Assert-TransportText([string] $text, [string] $kind) {
    $diagnostics = Get-TextDiagnostics $text
    if ($diagnostics.Count -gt 0) {
        throw ("$kind enthält unzulässige Zeichen: " + ($diagnostics -join "; "))
    }
}

function Assert-ExactGithubText([string] $expected, [string] $actual, [string] $kind) {
    Assert-TransportText $expected "Solltext"
    Assert-TransportText $actual "Isttext"
    $expectedNormalized = Normalize-LineEndings $expected
    $actualNormalized = Normalize-LineEndings $actual
    if ([string]::Equals($expectedNormalized, $actualNormalized, [System.StringComparison]::Ordinal)) {
        return
    }

    $unexpectedEscapes = @('\n', '\r', '\t') | Where-Object {
        $actualNormalized.Contains($_) -and -not $expectedNormalized.Contains($_)
    }
    $diagnostics = @("$kind stimmt nach ausschließlicher CRLF-zu-LF-Normalisierung nicht ordinal mit dem Solltext überein")
    if ($actualNormalized.StartsWith([string][char]0xFEFF)) {
        $diagnostics += "führendes BOM U+FEFF erkannt"
    }
    if ($unexpectedEscapes) {
        $diagnostics += "unerwartete literale Escape-Sequenzen: $($unexpectedEscapes -join ', ')"
    }
    $expectedBackslashes = [regex]::Matches($expectedNormalized, '\\').Count
    $actualBackslashes = [regex]::Matches($actualNormalized, '\\').Count
    if ($expectedBackslashes -ne $actualBackslashes) {
        $diagnostics += "unerwartete Backslash-Artefakte: Soll $expectedBackslashes, Ist $actualBackslashes"
    }
    $missingNonAscii = @($expectedNormalized.ToCharArray() | Where-Object {
        [int][char]$_ -gt 0x7F -and -not $actualNormalized.Contains([string]$_)
    } | Select-Object -Unique)
    if ($missingNonAscii) {
        $diagnostics += "möglicher Encoding-Verlust bei Nicht-ASCII-Zeichen: $($missingNonAscii -join ', ')"
    }
    $diagnostics += "Backslash-, Encoding- oder Steuerzeichen-Artefakte sind im Isttext gegen den Solltext zu prüfen"
    throw ($diagnostics -join "; ")
}

Assert-TransportText $body "Solltext"
$actualBody = [string](gh pr view $prNumber --json body | ConvertFrom-Json).body
Assert-ExactGithubText $body $actualBody "PR-Body"
```

Für einen Kommentar wird nach dem Aufruf die zurückgegebene URL auf `#issuecomment-<id>` geprüft und der gespeicherte Text mit `gh api repos/$owner/$repo/issues/comments/<id> --jq .body` gelesen. Erst wenn dieser Vergleich erfolgreich ist, darf die Verifikation als bestanden ausgegeben werden. Bei Abweichungen sind mindestens Soll-/Iststatus, erkannte Escape-Sequenzen, BOM, Encoding-Verlust beziehungsweise unzulässige Steuerzeichen sichtbar zu melden; ein erfolgreicher Exitcode allein ist kein Nachweis.

```powershell
$commentUrl = gh pr comment $prNumber --body-file $commentPath
if ($commentUrl.Trim() -notmatch '#issuecomment-(?<commentId>\d+)$') {
    throw "gh pr comment hat keine auswertbare issuecomment-URL zurückgegeben"
}
$actualComment = [string](gh api "repos/$owner/$repo/issues/comments/$($Matches.commentId)" --jq .body)
Assert-ExactGithubText $comment $actualComment "PR-Kommentar"
```

## Issue-Verknüpfungen

- Ein einzelnes primäres Issue mit `Closes #<nummer>` verknüpfen, wenn der Pull Request dieses Issue vollständig abschließt; andernfalls `Refs #<nummer>` verwenden.
- Wenn ein vorgelagerter Workflow mehrere Issues als durch denselben Pull Request vollständig abgeschlossen bestätigt, darf und soll für jedes dieser Issues eine eigene `Closes #<nummer>`-Verknüpfung gesetzt werden.
- Nicht vollständig abgeschlossene, nur kontextuelle, extern blockierte oder lediglich verwandte Issues mit `Refs #<nummer>` oder normalem Kontext verlinken, sofern sie für Review oder Merge relevant sind.
- Bei `issue-graph-implementation.md` ausschließlich den final bestätigten Scope aus dessen Abschlussphase verwenden. Den gelesenen Rohgraphen nicht automatisch als Closure-Liste übernehmen.

## Kommandos

```text
git status --short --branch
git branch --show-current
git log --oneline --decorate origin/<base-branch>..HEAD
git diff --stat origin/<base-branch>...HEAD
gh issue view <issue-number> --comments
gh pr list --head <branch-name> --state open
gh pr comment <pr-nummer> --body-file <kommentar-pfad>
gh pr create --draft --title "<pr-titel>" --body-file <pr-body-pfad> --base <basis-branch> --head <branch-name>
gh pr create --title "<pr-titel>" --body-file <pr-body-pfad> --base <basis-branch> --head <branch-name>
gh pr ready <pr-nummer>
gh pr view --json title,body,state,isDraft,url,baseRefName,headRefName
```

Platzhalter aus aktuellem Branch, Remote-Default, verknüpften Issues und PR-Kontext ableiten.

## Grenzen

- Extern wirksam arbeiten: Pull Request wird tatsächlich erstellt.
- Keine lokalen Git-Mutationen ausführen. Das gehört zum Workflow `commit-push.md`.
- Keine Codeänderungen vornehmen.
- Keine Tests oder Diff-Reviews ersetzen.
- Kein Changelog-Ersatz schreiben.
- PR nur erstellen, wenn Branch gepusht ist und Base/Head eindeutig sind.
- Wenn Base-Branch nach Prioritätenliste unklar bleibt, nachfragen.
- Bestehenden PR-Titel oder PR-Body nicht aktualisieren.
- Bei zusätzlichem Kontext zum bestehenden PR einen Kommentar ergänzen.
- Vorhandene Issue-Kontexte immer im PR-Body verlinken.
- `Closes` nur für Issues verwenden, deren vollständiger Abschluss durch den aktuellen PR aus dem vorhandenen Workflow-Kontext eindeutig bestätigt ist.
- Parent-, Sub-, Blocked- oder Related-Issues nur verlinken, wenn sie für Scope, Review oder Merge relevant sind.
- Keinen irrelevanten Issue-Graph in den PR-Body aufnehmen.
- Reviewer, Assignees oder Labels nur setzen, wenn der User es explizit verlangt.

## Output

- PR-Titel
- PR-Beschreibung
- PR-URL
- Draft-/Ready-Status
- Base-Branch und Head-Branch
- Teststatus
- bestätigter Transport- und Inhaltsvergleich für jeden PR-Body und Kommentar
- Risiken oder Review-Hinweise
- gesetzte Reviewer, Assignees oder Labels, falls explizit verlangt

## Qualitätskriterien

- Motivation, Änderung und Verifikation müssen erkennbar sein.
- Risiken und Testlücken nicht verstecken.
- PR-Titel muss Review-Scope knapp beschreiben.
- PR-Body muss keine Commit-Liste duplizieren.
- Closure-Verknüpfungen müssen den tatsächlich abgeschlossenen Scope widerspiegeln.
- Mehrzeilige Bodies und Kommentare werden über `--body-file` oder eine nachgewiesen sichere stdin-Variante übergeben.
- Der gespeicherte PR-Body beziehungsweise Kommentar wird nach jeder Mutation zurückgelesen und ordinal gegen den Solltext verglichen; ausschließlich CRLF wird zu LF normalisiert.
- Literale Escape-Sequenzen, Backslash-/Encoding-Artefakte, BOM und unzulässige Steuerzeichen werden als sichtbare Abweichung erkannt.
- Ein repräsentativer Markdown-Text mit Überschriften, Leerzeilen, Listen, Backticks, Backslashes, Umlauten und `ß` bleibt unverändert erhalten.
