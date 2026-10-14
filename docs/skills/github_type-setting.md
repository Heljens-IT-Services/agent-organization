# Skill: GitHub Type Setzen

## Zweck

Den nativen GitHub-Issue-Type eines bestehenden Issues gezielt setzen oder ändern.

## Verwenden

- Wenn für ein bestehendes GitHub-Issue der native Issue-Type gesetzt werden soll.
- Wenn `Task`, `Story`, `Spike`, `Epic` oder ein anderer in der Organisation vorhandener Issue-Type nachträglich gesetzt werden muss.
- Wenn klar ist, welche Organisation, welches Repository, welche Issue-Nummer und welcher Type-Name gemeint sind.
- Für den ausdrücklich zugewiesenen fachlichen oder technischen Issue-Scope. Verwende ausschließlich die in der Organisation tatsächlich vorhandenen nativen Types; technische Stories und Epics verwenden weiterhin `Story` und `Epic`.
- Nicht verwenden, um Labels zu setzen. GitHub-Issue-Type ist kein Label.
- Nicht verwenden, um Relationships zu setzen. Dann `relationship-setting` nutzen.

## Vorgehen

1. Organisation, Repository, Issue-Nummer und gewünschten Type-Namen bestimmen.
2. GitHub-Authentifizierung und Repository-Zugriff prüfen.
3. Issue-ID des Ziel-Issues lesen.
4. Verfügbare Issue-Types der Organisation lesen.
5. Issue-Type-ID anhand des Type-Namens eindeutig bestimmen.
6. Native GitHub-Mutation `updateIssueIssueType` ausführen.
7. Ergebnis lesen und prüfen, ob der native Issue-Type gesetzt ist.

## Kommandos

Issue-ID lesen:

```powershell
$issueId = gh issue view <issue-number> --repo <org>/<repo> --json id --jq .id
```

Verfügbare Issue-Types der Organisation lesen:

```powershell
gh api orgs/<org>/issue-types
$issueTypeId = gh api orgs/<org>/issue-types --jq '.[] | select(.name == "<issue-type>") | .node_id'
```

Native GitHub-Issue-Type-Mutation ausführen:

```powershell
gh api graphql `
  -f issueId="$issueId" `
  -f issueTypeId="$issueTypeId" `
  -f query='mutation($issueId:ID!, $issueTypeId:ID!) { updateIssueIssueType(input: { issueId: $issueId, issueTypeId: $issueTypeId }) { issue { number issueType { name } } } }'
```

Ergebnis prüfen:

```powershell
gh issue view <issue-number> --repo <org>/<repo> --json number,title,issueType,url
```

Platzhalter:

- `<org>`: GitHub-Organisation, z. B. `Heljens-IT-Services`.
- `<repo>`: Repository-Name ohne Organisation.
- `<issue-number>`: Nummer des bestehenden Issues.
- `<issue-type>`: exakt vorhandener nativer GitHub-Issue-Type-Name.

## Grenzen

- Extern wirksam arbeiten: Der native GitHub-Issue-Type wird tatsächlich in GitHub gesetzt.
- Keine Labels, Relationships oder Issues erstellen bzw. pflegen.
- Organisation, Repository, Issue und Type müssen eindeutig sein; andernfalls nachfragen.
- Fehlende GitHub-Authentifizierung, fehlende Rechte, unbekannte Issue-Types oder fehlende Repository-Zuordnung als Blocker melden.
- Wenn der Type-Name mehrfach oder nicht eindeutig auflösbar ist, nicht setzen und die Mehrdeutigkeit melden.

## Output

- Issue-Nummer und Issue-URL
- gesetzter nativer GitHub-Issue-Type
- nicht gesetzter Issue-Type mit Grund, falls relevant
- Blocker wie fehlende Rechte, unbekannter Issue-Type oder fehlende Authentifizierung

## Qualitätskriterien

- Der gesetzte Type wird nach der Mutation geprüft.
- Beobachtung und Änderung werden getrennt: erst lesen, dann setzen, dann verifizieren.

