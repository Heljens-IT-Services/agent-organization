$ErrorActionPreference = 'Stop'

function Get-WorkContextIndexRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('knowledge', 'workflow')][string]$Kind
    )

    $indexRelative = if ($Kind -eq 'knowledge') { 'knowledge/INDEX.md' } else { 'workflows/INDEX.md' }
    $indexPath = Join-Path $RepositoryRoot $indexRelative
    try {
        Assert-WorkContextPathChain -RepositoryRoot $RepositoryRoot -RelativePath $indexRelative -RequireFile
        $lines = [IO.File]::ReadAllLines($indexPath, [Text.Encoding]::UTF8)
    }
    catch {
        $diagnostic = if ($_.Exception.Message -eq 'IndexedFileNotFound') { 'index_missing' } elseif ($_.Exception.Message -eq 'IndexedPathReparsePointRejected') { 'index_reparse_rejected' } else { 'index_unreadable' }
        return [pscustomobject]@{ Kind = $Kind; IndexPath = $indexPath; Diagnostic = $diagnostic; Rows = @(); Incomplete = $false }
    }
    $rows = @()
    $diagnostics = @()
    $headerFound = $false
    $separatorFound = $false
    $tableStarted = $false
    $expectedHeaders = if ($Kind -eq 'knowledge') { @('Thema / Produkt', 'Suchworte', 'Gültigkeitskontext', 'Quelle / WorkItem', 'Einordnung', 'Pfad') } else { @('Workflow', 'Zweck und Suchworte', 'Anwendbarkeit', 'Pfad') }
    $expectedCells = $expectedHeaders.Count
    for ($lineNumber = 0; $lineNumber -lt $lines.Count; $lineNumber++) {
        $line = $lines[$lineNumber]
        $trimmed = $line.Trim()
        $hasOuterPipes = $trimmed.StartsWith('|') -and $trimmed.EndsWith('|')
        $cells = if ($hasOuterPipes -and $trimmed.Length -gt 2) { @($trimmed.Substring(1, $trimmed.Length - 2).Split('|') | ForEach-Object { $_.Trim() }) } elseif ($hasOuterPipes) { @() } else { @() }
        if (-not $headerFound) {
            if ($trimmed -match '^\|\s*(Thema\s*/\s*Produkt|Workflow)(\s*\||\s*$)') {
                # The fifth workflow column is optional; retain existing four-column indexes.
                if ($Kind -eq 'workflow' -and $cells.Count -eq 5 -and $cells[4] -ceq 'Skillreferenzen') {
                    $expectedHeaders = @('Workflow', 'Zweck und Suchworte', 'Anwendbarkeit', 'Pfad', 'Skillreferenzen')
                    $expectedCells = 5
                }
                $normalized = @($cells | ForEach-Object { ($_ -replace '\s+', ' ').Trim() })
                $expectedNormalized = @($expectedHeaders | ForEach-Object { ($_ -replace '\s+', ' ').Trim() })
                if ($hasOuterPipes -and $normalized.Count -eq $expectedCells -and [string]::Join("`n", $normalized) -ceq [string]::Join("`n", $expectedNormalized)) { $headerFound = $true; continue }
                $diagnostics += "${indexPath}:$($lineNumber + 1): damaged_table_header"
                continue
            }
            continue
        }
        if (-not $separatorFound) {
            $validSeparator = $false
            if ($hasOuterPipes -and $cells.Count -eq $expectedCells) {
                $validSeparator = @($cells | Where-Object { $_ -notmatch '^:?-{3,}:?$' }).Count -eq 0
            }
            if ($validSeparator) { $separatorFound = $true; $tableStarted = $true; continue }
            $diagnostics += "${indexPath}:$($lineNumber + 1): damaged_table_separator"
            continue
        }
        if ([string]::IsNullOrWhiteSpace($trimmed)) { $tableStarted = $false; continue }
        $hasPipe = $trimmed.Contains('|')
        if (-not $hasPipe) { $tableStarted = $false; continue }
        if (-not $tableStarted -and -not ($trimmed.StartsWith('|') -or $trimmed.EndsWith('|'))) { continue }
        $tableStarted = $true
        if (-not $hasOuterPipes -or $cells.Count -ne $expectedCells) { $diagnostics += "${indexPath}:$($lineNumber + 1): damaged_table_row"; continue }
        if ($Kind -eq 'knowledge') {
            $link = [regex]::Match($cells[5], '^\[[^\]]+\]\(([^)]+)\)$')
            if (-not $link.Success) { $diagnostics += "${indexPath}:$($lineNumber + 1): damaged_path_link"; continue }
            $rows += [pscustomobject]@{ Kind = $Kind; Name = $cells[0]; Terms = $cells[1]; Context = $cells[2]; Source = $cells[3]; Classification = $cells[4]; RelativePath = $link.Groups[1].Value; IndexPath = $indexPath }
        }
        else {
            $link = [regex]::Match($cells[3], '^\[[^\]]+\]\(([^)]+)\)$')
            if (-not $link.Success) { $diagnostics += "${indexPath}:$($lineNumber + 1): damaged_path_link"; continue }
            $skillReferences = @()
            if ($expectedCells -eq 5 -and -not [string]::IsNullOrWhiteSpace($cells[4])) {
                $skillReferences = @($cells[4].Split(',') | ForEach-Object { $_.Trim() })
                if (@($skillReferences | Where-Object { $_ -cnotmatch '^[a-z0-9][a-z0-9_-]{0,127}$' }).Count -gt 0 -or @($skillReferences | Select-Object -Unique).Count -ne $skillReferences.Count) {
                    $diagnostics += "${indexPath}:$($lineNumber + 1): damaged_skill_references"; continue
                }
            }
            $rows += [pscustomobject]@{ Kind = $Kind; Name = $cells[0]; Terms = $cells[1]; Context = $cells[2]; Source = $null; Classification = $null; RelativePath = $link.Groups[1].Value; IndexPath = $indexPath; SkillReferences = @($skillReferences) }
        }
    }
    if (-not $headerFound) { $diagnostics += "${indexPath}: expected_header_missing" }
    elseif (-not $separatorFound) { $diagnostics += "${indexPath}: expected_table_separator_missing" }
    $diagnostic = if ($diagnostics.Count -gt 0) { 'index_damaged' } else { $null }
    return [pscustomobject]@{ Kind = $Kind; IndexPath = $indexPath; Diagnostic = $diagnostic; Diagnostics = @($diagnostics); Rows = $rows; Incomplete = ($diagnostics.Count -gt 0) }
}

