# JSON Schema subset used by schemas/*.schema.json; no external runtime required.
function Read-ContractJson([string]$Path) {
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, $utf8)
    return ,($text | ConvertFrom-Json -ErrorAction Stop)
}

function Test-ContractProperty($Value, [string]$Name) {
    return ($null -ne $Value -and @($Value.PSObject.Properties.Name) -ccontains $Name)
}

function Get-ContractCanonicalJson($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $parts = foreach ($name in @($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive)) {
            ($name | ConvertTo-Json -Compress) + ':' + (Get-ContractCanonicalJson $Value.$name)
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [Array]) {
        $parts = foreach ($entry in $Value) { Get-ContractCanonicalJson $entry }
        return '[' + ($parts -join ',') + ']'
    }
    return (ConvertTo-Json -InputObject $Value -Compress -Depth 100)
}

function Assert-ContractSchemaVocabulary($Schema, $RootSchema = $Schema) {
    if ($Schema -isnot [System.Management.Automation.PSCustomObject]) { throw 'Schema must be an object.' }
    $supported = @('$schema','$id','$ref','$defs','$comment','title','description','type','const','enum','anyOf','required','properties','additionalProperties','items','minItems','uniqueItems','minLength','pattern','format','x-statusTransitions')
    foreach ($name in $Schema.PSObject.Properties.Name) {
        if ($supported -cnotcontains $name) { throw "Unsupported schema keyword: $name" }
    }
    foreach ($key in @('properties','$defs')) {
        if (Test-ContractProperty $Schema $key) {
            foreach ($property in $Schema.$key.PSObject.Properties) { Assert-ContractSchemaVocabulary $property.Value $RootSchema }
        }
    }
    if (Test-ContractProperty $Schema 'items') { Assert-ContractSchemaVocabulary $Schema.items $RootSchema }
    if (Test-ContractProperty $Schema 'anyOf') {
        foreach ($branch in $Schema.anyOf) { Assert-ContractSchemaVocabulary $branch $RootSchema }
    }
    if ((Test-ContractProperty $Schema '$ref') -and $Schema.'$ref' -notmatch '^#/\$defs/[a-zA-Z0-9_]+$') {
        throw 'Only local definition references are supported.'
    }
    if ((Test-ContractProperty $Schema '$ref') -and -not (Test-ContractProperty $RootSchema.'$defs' $Schema.'$ref'.Substring(8))) {
        throw "Missing schema definition: $($Schema.'$ref')"
    }
    if ((Test-ContractProperty $Schema 'format') -and $Schema.format -cne 'date-time') { throw 'Unsupported schema format.' }
}

