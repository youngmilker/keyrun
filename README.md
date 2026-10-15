<p align="right">简体中文 | <a href="./README.en.md">English</a></p>

# KeyRun 跨平台工具

此入口通过 `source-config.json → resource-loader.ps1 → keyrun.ps1` 读取普通资源。
支持 Windows PowerShell 5.1。Local 模式直接读取磁盘，无需 HTTP 服务。
项目初始配置为 HTTP 服务器来源；执行 -Mode local 后才从本地读取，模式保存在 source-config.json 中。
默认资源读取和路径诊断无需管理员权限；使用 -Install 执行恢复后的 Windows 原处理流程。
macOS/Linux 使用原生 Bash 入口，共用来源配置和资源目录，详见下方说明。

## macOS / Linux 本地使用

需要 Bash 3.2 或更新版本、jq；HTTP 模式另外需要 curl；文本读取使用系统 iconv。
无需 PowerShell。脚本不会自动安装软件或加载个人 shell 配置。
macOS 缺少 jq 时，可通过已有 Homebrew 执行 `brew install jq`；
Debian/Ubuntu 可执行 `sudo apt-get install bash jq curl`。KeyRun 安装本身请以普通桌面用户运行。

在完整项目目录中先切换 Local，再预览：

```bash
bash ./switch-source.sh --mode local
bash ./keyrun.sh --install --dry-run
bash ./keyrun.sh --diagnose-idea-paths
# 也可只检查一个指定文件或安装目录：
bash ./keyrun.sh --diagnose-idea-paths --properties-path '/路径/idea.properties'
```

预览会列出配置目录、启动参数文件和模板，不下载资源、不修改 IDE。
自动发现使用默认配置目录、缓存 `.home`、部分标准安装及 Toolbox 目录；
macOS 识别 `.app/Contents/bin`，Linux 支持 `XDG_CONFIG_HOME`、`XDG_CACHE_HOME` 和 Toolbox 的 `XDG_DATA_HOME`。
标准安装扫描根可通过 `KEYRUN_APPLICATIONS_DIR`（默认 `/Applications`）或 `KEYRUN_OPT_DIR`（默认 `/opt`）覆盖。
没有缓存时，可通过安装中的 `product-info.json` 的 `dataDirectoryName` 关联配置目录。
未知安装、隔离安装或自定义位置可显式指定：

```bash
bash ./keyrun.sh --install --dry-run \
  --config-dir '/你的配置目录' --product idea --ide-home '/你的安装目录或.app'
```

识别目录后，先关闭所有 JetBrains IDE，再执行实际安装：

```bash
bash ./keyrun.sh --install
# 无交互环境中，--yes 表示已确认目录并关闭 IDE：
bash ./keyrun.sh --install --yes
```

安装前先完整读取 25 个资源到临时目录，失败就停止。
写入用户配置目录中的 VM options 和 key，Agent 部署到 `~/.jb_run/`；不修改 macOS 应用包。
新建 VM options 时复制安装模板，保留已有 JVM 参数和其他 Agent，只替换 KeyRun/ja-netfilter 参数。
配置目录支持简单 `idea.config.path`、`${user.home}` 和相对路径，并优先检查产品的 `*_PROPERTIES` 环境变量。
不求值任意变量或命令；复杂 Java properties 转义、任意安装目录扫描和 Snap/Flatpak 权限映射不在自动发现范围内。

每次实际写入在 `~/.jb_run/backups/run-时间.随机值/` 保存原文件。
`manifest.jsonl` 记录文件是否原本存在；原文件位于备份下的 `files/原绝对路径`。
安装锁防止同一用户并发覆盖；若被强制终止而留下 `~/.jb_run/.install-lock`，确认没有安装运行后再移除该空目录。
发生写入失败时尝试恢复本次已修改文件，保留备份供核对；进程被强制终止或系统断电时需人工恢复。
只清理已识别产品在常见用户 profile 中的独立 `*_VM_OPTIONS=...` 赋值，并先备份；
遇到条件语句等复杂定义会停止并提示人工检查，不会执行 profile。
macOS 同步清理已识别产品的当前 launchctl 环境。自定义 LaunchAgent、systemd 用户环境等需单独核对；
子进程无法修改当前终端的父进程环境，必要时在新终端或重新登录后测试。

读取普通资源：

```bash
bash ./keyrun.sh --resource-path README.md
bash ./keyrun.sh --resource-path source-config.json --format json
bash ./keyrun.sh --resource-path LICENSE --format bytes
```

`--format bytes` 保留原始字节；文本严格按 UTF-8 解码并移除 UTF-8 BOM。
Local 无 HTTP 请求，资源路径拒绝父目录和根目录内部的符号链接。
系统根目录别名会规范化；安装写入路径中的符号链接会被拒绝。

## macOS / Linux HTTP 与独立引导

维护者在完整项目目录中执行：

```bash
bash ./switch-source.sh --mode http --http-base 'https://你的服务器/keyrun' --timeout-seconds 20
```

命令保存来源配置，并生成独立服务器入口 `sh`，内嵌地址和六个代码文件的 SHA-256。
把完整项目发布到该资源根目录。修改 Shell 代码后重新生成再发布，Shell 文件必须保留 LF 换行。
Windows 的配置命令也会同步生成 `sh`；从 macOS/Linux 部署时，如需 Windows 入口，
仍需在 Windows 执行原配置命令，生成匹配地址的 `ps1`。

最终使用者无需本地项目：

```bash
# 先预览；把地址换成实际部署地址：
curl -fsSL 'https://你的服务器/keyrun/sh' | bash -s -- --dry-run
# 确认后安装：
curl -fsSL 'https://你的服务器/keyrun/sh' | bash
```

引导验证全部代码后才运行安装入口，临时文件在结束时清理。
HTTP 不跟随重定向，拒绝非 2xx 状态，使用配置中的超时，不回退到其他地址。
哈希用于检查代码版本一致性；初始引导由所选服务器提供，请使用可信来源。
`scripts/install.sh` 是完整本地项目的兼容入口，远程管道请使用独立入口 `/sh`。

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

macOS/Linux 使用上方的 `/sh` 独立入口。

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
`test_script.ps1` 是仍阻止执行的旧重复副本；`scripts/install.sh` 已转发到原生 `install-unix.sh`。
安装链路验证见 tests/test-install-resource-wiring.ps1：只在项目内临时目录部署字节和模拟配置，不运行 Main，不申请 UAC，也不修改实际 IDE 或系统环境变量。
独立服务器引导验证见 tests/test-server-bootstrap.ps1：仅使用回环测试服务和无害入口，覆盖空目录启动、地址同步、代码校验拒绝和清理，不运行真实安装。
详见 [重构报告](./SOURCE-REFACTOR.md)。原始文件备份保留在 backups/ 中，仅供审计，不应执行。

跨平台模拟测试：`python3 tests/test-unix.py`。测试仅使用临时模拟资源和 IDE，
覆盖 Local/HTTP、目录发现、预览、备份、重复安装、写入失败恢复、独立引导代码校验和清理。
需要允许在回环地址启动临时 HTTP 服务，不会运行真实 JAR 或修改真实 IDE。
真实 Linux 容器验证可执行：

```bash
docker build -f tests/Dockerfile.unix -t keyrun-unix-test .
docker run --rm --network none keyrun-unix-test
```

本项目源代码许可为 [GNU GPL v3](./LICENSE)。JetBrains 软件授权请通过 [官方渠道](https://www.jetbrains.com/)处理。
