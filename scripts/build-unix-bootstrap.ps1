param(
    [Parameter(Mandatory = $true)][string]$HttpBase,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 20
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'resource-loader.ps1')
$base = Resolve-KeyRunHttpBase $HttpBase
$files = @('resource-loader.sh', 'keyrun.sh', 'scripts/platform-paths.sh', 'scripts/install.sh', 'scripts/install-unix.sh', 'scripts/diagnose-idea-paths.sh')
$hashLines = foreach ($relative in $files) {
    $path = Join-Path $projectRoot $relative
    if (-not [IO.File]::Exists($path)) { throw "Missing shell code file: $path" }
    $bytes = [IO.File]::ReadAllBytes($path)
    # Shell code must stay LF, including on Windows checkouts (.gitattributes).
    if ($bytes -contains [byte]13) { throw "Shell code contains CRLF. Restore LF before publishing: $relative" }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    "$relative|$hash"
}
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'server-bootstrap.template.sh')).Replace("`r`n", "`n")
$literal = "'" + $base.Replace("'", "'\''") + "'"
$content = $template.Replace('__KEYRUN_HTTP_BASE_LITERAL__', $literal)
$content = $content.Replace('__KEYRUN_TIMEOUT_SECONDS__', [string]$TimeoutSeconds)
$content = $content.Replace('__KEYRUN_HASH_LINES__', ($hashLines -join "`n"))
$output = Join-Path $projectRoot 'sh'
if (Test-Path -LiteralPath $output) {
    $item = Get-Item -LiteralPath $output -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked bootstrap output rejected: $output" }
}
[IO.File]::WriteAllText($output, $content, (New-Object Text.UTF8Encoding($false)))
Write-Host ("Shell server bootstrap generated for: {0}" -f $base)
