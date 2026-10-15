<p align="right"><a href="./README.md">简体中文</a> | English</p>

# KeyRun cross-platform tools

The supported entry is the local `keyrun.ps1` file. It reads ordinary resources through
`source-config.json → resource-loader.ps1 → keyrun.ps1` and supports Windows PowerShell 5.1.
The shipped configuration defaults to HTTP. Run -Mode local explicitly to select disk files;
the selection persists in source-config.json until another switch. Local mode needs no HTTP service. Resource reads and path diagnosis
need no administrator rights. Use -Install to run the restored Windows processing flow.
macOS/Linux use native Bash entries and share the same source configuration and resources.

## macOS / Linux

Requirements: Bash 3.2+, jq, and curl for HTTP. Text reads use the system iconv.
PowerShell is not required. The installer does not install dependencies or source shell profiles.
Use your normal desktop account, without sudo.

```bash
bash ./switch-source.sh --mode local
bash ./keyrun.sh --install --dry-run
bash ./keyrun.sh --diagnose-idea-paths
# Optional: inspect a particular properties file or installation directory.
bash ./keyrun.sh --diagnose-idea-paths --properties-path '/path/to/idea.properties'
# After reviewing paths and closing all JetBrains IDEs:
bash ./keyrun.sh --install
```

Dry runs show targets and templates without downloading resources or changing IDE files.
Discovery checks default configuration directories, cached `.home` files and bounded standard/Toolbox locations.
macOS supports `.app/Contents/bin`; Linux honors XDG_CONFIG_HOME, XDG_CACHE_HOME and Toolbox's XDG_DATA_HOME.
Installation metadata (`product-info.json`, `dataDirectoryName`) can identify configurations without caches.
For other layouts, use:

```bash
bash ./keyrun.sh --install --dry-run \
  --config-dir '/configuration directory' --product idea --ide-home '/installation or .app'
```

The installer stages all 25 resources before persistent changes. Agent files go into `~/.jb_run/`.
VM options and keys go into user configuration directories; macOS application bundles are not modified.
New VM options copy the installed template. Existing JVM settings and unrelated agents are preserved;
repeated installation replaces existing KeyRun/ja-netfilter options rather than appending duplicates.
Simple `idea.config.path`, `${user.home}`, relative paths and product `*_PROPERTIES` overrides are supported.
Complex Java properties syntax and Snap/Flatpak permissions require explicit configuration and testing.

Each write session keeps originals under `~/.jb_run/backups/run-*/files/<original absolute path>`.
`manifest.jsonl` records whether each file previously existed. Failed writes attempt to restore modified files;
forced termination or power loss requires manual restoration from the retained backup.
Simple VM_OPTIONS assignments for discovered products are backed up and removed from common profiles.
Complex definitions stop installation for manual review; profiles are never executed.
macOS also clears existing launchctl values. Custom LaunchAgents/systemd user environments need separate review;
a child process cannot clear its parent shell environment. Use a new terminal or login session when needed.
Installation targets reject symlink paths. `--yes` confirms installation in noninteractive sessions.

Resources can be read with `--resource-path PATH --format text|json|bytes`.
Bytes are preserved exactly, text must be valid UTF-8, and UTF-8 BOMs are removed.
Local mode makes no HTTP requests; resource traversal and links inside the configured root are rejected.

## macOS / Linux standalone HTTP entry

The maintainer runs this in a complete checkout and publishes the matching project:

```bash
bash ./switch-source.sh --mode http --http-base 'https://your-server/keyrun' --timeout-seconds 20
```

This generates `/sh` with the server address and SHA-256 hashes for six code files.
Regenerate after shell code changes and preserve LF line endings (.gitattributes).
Windows configuration also generates `/sh`. When deploying from macOS/Linux, regenerate Windows `/ps1`
on Windows if you also publish a Windows entry at the new address.

End users do not need a local project:

```bash
curl -fsSL 'https://your-server/keyrun/sh' | bash -s -- --dry-run
# After reviewing paths and closing IDEs:
curl -fsSL 'https://your-server/keyrun/sh' | bash
```

The bootstrap checks all code before execution and cleans temporary files afterwards.
HTTP rejects redirects and non-2xx responses, honors timeouts, and never falls back to another source.
Code hashes detect mismatched deployment versions; use a trusted bootstrap server.
`scripts/install.sh` is a local compatibility entry; use `/sh` for remote pipelines.

