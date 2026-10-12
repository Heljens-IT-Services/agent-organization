Set-StrictMode -Version 2

function New-LocalWebResponse {
    param([string]$RequestId, [string]$Operation, [bool]$Ok, [int]$StatusCode, $Data, $ErrorObject)
    [pscustomobject][ordered]@{
        transportVersion = '1'; requestId = $RequestId; ok = $Ok; operation = $Operation
        completedAt = [DateTime]::UtcNow.ToString('o'); data = $Data; error = $ErrorObject
    }
}

function Get-LocalWebFailure {
    param([string]$Code, [string]$Message, [int]$StatusCode = 400, [string]$CommitState = 'notWritten', $ExpectedRevision, $ActualRevision)
    $errorData = [ordered]@{ errorId = [Guid]::NewGuid().ToString('D'); code = $Code; message = $Message; commitState = $CommitState }
    if ($null -ne $ExpectedRevision) { $errorData.expectedRevision = $ExpectedRevision }
    if ($null -ne $ActualRevision) { $errorData.actualRevision = $ActualRevision }
    return @{ status = $StatusCode; error = [pscustomobject]$errorData }
}

function Get-LocalWebCallerError {
    param($Record, [string]$ExpectedRevision, [bool]$WriteAttempt = $false)
    $id = [string]$Record.FullyQualifiedErrorId
    $map = @{
        RevisionConflict = 409; DuplicateWorkItemId = 409; ItemNotFound = 404
        LockTimeout = 423; LockOwnerUncertain = 423; LockIdentityUnavailable = 423
        ValidationFailed = 422; InvalidCandidate = 422; InvalidStoredDocument = 503
        StoreRecoveryRequired = 503; StoreDirectoryMissing = 503; UnsafeStorePath = 503
        HumanResponseContractBlocked = 503; ItemIdMismatch = 422; NewItemMustBePlanned = 422
        SerializationFailed = 422; InvalidTimeout = 400; LockNotOwned = 503
        PublishFailed = 503; TemporaryCleanupFailed = 503
    }
    $code = $id.Split(',')[0]
    $known = $map.ContainsKey($code)
    if ([string]::IsNullOrWhiteSpace($code)) { $code = if ($WriteAttempt) { 'WriteOutcomeUnknown' } else { 'ReadUnavailable' } }
    $status = if ($known) { $map[$code] } else { 503 }
    $commitState = if ($WriteAttempt -and (-not $known -or $code -in @('PublishFailed','TemporaryCleanupFailed','LockNotOwned','WriteOutcomeUnknown'))) { 'unknown' } else { 'notWritten' }
    $messages = @{
        RevisionConflict = 'WorkItem-Bestand hat sich seit dem gelesenen Stand geändert.'
        DuplicateWorkItemId = 'Die WorkItem-ID ist bereits vorhanden; zuerst den Bestand neu lesen.'
        ItemNotFound = 'WorkItem wurde im aktuellen Bestand nicht gefunden.'
        LockTimeout = 'Der Store-Lock blieb belegt. Nicht löschen; später erneut lesen.'
        LockOwnerUncertain = 'Lock-Eigentümer konnte nicht sicher geklärt werden. Lock und Store unverändert erhalten.'
        LockIdentityUnavailable = 'Lock-Identität ist in dieser Umgebung nicht verfügbar.'
        InvalidStoredDocument = 'Der bestehende WorkItem-Bestand konnte nicht sicher gelesen oder validiert werden.'
        StoreRecoveryRequired = 'Der Store benötigt eine manuelle Recovery-Klärung.'
        StoreDirectoryMissing = 'Der konfigurierte Store-Ordner ist nicht vorhanden.'
        UnsafeStorePath = 'Der konfigurierte Store-Pfad enthält einen nicht unterstützten Reparse Point.'
        ReadUnavailable = 'Der vorhandene PowerShell-Caller konnte den Read nicht abschließen.'
        WriteOutcomeUnknown = 'Der Schreibcaller lieferte keinen eindeutig sicheren Abschlussstatus. Commitstatus unbekannt; zuerst den Store frisch lesen.'
        PublishFailed = 'Der Store-Caller meldet einen Fehler bei der Veröffentlichung. Commitstatus unbekannt; zuerst den Store frisch lesen.'
        TemporaryCleanupFailed = 'Der Store-Caller meldet einen Fehler beim temporären Aufräumen. Commitstatus unbekannt; zuerst den Store frisch lesen.'
        ItemIdMismatch = 'Die WorkItem-ID stimmt nicht mit dem Item überein.'
        NewItemMustBePlanned = 'Neue WorkItems müssen im geplanten Status beginnen.'
        ValidationFailed = 'Der vorhandene WorkItem-Validator hat die Änderung abgelehnt.'
        InvalidCandidate = 'Der vorhandene Store-Caller konnte den Kandidaten nicht verarbeiten.'
        SerializationFailed = 'Die Änderung konnte nicht sicher serialisiert werden.'
        LockNotOwned = 'Der vorhandene Store-Caller konnte die Lockfreigabe nicht bestätigen.'
    }
    $message = if ($messages.ContainsKey($code)) { $messages[$code] } elseif ($WriteAttempt) { 'Der vorhandene PowerShell-Schreibcaller ist mit einer nicht zugeordneten Fehler-ID fehlgeschlagen. Commitstatus unbekannt; zuerst den Store frisch lesen.' } else { 'Der vorhandene PowerShell-Caller hat den Read abgelehnt.' }
    $actual = $null
    if ($code -eq 'RevisionConflict' -and $null -ne $Record.Exception.Data['LocalWebFreshRevision']) { $actual = [string]$Record.Exception.Data['LocalWebFreshRevision'] }
    return Get-LocalWebFailure -Code $code -Message $message -StatusCode $status -CommitState $commitState -ExpectedRevision $ExpectedRevision -ActualRevision $actual
}

