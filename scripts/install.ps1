# encoding: utf-8
param([switch]$OpenPage)
$ErrorActionPreference = 'Stop'
$script:InstallerPath = $PSCommandPath
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $script:ProjectRoot 'resource-loader.ps1')

# 先设置控制台代码页为 UTF-8
chcp 65001 | Out-Null

# 设置 PowerShell 输入输出编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Clear-Host

$script:enable_debug = $false

try {
    $system_ui_language = (Get-UICulture).Name
    if ($system_ui_language -like "zh*" -or $system_ui_language -like "zh-*") {
        $script:language = "zh"
    } else {
        $script:language = "en"
    }
} catch {
    $script:language = "zh"
}

# Internationalization function
function Get-i18nString
{
    param(
        [string]$key
    )

    $i18n = @{
        "processing_env_vars" = @{
            "zh" = "处理 {0} 环境变量"
            "en" = "Processing {0} environment variables"
        }
        "checking_env" = @{
            "zh" = "检查 [{0}]: {1} = '{2}'"
            "en" = "Checking [{0}]: {1} = '{2}'"
        }
        "deleting_env" = @{
            "zh" = "删除 [{0}]: {1}"
            "en" = "Deleting [{0}]: {1}"
        }
        "welcome_msg" = @{
            "zh" = "`n欢迎使用 JetBrains 配置工具 | KeyRun"
            "en" = "`nWelcome to JetBrains Configuration Tool | KeyRun"
        }
        "script_date" = @{
            "zh" = "`n脚本日期：2025-12-10"
            "en" = "`nScript Date: 2025-12-10"
        }
        "warning_msg" = @{
            "zh" = "`n注意：此脚本将强制重新激活所有产品！！！"
            "en" = "`nWarning: This script will forcibly re-activate all products!!!"
        }
        "admin_request" = @{
            "zh" = "即将申请管理员权限运行，按回车继续..."
            "en" = "Administrator privileges will be requested to run, press Enter to continue..."
        }
        "close_products" = @{
            "zh" = "`n请确保所有 JetBrains 软件已关闭，按回车继续..."
            "en" = "`nPlease make sure all JetBrains software is closed, press Enter to continue..."
        }
        "processing" = @{
            "zh" = "`n处理中，请耐心等待..."
            "en" = "`nProcessing, please wait patiently..."
        }
        "processing_configs" = @{
            "zh" = "`n开始处理配置..."
            "en" = "`nStarting to process configurations..."
        }
        "not_found_dir" = @{
            "zh" = "未找到 {0} 目录!"
            "en" = "Directory not found: {0}!"
        }
        "processing_product" = @{
            "zh" = "`n处理: {0}"
            "en" = "`nProcessing: {0}"
        }
        "not_found_home" = @{
            "zh" = "未找到 .home 文件: {0}"
            "en" = ".home file not found: {0}"
        }
        "path_not_exist" = @{
            "zh" = "路径不存在: {0}"
            "en" = "Path does not exist: {0}"
        }
        "not_found_bin" = @{
            "zh" = "未找到 bin 目录: {0}"
            "en" = "bin directory not found: {0}"
        }
        "config_exists_cleaning" = @{
            "zh" = "{0} 配置文件已存在，正在清理..."
            "en" = "{0} configuration file already exists, cleaning..."
        }
        "key_exists_cleaning" = @{
            "zh" = "key已存在，正在清理..."
            "en" = "Key already exists, cleaning..."
        }
        "activation_success" = @{
            "zh" = "{0} 配置文件写入完成。"
            "en" = "{0} configuration files written."
        }
        "manual_activation_required" = @{
            "zh" = "{0} 需要手动输入激活码！"
            "en" = "{0} requires manual activation code entry!"
        }
        "download_failed" = @{
            "zh" = "下载失败: {0}"
            "en" = "Download failed: {0}"
        }
        "request_failed" = @{
            "zh" = "{0} 请求失败: {1}"
            "en" = "{0} request failed: {1}"
        }
        "file_in_use" = @{
            "zh" = "文件被占用，请先关闭所有 JetBrains IDE 后再试！"
            "en" = "File is in use, please close all JetBrains IDEs and try again!"
        }
        "processing_completed" = @{
            "zh" = "`n所有项处理完成，请重新打开 IDE 检查配置结果。"
            "en" = "`nAll items processed. Reopen the IDE to check the configuration."
        }
        "format_error" = @{
            "zh" = "格式错误：请使用 yyyy-MM-dd 格式"
            "en" = "Format error: Please use yyyy-MM-dd format"
        }
        "invalid_date" = @{
            "zh" = "非法日期：{0}"
            "en" = "Invalid date: {0}"
        }
        "reading_config" = @{
            "zh" = "读取配置文件：{0}, 寻找键：{1}"
            "en" = "Reading config file: {0}, looking for key: {1}"
        }
        "found_key" = @{
            "zh" = "找到键 '{0}'，值为 '{1}'"
            "en" = "Found key '{0}' with value '{1}'"
        }
        "failed_read_config" = @{
            "zh" = "读取配置文件失败：{0}"
            "en" = "Failed to read config file: {0}"
        }
        "cleaning_vmoptions" = @{
            "zh" = "清理 VMOptions: {0}"
            "en" = "Cleaning VMOptions: {0}"
        }
        "updating_vmoptions" = @{
            "zh" = "更新 VMOptions: {0}"
            "en" = "Updating VMOptions: {0}"
        }
        "processing_disabled_plugins" = @{
            "zh" = "已处理文件: {0} 中com.intellij.modules.ultimate项"
            "en" = "Processed file: {0} com.intellij.modules.ultimate item"
        }
        "file_not_exist_skip" = @{
            "zh" = "文件不存在,跳过: {0}"
            "en" = "File does not exist, skipping: {0}"
        }
        "error_processing_plugins" = @{
            "zh" = "处理禁用插件文件时出错: {0}"
            "en" = "Error processing disabled plugins file: {0}"
        }
        "processing_config" = @{
            "zh" = "处理配置: {0}, {1}, {2}"
            "en" = "Processing config: {0}, {1}, {2}"
        }
        "requesting_key" = @{
            "zh" = "请求key: {0},请求body: {1},保存地址: {2}"
            "en" = "Requesting key: {0}, request body: {1}, save path: {2}"
        }
        "writing_key" = @{
            "zh" = "写入key,激活中: {0}"
            "en" = "Writing key, activating: {0}"
        }
        "source_address" = @{
            "zh" = "源 ja-netfilter 地址: https://gitee.com/ja-netfilter/ja-netfilter/releases/tag/2025.3.0"
            "en" = "Source ja-netfilter address: https://gitee.com/ja-netfilter/ja-netfilter/releases/tag/2025.3.0"
        }
        "source_privacy" = @{
            "zh" = "源 privacy.jar 地址: https://gitea.998043.xyz/novice/plugin-privacy/releases/tag/release"
            "en" = "Source privacy.jar address: https://gitea.998043.xyz/novice/plugin-privacy/releases/tag/release"
        }
        "suggest_check_sha1" = @{
            "zh" = "建议核对 SHA1 值以确保完整性"
            "en" = "It is recommended to verify the SHA1 value to ensure integrity"
        }
        "configuring_ja_netfilter" = @{
            "zh" = "配置ja-netfilter："
            "en" = "Configuring ja-netfilter:"
        }
        "custom_license_name" = @{
            "zh" = "自定义授权名称(回车默认KeyRun)"
            "en" = "Custom license name (Enter for default KeyRun)"
        }
        "custom_expiry_date" = @{
            "zh" = "自定义授权到期时间(回车默认2099-12-31)"
            "en" = "Custom expiration date (Enter for default 2099-12-31)"
        }
        "default_license_name" = @{
            "zh" = "KeyRun"
            "en" = "KeyRun"
        }
        "default_expiry_date" = @{
            "zh" = "2099-12-31"
            "en" = "2099-12-31"
        }
        "file_path_empty" = @{
            "zh" = "文件路径为空，跳过处理:{0}"
            "en" = "File path is empty, skipping processing: {0}"
        }
        "found_home_file" = @{
            "zh" = "找到.home文件: {0}"
            "en" = "Found .home file: {0}"
        }
        "read_home_content" = @{
            "zh" = "读取.home文件内容: {0}"
            "en" = "Read .home file content: {0}"
        }
        "found_bin_dir" = @{
            "zh" = "找到bin目录: {0}"
            "en" = "Found bin directory: {0}"
        }
        "sha1_info" = @{
            "zh" = "{0} :SHA1: {1}"
            "en" = "{0} :SHA1: {1}"
        }
        "request_fail" = @{
            "zh" = "请求失败: {0}"
            "en" = "Request failed: {0}"
        }
    }

    if ( $i18n.ContainsKey($key))
    {
        if ( $i18n[$key].ContainsKey($script:language))
        {
            return $i18n[$key][$script:language]
        }
    }

    # Return the key itself if not found
    return $key
}

