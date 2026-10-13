# Applies one approved proposal; no discovery, activation, or human response write.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkItemStorePath,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$ExpectedRevision,
    [Parameter(Mandatory)][string]$ProposalPath,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$CodexHome,
    [Parameter(Mandatory)][string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot '../workitems/HumanInteraction.ps1')
Import-Module (Join-Path $PSScriptRoot '../workitems/WorkItemStore.psm1') -Force

function Resolve-SyncPath([string]$Root, [string]$Relative) {
    if ($Relative -cnotmatch '^[a-zA-Z0-9_./-]+$' -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Split('/') -contains '..') { throw 'Invalid scoped relative path.' }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
    if (-not $full.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path leaves its bound root.' }
    # Reject junctions/symlinks in every existing component, including the root.
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are outside the sync contract.' }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-SyncBytes($Stream) {
    $Stream.Position = 0
    $memory = New-Object IO.MemoryStream
    try { $Stream.CopyTo($memory); return ,$memory.ToArray() } finally { $memory.Dispose() }
}
function Write-SyncNewFile([string]$Path, [byte[]]$Bytes) {
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Get-SyncGit([string[]]$Arguments) {
    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $lines = @(& git -C $RepositoryRoot @Arguments)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read the bound Git baseline/diff.' }
        return $lines
    } finally { [Console]::OutputEncoding = $previousEncoding }
}
function Get-SyncApproval {
    $snapshot = Get-WorkItemStoreResult -Path $WorkItemStorePath -RepositoryRoot $RepositoryRoot
    if ($snapshot.Revision -cne $ExpectedRevision) { throw 'RevisionConflict: reload the approved WorkItem.' }
    $items = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
    if ($items.Count -ne 1) { throw 'WorkItem missing or ambiguous.' }
    $item = $items[0]
    if ($item.status -cnotin @('in_progress','rework') -or $item.owner.type -cne 'agent' -or $item.owner.id -cne 'agent_ressources_optimierer') { throw 'Only a resumed, executing Optimierer WorkItem can apply a proposal.' }
    $human = $item.humanInteraction
    Assert-HIInteraction $human
    if ((Get-HIValue $human 'kind') -cne 'approval' -or -not (Test-HISatisfied $human)) { throw 'A real satisfied human approval is required.' }
    Assert-HIProposalCurrent $human
    if ((Get-HIHash $proposalBytes) -cne $human.proposal.sha256 -or -not ([IO.Path]::GetFullPath($ProposalPath)).Equals([IO.Path]::GetFullPath($human.proposal.path), [StringComparison]::OrdinalIgnoreCase)) { throw 'Approval is bound to a different proposal.' }
    return $human
}

$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$CodexHome = [IO.Path]::GetFullPath($CodexHome)
$proposalBytes = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($ProposalPath))
$human = Get-SyncApproval
$proposal = [Text.Encoding]::UTF8.GetString($proposalBytes) | ConvertFrom-Json
if ($proposal.format -cne 'personal-organization-change/v1' -or $proposal.workItemId -cne $WorkItemId -or $proposal.teamId -cnotmatch '^[a-z][a-z0-9_]*$') { throw 'Invalid single-team change binding.' }
if (-not $RepositoryRoot.Equals([IO.Path]::GetFullPath($proposal.repositoryRoot), [StringComparison]::OrdinalIgnoreCase) -or -not $CodexHome.Equals([IO.Path]::GetFullPath($proposal.codexHome), [StringComparison]::OrdinalIgnoreCase)) { throw 'Repository/target root differs from approval.' }
if ($proposal.repositoryBaseSha -cnotmatch '^[a-f0-9]{40}$') { throw 'Exact repository commit required.' }
$head = Get-SyncGit @('rev-parse','HEAD')
if ($head -cne $proposal.repositoryBaseSha) { throw 'Repository baseline changed.' }
$entries = @($proposal.entries)
if ($entries.Count -eq 0) { throw 'Empty mutation scope.' }
$indexSource = 'teams/' + $proposal.teamId + '/agenten.json'
$indexEntries = @($entries | Where-Object { $_.source -ceq $indexSource })
if ($indexEntries.Count -ne 1) { throw 'The explicitly changed own index must be included in this change set.' }
$held = @(); $results = @(); $failure = $null; $writeStarted = $false
$sources = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$targets = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$utf8 = New-Object Text.UTF8Encoding($false)
$evidenceRoot = [IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\','/')
if ($evidenceRoot.Equals($CodexHome,[StringComparison]::OrdinalIgnoreCase) -or $evidenceRoot.StartsWith($CodexHome.TrimEnd('\','/') + '\',[StringComparison]::OrdinalIgnoreCase) -or $evidenceRoot.Equals($RepositoryRoot,[StringComparison]::OrdinalIgnoreCase) -or $evidenceRoot.StartsWith($RepositoryRoot.TrimEnd('\','/') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must be outside repository and CODEX_HOME.' }
[void](Resolve-SyncPath $evidenceRoot 'result.json')
if (Test-Path -LiteralPath $evidenceRoot) { throw 'Use a fresh evidence directory; existing backups are immutable.' }
[void][IO.Directory]::CreateDirectory($evidenceRoot)
try {
    foreach ($entry in $entries) {
        if (-not $sources.Add([string]$entry.source) -or -not $targets.Add([string]$entry.target)) { throw 'Duplicate source or destination.' }
        foreach ($hash in @($entry.sourceSha256, $entry.targetBeforeSha256, $entry.diffSha256, $entry.targetDiffSha256)) {
            if ([string]$hash -cnotmatch '^[a-f0-9]{64}$') { throw 'Missing exact SHA-256 content binding.' }
        }
        if ($entry.sourceBaselineBlob -cnotmatch '^[a-f0-9]{40}$') { throw 'Missing Git source baseline blob.' }
        if ([string]::IsNullOrWhiteSpace($entry.impact)) { throw 'Concrete per-file impact required.' }
        if ($entry.source -ceq $indexSource) {
            $expectedTarget = 'agents/' + $proposal.teamId + '/agenten.json'
        } else {
            $pattern = '^teams/' + [regex]::Escape($proposal.teamId) + '/agenten/([a-z][a-z0-9_]*)\.toml$'
            if ($entry.source -cnotmatch $pattern) { throw 'Source is outside the single-team role/index scope.' }
            $expectedTarget = 'agents/' + $proposal.teamId + '_' + $Matches[1] + '.toml'
        }
        if ($entry.target -cne $expectedTarget) { throw 'Target differs from the concept mapping.' }
        $source = Resolve-SyncPath $RepositoryRoot $entry.source
        $target = Resolve-SyncPath $CodexHome $entry.target
        $diff = Resolve-SyncPath $RepositoryRoot $entry.diffPath
        if ((Get-HIHash ([IO.File]::ReadAllBytes($diff))) -cne $entry.diffSha256) { throw 'Concrete approved diff changed.' }
        $targetDiff = Resolve-SyncPath $RepositoryRoot $entry.targetDiffPath
        if ((Get-HIHash ([IO.File]::ReadAllBytes($targetDiff))) -cne $entry.targetDiffSha256) { throw 'Concrete personal diff changed.' }
        $liveDiff = @(Get-SyncGit @('-c','core.quotePath=false','diff','--no-ext-diff','--no-textconv','--no-color',$proposal.repositoryBaseSha,'--',$entry.source))
        if ($liveDiff.Count -eq 0) { throw 'Entry has no actual repository change.' }
        $diffBytes = $utf8.GetBytes(($liveDiff -join "`n") + "`n")
        if ((Get-HIHash $diffBytes) -cne $entry.diffSha256) { throw 'Repository delta differs from the approved diff.' }
        $blob = Get-SyncGit @('rev-parse',($proposal.repositoryBaseSha + ':' + $entry.source))
        if ($blob -cne $entry.sourceBaselineBlob) { throw 'Source did not exist in the approved repository baseline.' }
        $sourceStream = New-Object IO.FileStream($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $held += [pscustomobject]@{stream=$sourceStream}
        $bytes = Read-SyncBytes $sourceStream
        if ((Get-HIHash $bytes) -cne $entry.sourceSha256) { throw 'Approved source bytes changed.' }
        $targetStream = New-Object IO.FileStream($target, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
        $held += [pscustomobject]@{stream=$targetStream}
        $before = Read-SyncBytes $targetStream
        $beforeHash = Get-HIHash $before
        $state = if ($beforeHash -ceq $entry.sourceSha256) { 'already-matching' } elseif ($beforeHash -ceq $entry.targetBeforeSha256) { 'pending' } else { 'deferred-individual-difference' }
        $results += [pscustomobject][ordered]@{source=$entry.source; target=$entry.target; beforeSha256=$beforeHash; afterSha256=$beforeHash; sourceSha256=$entry.sourceSha256; state=$state; backup=$null; impact=$entry.impact; stream=$targetStream; bytes=$bytes; before=$before}
    }
    # Read only the index explicitly included for mutation, never another team.
    $index = $utf8.GetString(($results | Where-Object source -CEQ $indexSource).bytes) | ConvertFrom-Json
    if ($index.team_id -cne $proposal.teamId -or $index.leader_id -cne ('teamleiter_' + $proposal.teamId)) { throw 'Index identity differs from the bound team.' }
    foreach ($result in $results | Where-Object source -CNE $indexSource) {
        $roleId = [IO.Path]::GetFileNameWithoutExtension($result.target)
        $refs = @($index.agents | Where-Object { $_.agent_id -ceq $roleId -and $_.role_file -ceq ($roleId + '.toml') })
        $name = [regex]::Match($utf8.GetString($result.bytes), '(?m)^name\s*=\s*"([^"\r\n]+)"\s*$')
        if ($refs.Count -ne 1 -or -not $name.Success -or $name.Groups[1].Value -cne $roleId) { throw 'Role is not uniquely referenced by the changed own index.' }
    }
    if (@($results | Where-Object state -CEQ 'deferred-individual-difference').Count -gt 0) {
        foreach ($result in $results | Where-Object state -CEQ 'pending') { $result.state = 'deferred-related-conflict' }
    } else {
        # Preflight and backup every pending target before the first mutation.
        foreach ($result in $results | Where-Object state -CEQ 'pending') {
            $backup = Join-Path $evidenceRoot (([string]$result.target).Replace('/','__') + '.before')
            Write-SyncNewFile $backup $result.before
            if ((Get-HIHash ([IO.File]::ReadAllBytes($backup))) -cne $result.beforeSha256) { throw 'Backup readback mismatch.' }
            $result.backup = $backup
        }
        $null = Get-SyncApproval
        foreach ($result in $results | Where-Object state -CEQ 'pending') {
            $writeStarted = $true
            $result.state = 'write-started'
            $result.stream.Position = 0
            $result.stream.Write($result.bytes, 0, $result.bytes.Length)
            $result.stream.SetLength($result.bytes.Length)
            $result.stream.Flush($true)
            $result.afterSha256 = Get-HIHash (Read-SyncBytes $result.stream)
            if ($result.afterSha256 -cne $result.sourceSha256) { throw 'Personal content readback mismatch.' }
            $result.state = 'applied'
        }
    }
} catch { $failure = $_.Exception.Message }
finally {
    foreach ($handle in $held) { $handle.stream.Dispose() }
    $publicResults = @($results | Select-Object source,target,beforeSha256,afterSha256,sourceSha256,state,backup,impact)
    $report = [ordered]@{workItemId=$WorkItemId; proposalSha256=(Get-HIHash $proposalBytes); requestId=$human.requestId; repositoryBaseSha=$proposal.repositoryBaseSha; writtenAtUtc=[DateTime]::UtcNow.ToString('o'); writeStarted=$writeStarted; failure=$failure; entries=$publicResults; functionalEvidence=$false; acceptance=$null}
    Write-SyncNewFile (Join-Path $evidenceRoot 'result.json') ($utf8.GetBytes(($report | ConvertTo-Json -Depth 15)))
}
if ($failure) { throw "Personal sync stopped: $failure. Read result.json and exact backups; no automatic rollback or activation." }
[pscustomobject]$report
