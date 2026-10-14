param(
    [Parameter(Mandatory = $true)][ValidateSet('local', 'http')][string]$Mode,
    [string]$HttpBase,
    [string]$LocalRoot,
    [ValidateRange(1, 300)][int]$TimeoutSeconds,
    [switch]$OpenPage
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'resource-loader.ps1')
if (-not [IO.File]::Exists($script:KeyRunConfigPath)) { throw "Configuration file not found: $script:KeyRunConfigPath" }
try { $config = Get-Content -LiteralPath $script:KeyRunConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
catch { throw "Cannot read source configuration: $($_.Exception.Message)" }
if ($null -eq $config -or $config -isnot [pscustomobject]) { throw 'Configuration must be a JSON object.' }
$config | Add-Member -NotePropertyName mode -NotePropertyValue $Mode -Force
if ($PSBoundParameters.ContainsKey('LocalRoot')) {
    $config | Add-Member -NotePropertyName localRoot -NotePropertyValue $LocalRoot -Force
} elseif (-not $config.PSObject.Properties['localRoot']) {
    $config | Add-Member -NotePropertyName localRoot -NotePropertyValue '.'
}
if ($PSBoundParameters.ContainsKey('HttpBase')) {
    $base = Resolve-KeyRunHttpBase $HttpBase
    $config | Add-Member -NotePropertyName httpBase -NotePropertyValue $base -Force
}
if ($PSBoundParameters.ContainsKey('TimeoutSeconds')) {
    $config | Add-Member -NotePropertyName timeoutSeconds -NotePropertyValue $TimeoutSeconds -Force
}
# Validate before writing; never save an invalid active configuration.
$resolved = Resolve-KeyRunSourceConfig $config
if ($Mode -eq 'http' -and [IO.File]::Exists((Join-Path $PSScriptRoot 'ps1'))) {
    $builder = Join-Path $PSScriptRoot 'scripts\build-server-bootstrap.ps1'
    if (-not [IO.File]::Exists($builder)) { throw "Server bootstrap builder not found: $builder" }
    & $builder -HttpBase $resolved.httpBase -TimeoutSeconds $resolved.timeoutSeconds
}
[IO.File]::WriteAllText($script:KeyRunConfigPath, ($config | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
Write-Host "当前模式 / Mode: $($resolved.mode)"
Write-Host "本地路径 / Local root: $($resolved.localRoot)"
Write-Host "HTTP base: $($resolved.httpBase)"
if ($OpenPage) {
    $page = Resolve-KeyRunResource 'index.html'
    Start-Process -FilePath $page.Location
}