function Test-LocalWebAllowedProperties {
    param($Value, [string[]]$Allowed, [string]$Label)
    if ($null -eq $Value -or $Value -isnot [System.Management.Automation.PSCustomObject]) { throw "Malformed$Label" }
    $unknown = @($Value.PSObject.Properties.Name | Where-Object { $_ -notin $Allowed })
    if ($unknown.Count -gt 0) { throw "Unknown$Label`:$($unknown -join ',')" }
}

function ConvertTo-LocalWebPlainObject {
    param($Value)
    $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress -ErrorAction Stop
    $wrapper = ConvertFrom-Json -InputObject ('{"value":' + $json + '}') -ErrorAction Stop
    return ,$wrapper.value
}

function Get-LocalWebSnapshot {
    param($Configuration)
    if (-not [IO.File]::Exists($Configuration.StorePath)) { return [pscustomobject]@{ exists = $false; revision = 'absent'; document = $null; readAt = [DateTime]::UtcNow.ToString('o'); capabilities = [pscustomobject]@{ create = $false; update = $false; humanResponse = $false; humanResponseReason = 'AR-TEMP: #20-Vertrag nicht freigegeben' }; lock = [pscustomobject]@{ state = 'unknown'; observedAt = [DateTime]::UtcNow.ToString('o'); owner = $null }; teams = [pscustomobject]@{ available = $false; reason = 'Keine freigegebene Teamprojektion vorhanden.'; items = @() } } }
    $caller = Join-Path $Configuration.RepositoryRoot 'scripts/workitems/Get-WorkItems.ps1'
    $snapshot = & $caller -Path $Configuration.StorePath -RepositoryRoot $Configuration.RepositoryRoot -TimeoutMilliseconds 5000
    [pscustomobject][ordered]@{
        exists = [bool]$snapshot.Exists; revision = [string]$snapshot.Revision; document = $snapshot.Document
        readAt = [DateTime]::UtcNow.ToString('o')
        capabilities = [pscustomobject]@{ create = $true; update = $true; humanResponse = $false; humanResponseReason = 'AR-TEMP: #20-Vertrag nicht freigegeben' }
        lock = [pscustomobject]@{ state = 'unknown'; observedAt = [DateTime]::UtcNow.ToString('o'); owner = $null }
        teams = [pscustomobject]@{ available = $false; reason = 'Keine freigegebene Teamprojektion vorhanden.'; items = @() }
    }
}

