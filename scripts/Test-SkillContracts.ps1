[CmdletBinding()]
param([string]$ResultPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'contracts/ContractValidation.ps1')
$root = Split-Path -Parent $PSScriptRoot
if (-not $ResultPath) { $ResultPath = Join-Path $root 'docs/task60-evidence/test-results.json' }
$tests = New-Object 'System.Collections.Generic.List[object]'
function Check([string]$Name, [bool]$Accept, [scriptblock]$Action) {
    $ok = $true; $detail = 'accepted'
    try { & $Action } catch { $ok = $false; $detail = $_.Exception.Message }
    $tests.Add([pscustomobject]@{name=$Name;expectedAcceptance=$Accept;passed=($ok -eq $Accept);detail=$detail})
}
function Copy-Json($Value) { return ,(ConvertTo-Json -InputObject $Value -Depth 100 -Compress | ConvertFrom-Json) }
function Assert-ParameterDefault($Value, [string]$Type) {
    $numeric = $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [decimal] -or $Value -is [double] -or $Value -is [single]
    $valid = switch -CaseSensitive ($Type) {
        'number' { $numeric }
        'integer' { $numeric -and [Math]::Truncate([double]$Value) -eq [double]$Value }
        'null' { $null -eq $Value }
        'boolean' { $Value -is [bool] }
        'string' { $Value -is [string] }
        'object' { $Value -is [pscustomobject] }
        'array' { $Value -is [array] }
    }
    if (-not $valid) { throw 'Parameter default does not match declared JSON type.' }
}
function Assert-Skills($Document) {
    Assert-ContractDocument $Document (Join-Path $root 'schemas/skills.schema.json')
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($skill in $Document.skills) {
        if (-not $ids.Add($skill.id)) { throw 'Duplicate skill ID.' }
        $file = Assert-ContractRelativeFile $root $skill.scriptPath
        $language = if (Test-ContractProperty $skill 'language') { $skill.language } else { 'powershell' }
        $extension = [IO.Path]::GetExtension($file).ToLowerInvariant()
        if ($extension -in @('.md','.markdown','.mdown','.mkd','.txt','.json')) { throw 'Documentation/data is not executable script code.' }
        $extensions = @{powershell='.ps1';python='.py';javascript='.js'}
        if ($extensions.ContainsKey($language) -and $extension -cne $extensions[$language]) { throw 'Declared language and script extension differ.' }
        if ($language -cne 'powershell' -and -not (Test-ContractProperty $skill 'interpreter')) { throw 'Alternative language needs an explicit interpreter.' }
        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($parameter in $skill.parameters) {
            if (-not $names.Add($parameter.name)) { throw 'Duplicate parameter name.' }
            if (Test-ContractProperty $parameter 'default') { Assert-ParameterDefault $parameter.default $parameter.type }
        }
        if (Test-ContractProperty $skill.result 'parameterRefs') {
            foreach ($reference in $skill.result.parameterRefs) { if (-not $names.Contains($reference)) { throw 'Unknown result parameter reference.' } }
        }
    }
}
function Assert-ResponseText([string]$Text) {
    # Focused text check: retain top-level names BEFORE any parser normalization.
    # Native Node JSON.parse checks standard syntax, not numeric representability.
    $tokenPattern = '"(?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"|true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|[{}\[\],:]|[ \t\r\n]+'
    $tokens = [regex]::Matches($Text,$tokenPattern)
    $end=0; $depth=0
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $significant = @($tokens | Where-Object { $_.Value -notmatch '^[ \t\r\n]+$' })
    for ($i=0; $i -lt $tokens.Count; $i++) {
        $token=$tokens[$i]
        if ($token.Index -ne $end) { throw 'Non-JSON syntax on stdout.' }
        $end=$token.Index+$token.Length
    }
    if ($end -ne $Text.Length) { throw 'Non-JSON syntax on stdout.' }
    for ($i=0; $i -lt $significant.Count; $i++) {
        $token=$significant[$i].Value
        if ($depth -eq 1 -and $token.StartsWith('"') -and $i+1 -lt $significant.Count -and $significant[$i+1].Value -ceq ':') {
            $name=ConvertFrom-Json -InputObject $token
            if (-not $names.Add($name)) { throw ('Duplicate top-level response key: '+$name) }
        }
        if ($token -ceq '{' -or $token -ceq '[') { $depth++ }
        if ($token -ceq '}' -or $token -ceq ']') { $depth-- }
    }
    # result has an empty schema: syntax-check it, then omit its payload from
    # PS5 conversion. Numeric values elsewhere are type-preserving placeholders;
    # no response schema keyword imposes a numeric value/range constraint.
    # JSON.parse may map 1e400 to Infinity; this is NOT payload roundtrip evidence.
    $source = 'const fs=require("fs");const v=JSON.parse(fs.readFileSync(0,"utf8"));if(v!==null&&!Array.isArray(v)&&typeof v==="object"&&Object.hasOwn(v,"result"))v.result=null;process.stdout.write(JSON.stringify(v,(_k,x)=>typeof x==="number"?0:x));'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$script:nodePath
    $start.Arguments='-e "'+$source.Replace('"','\"')+'"'
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    try {
        $null=$process.Start()
        $process.StandardInput.Write($Text); $process.StandardInput.Close()
        $normalized=$process.StandardOutput.ReadToEnd(); $diagnostic=$process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw ('Native JSON.parse rejected stdout: '+$diagnostic) }
    } finally { $process.Dispose() }
    $value = ConvertFrom-Json -InputObject $normalized -ErrorAction Stop
    Assert-ContractDocument $value (Join-Path $root 'schemas/skill-response.schema.json')
}
$script:nodePath = (Get-Command node -CommandType Application -ErrorAction Stop).Source
$fixtureRoot = Join-Path $root ('docs/task60-evidence/.temporary-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixtureRoot | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'fixture.py'), "print('temporary fixture')`n")
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'fixture.js'), "console.log('temporary fixture');`n")
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'fixture.xyz'), 'opaque custom-language metadata fixture')
    Check 'javascript-fixture-syntax' $true {
        $diagnostic = & $script:nodePath --check (Join-Path $fixtureRoot 'fixture.js') 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($diagnostic -join "`n") }
    }
    $base = '{"schemaVersion":"1.0","skills":[{"id":"test-skill","purpose":"Contract fixture","scriptPath":"scripts/Test-Contracts.ps1","parameters":[],"result":{"description":"Any JSON value including null"},"prerequisites":[]}]}' | ConvertFrom-Json
    Check 'workitem-schema' $true { Assert-ContractDocument (Read-ContractJson (Join-Path $root 'docs/task60-evidence/workitem.json')) (Join-Path $root 'schemas/workitems.schema.json') }
    Check 'own-optimizer-role' $true { Assert-ContractRole (Assert-ContractRelativeFile $root 'teams/agent_ressources/agenten/optimierer.toml') 'agent_ressources_optimierer' }
    Check 'own-teamleader-role' $true { Assert-ContractRole (Assert-ContractRelativeFile $root 'teams/agent_ressources/teamleiter.toml') 'teamleiter_agent_ressources' }
    Check 'powershell-default' $true { Assert-Skills $base }
    foreach ($pair in @(@('python','py','python.exe'),@('javascript','js','node.exe'),@('open_language','xyz','custom-runtime'))) {
        $d = Copy-Json $base
        $d.skills[0].scriptPath = 'docs/task60-evidence/' + (Split-Path -Leaf $fixtureRoot) + '/fixture.' + $pair[1]
        $d.skills[0] | Add-Member language $pair[0]; $d.skills[0] | Add-Member interpreter $pair[2]
        Check ('language-'+$pair[0]) $true { Assert-Skills $d }
    }
    foreach ($field in @('id','purpose','scriptPath','parameters','result','prerequisites')) {
        $d=Copy-Json $base; $d.skills[0].PSObject.Properties.Remove($field)
        Check ('missing-'+$field) $false { Assert-Skills $d }
    }
    foreach ($path in @('docs/contracts/WORKITEMS.md','missing.ps1','../outside.ps1','C:/outside.ps1','scripts','scripts/../../outside.ps1')) {
        $d=Copy-Json $base; $d.skills[0].scriptPath=$path
        Check ('path-'+$path) $false { Assert-Skills $d }
    }
    foreach ($change in @('duplicate-id','status','bad-id','case','bad-purpose','bad-result','bad-parameters','bad-prerequisites','interpreter-command','language-mismatch','no-alternative-interpreter','duplicate-parameter','unknown-parameter-ref','default-type')) {
        $d=Copy-Json $base
        switch ($change) {
            'duplicate-id' { $d.skills=@($d.skills[0],(Copy-Json $d.skills[0])) }
            'status' { $d.skills[0] | Add-Member status 'active' }
            'bad-id' { $d.skills[0].id='Bad ID' }
            'case' { $d = ((ConvertTo-Json -InputObject $d -Depth 100) -creplace '"purpose"','"Purpose"') | ConvertFrom-Json }
            'bad-purpose' { $d.skills[0].purpose=' ' }
            'bad-result' { $d.skills[0].result=$null }
            'bad-parameters' { $d.skills[0].parameters='text' }
            'bad-prerequisites' { $d.skills[0].prerequisites=@(1) }
            'interpreter-command' { $d.skills[0] | Add-Member interpreter 'pwsh -Command evil' }
            'language-mismatch' { $d.skills[0] | Add-Member language 'python'; $d.skills[0] | Add-Member interpreter 'python' }
            'no-alternative-interpreter' { $d.skills[0] | Add-Member language 'open_language' }
            'duplicate-parameter' { $d.skills[0].parameters=@(('{"name":"x","type":"string","required":true}'|ConvertFrom-Json),('{"name":"x","type":"string","required":false}'|ConvertFrom-Json)) }
            'unknown-parameter-ref' { $d.skills[0].result | Add-Member parameterRefs @('missing') }
            'default-type' { $d.skills[0].parameters=@(('{"name":"x","type":"number","required":false,"default":"text"}'|ConvertFrom-Json)) }
        }
        Check $change $false { Assert-Skills $d }
    }
    foreach ($pair in @(@('null','null'),@('boolean','true'),@('number','3.25'),@('string','"hello"'),@('object','{"items":[1,2,3]}'),@('array','[null,false,1,"x",{}]'))) {
        $response='{"isSuccessful":true,"exception":null,"result":'+$pair[1]+'}'
        Check ('response-'+$pair[0]) $true { Assert-ResponseText $response }
    }
    Check 'issue60-original-success' $true { Assert-ResponseText '{"isSuccessful":true,"exception":null,"result":{"items":[1,2,3]}}' }
    Check 'issue60-original-failure' $true { Assert-ResponseText '{"isSuccessful":false,"exception":{"message":"Ung\u00fcltige Eingabe"},"result":null}' }
    Check 'runner-error-template' $true { Assert-ResponseText ([IO.File]::ReadAllText((Join-Path $root 'docs/task60-evidence/runner-error.json'))) }
    Check 'failure-result-arbitrary' $true { Assert-ResponseText '{"isSuccessful":false,"exception":{"message":"failed","code":42},"result":[1]}' }
    foreach ($payload in @('1e400','-1e400','{"huge":1e400,"nested":[-1e400,{"tiny":1e-4000}]}','[1e400,1e-4000]','{"x":1,"x":2}','{"Result":1,"result":2}')) {
        Check ('unrestricted-result-'+$payload) $true { Assert-ResponseText ('{"isSuccessful":true,"exception":null,"result":'+$payload+'}') }
    }
    Check 'failure-result-large-number' $true { Assert-ResponseText '{"isSuccessful":false,"exception":{"message":"failed"},"result":1e400}' }
    foreach ($duplicate in @(
        '{"isSuccessful":false,"isSuccessful":true,"exception":null,"result":null}',
        '{"isSuccessful":true,"exception":null,"exception":null,"result":null}',
        '{"isSuccessful":true,"exception":null,"result":1,"result":2}',
        '{"isSuccessful":true,"exception":null,"result":1,"\u0072esult":2}'
    )) { Check ('duplicate-response-'+$duplicate) $false { Assert-ResponseText $duplicate } }
    Check 'response-key-case-distinct' $false { Assert-ResponseText '{"isSuccessful":true,"exception":null,"result":null,"Result":null}' }
    $badResponses=@(
        '{}','{"exception":null,"result":null}','{"isSuccessful":true,"result":null}','{"isSuccessful":true,"exception":null}',
        '{"IsSuccessful":true,"exception":null,"result":null}','{"isSuccessful":"true","exception":null,"result":null}',
        '{"isSuccessful":true,"exception":{},"result":null}','{"isSuccessful":false,"exception":null,"result":null}',
        '{"isSuccessful":false,"exception":{},"result":null}','{"isSuccessful":false,"exception":{"message":" "},"result":null}',
        '{"isSuccessful":false,"exception":{"message":1},"result":null}','{"isSuccessful":false,"exception":"error","result":null}',
        '{"isSuccessful":true,"exception":null,"result":null,"status":"ok"}','not JSON',
        '{"isSuccessful":true,"exception":null,"result":null} {}',
        'log line {"isSuccessful":true,"exception":null,"result":null}',
        '{"isSuccessful":true,"exception":null,"result":null} trailing','[]','null',
        '{isSuccessful:true,"exception":null,"result":null}',
        '{"isSuccessful":true,"exception":null,"result":null,}',
        '{"isSuccessful":true,"exception":null,"result":01}',
        '{"isSuccessful":true,"exception":null,"result":NaN}',
        '{"isSuccessful":true,"exception":null,"result":/*comment*/null}'
    )
    for ($i=0;$i -lt $badResponses.Count;$i++) { Check ('invalid-response-'+$i) $false { Assert-ResponseText $badResponses[$i] } }
    foreach ($pair in @(@('null','null'),@('boolean','false'),@('integer','12'),@('number','1.5'),@('string','"x"'),@('object','{}'),@('array','[]'))) {
        $d=Copy-Json $base; $d.skills[0].parameters=@(('{"name":"input","type":"'+$pair[0]+'","required":false,"default":'+$pair[1]+'}'|ConvertFrom-Json))
        $d.skills[0].result | Add-Member parameterRefs @('input')
        Check ('parameter-'+$pair[0]) $true { Assert-Skills $d }
    }
} finally {
    # Only this invocation's verified, repository-contained temporary fixture directory.
    $resolved=[IO.Path]::GetFullPath($fixtureRoot)
    $allowed=[IO.Path]::GetFullPath((Join-Path $root 'docs/task60-evidence'))+[IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$failed=@($tests | Where-Object { -not $_.passed })
$report=[pscustomobject]@{task=60;runtime=$PSVersionTable.PSVersion.ToString();total=$tests.Count;passed=($tests.Count-$failed.Count);failed=$failed.Count;tests=@($tests.ToArray());globalStoreGraphValidator='NOT_RUN';independentQA='PENDING';teamLeaderAcceptance='PENDING'}
[IO.File]::WriteAllText($ResultPath,($report|ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
$report | Select-Object total,passed,failed
if ($failed.Count -gt 0) { $failed | Format-Table name,detail; throw 'Skill contract tests failed.' }