function Assert-WorkContextPathChain {
    [CmdletBinding()]
    param([string]$RepositoryRoot, [string]$RelativePath, [switch]$RequireFile)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    if (-not [IO.Directory]::Exists($root)) { throw 'RepositoryRootNotFound' }
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'IndexedPathReparsePointRejected' }
    $current = $root
    $parts = $RelativePath -split '[\\/]'
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $current = Join-Path $current $parts[$i]
        $isFinal = $i -eq ($parts.Count - 1)
        if (-not (Test-Path -LiteralPath $current)) { throw 'IndexedFileNotFound' }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'IndexedPathReparsePointRejected' }
        if (-not $isFinal -and -not $item.PSIsContainer) { throw 'IndexedPathComponentInvalid' }
        if ($isFinal -and $RequireFile -and $item.PSIsContainer) { throw 'IndexedPathComponentInvalid' }
    }
}

function Resolve-WorkContextIndexedPath {
    [CmdletBinding()]
    param([string]$RepositoryRoot, [string]$Kind, [string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath -match '^(?:[A-Za-z]:|\\|/)' -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw 'IndexedPathMustBeRelativeAndContained'
    }
    $baseRelative = if ($Kind -eq 'knowledge') { 'knowledge' } else { 'workflows' }
    $base = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $baseRelative))
    $target = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    $prefix = $base.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $entriesRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'knowledge/entries')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or ($Kind -eq 'knowledge' -and -not $target.StartsWith($entriesRoot, [StringComparison]::OrdinalIgnoreCase)) -or [IO.Path]::GetExtension($target) -ine '.md') {
        throw 'IndexedPathOutsideAllowedMarkdownArea'
    }

    $repositoryPrefix = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $current = [IO.Path]::GetFullPath($RepositoryRoot)
    $relative = $target.Substring($repositoryPrefix.Length)
    foreach ($part in $relative.Split([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) {
        $current = Join-Path $current $part
        if (-not (Test-Path -LiteralPath $current -PathType Leaf) -and -not (Test-Path -LiteralPath $current -PathType Container)) { throw 'IndexedFileNotFound' }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'IndexedPathReparsePointRejected' }
    }
    if (-not [IO.File]::Exists($target)) { throw 'IndexedFileNotFound' }
    return $target
}

