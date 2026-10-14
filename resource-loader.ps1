# Compatible with Windows PowerShell 5.1. Dot-source this local module.
$script:KeyRunModuleRoot = $PSScriptRoot
$script:KeyRunConfigPath = Join-Path $script:KeyRunModuleRoot 'source-config.json'

function Resolve-KeyRunHttpBase {
    param([string]$HttpBase)
    $uri = $null
    if ([string]::IsNullOrWhiteSpace($HttpBase) -or
        $HttpBase -ne $HttpBase.Trim() -or $HttpBase.Contains('\') -or
        $HttpBase -match '^https?://.*https?://' -or
        -not [Uri]::TryCreate($HttpBase, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https') -or
        [string]::IsNullOrWhiteSpace($uri.Host) -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'Invalid httpBase: use an absolute HTTP/HTTPS directory URL without credentials, query or fragment.'
    }
    return $uri.AbsoluteUri.TrimEnd('/')
}

function Resolve-KeyRunSourceConfig {
    param([Parameter(Mandatory = $true)]$Config)
    if ($null -eq $Config -or $Config.mode -notin @('local', 'http')) {
        throw 'Invalid source mode: expected local or http.'
    }
    $rootSetting = [string]$Config.localRoot
    if ([string]::IsNullOrWhiteSpace($rootSetting)) { $rootSetting = '.' }
    if ([IO.Path]::IsPathRooted($rootSetting) -and
        $rootSetting -notmatch '^([a-zA-Z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+)') {
        throw 'Invalid localRoot: use a fully qualified path or a path relative to the Loader directory.'
    }
    if (-not [IO.Path]::IsPathRooted($rootSetting)) {
        $rootSetting = Join-Path $script:KeyRunModuleRoot $rootSetting
    }
    $root = [IO.Path]::GetFullPath($rootSetting)
    if ($Config.mode -eq 'local' -and -not [IO.Directory]::Exists($root)) {
        throw "Local directory not found: $root"
    }
    $base = [string]$Config.httpBase
    if ($Config.mode -eq 'http') { $base = Resolve-KeyRunHttpBase $base }
    $timeout = 20
    if ($Config.PSObject.Properties['timeoutSeconds']) {
        $number = 0
        if (-not [int]::TryParse([string]$Config.timeoutSeconds, [ref]$number) -or $number -lt 1 -or $number -gt 300) {
            throw 'Invalid timeoutSeconds: expected an integer between 1 and 300.'
        }
        $timeout = $number
    }
    return [pscustomobject]@{ mode = $Config.mode; localRoot = $root; httpBase = $base; timeoutSeconds = $timeout }
}

function Get-KeyRunSourceConfig {
    if (-not [IO.File]::Exists($script:KeyRunConfigPath)) {
        throw "Configuration file not found: $script:KeyRunConfigPath"
    }
    try {
        $raw = [IO.File]::ReadAllText($script:KeyRunConfigPath, (New-Object Text.UTF8Encoding($false, $true)))
        $config = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        return Resolve-KeyRunSourceConfig $config
    } catch {
        throw "Invalid source configuration '$script:KeyRunConfigPath': $($_.Exception.Message)"
    }
}

function Resolve-KeyRunResource {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $relative = $RelativePath.Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or
        $relative -match '[<>:"|?*#\x00-\x1f]') {
        throw "Invalid relative resource path: $RelativePath"
    }
    $segments = $relative.Split('/')
    foreach ($segment in $segments) {
        if ($segment -in @('', '.', '..') -or $segment -match '[ .]$') {
            throw "Invalid resource path segment: '$segment'"
        }
    }
    $config = Get-KeyRunSourceConfig
    if ($config.mode -eq 'http') {
        $encoded = ($segments | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
        return [pscustomobject]@{ Config = $config; Location = ($config.httpBase + '/' + $encoded) }
    }
    $root = $config.localRoot
    $path = [IO.Path]::GetFullPath((Join-Path $root ($segments -join [IO.Path]::DirectorySeparatorChar)))
    $prefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Resource path is outside the root directory: $RelativePath"
    }
    # Reject junctions/symlinks, including ancestors of the configured root.
    $ancestor = $root
    while ($ancestor) {
        $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Resource root contains a reparse point: $ancestor"
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    $candidate = $root
    foreach ($segment in $segments) {
        $candidate = Join-Path $candidate $segment
        if (-not (Test-Path -LiteralPath $candidate)) { throw "Local resource not found: $path" }
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Resource path contains a reparse point: $candidate"
        }
    }
    if (-not [IO.File]::Exists($path)) { throw "Local resource is not a file: $path" }
    return [pscustomobject]@{ Config = $config; Location = $path }
}

function Get-KeyRunResourceBytes {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $resource = Resolve-KeyRunResource $RelativePath
    if ($resource.Config.mode -eq 'local') {
        try { return ,([IO.File]::ReadAllBytes($resource.Location)) }
        catch { throw "Local resource read failed '$RelativePath': $($_.Exception.Message)" }
    }
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($resource.Config.timeoutSeconds)
    $response = $null
    try {
        $response = $client.GetAsync($resource.Location).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)"
        }
        return ,($response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult())
    } catch {
        $reason = $_.Exception
        while ($reason.InnerException) { $reason = $reason.InnerException }
        if ($reason -is [OperationCanceledException]) {
            throw "HTTP resource timeout after $($resource.Config.timeoutSeconds)s: $($resource.Location)"
        }
        throw "HTTP resource read failed '$($resource.Location)': $($reason.Message)"
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}

function Get-KeyRunResourceText {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $bytes = Get-KeyRunResourceBytes $RelativePath
    try {
        $encoding = New-Object Text.UTF8Encoding($false, $true)
        $offset = 0
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { $offset = 3 }
        return $encoding.GetString($bytes, $offset, ($bytes.Length - $offset))
    } catch { throw "Resource is not valid UTF-8 '$RelativePath': $($_.Exception.Message)" }
}

function Get-KeyRunResourceJson {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    try { return ConvertFrom-Json -InputObject (Get-KeyRunResourceText $RelativePath) -ErrorAction Stop }
    catch { throw "JSON resource read failed '$RelativePath': $($_.Exception.Message)" }
}