# 日志输出函数
function Log
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$message,

        [ValidateSet("INFO", "DEBUG", "WARNING", "ERROR", "SUCCESS")]
        [string]$level = "INFO"
    )

    if ($level -eq "DEBUG" -and -not $script:enable_debug)
    {
        return
    }

    switch ($level)
    {
        "INFO" {
            $color = "White"
        }
        "DEBUG" {
            $color = "DarkGray"
        }
        "WARNING" {
            $color = "Yellow"
        }
        "ERROR" {
            $color = "Red"
        }
        "SUCCESS" {
            $color = "Green"
        }
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ( $message.StartsWith("`n"))
    {
        $message = $message.Substring(1)
        Write-Host "`n[$timestamp][$level] $message" -ForegroundColor $color
    }
    else
    {
        Write-Host "[$timestamp][$level] $message" -ForegroundColor $color
    }
}

function Debug([string]$message)
{
    $formatArgs = $args
    if ($formatArgs.Count -gt 0)
    {
        try
        {
            $message = $message -f $formatArgs
        }
        catch
        {
            # 如果格式化失败，则保持原消息
        }
    }
    Log -message $message -level "DEBUG"
}
function Warning([string]$message)
{
    $formatArgs = $args
    if ($formatArgs.Count -gt 0)
    {
        try
        {
            $message = $message -f $formatArgs
        }
        catch
        {
            # 如果格式化失败，则保持原消息
        }
    }
    Log -message $message -level "WARNING"
}
function Error([string]$message)
{
    $formatArgs = $args
    if ($formatArgs.Count -gt 0)
    {
        try
        {
            $message = $message -f $formatArgs
        }
        catch
        {
            # 如果格式化失败，则保持原消息
        }
    }
    Log -message $message -level "ERROR"
}
function Success([string]$message)
{
    $formatArgs = $args
    if ($formatArgs.Count -gt 0)
    {
        try
        {
            $message = $message -f $formatArgs
        }
        catch
        {
            # 如果格式化失败，则保持原消息
        }
    }
    Log -message $message -level "SUCCESS"
}

