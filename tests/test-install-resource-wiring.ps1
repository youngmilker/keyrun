$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $PSScriptRoot ('install-wiring-' + [Guid]::NewGuid().ToString('N'))
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

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts/install.ps1'), [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) 'restored installer syntax'
    $functions = $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)
    foreach ($function in $functions) {
        # Import definitions only. Never invoke Main, elevation or actual IDE discovery.
        . ([scriptblock]::Create($function.Extent.Text))
    }
    . (Join-Path $repoRoot 'resource-loader.ps1')
    # Use an isolated config to read the repo's resources, regardless of the user's mode.
    $script:KeyRunConfigPath = Join-Path $testRoot 'source-config.json'
    $fixtureConfig = [pscustomobject]@{ mode = 'local'; localRoot = $repoRoot }
    [IO.File]::WriteAllText($script:KeyRunConfigPath, ($fixtureConfig | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Assert-True ((Get-KeyRunSourceConfig).mode -eq 'local') 'isolated Local config, user config untouched'
    $script:PublicRoot = $testRoot
    $script:dir_work = Join-Path $testRoot '.jb_run'
    $script:dir_config = Join-Path $script:dir_work 'config'
    $script:dir_plugins = Join-Path $script:dir_work 'plugins'
    $script:file_netfilter_jar = Join-Path $script:dir_work 'ja-netfilter.jar'
    $script:dir_roaming_jetbrains = Join-Path $testRoot 'IDE-configs'
    $script:language = 'zh'
    $script:enable_debug = $false
    $script:sPrds = @('idea','clion','phpstorm','goland','pycharm','webstorm','rider','datagrip','rubymine','appcode','dataspell','rustrover') | ForEach-Object { @{name = $_} }
    $plan = @(Get-Install_File_Plan)
    Assert-True ($plan.Count -eq 13 -and @($plan.save_path | Select-Object -Unique).Count -eq 13) '13 distinct resource destinations'
    Assert-True (($plan | Where-Object { $_.resource -eq 'ja-netfilter/config/env.conf' }).save_path.EndsWith('\env.conf')) 'env.conf does not overwrite dns.conf'
    Assert-True (($plan | Where-Object { $_.resource -eq 'ja-netfilter/plugins/env.jar' }).save_path.EndsWith('\env.jar')) 'env.jar does not overwrite dns.jar'
    $main = $functions | Where-Object Name -eq 'Main'
    $mainText = $main.Extent.Text
    Assert-True ($mainText.IndexOf('Initialize-Install_Resources') -lt $mainText.IndexOf('Remove_Env -env_scope')) 'preload before environment modifications'
    Assert-True ($mainText.Contains("'-File'") -and -not $mainText.Contains('-Command irm') -and -not $mainText.Contains('liyangxu1.github.io')) 'elevation runs local file, no remote bootstrap'
    Initialize-Install_Resources
    Assert-True ($script:InstallResources.Count -eq 25) 'all 25 real resources loaded through Loader without execution'
    $originalCache = $script:InstallResources
    $reader = (Get-Item Function:\Get-KeyRunResourceBytes).ScriptBlock
    function Get-KeyRunResourceBytes([string]$RelativePath) { throw 'simulated missing resource' }
    Expect-Failure { Initialize-Install_Resources } 'Install resource read failed' 'resource failure stops preflight'
    Assert-True (-not (Test-Path -LiteralPath $script:dir_work)) 'failed preflight leaves work directory untouched'
    Set-Item Function:\Get-KeyRunResourceBytes $reader
    $script:InstallResources = $originalCache

    Create_Work_Dir
    function Write-ProgressCustom { }
    File_Download
    foreach ($file in $plan) {
        Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file.save_path)) -eq [Convert]::ToBase64String((Get-Install_ResourceBytes $file.resource))) "byte-identical temp deployment: $($file.resource)"
    }
    $productFolder = Join-Path $script:dir_roaming_jetbrains 'fixture-idea'
    New-Item -ItemType Directory -Path $productFolder -Force | Out-Null
    $vmFile = Join-Path $productFolder 'idea64.exe.vmoptions'
    [IO.File]::WriteAllText($vmFile, "-Xmx1024m`n-javaagent:old.jar")
    $script:regex = New-Object Text.RegularExpressions.Regex '^-javaagent:.*'
    $script:content = @('-javaagent:fixture-agent.jar')
    Create_Key -product @{name='idea'} -prd_full_name 'fixture-idea' -custom_config_path ''
    $keyFile = Join-Path $productFolder 'idea.key'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($keyFile)) -eq [Convert]::ToBase64String((Get-Install_ResourceBytes 'licenses/idea.key'))) 'key write preserves resource bytes in temp fixture'
    Assert-True (-not ([IO.File]::ReadAllText($vmFile).Contains('-javaagent:old.jar'))) 'original cleanup operates in temp fixture'
    Append_Vm_Options $vmFile
    Assert-True ([IO.File]::ReadAllText($vmFile).Contains('-javaagent:fixture-agent.jar')) 'original option append operates in temp fixture'

    $invalidWork = Join-Path $testRoot 'unrelated'
    $script:dir_work = $invalidWork
    Expect-Failure { Create_Work_Dir } 'Unexpected work directory' 'unexpected delete target rejected'
    $script:dir_work = Join-Path $testRoot '.jb_run'
    $outside = Join-Path $testRoot 'outside'
    New-Item -ItemType Directory -Path $outside | Out-Null
    $junction = Join-Path $script:dir_work 'link'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    Expect-Failure { Create_Work_Dir } 'Unsafe work directory entry' 'nested junction blocks recursive deletion'
    [IO.Directory]::Delete($junction)

    # Verify public -Install dispatch against a harmless local installer stub.
    $entryFolder = Join-Path $testRoot 'entry'
    New-Item -ItemType Directory -Path (Join-Path $entryFolder 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'keyrun.ps1') -Destination $entryFolder
    Copy-Item -LiteralPath (Join-Path $repoRoot 'resource-loader.ps1') -Destination $entryFolder
    [IO.File]::WriteAllText((Join-Path $entryFolder 'scripts/install.ps1'), 'param([switch]$OpenPage); "LOCAL_INSTALL:$OpenPage"')
    [IO.File]::WriteAllText((Join-Path $entryFolder 'source-config.json'), '{"mode":"http","httpBase":"http://does-not-exist.invalid","localRoot":"."}')
    $output = & (Join-Path $entryFolder 'keyrun.ps1') -Install -OpenPage
    Assert-True ($output -eq 'LOCAL_INSTALL:True') 'Install invokes local file and forwards parameters even in HTTP mode'
    Expect-Failure { & (Join-Path $entryFolder 'keyrun.ps1') -Install -DiagnoseIdeaPaths } 'Choose either' 'conflicting modes rejected'
    Write-Host "All $script:Passed installer wiring checks passed. No installed IDE or system environment was changed."
} finally {
    $resolvedCleanup = [IO.Path]::GetFullPath($testRoot)
    $allowedPrefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\install-wiring-'
    if (-not $resolvedCleanup.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe installer-test cleanup path.' }
    $leftoverLink = Join-Path $testRoot '.jb_run/link'
    if ([IO.Directory]::Exists($leftoverLink)) { [IO.Directory]::Delete($leftoverLink) }
    if (Test-Path -LiteralPath $resolvedCleanup) { Remove-Item -LiteralPath $resolvedCleanup -Recurse -Force }
}
