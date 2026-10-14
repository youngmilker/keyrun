# Generated server bootstrap. Regenerate using switch-source.ps1 -Mode http.
& {
    $ErrorActionPreference = 'Stop'
    $KeyRunBootstrapHttpBase = __KEYRUN_HTTP_BASE_LITERAL__
    $KeyRunBootstrapTimeoutSeconds = __KEYRUN_TIMEOUT_SECONDS__
    $KeyRunExpectedHashes = __KEYRUN_HASHES_LITERAL__

    function Get-BootstrapLoaderBytes([string]$Url) {
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
        $handler = New-Object Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $false
        $client = New-Object Net.Http.HttpClient($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($KeyRunBootstrapTimeoutSeconds)
        $response = $null
        try {
            $response = $client.GetAsync($Url).GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) { throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)" }
            return ,($response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult())
        } catch { throw "Bootstrap loader download failed '$Url': $($_.Exception.Message)" }
        finally {
            if ($null -ne $response) { $response.Dispose() }
            $client.Dispose()
            $handler.Dispose()
        }
    }
    function Get-BootstrapSha256([byte[]]$Bytes) {
        $encoding = New-Object Text.UTF8Encoding($false, $true)
        $normalized = $encoding.GetBytes($encoding.GetString($Bytes).Replace("`r`n", "`n"))
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($normalized)).Replace('-', '') }
        finally { $sha.Dispose() }
    }
    function Remove-BootstrapDirectory([string]$Path, [string]$ExpectedPath, [string]$Parent) {
        $resolved = [IO.Path]::GetFullPath($Path)
        $prefix = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\keyrun-http-'
        if ($resolved -ne [IO.Path]::GetFullPath($ExpectedPath) -or
            -not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe bootstrap cleanup path.' }
        if (-not [IO.Directory]::Exists($resolved)) { return }
        $queue = New-Object 'Collections.Generic.Queue[string]'
        $queue.Enqueue($resolved)
        while ($queue.Count -gt 0) {
            $directory = $queue.Dequeue()
            $item = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Bootstrap directory contains a reparse point.' }
            foreach ($child in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Bootstrap directory contains a reparse point.' }
                if ($child.PSIsContainer) { $queue.Enqueue($child.FullName) }
            }
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This bootstrap requires Windows PowerShell.' }
    $tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $bootstrapRoot = Join-Path $tempParent ('keyrun-http-' + [Guid]::NewGuid().ToString('N'))
    $expectedRoot = $bootstrapRoot
    try {
        [void][IO.Directory]::CreateDirectory($bootstrapRoot)
        $loaderBytes = Get-BootstrapLoaderBytes ($KeyRunBootstrapHttpBase + '/resource-loader.ps1')
        if ((Get-BootstrapSha256 $loaderBytes) -ne $KeyRunExpectedHashes['resource-loader.ps1']) {
            throw 'Bootstrap loader SHA-256 mismatch. Republish the matching generated ps1 and project files.'
        }
        [IO.File]::WriteAllBytes((Join-Path $bootstrapRoot 'resource-loader.ps1'), $loaderBytes)
        # A local worker gives the Loader its own script scope, without changing caller bindings.
        $worker = @'
param([string]$HttpBase, [string]$HashesJson, [int]$TimeoutSeconds)
$ErrorActionPreference = 'Stop'
$config = [pscustomobject]@{mode='http'; localRoot='.'; httpBase=$HttpBase; timeoutSeconds=$TimeoutSeconds}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'source-config.json'), ($config | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
. (Join-Path $PSScriptRoot 'resource-loader.ps1')
$hashes = ConvertFrom-Json $HashesJson
foreach ($relative in @('keyrun.ps1', 'scripts/install.ps1', 'scripts/diagnose-idea-paths.ps1')) {
    $bytes = Get-KeyRunResourceBytes $relative
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    $normalized = $encoding.GetBytes($encoding.GetString($bytes).Replace("`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actualHash = [BitConverter]::ToString($sha.ComputeHash($normalized)).Replace('-', '') }
    finally { $sha.Dispose() }
    $expectedHash = $hashes.PSObject.Properties[$relative].Value
    if ($actualHash -ne $expectedHash) { throw "Bootstrap script SHA-256 mismatch: $relative. Regenerate and redeploy ps1 with the matching files." }
    $destination = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relative))
    $prefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (-not $destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe bootstrap destination.' }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    [IO.File]::WriteAllBytes($destination, $bytes)
}
Write-Host ('Server source: ' + $HttpBase)
& (Join-Path $PSScriptRoot 'keyrun.ps1') -Install
if (-not $?) { throw 'The downloaded local installer failed.' }
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "The local installer exited with code $LASTEXITCODE." }
'@
        $workerPath = Join-Path $bootstrapRoot 'run-bootstrap.ps1'
        [IO.File]::WriteAllText($workerPath, $worker, (New-Object Text.UTF8Encoding($true)))
        & $workerPath -HttpBase $KeyRunBootstrapHttpBase -HashesJson ($KeyRunExpectedHashes | ConvertTo-Json -Compress) -TimeoutSeconds $KeyRunBootstrapTimeoutSeconds
    } finally {
        try { Remove-BootstrapDirectory $bootstrapRoot $expectedRoot $tempParent }
        catch { Write-Warning ("Bootstrap temporary files retained at '$bootstrapRoot': $($_.Exception.Message)") }
    }
}
