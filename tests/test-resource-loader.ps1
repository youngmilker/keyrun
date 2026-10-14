param([string]$PythonExe = 'python.exe')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $PSScriptRoot ('temporary-' + [Guid]::NewGuid().ToString('N'))
$caseRoot = Join-Path $testRoot '中文 project'
$server = $null
$script:Passed = 0

function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
    Write-Host "PASS: $Name"
}
function Expect-Failure([scriptblock]$Action, [string]$Pattern, [string]$Name) {
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert-True ($null -ne $message -and $message -match $Pattern) $Name
}
function Write-TestConfig($Config) {
    [IO.File]::WriteAllText((Join-Path $caseRoot 'source-config.json'), ($Config | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

try {
    New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
    foreach ($file in @('resource-loader.ps1', 'switch-source.ps1', 'keyrun.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination (Join-Path $caseRoot $file)
    }
    $config = [pscustomobject]@{ mode = 'local'; localRoot = '.'; httpBase = 'http://127.0.0.1:1'; timeoutSeconds = 1 }
    Write-TestConfig $config
    $binary = [byte[]](@(0..255) + @(0,255,128))
    [IO.File]::WriteAllBytes((Join-Path $caseRoot 'binary.bin'), $binary)
    [IO.File]::WriteAllText((Join-Path $caseRoot '中文 空格.txt'), "中文资源`n第二行", (New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText((Join-Path $caseRoot 'plain.txt'), '中文无 BOM', (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $caseRoot 'README.md'), '普通入口 Local 测试', (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $caseRoot 'data.json'), '{"name":"中文","number":42}', (New-Object Text.UTF8Encoding($false)))
    . (Join-Path $caseRoot 'resource-loader.ps1')
    Assert-True ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) 'Windows PowerShell 5.1 runtime'
    # Local phase: forbid the HTTP branch's assembly-loading entry, with no server running.
    function Add-Type { throw 'HTTP branch entered during Local phase' }
    Push-Location $testRoot
    try {
        Assert-True ((Get-KeyRunSourceConfig).localRoot -eq $caseRoot) 'root independent of working directory'
        $read = Get-KeyRunResourceBytes 'binary.bin'
        Assert-True ($read -is [byte[]] -and [Convert]::ToBase64String($read) -eq [Convert]::ToBase64String($binary)) 'Local binary bytes and return type'
        Assert-True ((Get-KeyRunResourceText '中文 空格.txt') -ceq "中文资源`n第二行") 'Local BOM and Chinese path'
        Assert-True ((Get-KeyRunResourceText 'plain.txt') -ceq '中文无 BOM') 'Local UTF-8 without BOM'
        Assert-True ((Get-KeyRunResourceJson 'data.json').name -ceq '中文') 'Local JSON'
        $result = & (Join-Path $caseRoot 'keyrun.ps1')
        Assert-True ($result -ceq '普通入口 Local 测试') 'actual entry consumes Loader from another working directory'
        $result = & (Join-Path $caseRoot 'keyrun.ps1') -ResourcePath binary.bin -Format Bytes
        Assert-True ($result -is [byte[]] -and $result.Length -eq 259) 'entry Bytes format'
        $result = & (Join-Path $caseRoot 'keyrun.ps1') -ResourcePath data.json -Format Json
        Assert-True ($result.number -eq 42) 'entry JSON format'
        & (Join-Path $caseRoot 'switch-source.ps1') -Mode local | Out-Null
        Assert-True ((Get-KeyRunSourceConfig).mode -eq 'local') 'switch-source local'
        Expect-Failure { Get-KeyRunResourceText 'missing.txt' } 'Local resource not found' 'missing local file'
        foreach ($path in @('../outside.txt', '..\outside.txt', '/README.md', 'C:\README.md', 'a//b', './a', 'a?b', 'a:b', 'a. /b')) {
            Expect-Failure { Get-KeyRunResourceBytes $path } 'Invalid' "unsafe path $path"
        }
        Expect-Failure { Get-KeyRunResourceText 'binary.bin' } 'not valid UTF-8' 'invalid UTF-8 rejected'
        Expect-Failure { Get-KeyRunResourceJson 'plain.txt' } 'JSON resource' 'malformed JSON resource'
        New-Item -ItemType Directory -Path (Join-Path $testRoot 'outside') | Out-Null
        $junction = Join-Path $caseRoot 'link'
        New-Item -ItemType Junction -Path $junction -Target (Join-Path $testRoot 'outside') | Out-Null
        Expect-Failure { Get-KeyRunResourceBytes 'link/file.txt' } 'reparse point' 'junction traversal rejected'
        # Remove only the link itself, before recursive cleanup.
        [IO.Directory]::Delete($junction)
        $original = [IO.File]::ReadAllBytes((Join-Path $caseRoot 'source-config.json'))
        foreach ($base in @('ftp://host/root', 'http://http://127.0.0.1:8765/', 'https://host/root?q=1', 'https://user:pass@host/root', 'https://host/root#fragment')) {
            Expect-Failure { & (Join-Path $caseRoot 'switch-source.ps1') -Mode http -HttpBase $base } 'Invalid httpBase' "invalid HTTP root $base"
        }
        Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $caseRoot 'source-config.json'))) -eq [Convert]::ToBase64String($original)) 'invalid switch leaves configuration unchanged'
        foreach ($bad in @('{bad', '{"mode":"wrong"}', '{"mode":"local","timeoutSeconds":0}', '{"mode":"http","httpBase":"http://http://127.0.0.1"}', '{"mode":"local","localRoot":"missing"}', '{"mode":"local","localRoot":"D:relative"}', '{"mode":"local","localRoot":"\\rooted"}')) {
            [IO.File]::WriteAllText((Join-Path $caseRoot 'source-config.json'), $bad)
            Expect-Failure { Get-KeyRunResourceBytes 'README.md' } 'Invalid source configuration' 'invalid configuration fails without fallback'
        }
        Remove-Item -LiteralPath (Join-Path $caseRoot 'source-config.json')
        Expect-Failure { Get-KeyRunResourceText 'README.md' } 'Configuration file not found' 'missing configuration'
        Write-TestConfig $config
    } finally { Pop-Location; Remove-Item Function:\Add-Type }
    Write-Host 'Local phase complete. Starting loopback fixture ONLY for HTTP tests.'
    $portFile = Join-Path $testRoot 'port.txt'
    $fixture = Join-Path $PSScriptRoot 'http-resource-fixture.py'
    $server = Start-Process -FilePath $PythonExe -ArgumentList @('"' + $fixture + '"', '"' + $portFile + '"') -PassThru -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not [IO.File]::Exists($portFile)) {
        if ([DateTime]::UtcNow -gt $deadline -or $server.HasExited) { throw 'HTTP fixture did not start.' }
        Start-Sleep -Milliseconds 100
    }
    $port = [IO.File]::ReadAllText($portFile)
    & (Join-Path $caseRoot 'switch-source.ps1') -Mode http -HttpBase "http://127.0.0.1:$port/assets" -TimeoutSeconds 1 | Out-Null
    $read = Get-KeyRunResourceBytes 'binary.bin'
    Assert-True ($read -is [byte[]] -and [Convert]::ToBase64String($read) -eq [Convert]::ToBase64String($binary)) 'HTTP original binary bytes and return type'
    Assert-True ((Get-KeyRunResourceText '中文 空格.txt') -ceq "中文资源`n第二行") 'HTTP encoded Chinese path and BOM'
    Assert-True ((Get-KeyRunResourceJson 'data.json').name -ceq '中文') 'HTTP JSON'
    $result = & (Join-Path $caseRoot 'keyrun.ps1')
    Assert-True ($result -ceq '普通入口 HTTP 测试') 'same actual entry consumes HTTP resource'
    Expect-Failure { Get-KeyRunResourceBytes 'missing' } 'HTTP 404' 'HTTP 404 status'
    Expect-Failure { Get-KeyRunResourceBytes 'redirect' } 'HTTP 302' 'redirect explicitly rejected'
    Expect-Failure { Get-KeyRunResourceBytes 'slow' } 'timeout after 1s' 'HTTP timeout'
    Assert-True ((Resolve-KeyRunHttpBase 'https://example.com/keyrun/') -eq 'https://example.com/keyrun') 'HTTPS base supported and normalized'
    # Windows may take longer than one second to report a refused TCP connection.
    & (Join-Path $caseRoot 'switch-source.ps1') -Mode http -TimeoutSeconds 10 | Out-Null
    Stop-Process -Id $server.Id -Force
    $server.WaitForExit()
    $server = $null
    Expect-Failure { Get-KeyRunResourceBytes 'binary.bin' } 'HTTP resource read failed' 'connection failure after server stop'
    & (Join-Path $caseRoot 'switch-source.ps1') -Mode local | Out-Null
    Assert-True ((Get-KeyRunResourceText 'README.md') -ceq '普通入口 Local 测试') 'switch back to Local'
    Write-Host "All $script:Passed checks passed."
} finally {
    if ($null -ne $server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force; $server.WaitForExit() }
    $resolvedCleanup = [IO.Path]::GetFullPath($testRoot)
    $allowedPrefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\temporary-'
    if (-not $resolvedCleanup.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
    $leftoverLink = Join-Path $caseRoot 'link'
    if ([IO.Directory]::Exists($leftoverLink)) { [IO.Directory]::Delete($leftoverLink) }
    if (Test-Path -LiteralPath $resolvedCleanup) { Remove-Item -LiteralPath $resolvedCleanup -Recurse -Force }
}
