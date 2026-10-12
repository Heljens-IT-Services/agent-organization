[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$ParentTaskId,
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [string]$ParentJobPath,
    [string]$ParentContextPath,
    [string]$ParentContextHash,
    [string]$ResumeAssessment,
    [string]$RepositoryRoot
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\coordinator\Lifecycle.Persistence.ps1')
$utf8 = New-Object Text.UTF8Encoding($false, $true)
function Read-StrictJson([string]$File) {
    return ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($File)) -ErrorAction Stop
}
if (-not $RepositoryRoot) { $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$storePath = [IO.Path]::GetFullPath($Path)
$accounting = [IO.Path]::GetFullPath($AccountingDirectory)
$parentId = ([guid]$ParentTaskId).ToString('N')
$parentJobPath = if($ParentJobPath){$ParentJobPath}else{$env:AGENT_ORG_PARENT_JOB_FILE}
if($ParentJobPath -and $env:AGENT_ORG_PARENT_JOB_FILE -and [IO.Path]::GetFullPath($ParentJobPath) -cne [IO.Path]::GetFullPath($env:AGENT_ORG_PARENT_JOB_FILE)){throw 'ExplicitParentJobBindingConflict'}
if (-not $parentJobPath -or -not (Test-Path -LiteralPath $parentJobPath -PathType Leaf)) { throw 'Persistierter Elternjob fehlt; WorkItem-Start fail-closed.' }
$parentJobPath = [IO.Path]::GetFullPath($parentJobPath)
$parent = Read-StrictJson $parentJobPath
if ($parent.task_id -cne $parentId -or -not $parent.role -or [IO.Path]::GetFullPath($parent.accounting_directory) -cne $accounting) { throw 'Elternjob-Bindung widerspruechlich.' }
$activePath = $parentJobPath + '.active.json'
if (-not (Test-Path -LiteralPath $activePath -PathType Leaf)) { throw 'Persistierte aktive Eltern-Thread/Turn-Bindung fehlt.' }
$active = Read-StrictJson $activePath
if ($ParentContextPath -or $ParentContextHash) {
    if(-not $ParentContextPath -or -not $ParentContextHash){throw 'Immutable parent context path/hash must be paired.'}
    $cm=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
    $context=& $cm {param($p,$h,$j,$t,$s,$a) Assert-ExecutionContext $p $h $j $t $s $a} ([IO.Path]::GetFullPath($ParentContextPath)) $ParentContextHash $parentJobPath $ParentTaskId $storePath $accounting
    $historicalRoot=& $cm {param($p,$h,$s,$a) Assert-ExecutionAncestors $p $h $s $a -MaxLevels 2} ([IO.Path]::GetFullPath($ParentContextPath)) $ParentContextHash $storePath $accounting
    if($context.role -cne $parent.role -or $context.workItemId -cne $parent.work_item_id){throw 'Historical parent context does not match persisted job identity.'}
    $active=[pscustomobject]@{thread_id=$context.threadId;turn_id=$context.turnId;task_id=$context.taskId;role=$context.role;accounting_directory=$context.accountingDirectory}
} elseif ($active.task_id -cne $parent.task_id -or $active.role -cne $parent.role -or [IO.Path]::GetFullPath($active.accounting_directory) -cne $accounting -or [string]::IsNullOrWhiteSpace([string]$active.thread_id) -or [string]::IsNullOrWhiteSpace([string]$active.turn_id)) { throw 'Aktive Eltern-Thread/Turn-Bindung widerspruechlich.' }
$chainJob = $parent; $chainPath = $parentJobPath; $agentLevels = 2
while ($chainJob.parent_task_id -and -not $ParentContextPath) {
    if ($chainJob.role -ceq 'koordinator') { throw 'Coordinator must be the root of the delegation chain.' }
    if (-not $chainJob.parent_job_path -or -not (Test-Path -LiteralPath $chainJob.parent_job_path -PathType Leaf)) { throw 'Persistierter Vorfahrenjob in der Delegationskette fehlt.' }
    $ancestorPath = [IO.Path]::GetFullPath($chainJob.parent_job_path)
    $ancestor = Read-StrictJson $ancestorPath
    if ($ancestor.task_id -cne $chainJob.parent_task_id -or [IO.Path]::GetFullPath($ancestor.accounting_directory) -cne $accounting) { throw 'Vorfahrjob task/accounting Bindung widerspruechlich.' }
    $ancestorActivePath = $ancestorPath + '.active.json'
    if (-not (Test-Path -LiteralPath $ancestorActivePath -PathType Leaf)) { throw 'Persistierter Vorfahren-Thread/Turn fehlt.' }
    $ancestorActive = Read-StrictJson $ancestorActivePath
    if ($ancestorActive.task_id -cne $ancestor.task_id -or $ancestorActive.role -cne $ancestor.role -or [string]::IsNullOrWhiteSpace([string]$ancestorActive.thread_id) -or [string]::IsNullOrWhiteSpace([string]$ancestorActive.turn_id)) { throw 'Vorfahrjob Thread/Turn Bindung widerspruechlich.' }
    if ($chainJob.parent_thread_id -cne $ancestorActive.thread_id -or $chainJob.parent_turn_id -cne $ancestorActive.turn_id) { throw 'Kindjob ist nicht an den aktiven Thread/Turn des unmittelbaren Elternjobs gebunden.' }
    if ($chainJob.role -match '^teamleiter_' -and $ancestor.role -cne 'koordinator') { throw 'Teamleiter muss in der persistierten Kette vom Koordinator stammen.' }
    if ($chainJob.role -notmatch '^(koordinator|teamleiter_[a-z][a-z0-9_]*)$') { throw 'Operative Rolle darf die Delegationskette nicht fortsetzen.' }
    $agentLevels++; if ($agentLevels -gt 3) { throw 'Maximal drei Agentenebenen in der Kette.' }
    $chainJob = $ancestor; $chainPath = $ancestorPath
}
$rootRole=if($ParentContextPath){$historicalRoot.role}else{$chainJob.role}
if ($rootRole -cne 'koordinator') { throw 'Delegationskette muss beim Koordinator enden.' }
$isCoordinator = $parent.role -ceq 'koordinator'
$isLeader = $parent.role -cmatch '^teamleiter_[a-z][a-z0-9_]*$'
if (-not ($isCoordinator -or $isLeader)) { throw 'Nur Koordinator oder Teamleiter duerfen delegieren.' }
Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemStore.psm1') -Force
$snapshot = Get-WorkItemStoreResult -Path $storePath -RepositoryRoot $RepositoryRoot
$matches = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
if ($matches.Count -ne 1) { throw 'WorkItem fehlt oder ist nicht eindeutig.' }
$item = $matches[0]
if ($item.owner.type -cne 'agent') { throw 'WorkItem ist keinem Agenten zugewiesen.' }
$role = [string]$item.owner.id
if ($isCoordinator) {
    if ($role -notmatch '^teamleiter_[a-z][a-z0-9_]*$') { throw 'Koordinator-Routing ist auf Teamleiterrollen begrenzt.' }
} else {
    $teamPrefix = $parent.role.Substring('teamleiter_'.Length) + '_'
    if ($role -ceq $parent.role -or $role -notlike ($teamPrefix + '*') -or $role -match '^teamleiter_') { throw 'Teamleiter-Routing ist auf Rollen mit eigenem Team-Praefix begrenzt.' }
}
if ($parent.work_item_id) {
    if ([IO.Path]::GetFullPath($parent.work_item_store_path) -cne $storePath) { throw 'Store weicht vom Elternjob ab.' }
    $parentItem = @($snapshot.Document.items | Where-Object { $_.id -ceq $parent.work_item_id })
    if ($parentItem.Count -ne 1) { throw 'WorkItem-Elternpfad passt nicht zur persistierten Auftragskette.' }
    $seen = @{}; $cursor = $item; $foundParent = $false
    while ($null -ne $cursor.parentId) {
        $id = [string]$cursor.id
        if ($seen.ContainsKey($id)) { throw 'WorkItem-Elternpfad enthaelt einen Zyklus.' }
        $seen[$id] = $true
        if ($cursor.parentId -ceq $parent.work_item_id) { $foundParent = $true }
        $next = @($snapshot.Document.items | Where-Object { $_.id -ceq $cursor.parentId })
        if ($next.Count -ne 1) { throw 'WorkItem-Elternpfad unvollstaendig.' }
        $cursor = $next[0]
    }
    if ($seen.ContainsKey([string]$cursor.id)) { throw 'WorkItem-Elternpfad enthaelt einen Zyklus.' }
    if (-not $foundParent) { throw 'WorkItem liegt nicht unter dem persistierten Elternbeitrag.' }
} elseif ($null -ne $item.parentId) { throw 'Operativer WorkItem-Start ohne persistierte Elternaufgabe ist unzulaessig.' }

# Resolve routing against the currently installed organization data. A coordinator
# may route only to a registered team leader; a leader may inspect only its own
# team's agent index and may route only to an agent declared there.
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$agentsRoot = Join-Path $codexHome 'agents'
$team = $null
if ($isCoordinator) {
	$teamsFile = Join-Path $agentsRoot 'koordinator\teams.json'
	if (-not (Test-Path -LiteralPath $teamsFile -PathType Leaf)) { throw 'Aktueller Team-Lookup fehlt.' }
	$teams = @(Read-StrictJson $teamsFile).teams
    $leaderMatches = @($teams | Where-Object { $_.leader_id -ceq $role })
    if ($leaderMatches.Count -ne 1) { throw 'Ziel-Teamleiter ist im aktuellen teams.json nicht eindeutig registriert.' }
    $team = $leaderMatches[0]
    $roleFile = [string]$team.leader_role_file
    if (-not $roleFile) { $roleFile = [string]$team.role_file }
    if (-not $roleFile) { throw 'Aktueller Team-Lookup enthaelt keine role_file-Referenz fuer den Teamleiter.' }
    $expected = [IO.Path]::GetFullPath((Join-Path $agentsRoot ($role + '.toml')))
    $referenced = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $teamsFile) $roleFile))
    if ($referenced -cne $expected -or -not (Test-Path -LiteralPath $referenced -PathType Leaf)) { throw 'Teamleiter role_file-Referenz ist ungueltig oder fehlt.' }
} else {
	if ($parent.role -cnotmatch '^teamleiter_(?<team>.+)$') { throw 'Persistierte Elternrolle ist kein Teamleiter.' }
	$teamId = $Matches.team
    $teamDirectory = Join-Path $agentsRoot $teamId
    $agentIndex = Join-Path $teamDirectory 'agenten.json'
    if (-not (Test-Path -LiteralPath $agentIndex -PathType Leaf)) { throw 'Eigenes installiertes agenten.json fehlt.' }
	$teamIndex = Read-StrictJson $agentIndex
	if ($teamIndex.team_id -cne $teamId -or $teamIndex.leader_id -cne $parent.role -or $teamIndex.coordinator_role_file -cne 'koordinator.toml') { throw 'Eigenes Teamindex-Identitaetsfeld oder Koordinatorreferenz ungueltig.' }
	$leaderRoleFile = [IO.Path]::GetFullPath((Join-Path $agentsRoot ([string]$teamIndex.role_file)))
	$expectedLeaderRoleFile = [IO.Path]::GetFullPath((Join-Path $agentsRoot ($parent.role + '.toml')))
	if ($leaderRoleFile -cne $expectedLeaderRoleFile -or -not (Test-Path -LiteralPath $leaderRoleFile -PathType Leaf)) { throw 'Eigenes Teamindex verweist nicht auf die persistierte Elternrolle.' }
	$entries = @($teamIndex.agents | Where-Object { $_.agent_id -ceq $role })
    if ($entries.Count -ne 1) { throw 'Ziel-agent_id fehlt im eigenen Teamindex oder ist nicht eindeutig.' }
    $roleFile = [string]$entries[0].role_file
    if (-not $roleFile) { throw 'Teamindex enthaelt keine role_file-Referenz fuer das Ziel.' }
	$referenced = [IO.Path]::GetFullPath((Join-Path $agentsRoot $roleFile))
    $expected = [IO.Path]::GetFullPath((Join-Path $agentsRoot ($role + '.toml')))
    if ($referenced -cne $expected -or -not (Test-Path -LiteralPath $referenced -PathType Leaf)) { throw 'Ziel role_file-Referenz fehlt, liegt ausserhalb des Teams oder passt nicht zur Rolle.' }
}
if ($item.status -notin @('planned','in_progress','rework','blocked')) { throw "WorkItem ist nicht ausfuehrbar: $($item.status)" }
if ($null -ne $item.humanInteraction -and $null -eq $item.humanInteraction.response) { throw 'Unbeantwortete humanInteraction blockiert Resume.' }
if($item.status -ceq 'blocked'){throw 'Blocked WorkItem remains locked until a terminal propose_resume CAS decision.'}
[void](Assert-LCResume $ResumeAssessment $item $snapshot.Revision $storePath $RepositoryRoot)
foreach ($dependency in $item.dependencies) {
    $dep = @($snapshot.Document.items | Where-Object { $_.id -ceq $dependency })
    if ($dep.Count -ne 1 -or $dep[0].status -cne 'accepted') { throw "WorkItem-Abhaengigkeit ist nicht akzeptiert: $dependency" }
}
[pscustomobject]@{ item = $item; revision = $snapshot.Revision; role = $role; callerRole = $parent.role; parentTaskId = $parentId; parentJobPath = $parentJobPath; parentThreadId=$active.thread_id; parentTurnId=$active.turn_id; parentContextPath=$(if($ParentContextPath){[IO.Path]::GetFullPath($ParentContextPath)}else{$null});parentContextHash=$ParentContextHash;storePath = $storePath; accountingDirectory = $accounting } | ConvertTo-Json -Depth 40 -Compress
