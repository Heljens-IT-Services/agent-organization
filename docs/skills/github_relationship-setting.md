# Skill: GitHub Relationship Setzen

## Zweck

Native GitHub-Relationships zwischen bestehenden Issues gezielt setzen, insbesondere `blocked by` und Parent/Child-Beziehungen.

## Verwenden

- Wenn aus vorhandenem Kontext eindeutig hervorgeht, dass ein Issue durch ein anderes Issue blockiert wird.
- Wenn aus vorhandenem Kontext eindeutig hervorgeht, welches Issue Parent und welches Issue Child ist.
- Wenn Repository, beteiligte Issue-Nummern und Relationship-Art klar sind.
- Für fachliche Hierarchie oder technische Abhängigkeiten im ausdrücklich zugewiesenen Scope.
- Nicht verwenden, um Labels zu setzen. Labels ersetzen keine native Relationship.
- Nicht verwenden, um Body-Links oder Textverweise als Ersatz für native Relationships zu pflegen.
- Nicht verwenden, um GitHub-Issue-Types zu setzen. Dann `type-setting` nutzen.

## Vorgehen

1. Repository und beteiligte Issue-Nummern bestimmen.
2. Relationship-Art bestimmen: `blocked by` oder Parent/Child.
3. Prüfen, ob die Beziehung aus vorhandenem Kontext eindeutig hervorgeht.
4. GitHub-Authentifizierung und Repository-Zugriff prüfen.
5. IDs der beteiligten Issues lesen.
6. Passende native GitHub-GraphQL-Mutation ausführen.
7. Ergebnis lesen und prüfen, ob die Relationship gesetzt ist.

## Kommandos

Issue-IDs lesen:

```powershell
$blockedIssueId = gh issue view <blocked-issue-number> --repo <org>/<repo> --json id --jq .id
$blockingIssueId = gh issue view <blocking-issue-number> --repo <org>/<repo> --json id --jq .id
$parentIssueId = gh issue view <parent-issue-number> --repo <org>/<repo> --json id --jq .id
$childIssueId = gh issue view <child-issue-number> --repo <org>/<repo> --json id --jq .id
```

Blocked-by setzen:

```powershell
gh api graphql `
  -f blockedIssueId="$blockedIssueId" `
  -f blockingIssueId="$blockingIssueId" `
  -f query='mutation($blockedIssueId:ID!, $blockingIssueId:ID!) { addBlockedBy(input: { issueId: $blockedIssueId, blockingIssueId: $blockingIssueId }) { issue { number } blockingIssue { number } } }'
```

Parent/Child setzen:

```powershell
gh api graphql `
  -f parentIssueId="$parentIssueId" `
  -f childIssueId="$childIssueId" `
  -f query='mutation($parentIssueId:ID!, $childIssueId:ID!) { addSubIssue(input: { issueId: $parentIssueId, subIssueId: $childIssueId, replaceParent: false }) { issue { number } subIssue { number } } }'
```

Basisdaten zur Kontrolle lesen:

```powershell
gh issue view <issue-number> --repo <org>/<repo> --json id,number,title,url
```

Platzhalter:

- `<org>`: GitHub-Organisation oder Owner.
- `<repo>`: Repository-Name ohne Organisation.
- `<blocked-issue-number>`: Issue, das blockiert ist.
- `<blocking-issue-number>`: Issue, das den Blocker darstellt.
- `<parent-issue-number>`: übergeordnetes Issue.
- `<child-issue-number>`: untergeordnetes Issue.

## Grenzen

- Extern wirksam arbeiten: Native GitHub-Relationships werden tatsächlich in GitHub gesetzt.
- Relationships nur setzen, wenn Art und Richtung aus User-Anweisung, Issue-Kontext oder Workflow eindeutig hervorgehen; andernfalls nachfragen.
- Bei bestehendem anderem Parent `replaceParent: false` beibehalten und den Konflikt melden.
- Keine Issue-Types setzen.
- Fehlende GitHub-Authentifizierung, fehlende Rechte, fehlende Repository-Zuordnung oder nicht auffindbare Issues als Blocker melden.
- Bei GraphQL-Fehlern nicht auf Labels oder Body-Text ausweichen.

## Output

- gesetzte Relationship-Art
- beteiligte Issue-Nummern und Issue-URLs
- nicht gesetzte Relationships mit Grund, falls relevant
- Blocker wie fehlende Rechte, unklare Richtung, vorhandener anderer Parent oder fehlende Authentifizierung

## Qualitätskriterien

- `blocked by` und Parent/Child werden getrennt und richtungsstabil behandelt.
- Ergebnis der Mutation wird geprüft.