function Assert-ContractSchema($Value, $Schema, $RootSchema, [string]$Location = '$') {
    if (Test-ContractProperty $Schema '$ref') {
        $name = $Schema.'$ref'.Substring(8)
        if (-not (Test-ContractProperty $RootSchema.'$defs' $name)) { throw "Missing schema definition: $name" }
        Assert-ContractSchema $Value $RootSchema.'$defs'.$name $RootSchema $Location
    }
    if (Test-ContractProperty $Schema 'type') {
        $valid = switch -CaseSensitive ($Schema.type) {
            'null' { $null -eq $Value }
            'object' { $Value -is [System.Management.Automation.PSCustomObject] }
            'array' { $Value -is [Array] }
            'string' { $Value -is [string] }
            'boolean' { $Value -is [bool] }
            default { throw "Unsupported schema type: $($Schema.type)" }
        }
        if (-not $valid) { throw "Schema type at ${Location}: expected $($Schema.type)" }
    }
    if ((Test-ContractProperty $Schema 'const') -and (Get-ContractCanonicalJson $Value) -cne (Get-ContractCanonicalJson $Schema.const)) {
        throw "Schema const at $Location"
    }
    if (Test-ContractProperty $Schema 'enum') {
        $encoded = Get-ContractCanonicalJson $Value
        $choices = @($Schema.enum | ForEach-Object { Get-ContractCanonicalJson $_ })
        if ($choices -cnotcontains $encoded) { throw "Schema enum at $Location" }
    }
    if (Test-ContractProperty $Schema 'anyOf') {
        $matched = $false
        foreach ($branch in $Schema.anyOf) {
            try { Assert-ContractSchema $Value $branch $RootSchema $Location; $matched = $true; break } catch { }
        }
        if (-not $matched) { throw "Schema anyOf at $Location" }
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        if (Test-ContractProperty $Schema 'required') {
            foreach ($name in $Schema.required) {
                if (-not (Test-ContractProperty $Value $name)) { throw "Schema required at ${Location}: $name" }
            }
        }
        foreach ($property in $Value.PSObject.Properties) {
            if ((Test-ContractProperty $Schema 'properties') -and (Test-ContractProperty $Schema.properties $property.Name)) {
                Assert-ContractSchema $property.Value $Schema.properties.($property.Name) $RootSchema ($Location + '.' + $property.Name)
            } elseif ((Test-ContractProperty $Schema 'additionalProperties') -and $Schema.additionalProperties -eq $false) {
                throw "Schema additional property at ${Location}: $($property.Name)"
            }
        }
    }
    if ($Value -is [Array]) {
        if ((Test-ContractProperty $Schema 'minItems') -and $Value.Count -lt $Schema.minItems) { throw "Schema minItems at $Location" }
        if ((Test-ContractProperty $Schema 'uniqueItems') -and $Schema.uniqueItems) {
            $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($entry in $Value) {
                if (-not $seen.Add((Get-ContractCanonicalJson $entry))) { throw "Schema uniqueItems at $Location" }
            }
        }
        if (Test-ContractProperty $Schema 'items') {
            for ($i = 0; $i -lt $Value.Count; $i++) { Assert-ContractSchema $Value[$i] $Schema.items $RootSchema ($Location + '[' + $i + ']') }
        }
    }
    if ($Value -is [string]) {
        if ((Test-ContractProperty $Schema 'minLength') -and $Value.Length -lt $Schema.minLength) { throw "Schema minLength at $Location" }
        if ((Test-ContractProperty $Schema 'pattern') -and -not [regex]::IsMatch($Value, $Schema.pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
            throw "Schema pattern at $Location"
        }
        if (Test-ContractProperty $Schema 'format') {
            $date = [DateTimeOffset]::MinValue
            if ($Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?Z$' -or
                -not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) {
                throw "Schema date-time at $Location"
            }
        }
    }
}

function Assert-ContractDocument($Value, [string]$SchemaPath) {
    $schema = Read-ContractJson $SchemaPath
    Assert-ContractSchemaVocabulary $schema
    Assert-ContractSchema $Value $schema $schema
}

function Assert-ContractGraph($Edges, [string]$Kind) {
    # Iterative DFS: task depth is not limited by PowerShell's call stack.
    $colors = @{}
    foreach ($start in $Edges.Keys) {
        if ($colors[$start] -eq 2) { continue }
        $stack = New-Object 'System.Collections.Generic.Stack[object]'
        $stack.Push(@{ id = $start; exit = $false })
        while ($stack.Count -gt 0) {
            $node = $stack.Pop()
            if ($node.exit) { $colors[$node.id] = 2; continue }
            if ($colors[$node.id] -eq 1) { throw "$Kind cycle: $($node.id)" }
            if ($colors[$node.id] -eq 2) { continue }
            $colors[$node.id] = 1
            $stack.Push(@{ id = $node.id; exit = $true })
            foreach ($next in $Edges[$node.id]) { $stack.Push(@{ id = $next; exit = $false }) }
        }
    }
}

function Assert-ContractRelativeFile([string]$Root, [string]$Reference) {
    if ([IO.Path]::IsPathRooted($Reference) -or ($Reference -split '[/\\]') -contains '..') { throw "Unsafe relative reference: $Reference" }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Reference))
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Missing referenced file: $Reference"
    }
    # Do not follow junctions/symlinks outside the repository.
    $cursor = Get-Item -LiteralPath $full
    while ($null -ne $cursor -and $cursor.FullName -ne $base.TrimEnd('\','/')) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse reference: $Reference" }
        $cursor = if ($cursor -is [IO.DirectoryInfo]) { $cursor.Parent } else { $cursor.Directory }
    }
    return $full
}

function Assert-ContractRole([string]$Path, [string]$Id) {
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $text = [IO.File]::ReadAllText($Path, $utf8)
    $match = [regex]::Match($text, '(?m)^name\s*=\s*"([a-z][a-z0-9_]*)"\s*$')
    if (-not $match.Success -or $match.Groups[1].Value -cne $Id) { throw "Role name mismatch: $Id" }
}