# 结束运行
function Exit-Program
{
    $null = Read-Host
    exit 1
}

# 进度条显示
function Write-ProgressCustom([string]$message, [string]$progress_bar, [double]$percent, [string]$color = "White")
{
    $output = "{0} {1} {2}%" -f $message.PadRight(10), $progress_bar,$percent.ToString("F2")
    [Console]::ForegroundColor = $color
    [Console]::Write("`r" + $output.PadRight(100))
    [Console]::ResetColor()
}

# 创建 HttpClient 实例


# 读取日期输入
function Read-Valid_Date([string]$prompt, [string]$default = "2099-12-31")
{
    $date = ""
    while ([string]::IsNullOrWhiteSpace($date) -or -not ($date -match '^\d{4}-\d{2}-\d{2}$'))
    {
        $date = Read-Host -Prompt $prompt
        if ( [string]::IsNullOrWhiteSpace($date))
        {
            $date = $default
            break
        }

        if (-not ($date -match '^\d{4}-\d{2}-\d{2}$'))
        {
            $msg = Get-i18nString "format_error"
            Write-Host $msg -ForegroundColor Red
            continue
        }

        $date_obj = Get-Date
        if (-not [DateTime]::TryParseExact($date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date_obj))
        {
            $msg = Get-i18nString "invalid_date"
            Write-Host ($msg -f $date) -ForegroundColor Red
            $date = ""
        }
    }
    return $date
}