function Resolve-LocalWebSpecificationPath {
    param([string]$RepositoryRoot, [string]$Reference, [string[]]$SpecificationDirectories)
    if ([string]::IsNullOrWhiteSpace($Reference) -or $Reference -notmatch '^[a-zA-Z0-9_/.-]+\.md$' -or $Reference.Contains('..') -or $Reference.Contains(':') -or $Reference.StartsWith('/') -or $Reference.StartsWith('\\')) {
        throw 'SpecificationPathInvalid'
    }
    $segments = $Reference -split '[\\/]'
    if (@($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) { throw 'SpecificationPathInvalid' }
    $blocked = '(?i)(^|/)(teams|agents|roles|indices|indexes|auth|authentication|authorization|contracts|schemas|\.github)(/|$)|(^|/)(AGENTS\.md|agenten\.json|roles?\.toml)$|(^|/)(organization|workitems|.*(contract|schema|auth|role|index).*?)\.md$'
    if ($Reference -match $blocked) { throw 'SpecificationPathBlocked' }
    $allowedRoot = $false
    foreach ($directory in $SpecificationDirectories) { if ($Reference.StartsWith(($directory.TrimEnd('/') + '/'), [StringComparison]::OrdinalIgnoreCase)) { $allowedRoot = $true; break } }
    if (-not $allowedRoot) { throw 'SpecificationPathBlocked' }
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $target = [IO.Path]::GetFullPath((Join-Path $root ($Reference -replace '/', [IO.Path]::DirectorySeparatorChar)))
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'SpecificationPathInvalid' }
    $current = $root
    while ($current) {
        if (-not [IO.Directory]::Exists($current) -or (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'SpecificationPathBlocked' }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
    $current = $root
    foreach ($segment in $segments) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { throw 'SpecificationNotFound' }
        if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'SpecificationPathBlocked' }
    }
    if (-not [IO.File]::Exists($target)) { throw 'SpecificationNotFound' }
    return $target
}

