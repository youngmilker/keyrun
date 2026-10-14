<p align="right">简体中文 | <a href="./README.en.md">English</a></p>

# KeyRun Windows 工具

此入口通过 `source-config.json → resource-loader.ps1 → keyrun.ps1` 读取普通资源。
支持 Windows PowerShell 5.1。Local 模式直接读取磁盘，无需 HTTP 服务。
项目初始配置为 HTTP 服务器来源；执行 -Mode local 后才从本地读取，模式保存在 source-config.json 中。
默认资源读取和路径诊断无需管理员权限；使用 -Install 执行恢复后的 Windows 原处理流程。
macOS/Linux 兼容留待后续开发，目前 shell 安装入口仍停用。

## 从本地启动

在项目目录运行：

```powershell
.\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1
.\keyrun.ps1 -ResourcePath index.html
.\keyrun.ps1 -ResourcePath source-config.json -Format Json
.\keyrun.ps1 -ResourcePath LICENSE -Format Bytes
.\keyrun.ps1 -DiagnoseIdeaPaths
.\keyrun.ps1 -DiagnoseIdeaPaths -PropertiesPath 'C:\path\to\idea.properties'
```

也可以从任何工作目录使用 keyrun.ps1 的完整路径启动。
原 `ps1` 是历史本地调用兼容包装；Windows 的 `-File` 正式入口为 `keyrun.ps1`。
原 ps1 现在是可发布到服务器的独立 Windows 引导脚本，不是本地包装。Local 请使用 keyrun.ps1。
普通入口默认读取本说明，不会安装、激活或修改 IDE。
路径诊断默认逐个检查标准目录中找到的所有配置文件；使用 -PropertiesPath 时只检查指定文件。
每个结果单独显示编号和文件路径，某个文件失败后继续检查其他文件，最终汇总失败。
诊断只读，不修改 IDE 配置，也不读取远程脚本。
Windows PowerShell 的执行策略由用户或组织管理，本项目不会自动修改执行策略。

## Windows 原处理流程

先备份 IDE 配置及已有许可证文件，并关闭所有 JetBrains 软件，再运行：

```powershell
.\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1 -Install
```

安装模式会请求管理员权限，使用本地 scripts/install.ps1 的完整路径重新启动，保留 OpenPage 参数。
全部 25 个所需资源先通过 Loader 读取成功，之后才清理产品 VM_OPTIONS 环境变量、重建公共 .jb_run 工作目录、部署 Agent、修改原脚本涉及的启动参数和写入 .key。
许可证文件按来源中的原始字节写入；原名称和日期输入提示不重新生成这些静态文件。
原脚本仍按 JetBrains 本地缓存目录及 .home 文件发现产品；缺失时会输出跳过或错误信息。
资源根目录应包含 ja-netfilter/ 和 licenses/。只使用可信资源来源：Agent JAR 会由 IDE 加载。
没有调用失效的 GitHub Pages，也没有下载并执行远程 PowerShell 脚本。
写入完成不表示已验证软件授权结果；实际结果需要重新打开 IDE 检查。
需要执行后打开页面可加 -OpenPage；仅诊断请使用 -DiagnoseIdeaPaths。

## HTTP 模式

```powershell
.\switch-source.ps1 -Mode http -HttpBase 'https://liyangxu1.github.io/keyrun' -TimeoutSeconds 20
.\keyrun.ps1 -ResourcePath README.md
.\keyrun.ps1 -ResourcePath source-config.json -Format Json
.\switch-source.ps1 -Mode local
```

上面的原 KeyRun 地址只作示例，在 2026-10-14 核对时返回 404。实际部署必须换成你管理的资源根地址。
根地址支持 HTTP/HTTPS，不能包含凭据、查询串或片段。
HTTP 301/302 等重定向会明确报错；请配置最终资源根地址。PowerShell 入口始终使用本地代码。
`-TimeoutSeconds` 范围是 1–300，默认 20；配置错误或请求失败不会回退到其他网站。
Local 模式下未启用的 HTTP 地址不参与读取。

## 服务器部署与独立 Windows 引导