Run harmless integration tests with `python3 tests/test-unix.py` (requires loopback HTTP access).
Tests create only temporary resources and simulated IDEs, never execute real JARs or alter real IDEs.
For real Linux validation:

```bash
docker build -f tests/Dockerfile.unix -t keyrun-unix-test .
docker run --rm --network none keyrun-unix-test
```

```powershell
.\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1
.\keyrun.ps1 -ResourcePath index.html
.\keyrun.ps1 -ResourcePath source-config.json -Format Json
.\keyrun.ps1 -ResourcePath LICENSE -Format Bytes
.\keyrun.ps1 -DiagnoseIdeaPaths
.\keyrun.ps1 -DiagnoseIdeaPaths -PropertiesPath 'C:\path\to\idea.properties'

.\switch-source.ps1 -Mode http -HttpBase 'https://your-host.example/keyrun' -TimeoutSeconds 20
.\keyrun.ps1 -ResourcePath README.md
.\switch-source.ps1 -Mode local
```

Replace the example HTTP root with a resource server you control. Executable tools always
come from the local checkout; downloaded PowerShell script text is never executed.
Relative local roots resolve against the Loader directory, independently of the working directory.
Use `-LocalRoot` to override the root. Text is strict UTF-8, with or without a BOM.
The byte interface preserves binary data. Invalid paths, missing files, invalid configuration,
HTTP error statuses, connection failures and timeouts raise explicit errors.
Redirects are rejected; configure the final HTTP/HTTPS directory URL without credentials, query or fragment.
`-OpenPage` opens the local page or the configured HTTP page. Browser icons still use third-party URLs.

The original `ps1` file is now a standalone server bootstrap;
use `keyrun.ps1` with Windows PowerShell's `-File` option.
The read-only path diagnostic checks every discovered properties file by default.
Use -PropertiesPath to inspect just one file. Results are labeled separately;
a failed file does not prevent the remaining files from being checked.
Execution policy remains under your or your organization's control.

## Restored Windows processing flow

Back up IDE settings and existing license files, close all JetBrains IDEs, then run:

```powershell
.\switch-source.ps1 -Mode local
powershell.exe -NoProfile -File .\keyrun.ps1 -Install
```

Installation requests administrator rights and relaunches the local scripts/install.ps1 file,
preserving the optional -OpenPage parameter. It preloads all 25 resources before any environment,
work-directory or IDE changes. The original flow clears product VM_OPTIONS variables,
deploys Agent files, changes relevant startup options and writes .key resource bytes.
The source root must contain ja-netfilter/ and licenses/. Use a trusted source: Agent JARs will
be loaded by the IDE. No remote PowerShell script is downloaded or executed.
The original name/date prompts do not regenerate the static key resources.
File-write success does not verify the software's licensing outcome; reopen the IDE to check.

scripts/install.ps1 is restored and uses the Loader. The old duplicate test_script.ps1 remains
disabled. tests/test-install-resource-wiring.ps1 verifies the Windows
wiring in temporary directories without invoking Main, UAC, or installed IDE changes.
Original backups must not be executed.

## Standalone Windows server entry

The project maintainer runs switch-source.ps1 -Mode http -HttpBase with the actual server root.
This saves the source config and regenerates ps1 with the root URL and matching SHA-256 values
for the four required code files. Publish the complete project to that root; regenerate before
deploying code updates. The server only needs to serve static files.

End users can invoke the deployed Windows bootstrap without a pre-downloaded local project:

```powershell
irm https://liyangxu1.github.io/keyrun/ps1 | iex
```

The old default URL is an example and returned 404 when checked on 2026-10-14. Replace it with
an actual trusted deployment. The bootstrap prepares an isolated temporary project, verifies
matching code bytes, runs the Windows local installer with HTTP resources, then cleans up.
It does not use source files or configuration from the caller's working directory.
Embedded hashes detect mismatched deployments; the initial bootstrap is still supplied by the
chosen server and must be trusted. Local mode remains selected after -Mode local, until -Mode http
is executed again. End users of the deployed entry need no local switch command.

The macOS/Linux curl examples use the generated standalone `/sh` entry.
tests/test-server-bootstrap.ps1 uses only a loopback server and harmless fixture code, with no
real installation or IDE changes.

See [the refactor report](./SOURCE-REFACTOR.md) and `tests/test-resource-loader.ps1`.
Source code is licensed under [GNU GPL v3](./LICENSE).
Use [JetBrains' official channels](https://www.jetbrains.com/) for software licensing.
