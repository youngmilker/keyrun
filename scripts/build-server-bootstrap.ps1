param(
    [Parameter(Mandatory = $true)][string]$HttpBase,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 20
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'resource-loader.ps1')
$base = Resolve-KeyRunHttpBase $HttpBase
$resources = @('resource-loader.ps1','keyrun.ps1','scripts/install.ps1','scripts/diagnose-idea-paths.ps1')
$hashLines = foreach ($relative in $resources) {
    $path = Join-Path $projectRoot $relative
    if (-not [IO.File]::Exists($path)) { throw "Cannot build server bootstrap: missing local code file $path" }
    # Git and Windows may change line endings. Keep BOM semantics, normalize only CRLF.
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    $text = $encoding.GetString([IO.File]::ReadAllBytes($path)).Replace("`r`n", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($encoding.GetBytes($text))).Replace('-', '') }
    finally { $sha.Dispose() }
    "    '$relative' = '$hash'"
}
$templatePath = Join-Path $PSScriptRoot 'server-bootstrap.template.ps1'
if (-not [IO.File]::Exists($templatePath)) { throw "Bootstrap template not found: $templatePath" }
$template = [IO.File]::ReadAllText($templatePath)
$baseLiteral = "'" + $base.Replace("'", "''") + "'"
$hashLiteral = "@{`n" + ($hashLines -join "`n") + "`n}"
$content = $template.Replace('__KEYRUN_HTTP_BASE_LITERAL__', $baseLiteral).Replace('__KEYRUN_HASHES_LITERAL__', $hashLiteral)
$content = $content.Replace('__KEYRUN_TIMEOUT_SECONDS__', [string]$TimeoutSeconds)
$tokens = $null; $parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
[IO.File]::WriteAllText((Join-Path $projectRoot 'ps1'), $content, (New-Object Text.UTF8Encoding($false)))
Write-Host ("Server bootstrap generated for: {0}" -f $base)
