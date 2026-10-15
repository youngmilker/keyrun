<p align="right"><a href="./README.md">简体中文</a> | English</p>

# KeyRun

A command-line tool for configuring local JetBrains IDE startup options and license files on **Windows, macOS and Linux**.
Download the complete project and follow the steps for your system. Local use does not require a server.

[Windows](#windows) · [macOS](#macos) · [Linux](#linux) · [Troubleshooting](#troubleshooting)

## Before you start

1. Click **Code → Download ZIP** in this repository and extract it. Keep the entire folder; do not download individual scripts.
2. Install and open each IDE you want to configure at least once, then close all JetBrains IDEs.
3. Back up important IDE settings and existing license files. The tool changes local configuration; reopen your IDE afterwards to check the result.

## Windows

Open **PowerShell** in the extracted project folder. You can type `powershell` in File Explorer's address bar and press Enter.

Run these commands in order:

```powershell
powershell.exe -NoProfile -File .\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1 -Install
```

Follow the terminal prompts and approve the administrator request when ready. Reopen your IDE after the script finishes.

## macOS

Requires **Bash and jq**. Bash is included with macOS. If you already use Homebrew, install jq with `brew install jq`.
For other installation options, see the [jq installation guide](https://jqlang.org/download/).

Open Terminal, type `cd ` with a trailing space, drag the extracted project folder into the terminal, and press Enter.

**Preview the detected directories first:**

```bash
bash ./switch-source.sh --mode local
bash ./keyrun.sh --install --dry-run
```

The preview does not modify your IDE. After checking the listed configuration directories, run:

```bash
bash ./keyrun.sh --install
```

Enter `y` to confirm, wait for completion, then reopen your IDE. Run as your current login user, **without sudo**.

## Linux

Requires **Bash and jq**. On Debian / Ubuntu, install them with:

```bash
sudo apt-get install bash jq
```

On other distributions, use your package manager to install these dependencies.
Open a terminal in the extracted project folder, then run:

```bash
bash ./switch-source.sh --mode local
bash ./keyrun.sh --install --dry-run
```

After checking that the preview lists the correct directories, run:

```bash
bash ./keyrun.sh --install
```

Enter `y` to confirm, wait for completion, then reopen your IDE. Except for installing dependencies, run the tool as a normal user, **without sudo**.

## Checking the result

- Check the terminal for errors or skipped products. Products without a detected configuration are not processed automatically.
- Reopen your IDE and check that it starts normally and the configuration took effect.
- On macOS / Linux, the script prints the backup location. Keep that folder and close your IDE before restoring files.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| Script or file not found | Download the complete project and open your terminal in the extracted project folder. |
| Missing jq | With Homebrew on macOS, run `brew install jq`. On Debian / Ubuntu, run `sudo apt-get install jq`. |
| IDE not found or product skipped | Open that IDE once, close it, and retry. For custom locations, see [path diagnosis and custom directories](./docs/DEVELOPMENT.md#目录诊断与自定义路径) (Chinese). |
| Local use still contacts a server | Run the Local switch command for your system again, then run the installation command. |
| Windows execution policy blocks the script | Follow your system or organization's script permissions policy. The tool does not change it automatically. |
| Permission denied on macOS / Linux | Run as the login user who owns the configuration. Check the directory shown in the error rather than retrying with sudo. |
| The script only displays instructions | Add `-Install` on Windows or `--install` on macOS / Linux. |

**Where are backups?** On macOS / Linux, automatic backups are under `~/.jb_run/backups/`; the terminal shows the folder for each run. On Windows, back up settings and existing license files yourself before use.

If you still need help, provide your operating system, IDE name and complete error text. Do not include license contents or other sensitive information.

## Using an existing online service

If a maintainer provides a working service, use their command without downloading a local project. macOS / Linux also require curl.

<details>
<summary>Show online command examples</summary>

Replace `https://your-server.example/keyrun` with the actual service root provided by the maintainer. The example address cannot be used as-is.

Windows PowerShell:

```powershell
irm https://your-server.example/keyrun/ps1 | iex
```

On macOS / Linux, preview first:

```bash
curl -fsSL https://your-server.example/keyrun/sh | bash -s -- --dry-run
```

After checking the directories and closing your IDEs, run:

```bash
curl -fsSL https://your-server.example/keyrun/sh | bash
```

Use commands from a trusted source. If you do not have a service address, use the local steps above.

</details>

## More information

- [Development, deployment and advanced usage](./docs/DEVELOPMENT.md) (Chinese)
- [Project changes and verification notes](./SOURCE-REFACTOR.md) (Chinese)
- Source code is licensed under [GNU GPL v3](./LICENSE). Obtain JetBrains software licenses through [official channels](https://www.jetbrains.com/).
