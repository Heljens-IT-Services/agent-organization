# Technical persistence helpers; dot-sourced by existing stores, not a new WorkItem contract.
function Get-LCValue($Object,[string]$Name,$Default=$null) {
    if($null -eq $Object){return $Default}
    if($Object -is [Collections.IDictionary]){if($Object.Contains($Name)){return $Object[$Name]};return $Default}
    $p=$Object.PSObject.Properties[$Name];if($p){return $p.Value};return $Default
}
function Set-LCValue($Object,[string]$Name,$Value) {
    if($Object -is [Collections.IDictionary]){$Object[$Name]=$Value}else{$Object|Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force}
}
function Get-LCBytes($Value){return ,([Text.UTF8Encoding]::new($false,$true).GetBytes((ConvertTo-Json -InputObject $Value -Depth 100 -Compress)))}
function Get-LCHash([byte[]]$Bytes){$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Write-LCCreateNew([string]$Path,[byte[]]$Bytes) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    try{$s=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$s.Write($Bytes,0,$Bytes.Length);$s.Flush($true)}finally{$s.Dispose()}}
    catch [IO.IOException]{if(-not [IO.File]::Exists($Path) -or (Get-LCHash ([IO.File]::ReadAllBytes($Path))) -cne (Get-LCHash $Bytes)){throw}}
    if((Get-LCHash ([IO.File]::ReadAllBytes($Path))) -cne (Get-LCHash $Bytes)){throw 'ArchiveDurabilityReadbackConflict'}
}
function Save-LCImmutable([string]$Directory,$Value){$b=Get-LCBytes $Value;$h=Get-LCHash $b;$p=Join-Path $Directory ($h+'.json');Write-LCCreateNew $p $b;return [pscustomobject]@{path=$p;hash=$h}}
function Read-LCReceipt($Reference) {
    if(-not $Reference -or -not (Get-LCValue $Reference 'path') -or (Get-LCValue $Reference 'hash') -notmatch '^[a-f0-9]{64}$'){throw 'ReceiptReferenceInvalid'}
    $b=[IO.File]::ReadAllBytes([string]$Reference.path);if((Get-LCHash $b) -cne [string]$Reference.hash){throw 'ReceiptHashConflict'}
    return ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString($b)) -ErrorAction Stop
}
function Invoke-LCLock([string]$Path,[scriptblock]$Action) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)))
    $s=[IO.File]::Open($Path+'.lifecycle.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{& $Action}finally{$s.Dispose()}
}
function Read-LCArchive([string]$Path,$Document) {
    $refs=@(Get-LCValue $Document 'archiveSegments' @());$seen=@{}
    foreach($r in $refs){
        if($r.hash -notmatch '^[a-f0-9]{64}$' -or $seen.ContainsKey([string]$r.hash)){throw 'ArchiveManifestAmbiguous'};$seen[[string]$r.hash]=$true
        $p=Join-Path ($Path+'.archive') ($r.hash+'.json')
        if([IO.Path]::GetFullPath([string]$r.path) -cne [IO.Path]::GetFullPath($p)){throw 'ArchivePathBindingConflict'}
        $segment=Read-LCReceipt $r
        if($segment.kind -cne 'closed-journal-segment-v1' -or $segment.storePath -cne [IO.Path]::GetFullPath($Path) -or $segment.field -cne $r.field -or @($segment.records).Count -ne [int]$r.count){throw 'ArchiveSourceBindingConflict'}
        $values=@(Get-LCValue $Document ([string]$r.field) @());$hashes=@{}
        foreach($v in $values){$hashes[(Get-LCHash (Get-LCBytes $v))]=$true}
        $prefix=@();foreach($v in @($segment.records)){$h=Get-LCHash (Get-LCBytes $v);if(-not $hashes.ContainsKey($h)){$prefix+=,$v;$hashes[$h]=$true}};$values=@($prefix)+@($values)
        $identityField=switch([string]$r.field){'RequestHistory'{'requestId'};'events'{'id'};'executions'{'executionId'};'intents'{'intentId'};'effectReceipts'{'effectId'};default{$null}}
        if($identityField){$identityHashes=@{};foreach($v in $values){$id=[string](Get-LCValue $v $identityField);if(-not $id -and $r.field -ceq 'effectReceipts'){$id=[string](Get-LCValue (Get-LCValue $v 'context') 'effectId')};if($id){$h=Get-LCHash (Get-LCBytes $v);if($identityHashes.ContainsKey($id) -and $identityHashes[$id] -cne $h){throw 'ArchiveIdentityConflict'};$identityHashes[$id]=$h}}}
        Set-LCValue $Document ([string]$r.field) $values
    }
    return $Document
}
function Test-LCClosed([string]$Field,$Record) {
    $state=[string](Get-LCValue $Record 'state');$outcome=[string](Get-LCValue $Record 'outcome')
    switch($Field){
        'RequestHistory' {return $outcome -in @('completed','failed','interrupted') -and $null -ne (Get-LCValue $Record 'decision') -and [bool](Get-LCValue $Record 'archiveReady' $false)}
        'events' {return $state -ceq 'acknowledged'}
        'executions' {return $state -ceq 'Complete' -or ($state -ceq 'Returned' -and [string](Get-LCValue $Record 'purpose') -ceq 'coordinator-event' -and [bool](Get-LCValue $Record 'archiveReady' $false))}
        'intents' {return $state -ceq 'published' -and [bool](Get-LCValue $Record 'receiptHash')}
        'effectReceipts' {return [bool](Get-LCValue $Record 'receiptHash')}
        default {return $false}
    }
}
function Write-LCJournal([string]$Path,$Document,[int]$HotLimit=256,[int]$HotRetain=128) {
    # Called under the original store/dispatch/event lock, or the serial host ownership lock.
    if($HotLimit -lt 2 -or $HotRetain -lt 1 -or $HotRetain -ge $HotLimit){throw 'ArchiveParametersInvalid'}
    $full=[IO.Path]::GetFullPath($Path);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
    $projection=ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString((Get-LCBytes $Document))) -ErrorAction Stop
    $refs=@(Get-LCValue $Document 'archiveSegments' @())
    # Preserve existing manifests even when an existing caller rebuilds the root object.
    if([IO.File]::Exists($full)){
        $old=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($full,[Text.UTF8Encoding]::new($false,$true))) -ErrorAction Stop
        foreach($r in @(Get-LCValue $old 'archiveSegments' @())){if(-not @($refs|Where-Object{$_.hash -ceq $r.hash}).Count){$refs+=,$r}}
    }
    Set-LCValue $projection 'archiveSegments' $refs
    # Verify every immutable prior record is still present, unchanged, before projecting.
    foreach($r in $refs){
        $seg=Read-LCReceipt $r;$field=[string]$r.field;$values=@(Get-LCValue $projection $field @());$hashes=@{}
        foreach($v in $values){$hashes[(Get-LCHash (Get-LCBytes $v))]=$true}
        foreach($v in @($seg.records)){$h=Get-LCHash (Get-LCBytes $v);if(-not $hashes.ContainsKey($h)){throw 'ArchivedRecordMutationOrRemoval'}}
        $archived=@{};foreach($v in @($seg.records)){$archived[(Get-LCHash (Get-LCBytes $v))]=$true}
        Set-LCValue $projection $field @($values|Where-Object{-not $archived.ContainsKey((Get-LCHash (Get-LCBytes $_)))})
    }
    foreach($field in @('RequestHistory','events','executions','intents','effectReceipts')){
        $values=@(Get-LCValue $projection $field @());if($values.Count -lt $HotLimit){continue}
        $closed=@($values|Where-Object{Test-LCClosed $field $_}|Select-Object -First ([Math]::Max(0,$values.Count-$HotRetain)))
        if(-not $closed.Count){continue}
        $segment=[ordered]@{kind='closed-journal-segment-v1';storePath=$full;field=$field;records=$closed}
        $ref=Save-LCImmutable ($full+'.archive') $segment
        $manifest=[pscustomobject]@{path=$ref.path;hash=$ref.hash;field=$field;count=$closed.Count}
        $refs+=,$manifest;$hashes=@{};foreach($v in $closed){$hashes[(Get-LCHash (Get-LCBytes $v))]=$true}
        Set-LCValue $projection $field @($values|Where-Object{-not $hashes.ContainsKey((Get-LCHash (Get-LCBytes $_)))})
    }
    Set-LCValue $projection 'archiveSegments' $refs
    # Hash commit of manifest+hot projection; the journal replacement is the sole commit point.
    $tmp=$full+'.'+[guid]::NewGuid().ToString('N')+'.writing';$bytes=Get-LCBytes $projection
    Write-LCCreateNew $tmp $bytes
    if([IO.File]::Exists($full)){[IO.File]::Replace($tmp,$full,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$full)}
    if((Get-LCHash ([IO.File]::ReadAllBytes($full))) -cne (Get-LCHash $bytes)){throw 'JournalCommitReadbackConflict'}
    # Caller keeps the fully hydrated document, so live references remain intact.
    Set-LCValue $Document 'archiveSegments' $refs
}
function Get-LCResumeContent($Item) {
    $copy=ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString((Get-LCBytes $Item)))
    foreach($n in @('status','updatedAt','blockReason')){$copy.PSObject.Properties.Remove($n)}
    return Get-LCHash (Get-LCBytes $copy)
}
function Assert-LCResume([string]$Assessment,$Item,[string]$Revision,[string]$StorePath,[string]$RepositoryRoot,[switch]$BeforeCAS) {
    $module=Import-Module (Join-Path $RepositoryRoot 'scripts/workitems/WorkItemStore.psm1') -PassThru -Force
    $requirements=@(& $module {param($p,$i,$root)Get-WorkItemStoreResumeRequirement -Path $p -Item $i -RepositoryRoot $root} $StorePath $Item $RepositoryRoot)
    if([string]::IsNullOrWhiteSpace($Assessment)){if($Item.status -ceq 'blocked' -or $requirements.Count){throw 'ResumeRequiresTerminalReceipt'};return $null}
    $locator=ConvertFrom-Json -InputObject $Assessment -ErrorAction Stop;$r=Read-LCReceipt $locator
    if($r.kind -cne 'terminal-resume-decision-v1' -or $r.disposition -cne 'resume' -or $r.workItemId -cne $Item.id -or $r.storePath -cne [IO.Path]::GetFullPath($StorePath) -or $r.contentHash -cne (Get-LCResumeContent $Item)){throw 'ResumeDecisionBindingConflict'}
    if($BeforeCAS -and $r.candidateRevision -cne $Revision){throw 'ResumeDecisionRevisionConflict'}
    $cas=& $module {param($p,$id,$root) Get-WorkItemStoreEffectReceipt -Path $p -EffectId $id -RepositoryRoot $root -TimeoutMilliseconds 5000} $StorePath $r.effectId $RepositoryRoot
    if(-not $cas -or (Get-LCHash (Get-LCBytes $cas)) -cne $r.casReceiptHash -or $cas.state -cne 'published' -or $cas.candidateRevision -cne $r.candidateRevision -or (Get-LCValue $cas.context 'resumeCommandHash') -cne $r.commandHash -or (Get-LCValue $cas.context 'resumeEffectKind') -cne 'propose_resume'){throw 'ResumeCASReceiptConflict'}
    $context=Read-LCReceipt $r.terminalContext
    $decision=Read-LCReceipt $r.terminalDecision
    if($context.outcome -cne 'Completed' -or $context.requestId -cne $r.requestId -or $context.threadId -cne $r.threadId -or $context.turnId -cne $r.turnId -or $context.evidenceHash -cne $r.terminalDecision.hash -or $decision.outcome -cne 'completed' -or $decision.effectPlan.planHash -cne $r.planHash){throw 'ResumeTerminalContextConflict'}
    if($context.logicalSessionId -cne $r.logicalSessionId -or $context.jobPath -cne $r.coordinatorJobPath -or $context.jobHash -cne $r.coordinatorJobHash -or $context.taskId -cne $r.rootTaskId){throw 'ResumeSessionEpochConflict'}
    $commands=@($decision.effectPlan.commands|Where-Object{$_.effectId -ceq $r.effectId})
    if($commands.Count -ne 1 -or (Get-LCHash (Get-LCBytes $commands[0])) -cne $r.commandHash){throw 'ResumeTerminalCommandConflict'}
    return $r
}