function Find-WorkContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('knowledge', 'workflow', 'all')][string]$Kind,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Terms
    )

    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    if (-not [IO.Directory]::Exists($root)) { throw 'RepositoryRootNotFound' }
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [pscustomobject]@{ Kind = $Kind; Diagnostic = 'repository_root_reparse_rejected'; IndexPath = $root }; return }
    $kinds = if ($Kind -eq 'all') { @('knowledge', 'workflow') } else { @($Kind) }
    foreach ($selectedKind in $kinds) {
        $result = Get-WorkContextIndexRows -RepositoryRoot $root -Kind $selectedKind
        if ($result.Diagnostic) {
            [pscustomobject]@{ Kind = $selectedKind; Diagnostic = $result.Diagnostic; IndexPath = $result.IndexPath }
        }
        if ($result.Incomplete) { [pscustomobject]@{ Kind = $selectedKind; Diagnostic = 'discovery_incomplete'; IndexPath = $result.IndexPath; Details = $result.Diagnostics } }
        foreach ($row in $result.Rows) {
            $haystack = @($row.Name, $row.Terms, $row.Context, $row.Source, $row.Classification) -join "`n"
            if ($row.Kind -eq 'workflow') { $haystack += "`n" + (@($row.SkillReferences) -join ' ') }
            $matched = @($Terms | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $haystack.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
            if ($matched.Count -gt 0) {
                [pscustomobject]@{ Kind = $row.Kind; Name = $row.Name; Terms = $row.Terms; Context = $row.Context; Source = $row.Source; Classification = $row.Classification; RelativePath = $row.RelativePath; IndexPath = $row.IndexPath; MatchedTerms = @($matched | Select-Object -Unique); SkillReferences = @(if ($row.Kind -eq 'workflow') { $row.SkillReferences }) }
            }
        }
    }
}

function Read-WorkContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidateSet('knowledge', 'workflow')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    if (-not [IO.Directory]::Exists($root)) { throw 'RepositoryRootNotFound' }
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'RepositoryRootReparsePointRejected' }
    $index = Get-WorkContextIndexRows -RepositoryRoot $root -Kind $Kind
    if ($index.Diagnostic) { throw 'WorkContextIndexUnavailable' }
    $selected = @($index.Rows | Where-Object { $_.RelativePath -ceq $Path })
    if ($selected.Count -ne 1) { throw 'PathMustMatchExactlyOneIndexedEntry' }
    $fullPath = Resolve-WorkContextIndexedPath -RepositoryRoot $root -Kind $Kind -RelativePath $selected[0].RelativePath
    [pscustomobject]@{ Kind = $Kind; Name = $selected[0].Name; RelativePath = $selected[0].RelativePath; IndexPath = $selected[0].IndexPath; Content = [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8); SkillReferences = @(if ($Kind -eq 'workflow') { $selected[0].SkillReferences }) }
}

Export-ModuleMember -Function Find-WorkContext, Read-WorkContext
