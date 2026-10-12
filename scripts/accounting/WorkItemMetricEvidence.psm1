# Concrete accounting projection design. Does not mutate a WorkItem or fetch evidence sources.
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1') -Force
function Get-Reviewer($Value) {
    if ($Value -isnot [pscustomobject] -or (Get-Field $Value 'type') -cnotin @('human','agent')) { throw 'Reviewer must be the canonical actor object.' }
    $null = Get-Text (Get-Field $Value 'id')
    return $Value
}
function Get-Criteria($Values) {
    if ($Values -isnot [array] -or $Values.Count -eq 0) { throw 'Nonempty version criteria array required.' }
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $criteria = @()
    foreach ($value in $Values) {
        $id = Get-Text (Get-Field $value 'id')
        $description = Get-Text (Get-Field $value 'description')
        if (-not $ids.Add($id)) { throw 'Duplicate criterion ID.' }
        $criteria += @([pscustomobject]@{id=$id; description=$description})
    }
    return ,$criteria
}
function Get-WorkItemEvidenceProjection($Item, [string]$StoreSource, $VersionSnapshots) {
    $gaps = @(); $rawDecisions = @(); $complete = @(); $goals = @()
    $measurementById = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $measurementConflict = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $versionByTime = @{}; $versionConflicts = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $history = @(); $historyInvalid = $false; $implementedVersions = @{}
    $currentTime = if ($null -ne $Item.implementedAt) { (Get-UtcTime $Item.implementedAt).ToString('o') } else { $null }
    if ($null -ne $currentTime) {
        $versionByTime[$currentTime] = [pscustomobject]@{
            criteria=(Get-Criteria @($Item.acceptanceCriteria)); goal=$Item.goal
            source=$StoreSource; implementedAt=$currentTime
        }
        $implementedVersions[$currentTime] = $StoreSource
    }
    foreach ($snapshot in @($VersionSnapshots)) {
        $key = $null
        try {
            $document = $snapshot.document
            if ((Get-Field $document 'id') -cne $Item.id -or $snapshot.workItemId -cne $Item.id) { throw 'Snapshot WorkItem binding mismatch.' }
            if ($null -eq (Get-Field $document 'implementedAt')) { continue }
            $key = (Get-UtcTime $document.implementedAt).ToString('o')
            $criteria = Get-Criteria $document.acceptanceCriteria
            foreach ($name in @('metric','target','description')) { $null = Get-Text (Get-Field $document.goal $name) }
            $version = [pscustomobject]@{criteria=$criteria; goal=$document.goal; source=$snapshot.source; implementedAt=$key}
            if ($versionByTime.ContainsKey($key)) {
                $prior = $versionByTime[$key]
                if ((Get-CanonicalJson @(@($prior.criteria | Sort-Object id),$prior.goal)) -cne (Get-CanonicalJson @(@($criteria | Sort-Object id),$document.goal))) { throw 'Persisted version snapshot criteria/goal conflict.' }
            } else { $versionByTime[$key] = $version }
            $implementedVersions[$key] = $snapshot.source
        } catch {
            if ($null -ne $key) { $null = $versionConflicts.Add($key) }
            $gaps += @([pscustomobject]@{workItemId=$Item.id; implementedAt=$key; reason='invalid_or_conflicting_persisted_version_snapshot'; detail=$_.Exception.Message})
        }
    }
    # Scan the entire evidence set before resolving any goal decision. A conflicting
    # measurement ID is permanently poisoned, including malformed later/earlier claims.
    foreach ($line in @(Get-Field $Item.result 'evidence')) {
        if ($line -isnot [string]) { continue }
        if ($line.StartsWith('workitem-goal-measurement/v1:',[StringComparison]::Ordinal)) {
            $m = $null; $id = $null
            try {
                $raw = ConvertFrom-Json -InputObject $line.Substring('workitem-goal-measurement/v1:'.Length) -ErrorAction Stop
                $id = Get-Text (Get-Field $raw 'measurementId')
                $m = Get-EvidenceJson $line 'workitem-goal-measurement/v1:'
                if ($m.workItemId -cne $Item.id) { throw 'Wrong measurement WorkItem.' }
                foreach ($name in @('metric','target','unit','value','source','definition','period')) { $null = Get-Text (Get-Field $m $name) }
                $null = Get-UtcTime (Get-Field $m 'measuredAt')
                if ($measurementConflict.Contains($id)) { continue }
                if ($measurementById.ContainsKey($id) -and (Get-CanonicalJson $measurementById[$id]) -cne (Get-CanonicalJson $m)) {
                    $null = $measurementConflict.Add($id)
                    $measurementById.Remove($id)
                    throw 'Measurement ID conflict.'
                }
                $measurementById[$id] = $m
            } catch {
                if ($null -ne $id) { $null = $measurementConflict.Add($id); $measurementById.Remove($id) }
                $gaps += @([pscustomobject]@{workItemId=$Item.id; measurementId=$id; reason='invalid_or_conflicting_measurement'; detail=$_.Exception.Message})
            }
        } elseif ($line.StartsWith('workitem-version-evidence/v1:',[StringComparison]::Ordinal)) {
            $key = $null
            try {
                $v = Get-EvidenceJson $line 'workitem-version-evidence/v1:'
                if ($v.workItemId -cne $Item.id) { throw 'Wrong version WorkItem.' }
                $key = (Get-UtcTime $v.implementedAt).ToString('o')
                $source = Get-Text $v.source
                $criteria = Get-Criteria $v.criteria
                foreach ($name in @('metric','target','description')) { $null = Get-Text (Get-Field $v.goal $name) }
                $version = [pscustomobject]@{criteria=$criteria; goal=$v.goal; source=$source; implementedAt=$key}
                if ($versionByTime.ContainsKey($key)) {
                    $prior = $versionByTime[$key]
                    # Sources may differ, contents must agree. Current store always supplies
                    # current version criteria; an old snapshot never overwrites it.
                    $left = Get-CanonicalJson @(@($prior.criteria | Sort-Object id),$prior.goal)
                    $right = Get-CanonicalJson @(@($criteria | Sort-Object id),$v.goal)
                    if ($left -cne $right) { throw 'Version criteria/goal conflict.' }
                } else { $versionByTime[$key] = $version }
                $implementedVersions[$key] = $source
            } catch {
                if ($null -ne $key) { $null = $versionConflicts.Add($key) }
                $gaps += @([pscustomobject]@{workItemId=$Item.id; implementedAt=$key; reason='invalid_or_conflicting_version_source'; detail=$_.Exception.Message})
            }
        } elseif ($line.StartsWith('workitem-review-history/v1:',[StringComparison]::Ordinal)) {
            try {
                $h = Get-EvidenceJson $line 'workitem-review-history/v1:'
                if ($h.workItemId -cne $Item.id) { throw 'Wrong history WorkItem.' }
                $null = Get-Text $h.source
                $null = Get-Text $h.firstDecisionSource
                $h.firstCheckedAt = (Get-UtcTime $h.firstCheckedAt).ToString('o')
                $history += @($h)
            } catch { $historyInvalid = $true; $gaps += @([pscustomobject]@{workItemId=$Item.id; reason='invalid_history_source'; detail=$_.Exception.Message}) }
        }
    }
    $decisionByKey = @{}; $decisionConflicts = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($verification in @($Item.verifications)) {
        $versionKey = $null; $decisionKey = $null; $valid = $true; $criteriaSource = $null
        try {
            $versionKey = (Get-UtcTime $verification.implementedAt).ToString('o')
            $checked = Get-UtcTime $verification.checkedAt
            $reviewer = Get-Reviewer $verification.reviewer
            if ($checked -lt (Get-UtcTime $verification.implementedAt)) { throw 'Review precedes implementation.' }
            $decisionKey = $versionKey+'/'+$checked.ToString('o')
            if ($verification.passed -isnot [bool]) { throw 'Decision must be boolean.' }
            $implementedVersions[$versionKey] = 'stored verification '+$decisionKey
            if (-not $versionByTime.ContainsKey($versionKey) -or $versionConflicts.Contains($versionKey)) { throw 'Historical version criteria/goal source missing or conflicting.' }
            $criteriaSource = $versionByTime[$versionKey]
            $expectedIds = @($criteriaSource.criteria | ForEach-Object { $_.id })
            $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            $passed = $true
            foreach ($result in @($verification.results)) {
                $id = Get-Text $result.criterionId
                if (-not $seen.Add($id) -or $expectedIds -cnotcontains $id -or $result.passed -isnot [bool]) { throw 'Missing, duplicate, unknown or invalid criterion result.' }
                $null = Get-Text $result.evidence
                $passed = $passed -and $result.passed
            }
            if ($seen.Count -ne $expectedIds.Count -or $verification.passed -ne $passed) { throw 'Incomplete or inconsistent review.' }
            $decision = [pscustomobject]@{
                workItemId=$Item.id; implementedAt=$versionKey; checkedAt=$checked.ToString('o')
                reviewer=$reviewer; passed=$passed; results=@($verification.results)
                criteria=@($criteriaSource.criteria); criteriaSource=$criteriaSource.source
                goal=$criteriaSource.goal; key=$decisionKey
            }
            if ($decisionByKey.ContainsKey($decisionKey) -and (Get-CanonicalJson $decisionByKey[$decisionKey]) -cne (Get-CanonicalJson $decision)) {
                $null = $decisionConflicts.Add($decisionKey)
                $decisionByKey.Remove($decisionKey)
                throw 'Conflicting decisions at same implementation/review time.'
            }
            if (-not $decisionConflicts.Contains($decisionKey)) { $decisionByKey[$decisionKey] = $decision }
        } catch {
            $valid = $false
            if ($null -ne $decisionKey) { $null = $decisionConflicts.Add($decisionKey); $decisionByKey.Remove($decisionKey) }
            $gaps += @([pscustomobject]@{workItemId=$Item.id; implementedAt=$versionKey; reason='review_completeness_unknown'; detail=$_.Exception.Message})
        }
        foreach ($result in @($verification.results)) {
            $rawDecisions += @([pscustomobject]@{
                workItemId=$Item.id; implementedAt=$verification.implementedAt
                checkedAt=$verification.checkedAt; reviewer=$verification.reviewer
                criterionId=$result.criterionId; passed=$result.passed; evidence=$result.evidence
                decisionKey=$decisionKey; completeDecision=$valid; criteriaSource=$(if ($null -ne $criteriaSource) { $criteriaSource.source } else { $null })
            })
        }
    }
    $complete = @($decisionByKey.Values | Sort-Object checkedAt,implementedAt)
    foreach ($raw in $rawDecisions) {
        $raw.completeDecision = ($null -ne $raw.decisionKey -and $decisionByKey.ContainsKey($raw.decisionKey) -and -not $decisionConflicts.Contains($raw.decisionKey))
    }
    $firstObserved = if ($complete.Count -gt 0) { $complete[0] } else { $null }
    $firstAcceptance = $null; $firstBasis = 'unknown_first_review_source_missing'; $historyComplete = $false
    $distinctHistory = @($history | ForEach-Object { Get-CanonicalJson $_ } | Select-Object -Unique)
    if ($distinctHistory.Count -eq 1 -and -not $historyInvalid) {
        $h = $history[0]
        $first = @($complete | Where-Object { $_.checkedAt -ceq $h.firstCheckedAt })
        $earlierRaw = @($Item.verifications | Where-Object { (Get-UtcTime $_.checkedAt) -lt (Get-UtcTime $h.firstCheckedAt) })
        $firstRaw = @($Item.verifications | Where-Object { (Get-UtcTime $_.checkedAt).ToString('o') -ceq $h.firstCheckedAt })
        if ($first.Count -eq 1 -and $earlierRaw.Count -eq 0 -and $firstRaw.Count -eq 1) {
            # Fachbasis: first proven REVIEW ATTEMPT, not inferred first implementation.
            $firstAcceptance = $first[0].passed
            $firstBasis = [pscustomobject]@{source=$h.firstDecisionSource; checkedAt=$h.firstCheckedAt; decision=$first[0]}
        } else { $firstBasis = 'unknown_first_review_missing_incomplete_or_contradicted' }
        if ((Get-Field $h 'historyComplete') -is [bool] -and $h.historyComplete) {
            try {
                if ($h.decisionKeys -isnot [array] -or $h.implementedVersions -isnot [array]) { throw 'History manifest arrays required.' }
                $manifestVersions = @($h.implementedVersions | ForEach-Object { (Get-UtcTime $_).ToString('o') } | Sort-Object -Unique)
                $actualVersions = @($implementedVersions.Keys | Sort-Object -Unique)
                $manifestDecisions = @($h.decisionKeys | Sort-Object -Unique)
                $actualDecisions = @($complete | ForEach-Object { $_.key } | Sort-Object -Unique)
                $through = Get-UtcTime $h.coveredThrough
                $historyComplete = ($null -ne $firstAcceptance -and $decisionConflicts.Count -eq 0 -and $versionConflicts.Count -eq 0 -and
                    $complete.Count -eq @($Item.verifications).Count -and
                    (Get-CanonicalJson $manifestVersions) -ceq (Get-CanonicalJson $actualVersions) -and
                    (Get-CanonicalJson $manifestDecisions) -ceq (Get-CanonicalJson $actualDecisions) -and
                    @($complete | Where-Object { (Get-UtcTime $_.checkedAt) -gt $through }).Count -eq 0 -and
                    @($actualVersions | Where-Object { (Get-UtcTime $_) -gt $through }).Count -eq 0)
            } catch { $gaps += @([pscustomobject]@{workItemId=$Item.id; reason='history_manifest_invalid'; detail=$_.Exception.Message}) }
        }
    } elseif ($distinctHistory.Count -gt 1 -or $historyInvalid) { $firstBasis = 'unknown_conflicting_or_invalid_first_review_sources' }
    $failed = @($complete | Where-Object { -not $_.passed })
    $rework = @()
    foreach ($time in @($implementedVersions.Keys)) {
        $predecessors = @($failed | Where-Object { $_.implementedAt -cne $time -and (Get-UtcTime $_.checkedAt) -lt (Get-UtcTime $time) } | Sort-Object checkedAt -Descending)
        if ($predecessors.Count -gt 0) {
            $rework += @([pscustomobject]@{implementedAt=$time; implementationSource=$implementedVersions[$time]; precedingFailedDecision=$predecessors[0]})
        }
    }
    $completedRework = @($rework | Where-Object {
        $version = $_.implementedAt
        @($complete | Where-Object { $_.implementedAt -ceq $version }).Count -gt 0
    })
    # Goal claims are resolved only after all IDs and version/review conflicts are known.
    foreach ($decision in $complete) {
        foreach ($result in $decision.results) {
            if (-not $result.evidence.StartsWith('workitem-goal-decision/v1:',[StringComparison]::Ordinal)) { continue }
            try {
                $claim = Get-EvidenceJson $result.evidence 'workitem-goal-decision/v1:'
                if ($claim.workItemId -cne $Item.id -or (Get-UtcTime $claim.implementedAt).ToString('o') -cne $decision.implementedAt -or $claim.criterionId -cne $result.criterionId) { throw 'Goal decision review/version binding invalid.' }
                if ($claim.goal.metric -cne $decision.goal.metric -or $claim.goal.target -cne $decision.goal.target) { throw 'Wrong version goal.' }
                foreach ($name in @('sourceReview','rationale','unit','definition','period')) { $null = Get-Text (Get-Field $claim $name) }
                if ($claim.assessment -cnotin @('achieved','not_achieved') -or (($claim.assessment -ceq 'achieved') -ne $result.passed)) { throw 'Goal assessment/result inconsistency.' }
                if ($claim.measurementIds -isnot [array] -or $claim.measurementSources -isnot [array] -or $claim.measurementIds.Count -eq 0 -or $claim.measurementIds.Count -ne $claim.measurementSources.Count) { throw 'Measurement binding arrays missing.' }
                $resolved = @(); $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
                for ($i=0; $i -lt $claim.measurementIds.Count; $i++) {
                    $id = Get-Text $claim.measurementIds[$i]
                    $source = Get-Text $claim.measurementSources[$i]
                    if (-not $ids.Add($id) -or $measurementConflict.Contains($id) -or -not $measurementById.ContainsKey($id)) { throw 'Unresolved, duplicate or conflicting measurement ID.' }
                    $m = $measurementById[$id]
                    if ($m.metric -cne $claim.goal.metric -or $m.target -cne $claim.goal.target -or $m.unit -cne $claim.unit -or $m.definition -cne $claim.definition -or $m.period -cne $claim.period -or $m.source -cne $source -or (Get-UtcTime $m.measuredAt) -gt (Get-UtcTime $decision.checkedAt)) { throw 'Measurement context/source/time mismatch.' }
                    $resolved += @($m)
                }
                $scope = Get-Field $claim 'scope'
                if ($null -ne $scope -and $scope -cnotin @('criterion','whole_goal')) { throw 'Invalid goal decision scope.' }
                $whole = ($scope -ceq 'whole_goal')
                if ($whole) {
                    # Explicit overall goal interpretation; no inferred AND/OR from partial results.
                    $null = Get-Text (Get-Field $claim 'goalDefinitionSource')
                    $null = Get-Text (Get-Field $claim 'validityContext')
                }
                $goals += @([pscustomobject]@{
                    workItemId=$Item.id; implementedAt=$decision.implementedAt; checkedAt=$decision.checkedAt
                    reviewer=$decision.reviewer; criterionId=$result.criterionId; assessment=$claim.assessment
                    scope=$(if ($whole) { 'whole_goal' } else { 'criterion' }); measurements=$resolved
                    measurementIds=@($claim.measurementIds); sourceReview=$claim.sourceReview; rationale=$claim.rationale
                    goalDefinitionSource=(Get-Field $claim 'goalDefinitionSource'); validityContext=(Get-Field $claim 'validityContext')
                })
            } catch { $gaps += @([pscustomobject]@{workItemId=$Item.id; criterionId=$result.criterionId; reason='goal_decision_binding_invalid'; detail=$_.Exception.Message}) }
        }
    }
    $wholeGoals = @($goals | Where-Object { $_.implementedAt -ceq $currentTime -and $_.scope -ceq 'whole_goal' })
    $assessments = @($wholeGoals | ForEach-Object { $_.assessment } | Select-Object -Unique)
    $achievement = 'unknown'; $goalBasis = 'explicit_current_whole_goal_decision_missing'
    if ($assessments.Count -eq 1) { $achievement = $assessments[0]; $goalBasis = 'explicit_reviewer_whole_goal_decision_with_bound_sources' }
    elseif ($assessments.Count -gt 1) { $goalBasis = 'conflicting_whole_goal_decisions'; $gaps += @([pscustomobject]@{workItemId=$Item.id; reason=$goalBasis}) }
    $created = Get-UtcTime $Item.createdAt
    $implementationSeconds = $null; $acceptedSeconds = $null
    if ($null -ne $currentTime) {
        if ((Get-UtcTime $currentTime) -ge $created) { $implementationSeconds = ((Get-UtcTime $currentTime)-$created).TotalSeconds }
        else { $gaps += @([pscustomobject]@{workItemId=$Item.id; reason='implementation_precedes_creation'}) }
    }
    if ($null -ne $Item.acceptedAt) {
        $accepted = Get-UtcTime $Item.acceptedAt
        if ($accepted -ge $created -and $null -ne $currentTime -and $accepted -ge (Get-UtcTime $currentTime)) { $acceptedSeconds = ($accepted-$created).TotalSeconds }
        else { $gaps += @([pscustomobject]@{workItemId=$Item.id; reason='acceptance_time_order_invalid'}) }
    }
    $measurements = @($measurementById.Values)
    return [pscustomobject]@{
        lifecycle=[pscustomobject]@{
            id=$Item.id; status=$Item.status; createdAt=$Item.createdAt; implementedAt=$Item.implementedAt; acceptedAt=$Item.acceptedAt
            implementationSeconds=$implementationSeconds; acceptedLeadSeconds=$acceptedSeconds; eventSource=$StoreSource
            firstAcceptance=$firstAcceptance; firstAcceptanceBasis=$firstBasis; firstObservedDecision=$firstObserved
            failedVerificationCount=$failed.Count; evidencedFailedVersionLowerBound=@($failed | ForEach-Object { $_.implementedAt } | Select-Object -Unique).Count
            evidencedReworkFindingLowerBound=@($rawDecisions | Where-Object { $_.passed -is [bool] -and -not $_.passed -and $_.evidence -is [string] -and -not [string]::IsNullOrWhiteSpace($_.evidence) } | ForEach-Object { Get-CanonicalJson @($_.implementedAt,$_.checkedAt,$_.reviewer,$_.criterionId,$_.evidence) } | Select-Object -Unique).Count
            evidencedReworkAttemptLowerBound=$rework.Count; reworkEvidence=$rework
            evidencedCompletedReworkCycleLowerBound=$completedRework.Count
            reworkAttemptCount=$(if ($historyComplete) { $rework.Count } else { $null })
            verificationHistoryCompleteness=$(if ($historyComplete) { 'source_bound_complete' } else { 'unknown' })
            goal=[pscustomobject]@{metric=$Item.goal.metric; target=$Item.goal.target; observations=@($measurements | Where-Object { $_.metric -ceq $Item.goal.metric -and $_.target -ceq $Item.goal.target }); achievement=$achievement; basis=$goalBasis}
        }
        measurements=$measurements; measurementConflictIds=@($measurementConflict)
        criterionDecisions=$rawDecisions; completeDecisions=$complete; goalDecisions=$goals; gaps=$gaps
    }
}
Export-ModuleMember -Function Get-WorkItemEvidenceProjection