项目维护者在完整项目目录执行 -Mode http -HttpBase 实际地址，会保存配置并自动生成 ps1。
生成的 ps1 内嵌服务器根地址，以及四个所需代码文件的 SHA-256。之后把完整项目发布到该根地址。
代码更新后应重新运行服务器配置命令，再发布匹配版本的 ps1 和项目代码。
无需服务端执行 PowerShell；服务器提供可通过 HTTP/HTTPS 读取的静态文件即可。

最终使用者可以在没有本地项目的 Windows PowerShell 中运行服务器入口：

```powershell
irm https://liyangxu1.github.io/keyrun/ps1 | iex
```

示例地址需要替换成实际可用、可信的已部署地址。
引导在临时目录准备所需代码和 HTTP 配置，校验代码字节后运行 Windows 本地安装入口，资源继续从服务器获取。
引导不会使用调用方当前目录中的项目或来源配置，完成后清理临时文件。
初始引导脚本本身由所选服务提供，代码哈希用于防止文件版本混用，不等同于独立验证服务器可信度。

已有本地项目的用户必须执行 -Mode local 才转为本地读取；以后保持 Local，直到再执行 -Mode http。
Local 切换不会改写保留的服务器根地址或部署引导；HTTP 切换会替换为填写的地址。
直接使用已部署服务的最终用户不需要在本机运行 switch-source.ps1。
网页输入只生成命令；修改服务器地址需要维护者执行配置命令并重新发布项目。

macOS/Linux 的 curl 命令仅为服务端引导格式示例；仓库 shell 入口仍停用，实际兼容实现留待后续开发。

## 直接使用 Loader

```powershell
. .\resource-loader.ps1
$text = Get-KeyRunResourceText 'README.md'
$json = Get-KeyRunResourceJson 'source-config.json'
[byte[]]$bytes = Get-KeyRunResourceBytes 'LICENSE'
# 二进制内容可由调用方保存到明确指定的位置：
[IO.File]::WriteAllBytes((Join-Path $PWD 'license-copy.txt'), $bytes)
```

文本接口严格按 UTF-8 解码，支持有/无 BOM；非 UTF-8 文本应使用字节接口并显式选择实际编码。
二进制接口保留原始字节。相对资源路径不能使用绝对路径、父目录、空段或 Windows 非法字符。
本地读取拒绝路径中的符号链接、junction 和其他 reparse point，防止越过配置根目录。
不要让不可信进程在校验和读取之间替换根目录或文件。

`localRoot` 默认 `.`，相对路径以 Loader 所在目录为基准；可使用 `-LocalRoot` 显式覆盖。
`-OpenPage` 是可选浏览器操作：本地打开 index.html，HTTP 打开配置根地址下的 index.html。
网页自身的第三方图标和仓库链接仍属于浏览器资源，不受 PowerShell Loader 控制。

## 验证与边界

`tests/test-resource-loader.ps1` 在临时目录运行，Local 检查期间不启动服务；
随后临时开启只提供测试数据的回环 HTTP 服务，结束时清理。
它不运行原安装脚本，也不读取授权 key 或 Java Agent 文件。

`scripts/install.ps1` 已恢复，并通过统一 Loader 读取安装资源。
`test_script.ps1` 是旧重复副本，`scripts/install.sh` 等待 macOS/Linux 适配；两者仍在顶部阻止执行。
安装链路验证见 tests/test-install-resource-wiring.ps1：只在项目内临时目录部署字节和模拟配置，不运行 Main，不申请 UAC，也不修改实际 IDE 或系统环境变量。
独立服务器引导验证见 tests/test-server-bootstrap.ps1：仅使用回环测试服务和无害入口，覆盖空目录启动、地址同步、代码校验拒绝和清理，不运行真实安装。
详见 [重构报告](./SOURCE-REFACTOR.md)。原始文件备份保留在 backups/ 中，仅供审计，不应执行。

本项目源代码许可为 [GNU GPL v3](./LICENSE)。JetBrains 软件授权请通过 [官方渠道](https://www.jetbrains.com/)处理。