# 显示 KeyRun ASCII Logo
function Show-Ascii_Jetbrains
{
    # 使用 Unicode 转义确保中文正确显示
    $author = [char]0x9152 + [char]0x6C8F + [char]0x8336  # 酒沏茶
    
    Write-Host @"

 _  __          ____              
| |/ /___ _   _|  _ \ _   _ _ __  
| ' // _ \ | | | |_) | | | | '_ \ 
| . \  __/ |_| |  _ <| |_| | | | |
|_|\_\___|\__, |_| \_\\__,_|_| |_|
          |___/                   
"@ -ForegroundColor Cyan
    Write-Host "      JetBrains Activation Tool" -ForegroundColor White
    Write-Host "                        By $author`n" -ForegroundColor DarkGray
}

# 获取属性值（idea.properties）
function Get_Property_Value([string]$file_path, [string]$key_to_find)
{
    $msg = Get-i18nString "reading_config"
    Debug ($msg -f $file_path, $key_to_find)

    try
    {
        Get-Content -Path $file_path -Encoding UTF8 -ErrorAction Stop | ForEach-Object {
            $line = $_.Trim()
            if (-not $line.StartsWith("#") -and -not [string]::IsNullOrWhiteSpace($line))
            {
                if ($line -match "^\s*([^#=]+?)\s*=\s*(.*)$")
                {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    if ($key -eq $key_to_find)
                    {
                        if ($value -match '\$\{user\.home\}')
                        {
                            $value = $value.Replace('${user.home}', $user_path)
                        }
                        $clean_value = [System.IO.Path]::GetFullPath($value.Replace('/', '\').Trim())
                        $msg = Get-i18nString "found_key"
                        Debug ($msg -f $key_to_find, $clean_value)
                        return [string]::new($clean_value)
                    }
                }
            }
        }
    }
    catch
    {
        $msg = Get-i18nString "failed_read_config"
        Debug ($msg -f $_)
    }
}

# 清理环境变量
function Remove_Env([string]$env_scope, [array]$products)
{
    $msg = Get-i18nString "processing_env_vars"
    Log ("`n" + ($msg -f $env_scope))

    foreach ($prd in $products)
    {
        $upper_key2 = "$($prd.name.ToUpper() )_VM_OPTIONS"
        $val_upper2 = [Environment]::GetEnvironmentVariable($upper_key2, $env_scope)
        $msg = Get-i18nString "checking_env"
        Debug $msg $env_scope $upper_key2 $val_upper2

        if (-not [string]::IsNullOrEmpty($val_upper2))
        {
            $msg = Get-i18nString "deleting_env"
            Log ($msg -f $env_scope, $prd.name)
            [Environment]::SetEnvironmentVariable($upper_key2, $null, $env_scope)
        }
    }
}

# 创建工作目录
function Create_Work_Dir
{
    $expected = [IO.Path]::GetFullPath((Join-Path $script:PublicRoot '.jb_run')).TrimEnd('\')
    $actual = [IO.Path]::GetFullPath($script:dir_work).TrimEnd('\')
    if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected work directory: $actual" }
    $ancestor = $script:PublicRoot
    while ($ancestor)
    {
        $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Unsafe work directory ancestor: $ancestor" }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (Test-Path -LiteralPath $actual)
    {
        $queue = New-Object 'Collections.Generic.Queue[string]'
        $queue.Enqueue($actual)
        while ($queue.Count -gt 0)
        {
            $directory = $queue.Dequeue()
            $item = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Unsafe work directory: $directory" }
            foreach ($child in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)
            {
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Unsafe work directory entry: $($child.FullName)" }
                if ($child.PSIsContainer) { $queue.Enqueue($child.FullName) }
            }
        }
    }
    try
    {
        if (Test-Path -LiteralPath $actual) { Remove-Item -LiteralPath $actual -Recurse -Force -ErrorAction Stop }
        New-Item -Path $actual -ItemType Directory -Force | Out-Null
        New-Item -Path $script:dir_config -ItemType Directory -Force | Out-Null
        New-Item -Path $script:dir_plugins -ItemType Directory -Force | Out-Null
    }
    catch { throw "Cannot create work directory '$actual': $($_.Exception.Message)" }
}

# 下载文件
function Get-Install_File_Plan
{
    @{ resource = 'ja-netfilter/ja-netfilter.jar'; save_path = $script:file_netfilter_jar }
    foreach ($name in @('dns', 'env', 'native', 'power', 'url'))
    {
        @{ resource = "ja-netfilter/config/$name.conf"; save_path = [IO.Path]::Combine($script:dir_config, "$name.conf") }
    }
    foreach ($name in @('dns', 'env', 'native', 'power', 'url', 'hideme', 'privacy'))
    {
        @{ resource = "ja-netfilter/plugins/$name.jar"; save_path = [IO.Path]::Combine($script:dir_plugins, "$name.jar") }
    }
}

# Read all resources before environment, work-directory or IDE changes.
function Initialize-Install_Resources
{
    $script:InstallResources = @{}
    $resources = @((Get-Install_File_Plan | ForEach-Object { $_.resource }))
    $resources += @($script:sPrds | ForEach-Object { "licenses/$($_.name).key" })
    foreach ($relativePath in $resources)
    {
        try
        {
            [byte[]]$bytes = Get-KeyRunResourceBytes -RelativePath $relativePath
            if ($bytes.Length -eq 0) { throw 'Resource is empty.' }
            $script:InstallResources[$relativePath] = $bytes
        }
        catch { throw "Install resource read failed '$relativePath': $($_.Exception.Message)" }
    }
    Write-Host ("资源预检完成：{0} 个文件。" -f $script:InstallResources.Count) -ForegroundColor Green
}

function Get-Install_ResourceBytes([string]$RelativePath)
{
    if ($null -eq $script:InstallResources -or -not $script:InstallResources.ContainsKey($RelativePath))
    {
        throw "Install resource was not preloaded: $RelativePath"
    }
    return ,([byte[]]$script:InstallResources[$RelativePath])
}

# Deploy bytes already read through the Loader.
function File_Download
{
    $files = @(Get-Install_File_Plan)
    $current = 0
    foreach ($file in $files)
    {
        $current++
        $percent = [math]::Round(($current / $files.Count) * 100, 2)
        $filled = [math]::Floor($percent / (100 / 30))
        $bar = '[' + ('#' * $filled) + ('.' * (30 - $filled)) + ']'
        Write-ProgressCustom -message (Get-i18nString 'configuring_ja_netfilter') -progress_bar $bar -percent $percent -color Green
        try
        {
            $content = Get-Install_ResourceBytes $file.resource
            [IO.File]::WriteAllBytes($file.save_path, $content)
            if ($file.resource.EndsWith('.jar'))
            {
                $hashAlgorithm = [Security.Cryptography.SHA1]::Create()
                try { $sha1 = [BitConverter]::ToString($hashAlgorithm.ComputeHash($content)) }
                finally { $hashAlgorithm.Dispose() }
                Debug ((Get-i18nString 'sha1_info') -f $file.resource, $sha1)
            }
        }
        catch { throw "Install resource write failed '$($file.resource)' to '$($file.save_path)': $($_.Exception.Message)" }
    }
}

# 清理 vmoptions 文件
function Revert_Vm_Options([string]$file_path)
{
    $lines = Get-Content -Path $file_path -Encoding UTF8 -ErrorAction SilentlyContinue
    $filtered_lines = $lines | Where-Object {
        -not $script:regex.IsMatch($_)
    }
    Set-Content -Path $file_path -Value $filtered_lines -Force
    $msg = Get-i18nString "cleaning_vmoptions"
    Debug ($msg -f $file_path)
}

# 添加配置到 vmoptions 文件
function Append_Vm_Options([string]$file_path)
{
    if (Test-Path -Path $file_path)
    {
        Add-Content -Path $file_path -Value $script:content -Force
        $msg = Get-i18nString "updating_vmoptions"
        Debug ($msg -f $file_path)
    }
}

# 读取文件，如果文件中有com.intellij.modules.ultimate，则清空这行
function Process_Disabled_Plugins([string]$file_disabled_plugins)
{
    # 验证参数
    if ( [string]::IsNullOrWhiteSpace($file_disabled_plugins))
    {
        $msg = Get-i18nString "file_path_empty"
        Debug ($msg -f $file_disabled_plugins)
        return
    }

    # 检查文件是否存在
    if (-not (Test-Path -Path $file_disabled_plugins))
    {
        $msg = Get-i18nString "file_not_exist_skip"
        Debug ($msg -f $file_disabled_plugins)
        return
    }

    try
    {
        # 读取文件内容
        $content = Get-Content -Path $file_disabled_plugins -Encoding UTF8 -ErrorAction Stop

        # 过滤掉包含 com.intellij.modules.ultimate 的行
        $filtered_content = $content | Where-Object { $_ -ne "com.intellij.modules.ultimate" }

        # 如果有过滤操作，则写回文件
        if ($content.Count -ne $filtered_content.Count)
        {
            Set-Content -Path $file_disabled_plugins -Value $filtered_content -Encoding UTF8 -Force
            $msg = Get-i18nString "processing_disabled_plugins"
            Debug ($msg -f $file_disabled_plugins)
        }
    }
    catch
    {
        $msg = Get-i18nString "error_processing_plugins"
        Warning ($msg -f $_)
    }
}

# 创建激活密钥
function Create_Key([hashtable]$product, [string]$prd_full_name, [string]$custom_config_path)
{
    $msg = Get-i18nString "processing_config"
    Debug ($msg -f $product.name, $prd_full_name, $custom_config_path)

    if (![string]::IsNullOrWhiteSpace($custom_config_path))
    {
        $dir_product = $custom_config_path
    }
    else
    {
        $dir_product = Join-Path -Path $script:dir_roaming_jetbrains -ChildPath $prd_full_name
    }

    if (-not (Test-Path -Path $dir_product))
    {
        $msg = Get-i18nString "manual_activation_required"
        Warning ($msg -f $prd_full_name)
        return
    }

    $file_vm_options = Join-Path -Path $dir_product "$( $product.name )64.exe.vmoptions"
    $file_key = Join-Path -Path $dir_product "$( $product.name ).key"
    $file_disable_plugins = Join-Path -Path $dir_product "disabled_plugins.txt"

    if (Test-Path -Path $file_vm_options)
    {
        $msg = Get-i18nString "config_exists_cleaning"
        Debug ($msg -f $prd_full_name)
        Revert_Vm_Options -file_path $file_vm_options
    }

    if (Test-Path -Path $file_key)
    {
        $msg = Get-i18nString "key_exists_cleaning"
        Debug ($msg)
        Remove-Item -Path $file_key -Force
    }

    # Preserve the original key bytes from the configured source.
    $license_resource = "licenses/$($product.name).key"
    $msg = Get-i18nString "requesting_key"
    Debug ($msg -f $license_resource, $product.name, $file_key)
    try
    {
        $key_bytes = Get-Install_ResourceBytes $license_resource
        $msg = Get-i18nString "writing_key"
        Debug ($msg -f $file_key)
        [System.IO.File]::WriteAllBytes($file_key, $key_bytes)
        Process_Disabled_Plugins($file_disable_plugins)
        $msg = Get-i18nString "activation_success"
        Success ($msg -f $prd_full_name)
    }
    catch { throw "Key processing failed '$prd_full_name': $($_.Exception.Message)" }
}

# 处理所有 JetBrains 产品
function Process_Vm_Options
{
    Log (Get-i18nString "processing_configs")

    #判断$script:dir_local_jetbrains是否存在
    if (!(Test-Path -Path $script:dir_local_jetbrains))
    {
        $msg = Get-i18nString "not_found_dir"
        Error ($msg -f $script:dir_local_jetbrains)
        Exit-Program
    }
    $dirs_local_prds = Get-ChildItem -Path $script:dir_local_jetbrains -Directory

    foreach ($dir_prd in $dirs_local_prds)
    {
        $prd = Is_Product -prd_dir_name $dir_prd.Name
        if ($null -eq $prd)
        {
            continue
        }

        $msg = Get-i18nString "processing_product"
        Log ($msg -f $dir_prd)

        $file_home = Join-Path -Path $dir_prd.FullName ".home"
        if (-not (Test-Path -Path $file_home))
        {
            $msg = Get-i18nString "not_found_home"
            Warning ($msg -f $file_home)
            continue
        }
        $msg = Get-i18nString "found_home_file"
        Debug ($msg -f $file_home)
        $content_home = Get-Content -Path $file_home -Encoding UTF8
        if (-not (Test-Path -Path $content_home))
        {
            $msg = Get-i18nString "path_not_exist"
            Warning ($msg -f $content_home)
            continue
        }
        $msg = Get-i18nString "read_home_content"
        Debug ($msg -f $content_home)
        $dir_real_product = Join-Path -Path $content_home "bin"
        if (-not (Test-Path -Path $dir_real_product))
        {
            $msg = Get-i18nString "not_found_bin"
            Warning ($msg -f $dir_real_product)
            continue
        }
        $msg = Get-i18nString "found_bin_dir"
        Debug ($msg -f $dir_real_product)
        $files_vm_options = Get-ChildItem -Path $dir_real_product -Filter "*.vmoptions" -Recurse
        foreach ($file_vm_options in $files_vm_options)
        {
            Revert_Vm_Options -file_path $file_vm_options.FullName
            Append_Vm_Options -file_path $file_vm_options.FullName
        }

        $file_properties = Join-Path -Path $dir_real_product "idea.properties"
        $custom_config_path = Get_Property_Value -file_path $file_properties -key_to_find "idea.config.path"
        Create_Key -product $prd -prd_full_name $dir_prd.Name -custom_config_path $custom_config_path
    }
}

# 是否是 JetBrains 产品
function Is_Product([string]$prd_dir_name)
{
    foreach ($prd in $script:sPrds)
    {
        if ( $prd_dir_name.ToLower().Contains($prd.name))
        {
            return $prd
        }
    }
    return $null
}

# 获取用户授权信息
function Read_Host_License_Info
{
    $new_license_name = Read-Host -Prompt (Get-i18nString "custom_license_name")
    if ( [string]::IsNullOrEmpty($new_license_name))
    {
        $new_license_name = Get-i18nString "default_license_name"
    }
    $script:license.licenseName = $new_license_name

    $new_expiry = Read-Valid_Date -prompt (Get-i18nString "custom_expiry_date")
    if ( [string]::IsNullOrEmpty($new_expiry))
    {
        $new_expiry = Get-i18nString "default_expiry_date"
    }
    $script:license.expiryDate = $new_expiry
}

# 主程序入口
function Main
{
    $source = Get-KeyRunSourceConfig
    Show-Ascii_Jetbrains
    Log (Get-i18nString "welcome_msg")
    Warning (Get-i18nString "script_date")
    Error (Get-i18nString "warning_msg")

    # 提权检测
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
    {
        Warning (Get-i18nString "admin_request")
        $null = Read-Host
        $powershellPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
        $launchArguments = @('-NoProfile', '-File', ('"{0}"' -f $script:InstallerPath))
        if ($OpenPage) { $launchArguments += '-OpenPage' }
        try
        {
            $process = Start-Process -FilePath $powershellPath -ArgumentList $launchArguments -Verb RunAs -WorkingDirectory $script:ProjectRoot -WindowStyle Normal -Wait -PassThru
            exit $process.ExitCode
        }
        catch { throw "Cannot start the local installer with administrator rights: $($_.Exception.Message)" }
    }


    Warning (Get-i18nString "close_products")
    $null = Read-Host

    # 初始化全局变量
    $user_path = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $publicDocuments = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonDocuments)
    if ([string]::IsNullOrWhiteSpace($publicDocuments)) { throw 'Cannot locate the Windows public directory.' }
    $script:PublicRoot = Split-Path $publicDocuments -Parent
    $public_path = $script:PublicRoot
    Write-Host ("资源来源：{0}" -f $source.mode) -ForegroundColor Cyan

    $script:dir_work = "$public_path\.jb_run\"
    $script:dir_config = "$script:dir_work\config\"
    $script:dir_plugins = "$script:dir_work\plugins\"
    $script:file_netfilter_jar = Join-Path -Path $script:dir_work "ja-netfilter.jar"
    $script:dir_local_jetbrains = Join-Path -Path $user_path -ChildPath "AppData\Local\JetBrains\"
    $script:dir_roaming_jetbrains = Join-Path -Path $user_path -ChildPath "AppData\Roaming\JetBrains\"

    # 正则表达式
    $pattern = '^-javaagent:.*[/\\]*\.jar.*'
    $script:regex = New-Object System.Text.RegularExpressions.Regex $pattern, ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)

    # 配置内容
    $script:content = @(
        "-javaagent:$($script:file_netfilter_jar.Replace("\", "/") )"
    )

    # 产品列表
    $script:sPrds = @(
        @{ name = "idea";     product_code = "II,PCWMP,PSI" }
        @{ name = "clion"; product_code = "CL,PSI,PCWMP" }
        @{ name = "phpstorm"; product_code = "PS,PCWMP,PSI" }
        @{ name = "goland"; product_code = "GO,PSI,PCWMP" }
        @{ name = "pycharm"; product_code = "PC,PSI,PCWMP" }
        @{ name = "webstorm"; product_code = "WS,PCWMP,PSI" }
        @{ name = "rider"; product_code = "RD,PDB,PSI,PCWMP" }
        @{ name = "datagrip"; product_code = "DB,PSI,PDB" }
        @{ name = "rubymine"; product_code = "RM,PCWMP,PSI" }
        @{ name = "appcode"; product_code = "AC,PCWMP,PSI" }
        @{ name = "dataspell"; product_code = "DS,PSI,PDB,PCWMP" }
        @{ name = "rustrover"; product_code = "RR,PSI,PCWP" }
    )

    # 授权信息
    $script:license = [PSCustomObject]@{
        assigneeName = ""
        expiryDate = "2099-12-31"
        licenseName = "KeyRun"
        productCode = ""
    }

    Initialize-Install_Resources
    # 开始执行主流程
    Read_Host_License_Info
    Log (Get-i18nString "processing")

    Remove_Env -env_scope "User" -products $script:sPrds
    Remove_Env -env_scope "Machine" -products $script:sPrds

    Create_Work_Dir
    File_Download
    Process_Vm_Options

    Log (Get-i18nString "processing_completed")
    # 使用 Unicode 转义确保中文正确显示
    $author = [char]0x9152 + [char]0x6C8F + [char]0x8336  # 酒沏茶
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Powered by $author | KeyRun" -ForegroundColor Green
    $sourceLocation = if ($source.mode -eq 'local') { $source.localRoot } else { $source.httpBase }
    Write-Host ("  Source: {0}" -f $sourceLocation) -ForegroundColor DarkGray
    Write-Host "========================================`n" -ForegroundColor Cyan
    Start-Sleep -s 2
    if ($OpenPage)
    {
        try { $page = Resolve-KeyRunResource 'index.html'; Start-Process -FilePath $page.Location }
        catch { Write-Warning ("处理已完成，但打开页面失败：{0}" -f $_.Exception.Message) }
    }
    $null = Read-Host
}

try { Main }
catch {
    Write-Error ("KeyRun failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}
