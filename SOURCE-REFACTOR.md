# KeyRun 当前来源模式与服务器引导报告

更新日期：2026-10-14。当前初始配置已改为 **HTTP**：
httpBase 为 `https://liyangxu1.github.io/keyrun`，localRoot 为 `.`，超时 20 秒。
原地址是用户指定的示例；本轮 HEAD 核对根地址、/ps1 和 /scripts/install.sh 均为 404。
因此真实部署必须配置可用地址，不能使用当前旧示例地址执行安装。

## 最终行为

- 新项目未执行 Local 切换时，按服务器来源读取资源。
- 执行 -Mode local 后直接读取磁盘，不需要 HTTP 服务；模式保存并持续生效。
- 再执行 -Mode http -HttpBase 实际地址，保存新服务器地址并恢复 HTTP 读取。
- HTTP 切换同时重新生成 Windows 服务器引导 ps1，更新内嵌地址、超时和代码校验值。
- Local 切换不改写保留的服务器根地址和服务器引导内容。
- 页面选择与输入只生成命令；必须实际执行配置命令才能保存设置。
- 独立服务器入口的最终使用者无需预先下载本地项目，不需要本机来源切换命令。
- 服务器提供脚本和资源，脚本仍在使用者电脑上处理 IDE，不是由服务器直接修改客户端。

## 运行与部署

本地使用：

```powershell
Set-Location '你的项目地址'
.\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1 -Install
```

项目维护者部署前：

```powershell
Set-Location '你的项目地址'
.\switch-source.ps1 -Mode http -HttpBase 'https://你的实际服务器/keyrun' -TimeoutSeconds 20
```

然后将完整项目发布到该根地址。必须包含生成的 ps1、resource-loader.ps1、
keyrun.ps1、scripts/install.ps1、scripts/diagnose-idea-paths.ps1、
ja-netfilter/ 和 licenses/ 等项目文件。
源代码修改后应重新运行 HTTP 配置命令，再部署匹配版本。
服务器只需提供静态文件，不必在服务器执行 PowerShell。

最终 Windows 使用者：

```powershell
irm https://liyangxu1.github.io/keyrun/ps1 | iex
```

换成实际已部署地址。生成的服务器引导内嵌部署地址，所以迁移服务器后必须重新生成，
仅修改网页输入或复制命令不会更新服务器上已经发布的引导文件。

只读诊断继续保留：

```powershell
.\keyrun.ps1 -DiagnoseIdeaPaths
```

## Windows 独立引导

ps1 已从本地包装改为可独立运行的服务器引导：

1. 在随机临时目录中准备环境。
2. 下载 Loader 并核对生成时的 SHA-256。
3. 使用 Loader 下载其他三个代码文件，全部核对后才运行入口。
4. 写入独立 HTTP 配置，携带部署地址和超时，忽略调用方目录中的项目及配置。
5. 本地运行已核对的 keyrun.ps1 -Install；该入口保留原 Windows 处理逻辑。
6. 处理完成或失败后清理临时目录；清理前核对绝对路径边界并拒绝 reparse point。

代码摘要只规范化 CRLF 为 LF，保留 BOM，避免 Git/Windows 行尾转换导致版本误判；
下载和部署仍保留原始字节。初始引导本身来自所选服务器，摘要防止代码版本混用，
不等同于独立证明服务器可信。请仅使用可信服务提供的代码和资源。

普通资源继续通过 source-config.json → resource-loader.ps1 读取。
独立引导仅在取得 Loader 之前使用最小 HTTP 下载器下载该模块；
其余代码和安装资源均使用统一 Loader。没有静默回退到其他地址。

## 本轮文件

