$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $PSScriptRoot ('diagnosis-' + [Guid]::NewGuid().ToString('N'))
$script:Passed = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
    Microsoft.PowerShell.Utility\Write-Host "PASS: $Name"
}

try {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts/diagnose-idea-paths.ps1'), [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) 'diagnostic PowerShell syntax'
    # Import only reviewed local function definitions, without scanning the user's IDEs.
    foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $script:UserHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    foreach ($name in @('IDE A', 'IDE B')) { New-Item -ItemType Directory -Path (Join-Path $testRoot $name) -Force | Out-Null }
    $first = Join-Path $testRoot 'IDE A/idea.properties'
    $second = Join-Path $testRoot 'IDE B/idea.properties'
    $utf8 = New-Object Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($first, "# ignored comment`n idea.config.path = ./配置目录`nidea.system.path=./缓存目录", $utf8)
    [IO.File]::WriteAllText($second, 'idea.config.path=${user.home}/custom-config', $utf8)
    $beforeFirst = (Get-FileHash -LiteralPath $first).Hash
    $beforeSecond = (Get-FileHash -LiteralPath $second).Hash

    $values = Get-IdeaPropertyValues $first
    Assert-True ($values['idea.config.path'] -ceq './配置目录' -and $values['idea.system.path'] -ceq './缓存目录') 'configured values with whitespace parsed'
    $candidates = New-Object Collections.ArrayList
    Add-Candidate $candidates $first
    Add-Candidate $candidates $first.ToUpperInvariant()
    Assert-True ($candidates.Count -eq 1) 'case-insensitive discovery deduplication'
    $script:Fixtures = @($first, $second)
    $script:Discoveries = 0
    function Get-IdeaPropertiesCandidates {
        $script:Discoveries++
        $list = New-Object Collections.ArrayList
        foreach ($fixture in $script:Fixtures) { [void]$list.Add($fixture) }
        return ,$list
    }
    function Write-Host { $script:Messages += ($args -join ' ') }
    function Write-Warning { param([string]$Message) $script:Messages += $Message }
    $PropertiesPath = ''
    $script:Messages = @()
    Invoke-IdeaPathDiagnosis
    $output = $script:Messages -join "`n"
    Assert-True ($output.Contains($first) -and $output.Contains($second) -and $output.Contains('[1/2]') -and $output.Contains('[2/2]')) 'all discovered files diagnosed separately'
    Assert-True ($output.Contains('配置目录') -and $output.Contains('缓存目录') -and $output.Contains('共检查 2 个')) 'configured paths and batch summary displayed'

    $PropertiesPath = $second
    $script:Messages = @()
    $previousDiscoveries = $script:Discoveries
    Invoke-IdeaPathDiagnosis
    $output = $script:Messages -join "`n"
    Assert-True ($output.Contains($second) -and -not $output.Contains($first) -and $script:Discoveries -eq $previousDiscoveries) 'explicit path selects only one file'
    $PropertiesPath = Join-Path $testRoot 'missing'
    $message = $null
    try { Invoke-IdeaPathDiagnosis } catch { $message = $_.Exception.Message }
    Assert-True ($message -match '指定的路径' -and $script:Discoveries -eq $previousDiscoveries) 'invalid explicit path fails without scanning other files'

    # Simulate one failed read and verify the later file is still diagnosed.
    $PropertiesPath = ''
    $script:Messages = @()
    $originalReader = (Get-Item Function:\Get-IdeaPropertyValues).ScriptBlock
    function Get-IdeaPropertyValues([string]$PropertyFilePath) {
        if ($PropertyFilePath -eq $first) { throw 'simulated read failure' }
        & $originalReader $PropertyFilePath
    }
    $message = $null
    try { Invoke-IdeaPathDiagnosis } catch { $message = $_.Exception.Message }
    $output = $script:Messages -join "`n"
    Assert-True ($output.Contains('simulated read failure') -and $output.Contains('[2/2]') -and $output.Contains('custom-config')) 'read failure does not stop subsequent files'
    Assert-True ($message -match '1 个成功，1 个失败') 'failures reported after batch completes'
    Assert-True ((Get-FileHash -LiteralPath $first).Hash -eq $beforeFirst -and (Get-FileHash -LiteralPath $second).Hash -eq $beforeSecond) 'diagnosis preserves original file bytes'
    Microsoft.PowerShell.Utility\Write-Host "All $script:Passed diagnosis checks passed."
} finally {
    $resolvedCleanup = [IO.Path]::GetFullPath($testRoot)
    $allowedPrefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\diagnosis-'
    if (-not $resolvedCleanup.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe diagnosis cleanup path.' }
    if (Test-Path -LiteralPath $resolvedCleanup) { Remove-Item -LiteralPath $resolvedCleanup -Recurse -Force }
}
