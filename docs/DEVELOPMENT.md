# 开发、部署与高级用法

本文面向维护者以及需要排查自定义目录、资源来源问题的使用者。首次使用请从[中文使用指南](../README.md)或[英文使用指南](../README.en.md)开始。

## 入口与来源配置

| 用途 | Windows | macOS / Linux |
| --- | --- | --- |
| 本地入口 | `keyrun.ps1` | `keyrun.sh` |
| 切换来源 | `switch-source.ps1` | `switch-source.sh` |
| 资源读取 | `resource-loader.ps1` | `resource-loader.sh` |
| 安装实现 | `scripts/install.ps1` | `scripts/install.sh` → `scripts/install-unix.sh` |
| 独立服务器入口 | `ps1` | `sh` |

两个平台共用项目根目录的 `source-config.json`。当前提交的模式为 Local；用户运行来源切换命令后，选择会持续保存。

- Local 直接读取磁盘，不需要 HTTP 服务。相对 `localRoot` 以 Loader 所在目录为基准，不取决于当前工作目录。
- HTTP 从配置的根地址读取资源；根地址只接受 HTTP/HTTPS，不允许凭据、查询串或片段。
- 超时为 1–300 秒，默认 20 秒。HTTP 不跟随重定向，非 2xx、连接错误和超时均报错，不回退到其他网站。
- Local 切换保留已有服务器地址及已生成引导；HTTP 切换会更新对应服务器引导。
- 网页只生成命令，不保存配置。实际切换必须执行命令。
- 本地安装从当前项目读取代码；独立服务器入口会下载并校验代码后执行。

Windows 支持 Windows PowerShell 5.1。Unix 入口兼容 Bash 3.2，需要 jq；HTTP 还需要 curl，文本读取使用 iconv，引导校验使用 shasum 或 sha256sum。

## 服务器部署

服务器只需提供静态文件，无需在服务器执行 PowerShell。以下命令在完整项目的根目录运行。

### 从 Windows 发布

```powershell
powershell.exe -NoProfile -File .\switch-source.ps1 -Mode http -HttpBase 'https://your-server.example/keyrun' -TimeoutSeconds 20
```

替换示例地址后执行，会保存来源配置并生成 Windows `ps1` 和 Unix `sh`。把完整项目发布到同一个资源根地址。

### 从 macOS / Linux 发布

```bash
bash ./switch-source.sh --mode http --http-base 'https://your-server.example/keyrun' --timeout-seconds 20
```

此命令生成 Unix `sh`。如果同时发布 Windows 入口，还需在 Windows 运行上一条配置命令，为相同地址生成 `ps1`。

每次修改相关代码后都要重新生成引导，并发布匹配版本。Unix 引导按原始字节校验六个代码文件；Windows 引导校验四个代码文件并规范化 CRLF。Shell 文件必须保留 LF 换行，仓库通过 `.gitattributes` 约束。

初始引导由所选服务器提供，内嵌 SHA-256 用于检查代码版本一致性，不等同于独立验证服务器可信度。普通使用者无需在本机执行部署配置命令。

- Windows 在线入口：`/ps1`。
- macOS / Linux 在线入口：`/sh`；`scripts/install.sh` 依赖本地项目，不适用于独立远程管道。
- 引导在临时目录准备代码和 HTTP 配置，成功或失败后清理；不使用调用方工作目录中的项目配置。
- 仓库保留的旧服务器地址仅作示例，发布前应换成实际可用的服务地址。

## 目录诊断与自定义路径

只读诊断不修改 IDE。默认逐个检查发现的属性文件；指定路径时只检查该文件或安装目录。

Windows：

```powershell
powershell.exe -NoProfile -File .\keyrun.ps1 -DiagnoseIdeaPaths
powershell.exe -NoProfile -File .\keyrun.ps1 -DiagnoseIdeaPaths -PropertiesPath 'C:\path\to\idea.properties'
```

macOS / Linux：

```bash
bash ./keyrun.sh --diagnose-idea-paths
bash ./keyrun.sh --diagnose-idea-paths --properties-path '/path/to/idea.properties'
```

Unix 自定义安装可先显式预览，下面的 `idea` 代表 IntelliJ IDEA：

```bash
bash ./keyrun.sh --install --dry-run \
  --config-dir '/配置目录' --product idea --ide-home '/安装目录或.app'
```

确认后去掉 `--dry-run` 进行实际安装。可用产品名：`idea`、`clion`、`phpstorm`、`goland`、`pycharm`、`webstorm`、`rider`、`datagrip`、`rubymine`、`appcode`、`dataspell`、`rustrover`。

Unix 自动发现检查默认配置目录、缓存 `.home`、部分标准安装及 Toolbox 目录。macOS 支持 `.app/Contents/bin`；没有缓存时可通过 `product-info.json` 的 `dataDirectoryName` 关联配置目录。
Linux 支持 `XDG_CONFIG_HOME`、`XDG_CACHE_HOME` 和 Toolbox 的 `XDG_DATA_HOME`。标准安装扫描根可通过 `KEYRUN_APPLICATIONS_DIR`（默认 `/Applications`）或 `KEYRUN_OPT_DIR`（默认 `/opt`）覆盖。