| 文件 | 修改内容 |
| --- | --- |
| index.html | 默认展示 HTTP；根地址默认原 KeyRun 示例；Windows/macOS/Linux 服务器命令随输入变化；Local 仅提供本地切换与处理；区分部署配置命令和最终使用者命令；指南同步说明模式持久化。 |
| source-config.json | 初始模式改为 HTTP，保留相对 localRoot，设置原地址为服务器示例。 |
| switch-source.ps1 | HTTP 切换自动调用引导生成器，传递已验证地址与超时；Local 不重写服务器引导。 |
| scripts/build-server-bootstrap.ps1 | 新增生成器：读取四个代码文件、生成摘要、填充部署地址和超时、解析验证输出后写入 ps1。 |
| scripts/server-bootstrap.template.ps1 | 新增 Windows 独立引导模板，包含代码校验、独立临时配置、调用本地入口及边界安全的清理。 |
| ps1 | 根据当前部署配置生成的独立 Windows HTTP 入口。 |
| README.md / README.en.md | 更新默认服务器模式、显式 Local、模式保存、静态部署、独立引导及平台状态。 |
| tests/test-server-bootstrap.ps1 | 新增独立引导验证，使用无害入口与隔离配置。 |
| tests/bootstrap-http-fixture.py | 回环服务，只允许提供测试项目的五个明确脚本文件，不提供 IDE 或安装资源。 |
| SOURCE-REFACTOR.md | 本报告，按最终状态重写。 |

此前 Windows 原处理、Loader 的路径/配置/编码验证、批量只读诊断继续有效。
keyrun.ps1 -Install、实际 Java Agent/key/环境变量处理代码在本轮没有改动。
test_script.ps1 旧重复副本仍停用。

## 测试

Windows PowerShell 5.1.19041.1320：后台 **101 项通过**。

| 检查 | 数量 |
| --- | --- |
| 普通资源 Loader：Local/HTTP、UTF-8/BOM、JSON/字节、路径边界、错误和超时 | 47 |
| 批量路径诊断：解析、批量/单文件、失败后继续、保持字节 | 10 |
| 安装资源链路：25 个资源、13 个部署目标、临时 key/参数写入、本地提升结构 | 30 |
| 独立服务器引导：HTTP 获取、空目录启动、配置同步、超时、临时清理、摘要拒绝与 Git 行尾兼容 | 14 |

引导测试先核对回环 HTTP 返回的初始脚本与本地生成结果完全相同，再执行无害测试入口。
没有执行真实安装 Main、没有 UAC、没有加载 Agent、没有修改实际 IDE 或系统环境变量。
测试回环服务均已关闭，临时目录已清理；实际项目配置保持新的 HTTP 示例状态。

页面额外 **18 项离线交互检查通过**：
默认示例、三平台地址随动、复制一致、Local/HTTP 切换、无效地址禁用、
指南 Tab/跳转，以及不向指南注入具体项目目录。
Windows 服务器命令通过 5.1 语法解析；POSIX shell 引号解析也通过，输入中的引号和 shell 字符保持字面值。
HTML 标签/ID/ARIA、JavaScript 语法和 git diff --check 通过。
浏览器工具禁止 file:// 预览，因此没有绕过限制进行视觉验收。

原 HTTP/HTTPS 地址核对只做 HEAD 请求，没有下载或执行其脚本。
根地址与两个入口在本轮均返回 404；无法对这个失效服务进行真实远程安装验证。
Windows 安装本身此前由用户反馈“执行没有问题”；本轮不重新运行实际安装。

## macOS / Linux

保留用户指定的服务器命令格式示例：

```bash
curl -fsSL https://liyangxu1.github.io/keyrun/scripts/install.sh | bash
```

地址随页面输入更新。这些命令的实际处理能力取决于服务端提供兼容的独立 shell 脚本。
当前仓库 scripts/install.sh 仍在入口停用，Mac/Linux 本地与服务端处理兼容留待后续开发。
本轮没有把 Windows 引导误宣称为 Unix 可用实现，指南和命令卡片均注明该限制。

## 备份与限制

本轮备份保留在：
- backups/server-command-examples-20261014-175646/
- backups/server-bootstrap-20261014-180925/

此前所有阶段备份继续保留，只供审计，不应作为当前入口执行。
当前根地址仍是已失效示例；真实服务尚未部署，本次只准备本地可发布代码。
用户继续本机安装前必须执行 -Mode local；实际服务部署则使用新的 HTTP 配置并上传完整项目。
没有修改 Windows 执行策略或证书校验。Remote bootstrap 与安装仍受使用者系统权限及网络环境影响。
