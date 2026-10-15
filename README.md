<p align="right">简体中文 | <a href="./README.en.md">English</a></p>

# KeyRun

用于批量配置本机 JetBrains IDE 启动参数和许可证文件的命令行工具，支持 **Windows、macOS 和 Linux**。
下载完整项目后，按下面对应系统的步骤运行即可，本地使用不需要搭建服务器。

[Windows](#windows) · [macOS](#macos) · [Linux](#linux) · [常见问题](#常见问题)

## 使用前准备

1. 在本仓库点击 **Code → Download ZIP**，下载后解压。请保留整个文件夹，不要只下载某个脚本。
2. 确保要处理的 JetBrains IDE 已安装并至少打开过一次，然后关闭所有 JetBrains IDE。
3. 备份重要的 IDE 设置和已有许可证文件。工具会修改本机配置，执行结束后需要重新打开 IDE 检查结果。

## Windows

在解压后的项目文件夹中打开 **PowerShell**。可以在资源管理器地址栏输入 `powershell`，然后按回车。

依次运行：

```powershell
powershell.exe -NoProfile -File .\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1 -Install
```

按终端提示继续；出现管理员权限请求时，确认后允许。执行结束后，重新打开 IDE 检查结果。

## macOS

需要 **Bash 和 jq**。系统自带 Bash；如果已有 Homebrew，可先运行 `brew install jq` 安装 jq。
其他安装方式见 [jq 安装说明](https://jqlang.org/download/)。

打开「终端」，输入 `cd `（后面留一个空格），把解压后的项目文件夹拖入终端，再按回车。

**先预览识别到的目录：**

```bash
bash ./switch-source.sh --mode local
bash ./keyrun.sh --install --dry-run
```

预览不会修改 IDE。确认列出的配置目录正确后，执行：

```bash
bash ./keyrun.sh --install
```

输入 `y` 确认并等待完成，再重新打开 IDE。使用当前登录用户运行，**不要加 sudo**。

## Linux

需要 **Bash 和 jq**。Debian / Ubuntu 用户可先安装：

```bash
sudo apt-get install bash jq
```

其他发行版请使用对应包管理器安装这两个依赖。
在解压后的项目文件夹中打开终端，然后运行：

```bash
bash ./switch-source.sh --mode local
bash ./keyrun.sh --install --dry-run
```

确认预览中的配置目录正确后，执行：

```bash
bash ./keyrun.sh --install
```

输入 `y` 确认并等待完成，再重新打开 IDE。安装依赖以外的工具命令请使用普通用户运行，**不要加 sudo**。

## 如何确认执行结果

- 先看终端是否有报错或跳过的产品；未找到配置的产品不会被自动处理。
- 重新打开要使用的 IDE，检查能否正常启动以及配置是否生效。
- macOS / Linux 完成后会显示备份位置；如需恢复，请先关闭 IDE，并保留该目录。

## 常见问题

| 遇到的问题 | 处理方法 |
| --- | --- |
| 提示找不到脚本或文件 | 确认下载了完整项目，并在解压后的项目文件夹中打开终端。 |
| 提示缺少 jq | macOS 已有 Homebrew 时运行 `brew install jq`；Debian / Ubuntu 运行 `sudo apt-get install jq`。 |
| 没有找到 IDE 或某个产品被跳过 | 先打开该 IDE 一次，关闭后重试。自定义安装目录可参考[目录诊断与自定义路径](./docs/DEVELOPMENT.md#目录诊断与自定义路径)。 |
| 本地使用时仍然请求服务器 | 重新运行对应系统的第一条 Local 切换命令，再运行安装命令。 |
| Windows 提示脚本被执行策略阻止 | 按系统或组织要求处理脚本运行权限；工具不会自动修改执行策略。 |
| macOS / Linux 提示权限不足 | 使用配置所属的登录用户运行，不要用 sudo 重试；检查提示中的目录是否属于当前用户。 |
| 只显示了说明，没有执行安装 | Windows 命令需要带 `-Install`；macOS / Linux 命令需要带 `--install`。 |

**备份在哪里？** macOS / Linux 的自动备份保存在 `~/.jb_run/backups/`，每次安装的具体目录会在终端显示。Windows 使用前请自行备份配置和已有许可证文件。

仍有问题时，请提供操作系统、IDE 名称，以及完整报错文本；不要附带许可证内容或其他敏感信息。

## 已有在线服务时如何使用

如果维护者提供了可用的在线服务，可以直接使用其提供的命令，无需下载本地项目。macOS / Linux 额外需要 curl。

<details>
<summary>查看在线命令格式</summary>

请把下面的 `https://your-server.example/keyrun` 替换为维护者提供的实际服务根地址；示例地址不能直接使用。

Windows PowerShell：

```powershell
irm https://your-server.example/keyrun/ps1 | iex
```

macOS / Linux 先预览：

```bash
curl -fsSL https://your-server.example/keyrun/sh | bash -s -- --dry-run
```

确认目录并关闭 IDE 后，再运行：

```bash
curl -fsSL https://your-server.example/keyrun/sh | bash
```

请使用可信来源提供的命令。不确定服务地址时，使用本文前面的本地方式。

</details>

## 更多说明

- [开发、部署与高级用法](./docs/DEVELOPMENT.md)
- [项目变更与验证记录](./SOURCE-REFACTOR.md)
- 源代码采用 [GNU GPL v3](./LICENSE)；JetBrains 软件授权请通过[官方渠道](https://www.jetbrains.com/)处理。
