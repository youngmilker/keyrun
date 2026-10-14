param(
    [string]$ResourcePath = 'README.md',
    [ValidateSet('Text', 'Json', 'Bytes')][string]$Format = 'Text',
    [switch]$Install,
    [switch]$DiagnoseIdeaPaths,
    [string]$PropertiesPath,
    [switch]$OpenPage
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
. (Join-Path $PSScriptRoot 'resource-loader.ps1')
# Executable tools always come from the reviewed local checkout, even in HTTP mode.
if ($Install -and $DiagnoseIdeaPaths) { throw 'Choose either -Install or -DiagnoseIdeaPaths.' }
if ($Install) {
    $installer = Join-Path $PSScriptRoot 'scripts\install.ps1'
    if (-not [IO.File]::Exists($installer)) { throw "Local installer not found: $installer" }
    & $installer -OpenPage:$OpenPage
} elseif ($DiagnoseIdeaPaths) {
    $tool = Join-Path $PSScriptRoot 'scripts\diagnose-idea-paths.ps1'
    if (-not [IO.File]::Exists($tool)) { throw "Local diagnostic tool not found: $tool" }
    & $tool -PropertiesPath $PropertiesPath
} elseif ($OpenPage) {
    $page = Resolve-KeyRunResource 'index.html'
    Start-Process -FilePath $page.Location
} else {
    switch ($Format) {
        'Text' { Get-KeyRunResourceText $ResourcePath }
        'Json' { Get-KeyRunResourceJson $ResourcePath }
        'Bytes' { ,(Get-KeyRunResourceBytes $ResourcePath) }
    }
}