function Invoke-LocalWebOperation {
    param($Request, $Configuration)
    $writeAttempt = $false
    $writeResult = $null
    $allowedEnvelope = @('transportVersion', 'requestId', 'operation', 'payload')
    if ($null -eq $Request -or $Request -isnot [System.Management.Automation.PSCustomObject] -or @($Request.PSObject.Properties.Name | Where-Object { $_ -notin $allowedEnvelope }).Count -gt 0 -or @($allowedEnvelope | Where-Object { -not $Request.PSObject.Properties[$_] }).Count -gt 0) {
        return (Get-LocalWebFailure -Code 'MalformedRequest' -Message 'Request envelope must contain only transportVersion, requestId, operation and payload.' -StatusCode 400)
    }
    $requestId = [string]$Request.requestId
    $operation = [string]$Request.operation
    if ($Request.transportVersion -cne '1' -or $requestId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -or $Request.payload -isnot [System.Management.Automation.PSCustomObject]) {
        return (Get-LocalWebFailure -Code 'MalformedRequest' -Message 'Unsupported transport version, request id or payload.' -StatusCode 400)
    }
    if ($operation -eq 'humanResponse') { return (Get-LocalWebFailure -Code 'HumanResponseContractBlocked' -Message 'AR-TEMP: Human Response ist bis zur Freigabe des #20-Vertrags gesperrt.' -StatusCode 503) }
    if ($operation -notin @('read', 'specification', 'metrics', 'create', 'update')) { return (Get-LocalWebFailure -Code 'UnknownOperation' -Message 'Operation ist nicht unterstützt.' -StatusCode 400) }

    try {
        switch ($operation) {
            'read' {
                if (@($Request.payload.PSObject.Properties).Count -ne 0) { return (Get-LocalWebFailure -Code 'UnknownProperty' -Message 'read erwartet ein leeres payload.' -StatusCode 400) }
                $data = Get-LocalWebSnapshot $Configuration
            }
            'specification' {
                $allowed = @('workItemId', 'expectedRevision')
                if (@($Request.payload.PSObject.Properties.Name | Where-Object { $_ -notin $allowed }).Count -gt 0 -or @($allowed | Where-Object { -not $Request.payload.PSObject.Properties[$_] }).Count -gt 0) { return (Get-LocalWebFailure -Code 'UnknownProperty' -Message 'specification erwartet workItemId und expectedRevision.' -StatusCode 400) }
                $snapshot = Get-LocalWebSnapshot $Configuration
                if (-not $snapshot.exists) { return (Get-LocalWebFailure -Code 'StoreMissing' -Message 'WorkItem-Bestand ist nicht vorhanden.' -StatusCode 503) }
                if ($snapshot.revision -cne [string]$Request.payload.expectedRevision) { return (Get-LocalWebFailure -Code 'RevisionConflict' -Message 'WorkItem-Bestand hat sich seit dem Snapshot geändert.' -StatusCode 409 -ExpectedRevision ([string]$Request.payload.expectedRevision) -ActualRevision $snapshot.revision) }
                $items = @($snapshot.document.items | Where-Object { $_.id -ceq [string]$Request.payload.workItemId })
                if ($items.Count -ne 1) { return (Get-LocalWebFailure -Code 'ItemNotFound' -Message 'WorkItem wurde nicht eindeutig gefunden.' -StatusCode 404) }
                $item = $items[0]
                if ($item.specification.PSObject.Properties['inline'] -and $null -ne $item.specification.inline) {
                    $data = [pscustomobject]@{ workItemId = $item.id; revision = $snapshot.revision; markdownPath = $null; content = $item.specification.inline }
                } elseif ($item.specification.PSObject.Properties['markdown'] -and $null -ne $item.specification.markdown) {
                    $path = Resolve-LocalWebSpecificationPath $Configuration.RepositoryRoot ([string]$item.specification.markdown) $Configuration.SpecificationDirectories
                    $content = [IO.File]::ReadAllText($path, (New-Object Text.UTF8Encoding($false, $true)))
                    $data = [pscustomobject]@{ workItemId = $item.id; revision = $snapshot.revision; markdownPath = [string]$item.specification.markdown; content = $content }
                } else { return (Get-LocalWebFailure -Code 'SpecificationUnavailable' -Message 'WorkItem besitzt keine lesbare Spezifikation.' -StatusCode 422) }
            }
            'metrics' {
                $allowed = @('workItemId')
                if (@($Request.payload.PSObject.Properties.Name | Where-Object { $_ -notin $allowed }).Count -gt 0 -or @($allowed | Where-Object { -not $Request.payload.PSObject.Properties[$_] }).Count -gt 0) { return (Get-LocalWebFailure -Code 'UnknownProperty' -Message 'metrics erwartet workItemId.' -StatusCode 400) }
                if ([string]::IsNullOrWhiteSpace([string]$Configuration.AccountingDirectory)) { return (Get-LocalWebFailure -Code 'AccountingUnavailable' -Message 'AccountingDirectory wurde beim Start nicht konfiguriert.' -StatusCode 503) }
                $caller = Join-Path $Configuration.RepositoryRoot 'scripts/accounting/Get-WorkItemMetrics.ps1'
                $data = & $caller -StorePath $Configuration.StorePath -WorkItemId ([string]$Request.payload.workItemId) -AccountingDirectory $Configuration.AccountingDirectory -RepositoryRoot $Configuration.RepositoryRoot
            }
            'create' {
                Test-LocalWebAllowedProperties $Request.payload @('expectedRevision', 'item') 'CreatePayload'
                if (@($Request.payload.PSObject.Properties.Name).Count -ne 2 -or -not $Request.payload.PSObject.Properties['expectedRevision'] -or -not $Request.payload.PSObject.Properties['item']) { return (Get-LocalWebFailure -Code 'MalformedCreatePayload' -Message 'create erwartet expectedRevision und item.' -StatusCode 400) }
                $expected = [string]$Request.payload.expectedRevision
                if ([string]::IsNullOrWhiteSpace($expected)) { return (Get-LocalWebFailure -Code 'MalformedCreatePayload' -Message 'expectedRevision muss angegeben sein.' -StatusCode 400) }
                if (-not [IO.File]::Exists($Configuration.StorePath) -or $expected -eq 'absent') { return (Get-LocalWebFailure -Code 'StoreMissing' -Message 'Vorhandener WorkItem-Bestand ist zwingend erforderlich; Create initialisiert keinen Bestand.' -StatusCode 503 -ExpectedRevision $expected) }
                $itemInput = $Request.payload.item
                $createAllowed = @('id','parentId','title','description','owner','goal','priority','dependencies','specification','acceptanceCriteria','dueAt')
                Test-LocalWebAllowedProperties $itemInput $createAllowed 'CreateItem'
                if ($itemInput.PSObject.Properties.Name -contains 'dueAt' -and $null -eq $itemInput.dueAt) { return (Get-LocalWebFailure -Code 'InvalidCreateItem' -Message 'dueAt darf beim Anlegen nur als gültiger Wert gesetzt werden.' -StatusCode 422) }
                $item = ConvertTo-LocalWebPlainObject $itemInput
                $now = [DateTime]::UtcNow.ToString('o')
                $item | Add-Member -NotePropertyName status -NotePropertyValue 'planned'
                $item | Add-Member -NotePropertyName result -NotePropertyValue $null
                $item | Add-Member -NotePropertyName verifications -NotePropertyValue @()
                $item | Add-Member -NotePropertyName humanInteraction -NotePropertyValue $null
                $item | Add-Member -NotePropertyName blockReason -NotePropertyValue $null
                $item | Add-Member -NotePropertyName createdAt -NotePropertyValue $now
                $item | Add-Member -NotePropertyName updatedAt -NotePropertyValue $now
                $item | Add-Member -NotePropertyName implementedAt -NotePropertyValue $null
                $item | Add-Member -NotePropertyName acceptedAt -NotePropertyValue $null
                $caller = Join-Path $Configuration.RepositoryRoot 'scripts/workitems/New-WorkItem.ps1'
                if (-not [IO.File]::Exists($Configuration.StorePath)) { return (Get-LocalWebFailure -Code 'StoreMissing' -Message 'WorkItem-Bestand wurde vor dem Create entfernt; Schreibvorgang gesperrt.' -StatusCode 503 -ExpectedRevision $expected) }
                $writeAttempt = $true
                $callerErrors = @(); $writeResult = & $caller -Item $item -ExpectedRevision $expected -Path $Configuration.StorePath -RepositoryRoot $Configuration.RepositoryRoot -ErrorAction Continue 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $callerErrors += $_ } else { $_ } }
                if ($callerErrors.Count -gt 0) { $failed = $callerErrors | Where-Object { $_.FullyQualifiedErrorId -match '^TemporaryCleanupFailed' } | Select-Object -First 1; if ($failed) { return (Get-LocalWebCallerError $failed -ExpectedRevision $expected -WriteAttempt $true) }; throw $callerErrors[0] }
                $data = [pscustomobject][ordered]@{ revision = [string]$writeResult.Revision; changed = [bool]$writeResult.Changed; id = [string]$writeResult.Id; document = $writeResult.Document }
            }
            'update' {
                Test-LocalWebAllowedProperties $Request.payload @('workItemId','expectedRevision','changes') 'UpdatePayload'
                if (@($Request.payload.PSObject.Properties.Name).Count -ne 3 -or -not $Request.payload.PSObject.Properties['workItemId'] -or -not $Request.payload.PSObject.Properties['expectedRevision'] -or -not $Request.payload.PSObject.Properties['changes']) { return (Get-LocalWebFailure -Code 'MalformedUpdatePayload' -Message 'update erwartet workItemId, expectedRevision und changes.' -StatusCode 400) }
                $workItemId = [string]$Request.payload.workItemId
                $expected = [string]$Request.payload.expectedRevision
                if ([string]::IsNullOrWhiteSpace($workItemId) -or [string]::IsNullOrWhiteSpace($expected)) { return (Get-LocalWebFailure -Code 'MalformedUpdatePayload' -Message 'workItemId und expectedRevision müssen angegeben sein.' -StatusCode 400) }
                if (-not [IO.File]::Exists($Configuration.StorePath)) { return (Get-LocalWebFailure -Code 'StoreMissing' -Message 'Vorhandener WorkItem-Bestand fehlt; Update ist gesperrt.' -StatusCode 503 -ExpectedRevision $expected) }
                $updateAllowed = @('title','description','goal','priority','dueAt','parentId','dependencies','specification','acceptanceCriteria')
                Test-LocalWebAllowedProperties $Request.payload.changes $updateAllowed 'UpdateChanges'
                $snapshot = Get-LocalWebSnapshot $Configuration
                if (-not $snapshot.exists) { return (Get-LocalWebFailure -Code 'StoreMissing' -Message 'WorkItem-Bestand ist nicht vorhanden.' -StatusCode 503) }
                if ($snapshot.revision -cne $expected) { return (Get-LocalWebFailure -Code 'RevisionConflict' -Message 'WorkItem-Bestand hat sich seit dem Formularstand geändert.' -StatusCode 409 -ExpectedRevision $expected -ActualRevision $snapshot.revision) }
                $matches = @($snapshot.document.items | Where-Object { $_.id -ceq $workItemId })
                if ($matches.Count -ne 1) { return (Get-LocalWebFailure -Code 'ItemNotFound' -Message 'WorkItem wurde nicht eindeutig gefunden.' -StatusCode 404) }
                if ($null -ne $matches[0].humanInteraction) { return (Get-LocalWebFailure -Code 'HumanInteractionItemBlocked' -Message 'Items mit einer vorhandenen humanInteraction sind vollständig von der Webbearbeitung gesperrt.' -StatusCode 422) }
                $candidate = ConvertTo-LocalWebPlainObject $matches[0]
                $changes = $Request.payload.changes
                foreach ($property in $changes.PSObject.Properties) {
                    if ($property.Name -eq 'dueAt' -and $null -eq $property.Value) { $candidate.PSObject.Properties.Remove('dueAt'); continue }
                    if ($candidate.PSObject.Properties[$property.Name]) { $candidate.PSObject.Properties[$property.Name].Value = ConvertTo-LocalWebPlainObject $property.Value }
                    else { $candidate | Add-Member -NotePropertyName $property.Name -NotePropertyValue (ConvertTo-LocalWebPlainObject $property.Value) }
                }
                $oldJson = ConvertTo-Json -InputObject $matches[0] -Depth 100 -Compress
                $draftJson = ConvertTo-Json -InputObject $candidate -Depth 100 -Compress
                if ($oldJson -ceq $draftJson) {
                    $data = [pscustomobject][ordered]@{ revision = $snapshot.revision; changed = $false; id = $workItemId; document = $snapshot.document }
                } else {
                    $candidate.updatedAt = [DateTime]::UtcNow.ToString('o')
                    $caller = Join-Path $Configuration.RepositoryRoot 'scripts/workitems/Set-WorkItem.ps1'
                    if (-not [IO.File]::Exists($Configuration.StorePath)) { return (Get-LocalWebFailure -Code 'StoreMissing' -Message 'WorkItem-Bestand wurde vor dem Update entfernt; Schreibvorgang gesperrt.' -StatusCode 503 -ExpectedRevision $expected) }
                    $writeAttempt = $true
                    $callerErrors = @(); $writeResult = & $caller -Id $workItemId -Item $candidate -ExpectedRevision $expected -Path $Configuration.StorePath -RepositoryRoot $Configuration.RepositoryRoot -ErrorAction Continue 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $callerErrors += $_ } else { $_ } }
                    if ($callerErrors.Count -gt 0) { $failed = $callerErrors | Where-Object { $_.FullyQualifiedErrorId -match '^TemporaryCleanupFailed' } | Select-Object -First 1; if ($failed) { return (Get-LocalWebCallerError $failed -ExpectedRevision $expected -WriteAttempt $true) }; throw $callerErrors[0] }
                    $data = [pscustomobject][ordered]@{ revision = [string]$writeResult.Revision; changed = [bool]$writeResult.Changed; id = [string]$writeResult.Id; document = $writeResult.Document }
                }
            }
        }
        return @{ status = 200; response = (New-LocalWebResponse $requestId $operation $true 200 $data $null) }
    } catch {
        if ($_.Exception.Message -match '^Unknown(CreatePayload|CreateItem|UpdatePayload|UpdateChanges):') { return (Get-LocalWebFailure -Code 'UnknownProperty' -Message 'Payload enthält ein nicht erlaubtes Feld.' -StatusCode 400) }
        if ($_.Exception.Message -match '^Malformed(CreatePayload|CreateItem|UpdatePayload|UpdateChanges)') { return (Get-LocalWebFailure -Code 'MalformedRequest' -Message 'Payload oder Item hat nicht das erwartete JSON-Objektformat.' -StatusCode 400) }
        $id = [string]$_.FullyQualifiedErrorId
        if ($id -match 'SpecificationPathInvalid|SpecificationPathBlocked|SpecificationNotFound') {
            $code = $id.Split(',')[0]
            $status = if ($code -eq 'SpecificationNotFound') { 404 } else { 403 }
            $message = if ($code -eq 'SpecificationNotFound') { 'Spezifikationsdatei wurde nicht gefunden.' } elseif ($code -eq 'SpecificationPathBlocked') { 'Spezifikationspfad ist nicht freigegeben.' } else { 'Spezifikationsreferenz ist ungültig.' }
            return (Get-LocalWebFailure -Code $code -Message $message -StatusCode $status)
        }
        if ($writeAttempt -and $_.FullyQualifiedErrorId -match '^RevisionConflict') {
            try {
                $fresh = Get-LocalWebSnapshot $Configuration
                if ($fresh.exists -and -not [string]::IsNullOrWhiteSpace($fresh.revision)) { $_.Exception.Data['LocalWebFreshRevision'] = $fresh.revision }
            } catch { }
        }
        return (Get-LocalWebCallerError $_ -ExpectedRevision $(if ($operation -in @('create','update')) { [string]$Request.payload.expectedRevision }) -WriteAttempt $writeAttempt)
    }
}

Export-ModuleMember -Function Invoke-LocalWebOperation, Get-LocalWebFailure, New-LocalWebResponse