Unix 安装按优先级合并安装目录、用户配置目录及产品 `*_PROPERTIES` 环境变量指定文件中的简单 `idea.config.path`，支持 `${user.home}`、相对路径和常见路径转义，不执行变量或命令。
复杂 Java properties 语法、任意磁盘扫描和 Snap/Flatpak 权限映射不在自动发现范围内。
Windows 安装使用缓存 `.home` 定位安装目录，再读取安装目录 `idea.properties` 中的配置路径；具体解析能力与 Unix 入口不同。

## 安装行为与恢复

安装先读取全部 25 个资源，再修改配置。资源根需包含完整的 `ja-netfilter/` 和 `licenses/`。
Agent JAR 会由 IDE 加载；文件写入完成不表示已验证实际授权结果。名称和日期输入不重新生成静态 key 文件。

Windows 安装请求管理员权限，通过本地安装文件重新启动，保留 `OpenPage` 参数。原流程清理用户和机器级 VM_OPTIONS 环境变量，重建公共 `.jb_run` 工作目录并修改相关启动参数和 key。使用前应手动备份配置。

Unix 安装使用当前登录用户，不接受 root。资源部署到 `~/.jb_run/`，启动参数和 key 写到用户配置目录，不修改 macOS 应用包。
新建 VM options 时复制安装模板；保留原有 JVM 参数与其他 Agent，只替换 KeyRun/ja-netfilter 参数。相同用户的安装锁防止并发覆盖。

Unix 每次写入在 `~/.jb_run/backups/run-时间.随机值/` 保存原文件：

- `manifest.jsonl` 记录原绝对路径和文件是否原本存在。
- 原文件位于备份目录下的 `files/原绝对路径`，保留原有权限信息。
- 写入失败会尝试恢复本次修改，备份仍保留供核对；被强制终止或断电时可能需要人工恢复。
- 人工恢复前先关闭 IDE，按 manifest 核对目标；原本不存在的文件不能用旧备份盲目覆盖。
- 若留下 `~/.jb_run/.install-lock`，确认没有安装运行后再移除这个空目录。

Unix 只清理已识别产品在常见用户 profile 中的独立 VM_OPTIONS 赋值，并先备份。复杂定义会停止并提示人工检查，profile 不会被执行。
macOS 同步清理已识别产品的当前 launchctl 环境。自定义 LaunchAgent、systemd 用户环境需单独核对；子进程不能修改父终端环境，必要时在新终端或重新登录后测试。
`--yes` 用于无交互安装，表示使用者已确认目录并关闭 IDE。

## 普通资源与 Loader 接口

不传安装选项时，入口默认显示 README，不会安装。

```powershell
powershell.exe -NoProfile -File .\keyrun.ps1 -ResourcePath source-config.json -Format Json
powershell.exe -NoProfile -File .\keyrun.ps1 -ResourcePath LICENSE -Format Bytes

. .\resource-loader.ps1
$text = Get-KeyRunResourceText 'README.md'
$json = Get-KeyRunResourceJson 'source-config.json'
[byte[]]$bytes = Get-KeyRunResourceBytes 'LICENSE'
```

```bash
bash ./keyrun.sh --resource-path README.md
bash ./keyrun.sh --resource-path source-config.json --format json
bash ./keyrun.sh --resource-path LICENSE --format bytes
```

文本严格按 UTF-8 解码，支持 BOM；二进制接口保留原始字节。资源路径拒绝绝对路径、父目录、空段及非法字符。
Windows 本地读取拒绝路径及根目录祖先中的 reparse point；Unix 规范化系统目录别名并拒绝根目录内部的资源符号链接，安装写入路径也拒绝符号链接。
不要让不可信进程在路径校验与读取间替换文件。

可通过 Windows `-LocalRoot` 或 Unix `--local-root` 覆盖本地资源根。
`-OpenPage` / `--open-page` 为可选浏览器操作；Linux 打开网页需 xdg-open，网页第三方图标不受 Loader 控制。
Windows 执行策略由系统或组织管理，工具不自动修改。

## 测试与维护

Unix 模拟集成测试：

```bash
python3 tests/test-unix.py
```

测试使用临时的无害资源和模拟 IDE，覆盖 Local/HTTP、预览、目录发现、备份、重复安装、失败恢复及独立引导代码校验和清理。需要允许回环 HTTP 服务，不会执行真实 JAR 或修改真实 IDE。

真实 Linux 容器中的模拟测试：

```bash
docker build -f tests/Dockerfile.unix -t keyrun-unix-test .
docker run --rm --network none keyrun-unix-test
```

Windows PowerShell 5.1 测试：

```powershell
powershell.exe -NoProfile -File .\tests\test-resource-loader.ps1
powershell.exe -NoProfile -File .\tests\test-idea-path-diagnosis.ps1
powershell.exe -NoProfile -File .\tests\test-install-resource-wiring.ps1
powershell.exe -NoProfile -File .\tests\test-server-bootstrap.ps1
```

需要能通过 `python.exe` 找到 Python；HTTP 测试使用回环服务。安装测试只在模拟目录验证，不运行真实 Main 或 UAC。
历史重复文件 `test_script.ps1` 仍阻止执行；历史备份只供审计，不应执行。
详细验证记录和平台限制见[变更报告](../SOURCE-REFACTOR.md)。模拟测试不等同于实际 IDE 重启验证。
