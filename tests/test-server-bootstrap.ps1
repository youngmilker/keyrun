param([string]$PythonExe = 'python.exe')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $PSScriptRoot ('bootstrap-' + [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $testRoot 'server-package'
$server = $null
$oldMarker = $env:KEYRUN_BOOTSTRAP_TEST_MARKER
$script:Passed = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
    Write-Host "PASS: $Name"
}

try {
    New-Item -ItemType Directory -Path (Join-Path $packageRoot 'scripts') -Force | Out-Null
    foreach ($relative in @('resource-loader.ps1','switch-source.ps1','scripts/build-server-bootstrap.ps1','scripts/server-bootstrap.template.ps1','scripts/build-unix-bootstrap.ps1','scripts/server-bootstrap.template.sh')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $relative) -Destination (Join-Path $packageRoot $relative)
    }
    # Harmless LF-only shell code fixtures exercise the Windows-generated Unix entry.
    foreach ($relative in @('resource-loader.sh','keyrun.sh','scripts/platform-paths.sh','scripts/install.sh','scripts/install-unix.sh','scripts/diagnose-idea-paths.sh')) {
        [IO.File]::WriteAllText((Join-Path $packageRoot $relative), "#!/bin/bash`n# harmless fixture`n", (New-Object Text.UTF8Encoding($false)))
    }
    $stub = @'
param([switch]$Install)
if (-not $Install) { throw 'Install flag not forwarded.' }
. (Join-Path $PSScriptRoot 'resource-loader.ps1')
$config = Get-KeyRunSourceConfig
if ($config.mode -ne 'http') { throw 'Bootstrap did not select HTTP.' }
[IO.File]::WriteAllText($env:KEYRUN_BOOTSTRAP_TEST_MARKER, ($PSScriptRoot + '|' + $config.httpBase + '|' + $config.timeoutSeconds))
Write-Host 'Harmless HTTP bootstrap fixture completed.'
'@
    [IO.File]::WriteAllText((Join-Path $packageRoot 'keyrun.ps1'), $stub, (New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText((Join-Path $packageRoot 'scripts/install.ps1'), "throw 'Installer fixture must never run.'")
    [IO.File]::WriteAllText((Join-Path $packageRoot 'scripts/diagnose-idea-paths.ps1'), '# unused fixture')
    [IO.File]::WriteAllText((Join-Path $packageRoot 'ps1'), '# bootstrap placeholder')
    [IO.File]::WriteAllText((Join-Path $packageRoot 'source-config.json'), '{"mode":"http","localRoot":".","httpBase":"https://liyangxu1.github.io/keyrun","timeoutSeconds":20}')
    $portFile = Join-Path $testRoot 'port.txt'
    $fixture = Join-Path $PSScriptRoot 'bootstrap-http-fixture.py'
    $server = Start-Process -FilePath $PythonExe -ArgumentList @('"' + $fixture + '"', '"' + $packageRoot + '"', '"' + $portFile + '"') -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not [IO.File]::Exists($portFile)) {
        if ([DateTime]::UtcNow -gt $deadline -or $server.HasExited) { throw 'Bootstrap fixture did not start.' }
        Start-Sleep -Milliseconds 100
    }
    $base = 'http://127.0.0.1:' + [IO.File]::ReadAllText($portFile)
    & (Join-Path $packageRoot 'switch-source.ps1') -Mode http -HttpBase $base -TimeoutSeconds 3
    $config = [IO.File]::ReadAllText((Join-Path $packageRoot 'source-config.json')) | ConvertFrom-Json
    $bootstrapText = [IO.File]::ReadAllText((Join-Path $packageRoot 'ps1'))
    $servedBootstrap = Invoke-RestMethod -Uri ($base + '/ps1') -TimeoutSec 20
    Assert-True ($servedBootstrap -is [string] -and $servedBootstrap -ceq $bootstrapText) 'HTTP ps1 response equals the reviewed generated script'
    Assert-True ($config.mode -eq 'http' -and $config.httpBase -eq $base) 'server switch persists address'
    Assert-True ($bootstrapText.Contains("`$KeyRunBootstrapHttpBase = '$base'")) 'server switch regenerates standalone bootstrap address'
    Assert-True (-not $bootstrapText.Contains('__KEYRUN_')) 'all bootstrap placeholders replaced'
    $unixBootstrap = [IO.File]::ReadAllText((Join-Path $packageRoot 'sh'))
    Assert-True ($unixBootstrap.Contains("KR_BOOT_BASE='$base'")) 'Windows deployment synchronizes Unix server address'
    Assert-True (-not $unixBootstrap.Contains('__KEYRUN_') -and -not $unixBootstrap.Contains("`r")) 'Unix entry has resolved placeholders and LF endings'
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $fixtureHash = [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes((Join-Path $packageRoot 'keyrun.sh')))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    Assert-True ($unixBootstrap.Contains("keyrun.sh|$fixtureHash")) 'Unix code hash preserves raw fixture bytes'
    $marker = Join-Path $testRoot 'marker.txt'
    $env:KEYRUN_BOOTSTRAP_TEST_MARKER = $marker
    $emptyDirectory = Join-Path $testRoot 'empty-client'
    New-Item -ItemType Directory -Path $emptyDirectory | Out-Null
    Push-Location $emptyDirectory
    try { & ([scriptblock]::Create($servedBootstrap)) }
    finally { Pop-Location }
    Assert-True ([IO.File]::Exists($marker)) 'HTTP entry runs without a local project or config'
    $result = [IO.File]::ReadAllText($marker).Split('|')
    Assert-True ($result[1] -eq $base) 'remote client uses the configured server resource root'
    Assert-True ($result[2] -eq '3') 'deployment timeout preserved in independent HTTP client config'
    Assert-True (-not [IO.Directory]::Exists($result[0])) 'bootstrap temp project removed after execution'
    Assert-True (@(Get-ChildItem -LiteralPath $emptyDirectory -Force).Count -eq 0) 'caller working directory untouched'

    # Line-ending differences introduced by Git must not invalidate matching code.
    Remove-Item -LiteralPath $marker
    $keyrunPath = Join-Path $packageRoot 'keyrun.ps1'
    $sameCode = [IO.File]::ReadAllText($keyrunPath).Replace("`r`n", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($keyrunPath, $sameCode, (New-Object Text.UTF8Encoding($true)))
    & ([scriptblock]::Create($bootstrapText))
    Assert-True ([IO.File]::Exists($marker)) 'Git line-ending changes accepted without changing script bytes'
    Remove-Item -LiteralPath $marker
    # Changed code, rather than line endings, must be rejected before execution.
    [IO.File]::AppendAllText($keyrunPath, "`n# mismatching deployment")
    $message = $null
    try { & ([scriptblock]::Create($bootstrapText)) } catch { $message = $_.Exception.Message }
    Assert-True ($message -match 'SHA-256 mismatch' -and -not [IO.File]::Exists($marker)) 'changed remote code rejected before entry execution'
    $loaderPath = Join-Path $packageRoot 'resource-loader.ps1'
    [IO.File]::AppendAllText($loaderPath, "`n# mismatching loader")
    $message = $null
    try { & ([scriptblock]::Create($bootstrapText)) } catch { $message = $_.Exception.Message }
    Assert-True ($message -match 'loader SHA-256 mismatch') 'changed remote Loader rejected before import'

    & (Join-Path $packageRoot 'switch-source.ps1') -Mode local
    $config = [IO.File]::ReadAllText((Join-Path $packageRoot 'source-config.json')) | ConvertFrom-Json
    Assert-True ($config.mode -eq 'local') 'Local explicitly persisted'
    Assert-True ([IO.File]::ReadAllText((Join-Path $packageRoot 'ps1')).Contains("`$KeyRunBootstrapHttpBase = '$base'")) 'Local switch does not replace the server deployment address'
    Write-Host "All $script:Passed server bootstrap checks passed. No real installer or IDE changes executed."
} finally {
    $env:KEYRUN_BOOTSTRAP_TEST_MARKER = $oldMarker
    if ($null -ne $server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force; $server.WaitForExit() }
    $resolvedCleanup = [IO.Path]::GetFullPath($testRoot)
    $prefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\bootstrap-'
    if (-not $resolvedCleanup.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe bootstrap-test cleanup path.' }
    if (Test-Path -LiteralPath $resolvedCleanup) { Remove-Item -LiteralPath $resolvedCleanup -Recurse -Force }
}
